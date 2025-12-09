---@diagnostic disable: duplicate-set-field
require("test.setup")()

_G.IsInUnitTest = true -- prevent ao.send from attempting to execute
_G.VerboseTests = 0
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.MainProcessId = '123Pool321'
-- make global so that the main process and the non-mocked dependencies can use it for `ao.send()`
_G.ao = {
  id = _G.MainProcessId,
  env = {
    Module = {
      Id = "test_module_id"
    },
    Process = {
      ["Owner"] = "test_owner_id"
    }
  },
  -- this is to keep track of what is sent out
  send = function(msg)
    _G.OutboxLatest[msg.Target] = msg
  end
}

local pool = require "amm.pool.pool"
local provide = require "amm.pool.provide"
local burn = require "amm.pool.burn"
local balance = require "amm.token.balance"
local bint = require "utils.tl-bint" (256)
local bintmath = require "utils.bintmath"


-- UNIT TESTS FOR LIQUIDITY PROVISION


local resetGlobals = function()
  _G.Reserves = {
    tokenA = bint('0'),
    tokenB = bint('0')
  }
  _G.Balances = {}
end

describe("pool provide logic: ", function()
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
    resetGlobals()
  end)

  it("initial provide executes correctly", function()
    local qtyA = bint.ipow(bint(10), bint(6))
    local qtyB = bint.ipow(bint(10), bint(6)) * bint(3)
    local provideResult = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA,
      qtyB,
      "sender",
      0.01
    )

    assert.Equal(qtyA, provideResult.actualQuantityA)
    assert.Equal(qtyB, provideResult.actualQuantityB)
    assert.Equal(qtyA, _G.Reserves['tokenA'])
    assert.Equal(qtyB, _G.Reserves['tokenB'])

    local expSupply = bintmath.sqrt(qtyA * qtyB)
    assert.Equal(expSupply, provideResult.lpTokensMinted)
    assert.Equal(expSupply, balance.totalSupply())
  end)

  it("subsequent provide executes correctly", function()
    local qtyA1 = bint.ipow(bint(10), bint(6))
    local qtyB1 = bint.ipow(bint(10), bint(6)) * bint(3)
    local provideResult1 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "sender",
      0.01
    )

    local qtyA2 = bint.ipow(bint(10), bint(3))
    local qtyB2 = bint.ipow(bint(10), bint(3)) * bint(3)
    local provideResult2 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA2,
      qtyB2,
      "sender",
      0.01
    )

    assert.Equal(qtyA2, provideResult2.actualQuantityA)
    assert.Equal(qtyB2, provideResult2.actualQuantityB)
    assert.Equal(qtyA1 + qtyA2, _G.Reserves['tokenA'])
    assert.Equal(qtyB1 + qtyB2, _G.Reserves['tokenB'])

    local supplyAfter1 = bintmath.sqrt(qtyA1 * qtyB1)
    local reservesABefore2 = qtyA1
    local supplyOn2 = bint.udiv(supplyAfter1 * qtyA2, reservesABefore2)
    assert.Equal(supplyOn2, provideResult2.lpTokensMinted)
    local expSupply = supplyAfter1 + supplyOn2
    assert.Equal(expSupply, balance.totalSupply())
  end)

  it("adjusts provide input A when it is in excess, within slippage tolerance limit", function()
    local qtyA1 = bint.ipow(bint(10), bint(6))
    local qtyB1 = bint.ipow(bint(10), bint(6)) * bint(3)
    local provideResult1 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "sender",
      0.01
    )

    -- now reserves ratio is A/B = 1/3

    -- provide like before, but with 123 excess quantity for A
    local qtyA2 = qtyA1 + bint(123)
    local qtyB2 = qtyB1
    -- 0.5 %    i.e. 0.005    i.e.    for token A: 5000.615 >= 123    so we are within limits with our excess amount
    local slippageTolerance = 0.5
    local provideResult2 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA2,
      qtyB2,
      "sender",
      slippageTolerance
    )

    assert.Equal(qtyA1, provideResult2.actualQuantityA) -- A qty was reduced
    assert.Equal(qtyB2, provideResult2.actualQuantityB) -- B qty was preserved

    assert.Equal(qtyA1 + qtyA1, _G.Reserves['tokenA'])
    assert.Equal(qtyB1 + qtyB2, _G.Reserves['tokenB'])

    local supplyAfter1 = bintmath.sqrt(qtyA1 * qtyB1)
    local reservesABefore2 = qtyA1
    local inputAOn2 = qtyA1
    local supplyOn2 = bint.udiv(supplyAfter1 * inputAOn2, reservesABefore2)
    assert.Equal(supplyOn2, provideResult2.lpTokensMinted)
    local expSupply = supplyAfter1 + supplyOn2
    assert.Equal(expSupply, balance.totalSupply())
  end)


  it("adjusts provide input B when it is in excess, within slippage tolerance limit", function()
    local qtyA1 = bint.ipow(bint(10), bint(6))
    local qtyB1 = bint.ipow(bint(10), bint(6)) * bint(3)
    provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "sender",
      0.01
    )

    -- now reserves ratio is A/B = 1/3

    -- provide like before, but with 123 excess quantity for B
    local qtyA2 = qtyA1
    local qtyB2 = qtyB1 + bint(123)
    -- 0.5 %    i.e. 0.005    i.e.    for token A: 15001.845 >= 123    so we are within limits with our excess amount
    local slippageTolerance = 0.5
    local provideResult2 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA2,
      qtyB2,
      "sender",
      slippageTolerance
    )

    assert.Equal(qtyA2, provideResult2.actualQuantityA) -- A qty was preserved
    assert.Equal(qtyB1, provideResult2.actualQuantityB) -- B qty was reduced

    assert.Equal(qtyA1 + qtyA2, _G.Reserves['tokenA'])
    assert.Equal(qtyB1 + qtyB1, _G.Reserves['tokenB'])

    local supplyAfter1 = bintmath.sqrt(qtyA1 * qtyB1)
    local reservesABefore2 = qtyA1
    local inputAOn2 = qtyA2
    local supplyOn2 = bint.udiv(supplyAfter1 * inputAOn2, reservesABefore2)
    assert.Equal(supplyOn2, provideResult2.lpTokensMinted)
    local expSupply = supplyAfter1 + supplyOn2
    assert.Equal(expSupply, balance.totalSupply())
  end)

  it("cannot adjust provide input A when it is in excess beyond slippage tolerance limit", function()
    local qtyA1 = bint.ipow(bint(10), bint(6))
    local qtyB1 = bint.ipow(bint(10), bint(6)) * bint(3)
    provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "sender",
      0.01
    )

    -- now reserves ratio is A/B = 1/3

    -- provide like before, but with 5100 excess quantity for A
    local qtyA2 = qtyA1 + bint(5100)
    local qtyB2 = qtyB1

    -- we would have to reduce A by 5100, which means actualQtyA = qtyA2 - 5100, which means we slip 5100 / 1005100 ~ 0.507 %
    -- => we are beyond the 0.5 % threshold
    local slippageTolerance = 0.5

    local provideAttempt = function()
      provide.executeProvide(
        "tokenA",
        "tokenB",
        qtyA2,
        qtyB2,
        "sender",
        slippageTolerance
      )
    end

    assert.has_error(provideAttempt, "Could not provide liquidity within the given slippage tolerance")
  end)


  it("cannot adjust provide input B when it is in excess beyond slippage tolerance limit", function()
    local qtyA1 = bint.ipow(bint(10), bint(6))
    local qtyB1 = bint.ipow(bint(10), bint(6)) * bint(3)
    provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "sender",
      0.01
    )

    -- now reserves ratio is A/B = 1/3

    -- provide like before, but with 15300 excess quantity for B
    local qtyA2 = qtyA1
    local qtyB2 = qtyB1 + bint(15300)

    -- we would have to reduce A by 15300, which means actualQtyA = qtyA2 - 15300, which means we slip 15300 / 1015300 ~ 0.507 %
    -- => we are beyond the 0.5 % threshold
    local slippageTolerance = 0.5

    local provideAttempt = function()
      provide.executeProvide(
        "tokenA",
        "tokenB",
        qtyA2,
        qtyB2,
        "sender",
        slippageTolerance
      )
    end

    assert.has_error(provideAttempt, "Could not provide liquidity within the given slippage tolerance")
  end)

  --[[
    provider 1: 5 & 15  - 50%

    provider 2: 4 & 12  - 40%

    provider 3: 1 & 3   - 10%

    AFTER BURN of provider 2

    provider 1: 5/6
    provider 2: 1/6

    We check that, after burning of provider 2
      - the redeemed value is the same as the deposited value
      - the lp shares are correct
  ]]
  it("burning - fee shares are updated correctly", function()
    local qtyA1 = bint(5) * bint.ipow(bint(10), bint(18))
    local qtyB1 = bint(15) * bint.ipow(bint(10), bint(18))
    local provideResult1 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA1,
      qtyB1,
      "provider1",
      0.01
    )

    local qtyA2 = bint(4) * bint.ipow(bint(10), bint(18))
    local qtyB2 = bint(12) * bint.ipow(bint(10), bint(18))
    local provideResult2 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA2,
      qtyB2,
      "provider2",
      0.01
    )

    local qtyA3 = bint(1) * bint.ipow(bint(10), bint(18))
    local qtyB3 = bint(3) * bint.ipow(bint(10), bint(18))
    local provideResult3 = provide.executeProvide(
      "tokenA",
      "tokenB",
      qtyA3,
      qtyB3,
      "provider3",
      0.01
    )

    -- RESERVES
    assert.Equal(qtyA1 + qtyA2 + qtyA3, _G.Reserves['tokenA'])
    assert.Equal(qtyB1 + qtyB2 + qtyB3, _G.Reserves['tokenB'])

    -- MINTED LP SHARES
    local supplyOn1 = bintmath.sqrt(qtyA1 * qtyB1)
    local supplyAfter1 = supplyOn1
    local reservesABefore2 = qtyA1
    local supplyOn2 = bint.udiv(supplyAfter1 * qtyA2, reservesABefore2)
    assert.Equal(supplyOn2, provideResult2.lpTokensMinted)
    local supplyAfter2 = supplyAfter1 + supplyOn2
    local reservesABefore3 = qtyA1 + qtyA2
    local supplyOn3 = bint.udiv(supplyAfter2 * qtyA3, reservesABefore3)
    assert.Equal(supplyOn3, provideResult3.lpTokensMinted)
    local supplyAfter3 = supplyAfter1 + supplyOn2 + supplyOn3
    assert.Equal(supplyAfter3, balance.totalSupply())

    -- SHARE RATIOS
    local shares1 = _G.Balances['provider1']
    local shares2 = _G.Balances['provider2']
    local shares3 = _G.Balances['provider3']
    assert.Equal(shares1, provideResult1.lpTokensMinted)
    assert.Equal(shares2, provideResult2.lpTokensMinted)
    assert.Equal(shares3, provideResult3.lpTokensMinted)

    local scaleFactor = bint.ipow(bint(10), bint(18))
    local totalShares = balance.totalSupply()
    local shareRatio1 = bint.udiv(shares1 * scaleFactor, totalShares)
    local shareRatio2 = bint.udiv(shares2 * scaleFactor, totalShares)
    local shareRatio3 = bint.udiv(shares3 * scaleFactor, totalShares)
    local expRatio1 = bint.udiv(bint(50) * scaleFactor, bint(100))
    local expRatio2 = bint.udiv(bint(40) * scaleFactor, bint(100))
    local expRatio3 = bint.udiv(bint(10) * scaleFactor, bint(100))

    -- we accept a deviation of 1 unit due to rounding errors
    assert.is_true(bint.abs(expRatio1 - shareRatio1):ule(bint(1)))
    assert.is_true(bint.abs(expRatio2 - shareRatio2):ule(bint(1)))
    assert.is_true(bint.abs(expRatio3 - shareRatio3):ule(bint(1)))

    -- BURN
    local burnResult = burn.executeBurn(
      provideResult2.lpTokensMinted,
      'provider2'
    )

    -- redeemed value
    local redeemedA = burnResult.withdrawnTokenA
    local redeemedB = burnResult.withdrawnTokenB
    -- we accept a deviation of 1 unit due to rounding errors
    assert.is_true(bint.abs(qtyA2 - redeemedA):ule(bint(1)))
    assert.is_true(bint.abs(qtyB2 - redeemedB):ule(bint(1)))

    -- remaining shares
    local shares1PostBurn = _G.Balances['provider1']
    local shares2PostBurn = _G.Balances['provider2']
    local shares3PostBurn = _G.Balances['provider3']

    assert.Equal(shares1PostBurn, shares1)
    assert.Equal(shares3PostBurn, shares3)
    assert.Equal(shares2PostBurn, bint(0))

    local totalSharesPostBurn = balance.totalSupply()
    local shareRatio1PostBurn = bint.udiv(shares1PostBurn * scaleFactor, totalSharesPostBurn)
    local shareRatio3PostBurn = bint.udiv(shares3PostBurn * scaleFactor, totalSharesPostBurn)

    local expRatio1PostBurn = bint.udiv(bint(5) * scaleFactor, bint(6))
    local expRatio3PostBurn = bint.udiv(bint(1) * scaleFactor, bint(6))

    -- we accept a deviation of 1 unit due to rounding errors
    assert.is_true(bint.abs(expRatio1PostBurn - shareRatio1PostBurn):ule(bint(1)))
    assert.is_true(bint.abs(expRatio3PostBurn - shareRatio3PostBurn):ule(bint(1)))
  end)
end)
