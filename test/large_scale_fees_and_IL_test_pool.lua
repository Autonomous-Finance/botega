---@diagnostic disable: duplicate-set-field
require("test.setup")()

_G.VerboseTests = 0
_G.printVerb = function(level)
    level = level or 2
    return function(...) -- define here as global so we can use it in the application code too
        if _G.VerboseTests >= level then print(table.unpack({ ... })) end
    end
end

_G.Owner = '123Owner321'
_G.User = '123User321'
_G.MainProcessId = 'xyzPoolzyx' -- pool process

_G.Handlers = require "handlers"
_G.aos = require "aos"

-- MOCKED PROCESSES

_G.AoCredProcessId = 'AoCred-123xyz'
_G.BarkTokenProcessId = '8p7ApPZxC_37M06QHVejCQrKsHbcJEerd3jWNkDUWPQ'

_G.OutboxLatest = {}
_G.ao = {
    id = _G.MainProcessId,
    env = {
        Process = {
            Tags = {
                ["Name"] = "AOCred-Bark-Testpool",
                ["Token-A"] = _G.AoCredProcessId,
                ["Token-B"] = _G.BarkTokenProcessId,
                ["Dexi-Token"] = "Dexi-Token-Process-Id"
            }
        }
    },
    send = function(msg)
        if msg.Target then
            _G.OutboxLatest[msg.Target] = msg
        else
            _G.OutboxLatest[msg.device] = msg
        end
    end,
}

local amm = require "amm.main" -- require so that process handlers are loaded, as well as global variables
local pool = require "amm.pool.pool"
local balance = require "amm.token.balance"
local swap = require "amm.pool.swap"
local provide = require "amm.pool.provide"
local burn = require "amm.pool.burn"
local math = require "math"

local bint = require "utils.tl-bint" (256)
local rebalancingSwap = require "rebalancing-swap"



local function poolGetOutputOnSwap(input, token)
    local inputExcludingFees = pool.deductFees(input)
    return pool.getOutput(inputExcludingFees, token)
end



-- LARGE SCALE TESTS

describe("liquidity and swapping at scale", function()
    -- make sure this number would overflow in lua
    local POOL_SIZE_SCALER = bint.ipow(bint(10), bint(20))
    -- start with a 1/2 ratio for AO/Bark
    local initialReserveAO = bint("500") * POOL_SIZE_SCALER
    assert(initialReserveAO:gt(bint(math.maxinteger)), 'initial number not greater than lua max integer')
    local initialReserveBark = bint("1000") * POOL_SIZE_SCALER

    local originalGetPair
    setup(function()
        originalGetPair = pool.getPair

        pool.getPair = function()
            return { "tokenA", "tokenB" }
        end
    end)

    teardown(function()
        pool.getPair = originalGetPair
    end)

    before_each(function()
        local pair = pool.getPair()
        _G.Reserves = {
            [pair[1]] = bint(0),
            [pair[2]] = bint(0),
        }
        _G.Balances = {}

        -- INITIALIZE WITH A PROVIDE
        provide.executeProvide(
            pair[1], pair[2],
            initialReserveAO, initialReserveBark,
            "initializer", 0.1
        )

        pool.getProtocolFeePercentage = function()
            return 0
        end

        pool.getLPFeePercentage = function()
            return 0.25
        end
    end)

    after_each(function()
    end)


    --[[
        We test the burning logic based on the lp share ratio,
        and the expected protocol fees for the swaps

        Setup: the pool has preexisting liquidity,

        2 users provide additional liquidity, thereby
        becoming holders of 40% and 10% of pool shares.

        Many swaps are performed.

        The users redeem their share of the pool reserves.

        We assert that they obtain the reserves fractions
        according to
        their lp shares in ratio to the total lp tokens supply.
    ]]
    it("provide, perform many swaps, burn - protocol fees considered & lp shares reflected in redeemed output",
        function()
            local verbosity = 0
            local pair = pool.getPair()

            _G.VerboseTests = verbosity

            -- Provide liquidity
            -- preexisting liquidity = bint(500) & bint(1000)
            -- provider 1 and 2 together provide the same liquidity on top

            -- after providing we'll have
            -- preexisting -> 50% of pool
            -- provider 1 -> 40% of pool
            -- provider 2 -> 10% of pool
            local addLiquidityA1 = bint(400) * POOL_SIZE_SCALER
            local addLiquidityA2 = bint(100) * POOL_SIZE_SCALER
            local addLiquidityB1 = bint(800) * POOL_SIZE_SCALER
            local addLiquidityB2 = bint(200) * POOL_SIZE_SCALER

            printVerb(1)("= = = = Provide/swap/burn = = = =")

            printVerb(1)("Reserves PRE-PROVIDE")
            printVerb(1)("A: ", _G.Reserves[pair[1]])
            printVerb(1)("B: ", _G.Reserves[pair[2]])


            printVerb(1)("Providing liquidity 1:")
            printVerb(1)("A: ", addLiquidityA1)
            printVerb(1)("B: ", addLiquidityB1)

            local provideResult1 = provide.executeProvide(
                pair[1], pair[2],
                addLiquidityA1, addLiquidityB1,
                "provider1",
                0.01
            )

            printVerb(1)("Providing liquidity 2:")
            printVerb(1)("A: ", addLiquidityA2)
            printVerb(1)("B: ", addLiquidityB2)

            local provideResult2 = provide.executeProvide(
                pair[1], pair[2],
                addLiquidityA2, addLiquidityB2,
                "provider2",
                0.01
            )

            printVerb(1)("Reserves POST-PROVIDE")
            local preSwapReservesA = _G.Reserves[pair[1]]
            local preSwapReservesB = _G.Reserves[pair[2]]
            printVerb(1)("A: ", preSwapReservesA)
            printVerb(1)("B: ", preSwapReservesB)

            -- Perform many swaps
            local totalInputQtyA = bint(0)
            local totalOutputQtyA = bint(0)
            local totalProtocolFeeQtyA = bint(0)

            local totalInputQtyB = bint(0)
            local totalOutputQtyB = bint(0)
            local totalProtocolFeeQtyB = bint(0)

            printVerb(1)('- - - EXECUTE 1000 random SWAPS (bi-directional)')
            for i = 1, 100 do
                local isAtoB = math.random() > 0.5

                local tokenIn = isAtoB and pair[1] or pair[2]

                local inputQty = bint.ipow(bint(math.random(1000, 10000)), bint(5))

                local expectedOutput = poolGetOutputOnSwap(inputQty, tokenIn)

                local swapResult = swap.executeSwapWithMinOutput(tokenIn, inputQty, expectedOutput)
                assert.Equal(expectedOutput, swapResult.outputQty)

                if isAtoB then
                    totalInputQtyA = totalInputQtyA + inputQty
                    totalOutputQtyB = totalOutputQtyB + swapResult.outputQty
                    totalProtocolFeeQtyA = totalProtocolFeeQtyA + swapResult.protocolFeeQty
                else
                    totalInputQtyB = totalInputQtyB + inputQty
                    totalOutputQtyA = totalOutputQtyA + swapResult.outputQty
                    totalProtocolFeeQtyB = totalProtocolFeeQtyB + swapResult.protocolFeeQty
                end
            end

            printVerb(1)("Total input  (A):", totalInputQtyA)
            printVerb(1)("Total input  (B):", totalInputQtyB)
            printVerb(1)("Total output (A):", totalOutputQtyA)
            printVerb(1)("Total output (B):", totalOutputQtyB)
            printVerb(1)("Total protocol fees   (A):", totalProtocolFeeQtyA)
            printVerb(1)("Total protocol fees   (B):", totalProtocolFeeQtyB)

            --[[
            Verify reserves after swaps

            Swaps should have affected reserves as follows:
            - swap input increases the reserve of the input token
                -> but not by the full input qty, since PROTOCOL fees are deducted and transferred out of the pool immediately
            - swap output decreases the reserve of the output token
                -> the full swap output amount leaves the pool reserve
        ]]
            local postSwapsReserveA = preSwapReservesA + totalInputQtyA - totalOutputQtyA -
                totalProtocolFeeQtyA
            printVerb(1)('postSwapsReserveA', postSwapsReserveA, " =",
                tostring(preSwapReservesA) ..
                " + " ..
                tostring(totalInputQtyA) .. " - " .. tostring(totalOutputQtyA) .. " - " .. tostring(totalProtocolFeeQtyA),
                "  = pre-swaps (A) + total input (A) - total output (A) - total protocol fees (A)")
            local postSwapsReserveB = preSwapReservesB + totalInputQtyB - totalOutputQtyB -
                totalProtocolFeeQtyB
            printVerb(1)('postSwapsReserveB', postSwapsReserveB, " =",
                tostring(preSwapReservesB) ..
                " - " ..
                tostring(totalOutputQtyB) ..
                " - " .. tostring(totalOutputQtyB) .. " - " .. tostring(totalProtocolFeeQtyB),
                "  = pre-swaps (B) + total input (B) - total output (B) - total protocol fees (B)")

            assert.Equal(postSwapsReserveA, _G.Reserves[pair[1]])
            assert.Equal(postSwapsReserveB, _G.Reserves[pair[2]])

            -- Burn liquidity
            printVerb(1)('- - - BURN provided liquidity for provider 1 and provider 2')
            local burnResult1 = burn.executeBurn(
                provideResult1.lpTokensMinted,
                'provider1'
            )
            local burnResult2 = burn.executeBurn(
                provideResult2.lpTokensMinted,
                'provider2'
            )

            -- Calculate expected returns
            -- base share issuance calculation on tokenA liquidity rather than on total liquidity,
            -- since we take the same approach in calculateLpTokensToMint()

            local totalLiquidityA = initialReserveAO + addLiquidityA1 + addLiquidityA2
            printVerb(1)('totalLiquidityA:', totalLiquidityA)

            local SCALE_FACTOR = bint("1000000")

            -- Calculate provider share using fixed-point arithmetic
            local scaledAddLiquidityA1 = addLiquidityA1 * SCALE_FACTOR
            local scaledAddLiquidityA2 = addLiquidityA2 * SCALE_FACTOR
            local providerShare1 = bint.udiv(scaledAddLiquidityA1, totalLiquidityA)
            local providerShare2 = bint.udiv(scaledAddLiquidityA2, totalLiquidityA)
            printVerb(1)('provider 1 share:    ', providerShare1)
            printVerb(1)('provider 2 share:    ', providerShare2)

            -- Calculate expected burn returns using the scaled provider share
            local expectedBurnReturnA1 = bint.udiv(postSwapsReserveA * providerShare1, SCALE_FACTOR)
            printVerb(1)('expectedBurnReturnA1:', expectedBurnReturnA1, " =",
                tostring(postSwapsReserveA) .. " * " .. tostring(providerShare1) .. " / " .. tostring(SCALE_FACTOR),
                " = post-swaps (A) * providerShare1 / SCALE_FACTOR")
            local expectedBurnReturnB1 = bint.udiv(postSwapsReserveB * providerShare1, SCALE_FACTOR)
            printVerb(1)('expectedBurnReturnB1:', expectedBurnReturnB1, " =",
                tostring(postSwapsReserveB) .. " * " .. tostring(providerShare1) .. " / " .. tostring(SCALE_FACTOR),
                " = post-swaps (B) * providerShare1 / SCALE_FACTOR")

            local expectedBurnReturnA2 = bint.udiv(postSwapsReserveA * providerShare2, SCALE_FACTOR)
            printVerb(1)('expectedBurnReturnA2:', expectedBurnReturnA2, " =",
                tostring(postSwapsReserveA) .. " * " .. tostring(providerShare2) .. " / " .. tostring(SCALE_FACTOR),
                " = post-swaps (A) * providerShare2 / SCALE_FACTOR")
            local expectedBurnReturnB2 = bint.udiv(postSwapsReserveB * providerShare2, SCALE_FACTOR)
            printVerb(1)('expectedBurnReturnB2:', expectedBurnReturnB2, " =",
                tostring(postSwapsReserveB) .. " * " .. tostring(providerShare2) .. " / " .. tostring(SCALE_FACTOR),
                " = post-swaps (B) * providerShare2 / SCALE_FACTOR")

            -- due to rounding errors we accept for the burn returns 1 unit of deviation from the expected values

            assert.is_true(bint.abs(expectedBurnReturnA1 - burnResult1.withdrawnTokenA):ule(bint(1)))
            assert.is_true(bint.abs(expectedBurnReturnB1 - burnResult1.withdrawnTokenB):ule(bint(1)))

            assert.is_true(bint.abs(expectedBurnReturnA2 - burnResult2.withdrawnTokenA):ule(bint(1)))
            assert.is_true(bint.abs(expectedBurnReturnB2 - burnResult2.withdrawnTokenB):ule(bint(1)))

            -- Verify final reserves
            local expectedFinalReservesA = postSwapsReserveA - expectedBurnReturnA1 - expectedBurnReturnA2
            local expectedFinalReservesB = postSwapsReserveB - expectedBurnReturnB1 - expectedBurnReturnB2
            assert.is_true(bint.abs(expectedFinalReservesA - _G.Reserves[pair[1]]):ule(bint(1)))
            assert.is_true(bint.abs(expectedFinalReservesB - _G.Reserves[pair[2]]):ule(bint(1)))

            -- verify burn return vs deposited value
            -- we only print out the values -> not practical to compare since
            -- lp fees would complicate the situation (see tests below)

            -- addLiquidityA, addLiquidityB
            -- vs
            -- burnResult.withdrawnTokenA , burnResult.withdrawnTokenB
            printVerb(1)('addLiquidityA1', tostring(addLiquidityA1))
            printVerb(1)('addLiquidityB1', tostring(addLiquidityB1))
            printVerb(1)('redeemedA1', tostring(burnResult1.withdrawnTokenA))
            printVerb(1)('redeemedB1', tostring(burnResult1.withdrawnTokenB))

            printVerb(1)('addLiquidityA2', tostring(addLiquidityA2))
            printVerb(1)('addLiquidityB2', tostring(addLiquidityB2))
            printVerb(1)('redeemedA2', tostring(burnResult2.withdrawnTokenA))
            printVerb(1)('redeemedB2', tostring(burnResult2.withdrawnTokenB))

            _G.VerboseTests = 0
        end)

    -- VERSION WITHOUT PROTOCOL FEES (simpler calculations)
    --[[
        This test is not concerned with lp shares and burning, but merely tracks fee accumulation in the reserves
        (lp shares - based burning is tested elsewhere)

        Setup: we have 1 sole provider to the amm.
        Once they provide, many swaps are performed, but always as "rebalancing" pairs.

        A rebalancing pair of swaps is such that the first swap may be of any input value,
        while the second swap goes the opposite direction, in order to return to the initial
        reserves ratio.

        --- The testing logic ---

        We want to assert that fees are being accumulated via the swaps, and that the
        accumulated amount of fees is reflected in the additional reserves amount
        that is present when the user burns their lp tokens, taking out the liquidity.

        Since a pool with no LP fee mechanism evolves differently from a pool with LP fees
        (reserves ratio evolves differently), we need to account for the special effect that
        the presence of accumulated fees has on the overall reserves evolution.

        For this, we track and accumulate the associated "pseudo-losses" (See explanation below)
        At the end, we take into account accumulated fees and pseudo-losses, to verify that the

        LP PROVIDER HAS OBTAINED THE CORRECT AMOUNT OF PROFIT ON TOP OF THEIR PROVIDED LIQUIDITY.

        -------- "pseudo-loss" explanation ---------

        Scenario: reserves A and B

        we consider the initial ratio
        we swap form A to B (qty a for output b)
        we make a rebalancing swap from B to A (qty r_b for output r_a)

        1. no fees => B becomes more expensive than A by delta_NF
        2. lp fees => B becomes more expensive than A by delta_F (ratio)

        delta_NF > delta_F
        because the effective swap input in case "FEES" is **less than** in case "NO_FEES".
        more exactly, effective_a = a * (1 - lpFee)

        ==>

        3. the "rebalancing" swap involves a larger input quantity of B in case "FEES", because:
            - B is cheaper here
            - part of r_b will not flow into the trade anyway (effective_r_b = r_b * (1 - lpFee))

        ==>

        4. the "rebalancing" swap output (r_a) is larger in case "FEES"
            => reserves of A decrease more from the rebalancing swap
                in the case "NO_FEES" than in the case "FEES"
            -! however, reserves of A were increase identically in both cases by the first swap
            => the "rebalancing" swap in case "FEES" seems to take away more from A than in the case "NO_FEES"

        ==>

        5. this leaves us with reserves A incurring a pseudo-loss in case "FEES"
            i.e. if we disregard A's accrued fees in the reserves, we are left with less than the initial reserves A

        We call this a "pseudo-loss" on the reserves of token A
    ]]
    it("provide, do many symmetrical (rebalancing) swaps, then burn: demonstrate fee accrual (no protocol fees)",
        function()
            local verbosity = 0
            -- setting non-zero protocol fee to verify that fee accrual can be confirmed even when this fee is incured
            pool.getProtocolFeePercentage = function()
                return 0
            end

            pool.getLPFeePercentage = function()
                return 0.25
            end

            _G.VerboseTests = verbosity
            local pair = pool.getPair()

            -- MAKE 'provider' the only LP
            _G.Reserves = {
                [pair[1]] = bint(0),
                [pair[2]] = bint(0),
            }
            _G.Balances = {}

            -- Provide liquidity
            local addLiquidityA = bint(500) * POOL_SIZE_SCALER
            local addLiquidityB = bint(2000) * POOL_SIZE_SCALER

            local provideResult = provide.executeProvide(
                pair[1], pair[2],
                addLiquidityA, addLiquidityB,
                "provider",
                0.01
            )

            local reservesRatioPrecision = bint(1000000) -- only for printing
            printVerb(1)("= = = = Symmatrical swaps, demonstrate FEE ACCRUAL = = = =")

            printVerb(1)("Reserves Before Swaps")
            local initialReservesA = _G.Reserves[pair[1]]
            local initialReservesB = _G.Reserves[pair[2]]
            local initialRatio = bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]])
            printVerb(1)("A: ", initialReservesA)
            printVerb(1)("B: ", initialReservesB)
            printVerb(1)("Initial Ratio (precision 6): ", tostring(initialRatio))

            local accFeesA = bint(0)
            local accFeesB = bint(0)
            local accPseudoLossA = bint(0)
            local accPseudoLossB = bint(0)
            local iterations = 0
            local swapSize = bint.ipow(bint(10), bint(18))

            printVerb(1)(' ========== 1000 runs of 2 symmetrical swaps =========')
            _G.VerboseTests = 0
            for i = 1, 1000 do
                iterations                = iterations + 1

                local roll                = math.random(1, 10) > 5
                -- true     => direction is pair[1] -> pair[2] -> pair[1]
                -- false    => direction is pair[2] -> pair[1] -> pair[2]

                local token1              = roll and pair[1] or pair[2]
                local token2              = roll and pair[2] or pair[1]

                local initialReservesFrom = _G.Reserves[token1]
                local initialReservesTo   = _G.Reserves[token2]

                -- EXECUTE SWAP 1
                local tokenIn1            = token1

                local inputQty1           = swapSize

                local expectedOutput1     = poolGetOutputOnSwap(inputQty1, tokenIn1)

                local swapResult1         = swap.executeSwapWithMinOutput(tokenIn1, inputQty1, expectedOutput1)

                local outputQty1          = swapResult1.outputQty
                local lpFeeQty1           = swapResult1.lpFeeQty

                printVerb(1)('input 1                     ', tostring(inputQty1))
                printVerb(1)('input 1 after total fees    ', tostring(pool.deductFees(inputQty1)))
                printVerb(1)('output 1                    ', tostring(outputQty1))
                printVerb(1)('lp fee on swap 1            ', tostring(lpFeeQty1))

                local postSwap1ReservesFrom = _G.Reserves[token1]
                local postSwap1ReservesTo   = _G.Reserves[token2]

                printVerb(1)("Reserves after swap 1")
                printVerb(1)("A: ", _G.Reserves[pair[1]])
                printVerb(1)("B: ", _G.Reserves[pair[2]])
                printVerb(1)("Ratio (precision 6)",
                    bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]]))

                -- EXECUTE SWAP 2
                local tokenIn2        = token2

                local inputQty2       = rebalancingSwap.getInputForBalancingSwap(initialReservesFrom, initialReservesTo,
                    postSwap1ReservesFrom, postSwap1ReservesTo) + bint(1)

                local expectedOutput2 = poolGetOutputOnSwap(inputQty2, tokenIn2)

                local swapResult2     = swap.executeSwapWithMinOutput(tokenIn2, inputQty2, expectedOutput2)

                local lpFeeQty2       = swapResult2.lpFeeQty

                local newRatio        = bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]])

                printVerb(1)('input 2                     ', tostring(inputQty2))
                printVerb(1)('output 2                    ', tostring(swapResult2.outputQty))
                printVerb(1)('lp fee on swap 2            ', tostring(lpFeeQty2))

                printVerb(1)("Reserves after swap 2")
                printVerb(1)("A: ", _G.Reserves[pair[1]])
                printVerb(1)("B: ", _G.Reserves[pair[2]])
                printVerb(1)("Ratio (precision 6)", newRatio)

                local pseudoLossToken1 = _G.Reserves[token1] - (initialReservesFrom + lpFeeQty1)
                printVerb(1)("PseudoLoss: ", tostring(pseudoLossToken1))

                if roll then
                    accFeesA = accFeesA + lpFeeQty1
                    accFeesB = accFeesB + lpFeeQty2
                    accPseudoLossA = accPseudoLossA + pseudoLossToken1
                else
                    accFeesA = accFeesA + lpFeeQty2
                    accFeesB = accFeesB + lpFeeQty1
                    accPseudoLossB = accPseudoLossB + pseudoLossToken1
                end
            end

            _G.VerboseTests = verbosity

            -- Burn liquidity
            printVerb(1)('- - - BURN provided liquidity')
            local burnResult = burn.executeBurn(
                provideResult.lpTokensMinted,
                'provider'
            )

            -- Calculate expected returns
            -- base share issuance calculation on tokenA liquidity rather than on total liquidity,
            -- since we take the same approach in calculateLpTokensToMint()

            -- verify burn return vs deposited value
            printVerb(1)('addLiquidityA', tostring(addLiquidityA))
            printVerb(1)('addLiquidityB', tostring(addLiquidityB))
            printVerb(1)('redeemedA', tostring(burnResult.withdrawnTokenA))
            printVerb(1)('redeemedB', tostring(burnResult.withdrawnTokenB))

            -- CHECK THE PROFIT FROM FEES

            local profitA = burnResult.withdrawnTokenA - addLiquidityA
            local profitB = burnResult.withdrawnTokenB - addLiquidityB

            printVerb(1)('Acc Fees A', tostring(accFeesA))
            printVerb(1)('Acc Fees B', tostring(accFeesB))
            printVerb(1)('Acc PseudoLoss A', tostring(accPseudoLossA))
            printVerb(1)('Acc PseudoLoss B', tostring(accPseudoLossB))

            printVerb(1)('profit A', tostring(profitA))
            printVerb(1)('profit B', tostring(profitB))

            -- we accept a diff of 1 due to rounding errors
            local profitDiffA = bint.abs(profitA - (accFeesA + accPseudoLossA))
            local profitDiffB = bint.abs(profitB - (accFeesB + accPseudoLossB))

            printVerb(1)('profit Diff A', tostring(profitDiffA))
            printVerb(1)('profit Diff B', tostring(profitDiffB))

            -- we accept 1 unit of deviation per iteration, regardless of direction (rounding errors)
            assert.is_true(bint.ule(profitDiffA + profitDiffB, bint(iterations)), "lp profit diff too high")

            _G.VerboseTests = 0
        end)


    -- -- VERSION WITH PROTOCOL FEES
    --[[
        Same as previous test, but with non-zero protocol fees
    ]]
    it("provide, do many symmetrical (rebalancing) swaps, then burn: demonstrate fee accrual (with protocol fees)",
        function()
            local verbosity = 0
            -- setting non-zero protocol fee to verify that fee accrual can be confirmed even when this fee is incured
            pool.getProtocolFeePercentage = function()
                return 0.05
            end

            pool.getLPFeePercentage = function()
                return 0.2
            end

            _G.VerboseTests = verbosity
            local pair = pool.getPair()

            -- MAKE 'provider' the only LP
            _G.Reserves = {
                [pair[1]] = bint(0),
                [pair[2]] = bint(0),
            }
            _G.Balances = {}

            -- Provide liquidity
            local addLiquidityA = bint(500) * POOL_SIZE_SCALER
            local addLiquidityB = bint(2000) * POOL_SIZE_SCALER

            local provideResult = provide.executeProvide(
                pair[1], pair[2],
                addLiquidityA, addLiquidityB,
                "provider",
                0.01
            )

            local reservesRatioPrecision = bint(1000000) -- only for printing
            printVerb(1)("= = = = Symmatrical swaps, demonstrate FEE ACCRUAL = = = =")

            printVerb(1)("Reserves Before Swaps")
            local initialReservesA = _G.Reserves[pair[1]]
            local initialReservesB = _G.Reserves[pair[2]]
            local initialRatio = bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]])
            printVerb(1)("A: ", initialReservesA)
            printVerb(1)("B: ", initialReservesB)
            printVerb(1)("Initial Ratio (precision 6): ", tostring(initialRatio))

            local accFeesA = bint(0)
            local accFeesB = bint(0)
            local accPseudoLossA = bint(0)
            local accPseudoLossB = bint(0)
            local iterations = 0
            local swapSize = bint.ipow(bint(10), bint(18))

            printVerb(1)(' ========== 1000 runs of 2 symmetrical swaps =========')
            _G.VerboseTests = 0
            for i = 1, 1000 do
                iterations                = iterations + 1

                local roll                = math.random(1, 10) > 5
                -- true     => direction is pair[1] -> pair[2] -> pair[1]
                -- false    => direction is pair[2] -> pair[1] -> pair[2]

                local token1              = roll and pair[1] or pair[2]
                local token2              = roll and pair[2] or pair[1]

                local initialReservesFrom = _G.Reserves[token1]
                local initialReservesTo   = _G.Reserves[token2]

                -- EXECUTE SWAP 1
                local tokenIn1            = token1

                local inputQty1           = swapSize

                local expectedOutput1     = poolGetOutputOnSwap(inputQty1, tokenIn1)

                local swapResult1         = swap.executeSwapWithMinOutput(tokenIn1, inputQty1, expectedOutput1)

                local outputQty1          = swapResult1.outputQty
                local lpFeeQty1           = swapResult1.lpFeeQty

                printVerb(1)('input 1                     ', tostring(inputQty1))
                printVerb(1)('input 1 after total fees    ', tostring(pool.deductFees(inputQty1)))
                printVerb(1)('output 1                    ', tostring(outputQty1))
                printVerb(1)('lp fee on swap 1            ', tostring(lpFeeQty1))

                local postSwap1ReservesFrom = _G.Reserves[token1]
                local postSwap1ReservesTo   = _G.Reserves[token2]

                printVerb(1)("Reserves after swap 1")
                printVerb(1)("A: ", _G.Reserves[pair[1]])
                printVerb(1)("B: ", _G.Reserves[pair[2]])
                printVerb(1)("Ratio (precision 6)",
                    bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]]))

                -- EXECUTE SWAP 2
                local tokenIn2        = token2

                local inputQty2       = rebalancingSwap.getInputForBalancingSwap(initialReservesFrom, initialReservesTo,
                    postSwap1ReservesFrom, postSwap1ReservesTo) + bint(1)

                local expectedOutput2 = poolGetOutputOnSwap(inputQty2, tokenIn2)

                local swapResult2     = swap.executeSwapWithMinOutput(tokenIn2, inputQty2, expectedOutput2)

                local lpFeeQty2       = swapResult2.lpFeeQty

                local newRatio        = bint.udiv(_G.Reserves[pair[2]] * reservesRatioPrecision, _G.Reserves[pair[1]])

                printVerb(1)('input 2                     ', tostring(inputQty2))
                printVerb(1)('output 2                    ', tostring(swapResult2.outputQty))
                printVerb(1)('lp fee on swap 2            ', tostring(lpFeeQty2))

                printVerb(1)("Reserves after swap 2")
                printVerb(1)("A: ", _G.Reserves[pair[1]])
                printVerb(1)("B: ", _G.Reserves[pair[2]])
                printVerb(1)("Ratio (precision 6)", newRatio)

                local pseudoLossToken1 = _G.Reserves[token1] - (initialReservesFrom + lpFeeQty1)
                printVerb(1)("PseudoLoss: ", tostring(pseudoLossToken1))

                if roll then
                    accFeesA = accFeesA + lpFeeQty1
                    accFeesB = accFeesB + lpFeeQty2
                    accPseudoLossA = accPseudoLossA + pseudoLossToken1
                else
                    accFeesA = accFeesA + lpFeeQty2
                    accFeesB = accFeesB + lpFeeQty1
                    accPseudoLossB = accPseudoLossB + pseudoLossToken1
                end
            end

            _G.VerboseTests = verbosity

            -- Burn liquidity
            printVerb(1)('- - - BURN provided liquidity')
            local burnResult = burn.executeBurn(
                provideResult.lpTokensMinted,
                'provider'
            )

            -- Calculate expected returns
            -- base share issuance calculation on tokenA liquidity rather than on total liquidity,
            -- since we take the same approach in calculateLpTokensToMint()

            -- verify burn return vs deposited value
            printVerb(1)('addLiquidityA', tostring(addLiquidityA))
            printVerb(1)('addLiquidityB', tostring(addLiquidityB))
            printVerb(1)('redeemedA', tostring(burnResult.withdrawnTokenA))
            printVerb(1)('redeemedB', tostring(burnResult.withdrawnTokenB))

            -- CHECK THE PROFIT FROM FEES

            local profitA = burnResult.withdrawnTokenA - addLiquidityA
            local profitB = burnResult.withdrawnTokenB - addLiquidityB

            printVerb(1)('Acc Fees A', tostring(accFeesA))
            printVerb(1)('Acc Fees B', tostring(accFeesB))
            printVerb(1)('Acc PseudoLoss A', tostring(accPseudoLossA))
            printVerb(1)('Acc PseudoLoss B', tostring(accPseudoLossB))

            printVerb(1)('profit A', tostring(profitA))
            printVerb(1)('profit B', tostring(profitB))

            -- we accept a diff of 1 due to rounding errors
            local profitDiffA = bint.abs(profitA - (accFeesA + accPseudoLossA))
            local profitDiffB = bint.abs(profitB - (accFeesB + accPseudoLossB))

            printVerb(1)('profit Diff A', tostring(profitDiffA))
            printVerb(1)('profit Diff B', tostring(profitDiffB))

            -- we accept 1 unit of deviation per iteration, regardless of direction (rounding errors)
            assert.is_true(bint.ule(profitDiffA + profitDiffB, bint(iterations)), "lp profit diff too high")

            _G.VerboseTests = 0
        end)

    --[[
        We test the IMPERMANENT LOSS => we expect it to be reflected in the returns after LP burning

        Setup: the pool has preexisting liquidity,

        2 users provide additional liquidity, thereby
        becoming holders of 40% and 10% of pool shares.

        Many swaps are performed.

        User 1 burns (redeems their pool share)

        We assert that the imbalance (reserves ratio) in the reserves before burning
         - is reflected in the imbalance of redeemed liquidity for user 1 => the impermanent loss translates into a permanent loss
         - remains the same for the reserves after burning
    ]]
    it("provide, perform many swaps, and burn - impernanent loss reflected in redeemed liquidity", function()
        local verbosity = 0
        local pair = pool.getPair()

        _G.VerboseTests = verbosity

        -- Provide liquidity
        -- preexisting liquidity = bint(500) & bint(1000)
        -- provider 1 and 2 together provide the same liquidity on top

        -- after providing we'll have
        -- preexisting -> 50% of pool
        -- provider 1 -> 40% of pool
        -- provider 2 -> 10% of pool
        local addLiquidityA1 = bint(400) * POOL_SIZE_SCALER
        local addLiquidityA2 = bint(100) * POOL_SIZE_SCALER
        local addLiquidityB1 = bint(800) * POOL_SIZE_SCALER
        local addLiquidityB2 = bint(200) * POOL_SIZE_SCALER

        printVerb(1)("= = = = Provide/swap/burn = = = =")

        printVerb(1)("Reserves PRE-PROVIDE")
        printVerb(1)("A: ", _G.Reserves[pair[1]])
        printVerb(1)("B: ", _G.Reserves[pair[2]])


        printVerb(1)("Providing liquidity 1:")
        printVerb(1)("A: ", addLiquidityA1)
        printVerb(1)("B: ", addLiquidityB1)

        local provideResult1 = provide.executeProvide(
            pair[1], pair[2],
            addLiquidityA1, addLiquidityB1,
            "provider1",
            0.01
        )

        printVerb(1)("Providing liquidity 2:")
        printVerb(1)("A: ", addLiquidityA2)
        printVerb(1)("B: ", addLiquidityB2)

        local provideResult2 = provide.executeProvide(
            pair[1], pair[2],
            addLiquidityA2, addLiquidityB2,
            "provider2",
            0.01
        )

        printVerb(1)("Reserves POST-PROVIDE")
        local preSwapReservesA = _G.Reserves[pair[1]]
        local preSwapReservesB = _G.Reserves[pair[2]]
        printVerb(1)("A: ", preSwapReservesA)
        printVerb(1)("B: ", preSwapReservesB)

        -- Perform many swaps
        local totalInputQtyA = bint(0)
        local totalOutputQtyA = bint(0)
        local totalProtocolFeeQtyA = bint(0)

        local totalInputQtyB = bint(0)
        local totalOutputQtyB = bint(0)
        local totalProtocolFeeQtyB = bint(0)

        printVerb(1)('- - - EXECUTE 1000 random SWAPS (bi-directional)')
        for i = 1, 100 do
            local isAtoB = math.random() > 0.5

            local tokenIn = isAtoB and pair[1] or pair[2]

            local inputQty = bint.ipow(bint(math.random(1000, 10000)), bint(5))

            local expectedOutput = poolGetOutputOnSwap(inputQty, tokenIn)

            local swapResult = swap.executeSwapWithMinOutput(tokenIn, inputQty, expectedOutput)
            assert.Equal(expectedOutput, swapResult.outputQty)

            if isAtoB then
                totalInputQtyA = totalInputQtyA + inputQty
                totalOutputQtyB = totalOutputQtyB + swapResult.outputQty
                totalProtocolFeeQtyA = totalProtocolFeeQtyA + swapResult.protocolFeeQty
            else
                totalInputQtyB = totalInputQtyB + inputQty
                totalOutputQtyA = totalOutputQtyA + swapResult.outputQty
                totalProtocolFeeQtyB = totalProtocolFeeQtyB + swapResult.protocolFeeQty
            end
        end

        printVerb(1)("Total input  (A):", totalInputQtyA)
        printVerb(1)("Total input  (B):", totalInputQtyB)
        printVerb(1)("Total output (A):", totalOutputQtyA)
        printVerb(1)("Total output (B):", totalOutputQtyB)
        printVerb(1)("Total protocol fees   (A):", totalProtocolFeeQtyA)
        printVerb(1)("Total protocol fees   (B):", totalProtocolFeeQtyB)

        --[[
            Verify reserves after swaps

            Swaps should have affected reserves as follows:
            - swap input increases the reserve of the input token
                -> but not by the full input qty, since PROTOCOL fees are deducted and transferred out of the pool immediately
            - swap output decreases the reserve of the output token
                -> the full swap output amount leaves the pool reserve
        ]]
        local preBurnReserveA = _G.Reserves[pair[1]]
        local preBurnReserveB = _G.Reserves[pair[2]]
        local ratioPrecision = bint.ipow(bint(10), bint(18))
        local preBurnReservesRatio = bint.udiv(preBurnReserveB * ratioPrecision, preBurnReserveA)

        -- Burn liquidity
        printVerb(1)('- - - BURN provided liquidity for provider 1')
        local burnResult1 = burn.executeBurn(
            provideResult1.lpTokensMinted,
            'provider1'
        )

        -- Calculate expected returns
        -- base share issuance calculation on tokenA liquidity rather than on total liquidity,
        -- since we take the same approach in calculateLpTokensToMint()

        local SCALE_FACTOR = bint("1000000")
        local totalLiquidityA = initialReserveAO + addLiquidityA1 + addLiquidityA2
        printVerb(1)('totalLiquidityA:', totalLiquidityA)

        local postBurnReserveA = _G.Reserves[pair[1]]
        local postBurnReserveB = _G.Reserves[pair[2]]
        local postBurnReservesRatio = bint.udiv(postBurnReserveB * ratioPrecision, postBurnReserveA)

        local burnReturnRatio = bint.udiv(burnResult1.withdrawnTokenB * ratioPrecision, burnResult1.withdrawnTokenA)

        assert.is_true(preBurnReservesRatio == postBurnReservesRatio, 'Reserves Ratios pre and post burn are different')
        assert.is_true(preBurnReservesRatio == burnReturnRatio,
            'Burn returns and pre-burn reserves have different ratios')
        _G.VerboseTests = 0
    end)
end)
