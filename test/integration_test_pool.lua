---@diagnostic disable: duplicate-set-field
require("test.setup")()

_G.VerboseTests = 0
_G.TestStartTime = os.time()
_G.VirtualTime = os.time()

_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in the application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.Owner = '123Owner321'
_G.User = '123User321'
_G.MainProcessId = 'xyzPoolzyx'         -- pool process

_G.ao = require "ao" (_G.MainProcessId) -- make global so that the main process and its non-mocked modules can use it
-- => every ao.send({}) in this test file effectively appears as if the message comes the main process

_G.Handlers = require "handlers"
_G.aos = require "aos"

-- MOCKED USER WALLETS

_G.LastMsgToOwner = nil
_G.LastMsgToUser = nil

-- MOCKED PROCESSES

_G.AoCredProcessId = 'AoCred-123xyz'
_G.BarkTokenProcessId = '8p7ApPZxC_37M06QHVejCQrKsHbcJEerd3jWNkDUWPQ'

local aoCredInitial = {
  [_G.Owner] = "1000000000", -- 1 million units ~ 1000 AOCRED
  [_G.User] = "1000000000",  -- 1 million units ~ 1000 AOCRED
  [_G.MainProcessId] = "0"
}

local barkInitial = {
  [_G.Owner] = "1000000000", -- 1 million units ~ 1000 BRKTST
  [_G.User] = "1000000000",  -- 1 million units ~ 1000 BRKTST
  [_G.MainProcessId] = "0"
}

_G.Processes = {
  [_G.AoCredProcessId] = require 'token' (_G.AoCredProcessId, 'AOCRED', aoCredInitial),
  [_G.BarkTokenProcessId] = require 'token' (_G.BarkTokenProcessId, 'BRKTST', barkInitial),
}

_G.ao.env = {
  Process = {
    Tags = {
      ["Name"] = "Bark v2 LP " .. string.sub(AoCredProcessId, 1, 6) .. "..." .. string.sub(BarkTokenProcessId, 1, 6),
      ["Token-A"] = _G.AoCredProcessId,
      ["Token-B"] = _G.BarkTokenProcessId,
      ["Dexi-Token"] = "Dexi-Token-Process-Id",
      ["Fee-Bps"] = "25"
    }
  }
}

local main = require "amm.main" -- require so that process handlers are loaded, as well as global variables
local token = require "amm.token.token"
local pool = require "amm.pool.pool"
local swap = require "amm.pool.swap"
local provide = require "amm.pool.provide"
local burn = require "amm.pool.burn"

local bint = require "utils.tl-bint" (256)

-- INTEGRATION TESTS (mocked token processes)
-- Global state is preserved across tests below --> order is important

describe("basic swap functionality", function()
  -- start with a 1/2 ratio for AO/Bark
  -- AO 50 Million units
  local initialReserveAO   = bint("5000000")
  -- Bark 100 Million units
  local initialReserveBark = bint("10000000")
  --   => K = 50 * 10 ^ 12

  setup
  (function()
    -- INITIALIZE WITH POOL RESERVES / LP TOKEN BALANCES
    local pair = pool.getPair()

    provide.executeProvide(
      pair[1], pair[2],
      initialReserveAO, initialReserveBark,
      "initializer", 0.1
    )
  end)

  teardown(function()
    -- not needed if we stick to 1 describe block per *_test.lua
  end)

  before_each(function()
  end)

  after_each(function()
  end)

  it("should return the lp token info", function()
    local tokenInfo = token.info()

    assert.Equal(tokenInfo.Ticker, "Bark v2 LP AoCred...8p7ApP")
    assert.Equal(tokenInfo.Name, "Bark v2 LP AoCred...8p7ApP")
    assert.Equal(tokenInfo.Logo, "fTKfocxQs94bj444uVDiVKSZQ8bKu4rqkx5hHhjIYrw")
    assert.Equal(tokenInfo.Denomination, '12')
    assert.Equal(tokenInfo.TokenA, _G.AoCredProcessId)
    assert.Equal(tokenInfo.TokenB, _G.BarkTokenProcessId)
  end)

  it("should error when providing", function()
    local pair = pool.getPair()

    -- Add the same pool again
    local status, error = pcall(function()
      provide.executeProvide(
        pair[1], pair[2],
        bint(5000000), bint(10000000),
        "provider", -1
      )
    end)

    assert.Same(status, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error:find("Invalid slippage tolerance percentage"))
  end)



  it("should provide and swap and burn", function()
    local pair = pool.getPair()

    -- - - - PROVIDE

    local addLiquidityA = bint(5000000)
    local addLiquidityB = bint(10000000)

    printVerb(1)('pairs', pair[1], pair[2])
    local provideResult = provide.executeProvide(
      pair[1], pair[2],
      addLiquidityA, addLiquidityB,
      "provider", 0.01
    )

    assert.Equal(addLiquidityA, provideResult.actualQuantityA)
    assert.Equal(addLiquidityB, provideResult.actualQuantityB)

    -- - - - SWAP

    local inputQty = bint("10000")

    -- relying on pool calculations for output & fees (they are tested in the unit tests)
    local inputQtyFeeAdjusted, lpFee, protocolFee = pool.deductFees(inputQty)
    local totalFee = inputQty - inputQtyFeeAdjusted
    local expectedOutput = pool.getOutput(inputQtyFeeAdjusted, _G.AoCredProcessId)

    local swapResult = swap.executeSwapWithMinOutput(_G.AoCredProcessId, inputQty, expectedOutput)

    assert.Equal(expectedOutput, swapResult.outputQty)

    assert.Equal(totalFee, swapResult.totalFeeQty)

    local reserveIncreaseOnProvideA = inputQty - protocolFee
    local reserveDecreaseOnProvideB = swapResult.outputQty

    assert.Equal(
      bint(initialReserveAO) + addLiquidityA + reserveIncreaseOnProvideA,
      _G.Reserves[pair[1]]
    )

    assert.Equal(
      bint(initialReserveBark) + addLiquidityB - reserveDecreaseOnProvideB,
      _G.Reserves[pair[2]]
    )

    -- -- - - - BURN LP TOKENS (WITHDRAW LIQUIDITY)

    local preBurnReservesA = _G.Reserves[pair[1]]
    local preBurnReservesB = _G.Reserves[pair[2]]

    local burnResult = burn.executeBurn(
      provideResult.lpTokensMinted,
      'provider'
    )

    printVerb(1)('withdrawn token a', burnResult.withdrawnTokenA, 'withdrawn token b', burnResult.withdrawnTokenB)

    -- half the liquidity belongs to 'provider' -> swap amounts have affected the liquidity of 'provider'

    local swapIncreasedLiquidityA = bint.udiv(inputQty - protocolFee, bint(2))
    local swapDecreasedLiquidityB = bint.udiv(swapResult.outputQty, bint(2))

    local burnReturnA = addLiquidityA + swapIncreasedLiquidityA
    local burnReturnB = addLiquidityB - swapDecreasedLiquidityB

    assert.Equal(
      burnResult.withdrawnTokenA,
      burnReturnA
    )

    assert.Equal(
      burnResult.withdrawnTokenB,
      burnReturnB
    )

    printVerb(1)('halfInput', swapIncreasedLiquidityA)

    assert.Equal(
      preBurnReservesA - burnReturnA,
      _G.Reserves[pair[1]]
    )

    assert.Equal(
      preBurnReservesB - burnReturnB,
      _G.Reserves[pair[2]]
    )


    assert.Equal(
      initialReserveAO + reserveIncreaseOnProvideA - swapIncreasedLiquidityA,
      _G.Reserves[pair[1]]
    )

    assert.Equal(
      initialReserveBark - reserveDecreaseOnProvideB + swapDecreasedLiquidityB,
      _G.Reserves[pair[2]]
    )
  end)
end)
