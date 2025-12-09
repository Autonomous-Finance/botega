---@diagnostic disable: duplicate-set-field
require("test.setup")()

local factory_lib = require "factory.factory_lib"
local json = require "json"

_G.IsInUnitTest = true -- prevent ao.send from attempting to execute
_G.VerboseTests = 0
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end

_G.OutboxLatest = {}
_G.ao = {
  id = _G.MainProcessId,
  -- this is to keep track of what is sent out
  send = function(msg)
    _G.OutboxLatest[msg.Target] = msg
    if msg.Action == "Info" then
      _G.RespMsg = _G.RespMessages.TokenInfo(msg.Target)
    else
      _G.RespMsg = nil
    end
  end,
}

_G.TransientTokenInfo = {
  -- format like this, set within tests
  ["Token-Process-Id"] = {
    ["Ticker"] = "...",
    ["Name"] = "...",
    ["Denomination"] = "...",
    ["X-Reference"] = "..."
  }
}
_G.RespMessages = {
  TokenInfo = function(tokenProcessId)
    return {
      Tags = {
        ["From-Process"] = tokenProcessId,
        -- set values below to the expected values
        ["Ticker"] = _G.TransientTokenInfo[tokenProcessId]["Ticker"],
        ["Name"] = _G.TransientTokenInfo[tokenProcessId]["Name"],
        ["Denomination"] = _G.TransientTokenInfo[tokenProcessId]["Denomination"],
        ["X-Reference"] = _G.TransientTokenInfo[tokenProcessId]["X-Reference"]
      }
    }
  end
}

_G.BarkTokenProcessId = "________________________________________brk"
_G.ArTokenProcessId = "_________________________________________ar"

_G.DEFAULT_LP_FEE = '25'

--[[
  - update on each ao.send (see the mocked ao.send() above)
  - set to the expected resp value if the ao.send() within
      the application code has a associated Receive() in the execution flow
]]
_G.RespMsg = nil
_G.Receive = function(matchFn)
  if matchFn(_G.RespMsg) then
    return _G.RespMsg
  end
  error('Test Setup Error: No matching response on Receive(). RespMsg: ' .. json.encode(_G.RespMsg))
end


local resetGlobals = function()
  _G.Pools = {}
  _G.PoolFeesBps = {}
end

describe("factory lib", function()
  it("should sort tokens", function()
    local tokenA, tokenB = factory_lib.sortTokens("aaa", "bbb")
    assert.Same("aaa", tokenA)
    assert.Same("bbb", tokenB)

    tokenA, tokenB = factory_lib.sortTokens("bbb", "aaa")
    assert.Same("aaa", tokenA)
    assert.Same("bbb", tokenB)

    tokenA, tokenB = factory_lib.sortTokens("0x000", "0x111")
    assert.Same("0x000", tokenA)
    assert.Same("0x111", tokenB)

    tokenA, tokenB = factory_lib.sortTokens("0x111", "0x000")
    assert.Same("0x000", tokenA)
    assert.Same("0x111", tokenB)
  end)

  it("should check if a pool exists", function()
    resetGlobals()

    _G.PoolsByTokens = {
      ["aaa:bbb"] = { [_G.DEFAULT_LP_FEE] = "123" },
    }

    assert.Same(factory_lib.poolExists("aaa", "bbb", _G.DEFAULT_LP_FEE), true)
    assert.Same(factory_lib.poolExists("bbb", "aaa", _G.DEFAULT_LP_FEE), false)
  end)

  it("should discern token compatibility", function()
    resetGlobals()

    -- COMPATIBLE
    _G.TransientTokenInfo[_G.ArTokenProcessId] = {
      ["Ticker"] = "AR",
      ["Name"] = "Arweave",
      ["Denomination"] = "12",
      ["X-Reference"] = "123"
    }

    -- INCOMPATIBLE: missing X-Reference
    _G.TransientTokenInfo[_G.BarkTokenProcessId] = {
      ["Ticker"] = "BRK",
      ["Name"] = "Bark",
      ["Denomination"] = "12"
    }

    local compatibilityCheck1 = factory_lib.checkTokenCompatibility(_G.ArTokenProcessId, _G.BarkTokenProcessId)
    assert.is_true(compatibilityCheck1.isCompatibleA == true)
    assert.is_true(compatibilityCheck1.isCompatibleB == false)

    -- INCOMPATIBLE: non-numeric Denomination
    _G.TransientTokenInfo[_G.ArTokenProcessId] = {
      ["Ticker"] = "AR",
      ["Name"] = "Arweave",
      ["Denomination"] = "abc",
      ["X-Reference"] = "123"
    }

    -- INCOMPATIBLE: wrong Denomination
    _G.TransientTokenInfo[_G.BarkTokenProcessId] = {
      ["Ticker"] = "BRK",
      ["Name"] = "Bark",
      ["Denomination"] = "22",
      ["X-Reference"] = "123"
    }

    local compatibilityCheck2 = factory_lib.checkTokenCompatibility(_G.ArTokenProcessId, _G.BarkTokenProcessId)
    assert.is_true(compatibilityCheck2.isCompatibleA == false)
    assert.is_true(compatibilityCheck2.isCompatibleB == false)
  end)
end)
