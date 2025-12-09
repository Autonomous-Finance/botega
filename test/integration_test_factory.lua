---@diagnostic disable: duplicate-set-field
require("test.setup")()
local json = require("json")

_G.VerboseTests = 0
--
_G.printVerb = function(level)
  level = level or 2
  return function(...) -- define here as global so we can use it in application code too
    if _G.VerboseTests >= level then print(table.unpack({ ... })) end
  end
end
_G.Handlers = require "handlers"
_G.MainProcessId = 'amm_factory_id'
_G.User = 'test_user_id'

_G.OutboxLatest = {}
_G.ao = {
  id = _G.MainProcessId,
  env = {
    Module = {
      Id = "test_module_id"
    },
    Process = {
      ["Owner"] = "test_owner_id",
      Tags = {
        ["Dexi-Token"] = "Dexi-Token-Process-Id",
        ["Dexi"] = "Dexi-Token-Process-Id",
      }
    }
  },
  -- this is to keep track of what is sent out
  send = function(msg)
    -- if msg.device exists skip everything
    if msg.device then return end
    if not msg.Target then print('NO TARGET', json.encode(msg)) end
    _G.OutboxLatest[msg.Target] = msg
    if msg.Action == "Info" then
      _G.RespMsg = _G.RespMessages.TokenInfo(msg.Target)
    elseif msg.Action == "Eval" then
      _G.RespMsg = _G.RespMessages.AmmEval(msg.Target)
    else
      _G.RespMsg = nil
    end

    return {
      receive = function()
        return _G.RespMsg
      end
    }
  end,
  -- this is so that we can do
  -- local spawnResult = ao.spawn().receive()
  spawn = function(msg)
    return {
      receive = _G.SpawnReceiveFn
    }
  end
}

_G.RespMessages = {
  TokenInfo = function(tokenProcessId)
    -- pretend tokenInfo returns these dummy values that pass the compatibility check
    return {
      Tags = {
        ["From-Process"] = tokenProcessId,
        ["Ticker"] = "Ticker",
        ["Name"] = "Name",
        ["Denomination"] = "12",
        ["X-Reference"] = "123",
      }
    }
  end
}


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

_G.SpawnReceiveFn = function()
  error('RECEIVE fn NOT SET')
end

_G.BarkTokenProcessId = "________________________________________brk"
_G.UsdtTokenProcessId = "_______________________________________usdt"
_G.ArTokenProcessId = "_________________________________________ar"
_G.SpawnedPoolProcessId = "_______________________________________pool"

_G.DEFAULT_LP_FEE = '25'

local factory = require "factory.factory" -- require so that process handlers are loaded
local factory_lib = require "factory.factory_lib"

local pairIdentifier = function(tokenA, tokenB)
  return tokenA .. ":" .. tokenB
end

local resetGlobals = function()
  _G.Tokens = {}
  _G.Pools = {}
  _G.PoolFeesBps = {}
  _G.PoolsByTokens = {}

  _G.OutboxLatest = {}
end

describe("factory", function()
  it("should add a pool", function()
    resetGlobals()

    -- MOCKS

    local stateAfterInitializeAddPool = {}
    local originalInitializeAddPool = _G.Factory.initializeAddPool
    _G.Factory.initializeAddPool = function(msg)
      originalInitializeAddPool(msg)
      stateAfterInitializeAddPool = {
        Outbox = json.decode(json.encode(_G.OutboxLatest)),
        PoolsByTokens = json.decode(json.encode(_G.PoolsByTokens)),
        Tokens = json.decode(json.encode(_G.Tokens)),
        Pools = json.decode(json.encode(_G.Pools))
      }
    end

    local stateAfterSpawn = {}
    _G.SpawnReceiveFn = function()
      stateAfterSpawn = {
        Outbox = json.decode(json.encode(_G.OutboxLatest)),
        PoolsByTokens = json.decode(json.encode(_G.PoolsByTokens)),
        Tokens = json.decode(json.encode(_G.Tokens)),
        Pools = json.decode(json.encode(_G.Pools))
      }
      return {
        Tags = {
          ['Process'] = _G.SpawnedPoolProcessId
        }
      }
    end

    local originalRecordSpawnedPool = _G.Factory._recordSpawnedPool
    local stateAfterRecordPool = {}
    _G.Factory._recordSpawnedPool = function(msg, processId)
      originalRecordSpawnedPool(msg, processId)
      stateAfterRecordPool = {
        PoolsByTokens = json.decode(json.encode(_G.PoolsByTokens)),
        Tokens = json.decode(json.encode(_G.Tokens)),
        Pools = json.decode(json.encode(_G.Pools))
      }
    end

    local originalCreatePool = _G.Factory.createPool
    local stateAfterCreatePool = {}
    _G.Factory.createPool = function(msg, tokenA, tokenB)
      local processId = originalCreatePool(msg, tokenA, tokenB)
      stateAfterCreatePool = {
        Outbox = json.decode(json.encode(_G.OutboxLatest)),
      }
      return processId
    end

    -- EXECUTE
    _G.Factory.handleAddPool({
      From = _G.User,
      Tags = {
        Action = "Add-Pool",
        ["Token-A"] = _G.BarkTokenProcessId,
        ["Token-B"] = _G.ArTokenProcessId,
        ["Reference"] = "321"
      },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        replyMsg["X-Reference"] = "321"

        return ao.send(replyMsg)
      end
    })

    -- RESTORED MOCKED
    _G.Factory.initializeAddPool = originalInitializeAddPool
    _G.Factory._recordSpawnedPool = originalRecordSpawnedPool
    _G.Factory.createPool = originalCreatePool

    -- ASSERTIONS

    -- after initializing
    assert.Same(
      { [pairIdentifier(_G.BarkTokenProcessId, _G.ArTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = 'pending' } },
      stateAfterInitializeAddPool.PoolsByTokens
    )
    assert.Same({}, stateAfterInitializeAddPool.Tokens)
    assert.Same({}, stateAfterInitializeAddPool.Pools)
    local messageToCreatorAfterInitialize = stateAfterInitializeAddPool.Outbox[_G.User]
    assert.Same('Add-Pool-Progress', messageToCreatorAfterInitialize.Action)
    assert.Same("true", messageToCreatorAfterInitialize.Tags['Pending'])

    -- after pool creation
    local messageToCreatorAfterCreatePool = stateAfterCreatePool.Outbox[_G.User]
    assert.Same('Add-Pool-Progress', messageToCreatorAfterCreatePool.Action)
    assert.Same("true", messageToCreatorAfterCreatePool.Tags["Eval-Successful"])
    assert.Same(_G.SpawnedPoolProcessId, messageToCreatorAfterCreatePool.Tags["Pool-Id"])

    assert.Same(
      { [pairIdentifier(_G.BarkTokenProcessId, _G.ArTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = 'pending' } },
      stateAfterSpawn.PoolsByTokens
    )
    assert.Same({}, stateAfterSpawn.Tokens)
    assert.Same({}, stateAfterSpawn.Pools)

    -- after recording pool
    assert.Same(
      { [pairIdentifier(_G.BarkTokenProcessId, _G.ArTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = _G.SpawnedPoolProcessId } },
      stateAfterRecordPool.PoolsByTokens
    )
    assert.Same(
      { _G.BarkTokenProcessId, _G.ArTokenProcessId },
      stateAfterRecordPool.Pools[_G.SpawnedPoolProcessId])
    assert.Same(
      { _G.BarkTokenProcessId, _G.ArTokenProcessId },
      stateAfterRecordPool.Tokens
    )

    -- after subscription and fee collector set

    local dexiSubscriptionMsg = _G.OutboxLatest[_G.DexiTokenProcess]
    local expectedSubscriptionMsg = {
      Target = _G.DexiTokenProcess,
      Action = "Transfer",
      Quantity = "100",
      Recipient = _G.AmmMonitor,
      ["X-Action"] = "Register-AMM",
      ["X-AMM-Process"] = _G.SpawnedPoolProcessId
    }
    assert.Same(expectedSubscriptionMsg, dexiSubscriptionMsg)

    local setAmmFeeCollectorMsg = _G.OutboxLatest[_G.SpawnedPoolProcessId]
    local expectedSetAmmFeeCollectorMsg = {
      Target = _G.SpawnedPoolProcessId,
      Action = "Set-Fee-Collector",
      ["Fee-Collector"] = _G.FeeCollector
    }
    assert.Same(expectedSetAmmFeeCollectorMsg, setAmmFeeCollectorMsg)

    -- final confirmation
    local finalMessageToCreator = _G.OutboxLatest[_G.User]
    assert.Same('Add-Pool-Confirmation', finalMessageToCreator.Action)
    assert.Same('OK', finalMessageToCreator.Status)
    assert.Same(_G.SpawnedPoolProcessId, finalMessageToCreator.Tags["Pool-Id"])
    assert.Same(_G.BarkTokenProcessId, finalMessageToCreator.Tags["Token-A"])
    assert.Same(_G.ArTokenProcessId, finalMessageToCreator.Tags["Token-B"])
  end)

  it("should require valid token ids on add pool", function()
    resetGlobals()

    local originalValidateAddPoolRequest = _G.Factory.validateAddPoolRequest
    local isValidRequest = nil
    _G.Factory.validateAddPoolRequest = function(msg)
      isValidRequest = originalValidateAddPoolRequest(msg)
      return isValidRequest
    end

    -- add pool

    _G.Factory.handleAddPool({
      From = _G.User,
      Tags = {
        Action = "Add-Pool",
        ["Token-A"] = "111",
        ["Token-B"] = _G.BarkTokenProcessId,
      },
    })

    assert.Same(false, isValidRequest)
    local errorResponse = _G.OutboxLatest[_G.User]
    assert.Same(errorResponse.Action, "Add-Pool-Error")
    assert.Same(errorResponse.Status, "Error")
    assert.Same(errorResponse.Error, "Invalid Token-A :" .. "Invalid length for Arweave address")
    assert.Same(errorResponse.Tags["Token-A"], "111")
    assert.Same(errorResponse.Tags["Token-B"], _G.BarkTokenProcessId)

    -- nothing added
    local tokensAfterAdd = {}
    local poolsAfterAdd = {}
    local poolsByTokensAfterAdd = {}

    assert.Same(poolsByTokensAfterAdd, _G.PoolsByTokens)
    assert.Same(tokensAfterAdd, _G.Tokens)
    assert.Same(poolsAfterAdd, _G.Pools)

    _G.Factory.validateAddPoolRequest = originalValidateAddPoolRequest
  end)

  it("should require compatible tokens add pool", function()
    resetGlobals()

    local originalValidateAddPoolRequest = _G.Factory.validateAddPoolRequest
    local isValidRequest = nil
    _G.Factory.validateAddPoolRequest = function(msg)
      isValidRequest = originalValidateAddPoolRequest(msg)
      return isValidRequest
    end

    local originalCheckTokenCompatibility = factory_lib.checkTokenCompatibility
    factory_lib.checkTokenCompatibility = function(tokenA, tokenB)
      -- pretend one of them isn't compatible
      return { isCompatibleA = false, isCompatibleB = true }
    end

    -- add pool

    _G.Factory.handleAddPool({
      From = _G.User,
      Tags = {
        Action = "Add-Pool",
        ["Token-A"] = _G.ArTokenProcessId,
        ["Token-B"] = _G.BarkTokenProcessId,
      },
    })

    assert.Same(false, isValidRequest)
    local errorResponse = _G.OutboxLatest[_G.User]
    assert.Same(errorResponse.Action, "Add-Pool-Error")
    assert.Same(errorResponse.Status, "Error")
    assert.Same(errorResponse.Error, "Tokens are not supported (aos 2.0 replies)")
    assert.Same(errorResponse.Tags["Token-A"], _G.ArTokenProcessId)
    assert.Same(errorResponse.Tags["Token-B"], _G.BarkTokenProcessId)
    assert.Same(errorResponse.Tags["Compatible-A"], "false")
    assert.Same(errorResponse.Tags["Compatible-B"], "true")

    -- nothing added
    local tokensAfterAdd = {}
    local poolsAfterAdd = {}
    local poolsByTokensAfterAdd = {}

    assert.Same(poolsByTokensAfterAdd, _G.PoolsByTokens)
    assert.Same(tokensAfterAdd, _G.Tokens)
    assert.Same(poolsAfterAdd, _G.Pools)

    _G.Factory.validateAddPoolRequest = originalValidateAddPoolRequest
    factory_lib.checkTokenCompatibility = originalCheckTokenCompatibility
  end)

  it("should not add a pool twice", function()
    resetGlobals()

    _G.SpawnReceiveFn = function()
      return { Tags = { ['Process'] = _G.SpawnedPoolProcessId } }
    end

    -- add pool

    _G.Factory.handleAddPool({
      From = _G.User,
      Tags = {
        Action = "Add-Pool",
        ["Token-A"] = _G.BarkTokenProcessId,
        ["Token-B"] = _G.ArTokenProcessId,
        ["Fee-Bps"] = _G.DEFAULT_LP_FEE,
        ["Reference"] = "321"
      },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        replyMsg["X-Reference"] = "321"

        return ao.send(replyMsg)
      end
    })

    -- add same pool again
    local originalValidateAddPoolRequest = _G.Factory.validateAddPoolRequest
    local isValidRequest = nil
    _G.Factory.validateAddPoolRequest = function(msg)
      isValidRequest = originalValidateAddPoolRequest(msg)
      return isValidRequest
    end

    _G.Factory.handleAddPool({
      From = _G.User,
      Tags = {
        Action = "Add-Pool",
        ["Token-A"] = _G.BarkTokenProcessId,
        ["Token-B"] = _G.ArTokenProcessId,
      },
    })

    assert.are.Equal(false, isValidRequest)
    local errorResponse = _G.OutboxLatest[_G.User]
    assert.Same(errorResponse.Action, "Add-Pool-Error")
    assert.Same(errorResponse.Status, "Error")
    assert.Same(errorResponse.Error, "Pool with these tokens and this fee already exists")
    assert.Same(errorResponse.Tags["Token-A"], _G.BarkTokenProcessId)
    assert.Same(errorResponse.Tags["Token-B"], _G.ArTokenProcessId)

    local tokensAfterAdd = {
      _G.BarkTokenProcessId,
      _G.ArTokenProcessId
    }
    local poolsAfterAdd = {
      [_G.SpawnedPoolProcessId] = tokensAfterAdd
    }
    local poolsByTokensAfterAdd = {
      [pairIdentifier(_G.BarkTokenProcessId, _G.ArTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = _G.SpawnedPoolProcessId }
    }

    assert.Same(poolsByTokensAfterAdd, _G.PoolsByTokens)
    assert.Same(tokensAfterAdd, _G.Tokens)
    assert.Same(poolsAfterAdd, _G.Pools)

    _G.Factory.validateAddPoolRequest = originalValidateAddPoolRequest
  end)

  it("should not get a non-existent pool", function()
    resetGlobals()

    local status, error = pcall(function()
      _G.Factory.handleGetPool({
        From = _G.User,
        Tags = {
          Action = "Get-Pool",
          ["Token-A"] = _G.BarkTokenProcessId,
          ["Token-B"] = _G.UsdtTokenProcessId
        }
      })
    end)

    assert.Same(status, false)
    ---@diagnostic disable-next-line: need-check-nil
    assert.Not.Nil(error:find("Pool not found"))

    assert.is_nil(_G.OutboxLatest[_G.User])
  end)

  it("should get a pool by replying aos 2.0 style", function()
    resetGlobals()

    _G.PoolsByTokens = {
      [pairIdentifier(_G.ArTokenProcessId, _G.BarkTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = "brk-ar-pool" }
    }

    _G.Factory.handleGetPool({
      From = _G.User,
      Tags = {
        Action = "Get-Pool",
        ["Token-A"] = _G.BarkTokenProcessId,
        ["Token-B"] = _G.ArTokenProcessId,
        ["Reference"] = "321"
      },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        replyMsg["X-Reference"] = "321"

        return ao.send(replyMsg)
      end
    })

    local response = _G.OutboxLatest[_G.User]
    assert.Same('Get-Pool-Response', response['Action'])
    assert.Same('brk-ar-pool', response.Tags['Pool-Id'])
    assert.Same("false", response.Tags['Pending'])
    assert.Same("321", response["X-Reference"])
  end)

  it("should accurately return pending pool state when getting pool", function()
    resetGlobals()

    _G.PoolsByTokens = {
      [pairIdentifier(_G.ArTokenProcessId, _G.BarkTokenProcessId)] = { [_G.DEFAULT_LP_FEE] = "pending" }
    }

    _G.Factory.handleGetPool({
      From = _G.User,
      Tags = {
        Action = "Get-Pool",
        ["Token-A"] = _G.BarkTokenProcessId,
        ["Token-B"] = _G.ArTokenProcessId
      },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        return ao.send(replyMsg)
      end
    })

    local response = _G.OutboxLatest[_G.User]
    assert.Same('Get-Pool-Response', response['Action'])
    assert.Same('pending', response.Tags['Pool-Id'])
    assert.Same("true", response.Tags['Pending'])
  end)

  it("should get all pools", function()
    resetGlobals()

    local pools = {
      ["brk-ar-pool"] = { _G.BarkTokenProcessId, _G.ArTokenProcessId },
      ["brk-usdt-pool"] = { _G.BarkTokenProcessId, _G.UsdtTokenProcessId }
    }

    _G.Pools = pools
    _G.Factory.handleGetPools({
      From = _G.User,
      Tags = { Action = "Get-Pools" },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        return ao.send(replyMsg)
      end
    })

    local response = _G.OutboxLatest[_G.User]
    assert.Same('Get-Pools-Response', response['Action'])
    assert.Same(json.encode(pools), response.Data)
  end)

  it("should get all tokens", function()
    resetGlobals()
    local tokens = {
      _G.BarkTokenProcessId,
      _G.ArTokenProcessId,
      _G.UsdtTokenProcessId
    }
    _G.Tokens = tokens

    _G.Factory.handleGetTokens({
      From = _G.User,
      Tags = { Action = "Get-Tokens" },
      reply = function(replyMsg)
        replyMsg.Target = _G.User
        return ao.send(replyMsg)
      end
    })

    local response = _G.OutboxLatest[_G.User]
    assert.Same('Get-Tokens-Response', response['Action'])
    assert.Same(json.encode(tokens), response.Data)
  end)
end)
