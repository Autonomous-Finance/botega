---@diagnostic disable: duplicate-set-field
require("test.setup")()
local json = require("json")

_G.VerboseTests = 0
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in the application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.Owner = 'test_owner_id'
_G.User = 'dexi_owner_id'
_G.MainProcessId = 'amm_factory_id' -- pool process

_G.Handlers = require "handlers"
_G.aos = require "aos"

-- MOCKED PROCESSES

_G.AoCredProcessId = 'AoCred-123xyz'
_G.BarkTokenProcessId = '8p7ApPZxC_37M06QHVejCQrKsHbcJEerd3jWNkDUWPQ'

_G.OutboxLatest = {}
_G.ao = {
  id = _G.MainProcessId,
  env = {
    Module = {
      Id = "test_module_id"
    },
    Process = {
      Tags = {
        ["AMM-Factory"] = "FactoryId",
        ["Name"] = "AOCred-Bark-Testpool",
        ["Token-A"] = _G.AoCredProcessId,
        ["Token-B"] = _G.BarkTokenProcessId,
        ["Dexi-Token"] = "Dexi-Token-Process-Id",
        ["Fee-Bps"] = "25"
      }
    }
  },
  -- this is to keep track of what is sent out
  send = function(msg)
    if msg.Target then
      _G.OutboxLatest[msg.Target] = msg
    else
      _G.OutboxLatest[msg.device] = msg
    end
  end,
}

require "amm.main" -- require so that process handlers are loaded, as well as global variables
local pool = require "amm.pool.pool"
local swap = require "amm.pool.swap"
local bint = require "utils.tl-bint" (256)


-- UNIT TESTS FOR SWAPS

-- acceptance
describe("validity of swap credit notices", function()
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
    _G.OutboxLatest = {}
    _G.Reserves = {
      tokenA = bint(1000),
      tokenB = bint(90)
    }
  end)


  it("should only accept properly formatted swap requests", function()
    local pair = pool.getPair()

    -- rejects as deprecated X-Expected-Output
    local status, error = pcall(function()
      swap.swap({
        From = pair[1],
        Tags = {
          ["X-Expected-Output"] = "123"
        }
      })
    end)
    assert.Same(status, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error:find("X-Expected-Output is disabled, use X-Expected-Min-Output instead", 1, true))


    -- missing X-Expected-Min-Output
    local status2, error2 = pcall(function()
      swap.swap({
        From = pair[1],
        Tags = {}
      })
    end)
    assert.Same(status2, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error2:find("X-Expected-Min-Output is not present", 1, true))

    -- only the pool tokens
    local rt = "RandomToken"
    assert(pair[1] ~= rt and pair[2] ~= rt)
    local status3, error3 = pcall(function()
      swap.swap({
        From = rt,
        Tags = {
          ["X-Expected-Min-Output"] = "123",
        }
      })
    end)
    assert.Same(status3, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error3:find("This pool does not support this token", 1, true))

    -- invalid amount
    local status4, error4 = pcall(function()
      swap.swap({
        From = pair[1],
        Tags = {
          ["X-Expected-Min-Output"] = "123a",
        }
      })
    end)
    assert.Same(status4, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error4:find("value cannot be represented by a bint", 1, true))
  end)
end)

-- basic output calculation
describe("pool output calculation", function()
  local originalGetPair
  setup(function()
    originalGetPair = pool.getPair

    pool.getPair = function()
      return { "tokenA", "tokenB" }
    end

    _G.Reserves = {
      tokenA = bint(1000),
      tokenB = bint(90)
    }
  end)
  teardown(function()
    pool.getPair = originalGetPair
  end)

  it("should return the lp fee percentage", function()
    assert.Equal(pool.getLPFeePercentage(), 0.25)
  end)

  it("should return the protocol fee percentage", function()
    assert.Equal(pool.getProtocolFeePercentage(), 0)
  end)

  it("should return K", function()
    assert.Equal(tostring(pool.K()), "90000")
  end)

  it("Fails on a swap if output is below the specified minimum", function()
    local pair = pool.getPair()

    local input = "456"

    local inputExcludingFees = pool.deductFees(bint(input))
    local expOutput = pool.getOutput(inputExcludingFees, pair[1])

    local originalGetOutput = pool.getOutput
    pool.getOutput = function(fee, token)
      return originalGetOutput(fee, token) -
          bint(1) -- make it so that it's less than expected; even 1 unit of deviation should make it fail
    end

    local status, error = pcall(function()
      swap.swap({
        From = pair[1],
        Tags = {
          ["X-Expected-Min-Output"] = tostring(expOutput),
          Quantity = input,
        }
      })
    end)
    assert.Same(status, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error:find("Could not swap with expected min output", 1, true))

    pool.getOutput = originalGetOutput
  end)

  -- hand picked
  it("should deduct fees from an input using precision of 100 (basis points), while rounding due to integer division",
    function()
      --[[
        fee = lp + protocol = 0.25 + 0 = 0.25

        Testing marginal changes to inputQty
        INTERNALLY we have:

        inputAfter = inputBefore * (100 - fee) * 100 / (100 * 100)           (INTEGER DIVISION)

        integer division rounds down the INPUT AMOUNT, which is equivalent to
        the EFFECTIVE FEE AMOUNT being rounded up for any decimals beyond the basis point accuracy
      ]]
      local quantitiesBeforeAndEffectiveFees = {
        ["10000"] = "25", -- 25.00
        ["10001"] = "26", -- 25.0025
        ["10399"] = "26", -- 25.9975
        ["10400"] = "26", -- 26.0

        ["10401"] = "27", -- 26.0025

        ["20000"] = "50", -- 50.00
        ["20001"] = "51", -- 50.0025
        ["20399"] = "51", -- 50.9975
        ["20400"] = "51", -- 51.0

        ["20401"] = "52", -- 51.0025
      }
      for quantity, expectedFee in ipairs(quantitiesBeforeAndEffectiveFees) do
        assert.Equal(tostring(pool.deductFees(quantity)), tostring(tonumber(quantity) - tonumber(expectedFee)))
      end
    end)

  -- fuzzed
  -- it("should deduct fees from an input with precision of 100, while rounding up the deducted fee amount",
  --   function()
  --     local quantities = {}
  --     for _ = 1, 50 do
  --       table.insert(quantities, math.random(1000, 100000))
  --     end
  --     for _, quantity in ipairs(quantities) do
  --       local feePercentage = pool.getLPFeePercentage() + pool.getProtocolFeePercentage()
  --       local feePart = math.ceil(tonumber(quantity) * feePercentage * 100 / 10000)
  --       assert.Equal(tostring(pool.deductFees(quantity)), tostring(tonumber(quantity) - feePart))
  --     end
  --   end)

  -- hand picked
  it("should calc the swap output - handpicked", function()
    local inputsAndExps = {
      [100] = "8",
      [10] = "0",
      [1] = "0",
      [0] = "0",
      [1000] = "45",
      [2000] = "60",
    }
    for input, expectedOutput in pairs(inputsAndExps) do
      assert.Equal(tostring(pool.getOutput(bint(input), "tokenA")), expectedOutput)
    end
  end)

  -- fuzzed
  it("should calc the swap output - fuzzed", function()
    -- for the small amounts in this example we can use numbers instead of bints
    local function calcOut(inAmount, token)
      local reservesA = bint.tonumber(_G.Reserves['tokenA'])
      local reservesB = bint.tonumber(_G.Reserves['tokenB'])
      local reservesIn = token == 'tokenA' and reservesA or reservesB
      local reservesOut = token == 'tokenA' and reservesB or reservesA
      local K = bint.tonumber(pool.K())

      local outAmount = math.floor(reservesOut - K / (reservesIn + inAmount))
      return tostring(outAmount)
    end

    local swaps = {}
    for _ = 1, 100 do
      local inputQty = math.random(1, 10000)
      local tokenIn = math.random() < 0.5 and "tokenA" or "tokenB"
      local outputQty = calcOut(inputQty, tokenIn)
      table.insert(swaps, { input = tostring(inputQty), token = tokenIn, output = tostring(outputQty) })
    end
    for _, swap in ipairs(swaps) do
      assert.Equal(tostring(pool.getOutput(bint(swap.input), swap.token)), swap.output)
    end
  end)
end)

-- edge cases where output would be < 1 unit
describe("pool last ever swap", function()
  local originalGetPair
  setup(function()
    originalGetPair = pool.getPair

    pool.getPair = function()
      return { "tokenA", "tokenB" }
    end

    _G.Reserves = {
      tokenA = bint(100),
      tokenB = bint(1)
    }
  end)
  teardown(function()
    pool.getPair = originalGetPair
  end)

  it("should return the lp fee percentage", function()
    assert.Equal(pool.getLPFeePercentage(), 0.25)
  end)

  it("should return the protocol fee percentage", function()
    assert.Equal(pool.getProtocolFeePercentage(), 0)
  end)

  it("should return K", function()
    assert.Equal(tostring(pool.K()), "100")
  end)

  -- hand picked
  it("should calc the output", function()
    local inputsAndExps = {
      [100] = "0",
      [10] = "0",
      [1] = "0",
      [0] = "0",
      [1000] = "0",
      [2000] = "0",
    }
    for input, expectedOutput in pairs(inputsAndExps) do
      -- print('input', input)
      -- print('expectedOutput', expectedOutput)
      -- print('output', pool.getOutput(bint(input), "tokenA"))
      -- print('///////')
      assert.Equal(tostring(pool.getOutput(bint(input), "tokenA")), expectedOutput)
    end
  end)
end)



describe("sanity checks with real bark pool reserves", function()
  local originalGetPair

  setup(function()
    originalGetPair = pool.getPair

    pool.getPair = function()
      return {
        "tokenA", -- AOCRED
        "tokenB"  -- BRK
      }
    end

    _G.Reserves = {
      tokenA = bint('3630252'),
      tokenB = bint('63338960')
    }
  end)

  teardown(function()
    pool.getPair = originalGetPair
  end)

  -- hand picked
  it("sanity check outputs with real amm", function()
    -- checked these outputs against an independant constant product amm calculator
    -- https://amm-calculator.vercel.app/
    local baseAmount = bint(1000)
    local allTheTokens = _G.Reserves.tokenB

    local inputsAndExps = {
      [baseAmount] = bint(57),
      [baseAmount * bint(100)] = bint(5722),
      [baseAmount * bint(1000)] = bint(56423),
      [baseAmount * bint(5000)] = bint(265606),
      [baseAmount * bint(7500)] = bint(384349),
      [baseAmount * bint(10000)] = bint(494996),
      [allTheTokens] = bint(1815126),
      [bint('1000000000000000000000000')] = _G.Reserves.tokenA - bint(1),
    }

    for input, expectedOutput in pairs(inputsAndExps) do
      assert.Equal(pool.getOutput(input, "tokenB"), expectedOutput)
    end
  end)
end)


describe("sanity checks with real 0rbit pool reserves (very imbalanced)", function()
  local originalGetPair

  local initialReserveA = bint('16184')
  local initialReserveB = bint('30957060795679')

  setup(function()
    originalGetPair = pool.getPair

    pool.getPair = function()
      return {
        "tokenA", -- AOCRED
        "tokenB"  -- BRK
      }
    end

    _G.Reserves = {
      tokenA = initialReserveA,
      tokenB = initialReserveB,
    }
  end)

  teardown(function()
    pool.getPair = originalGetPair
  end)



  -- hand picked
  it("sanity check outputs with real amm", function()
    -- checked these outputs against an independant constant product amm calculator
    -- https://amm-calculator.vercel.app/
    local baseAmount = bint(1000)
    local k = pool.K()

    assert.Equal(k, bint(501009071917268936))

    printVerb(1)(k)

    assert.Equal(pool.getOutput(bint(1), "tokenA"), bint(1912700697))
    assert.Equal(pool.getOutput(baseAmount, "tokenA"), bint(1801504934571))
    assert.Equal(pool.getOutput(baseAmount, "tokenB"), bint(0))
  end)
end)
