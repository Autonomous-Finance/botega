---@diagnostic disable: duplicate-set-field
require("test.setup")()
local json = require("json")

_G.VerboseTests = 0
_G.TestStartTime = os.time()
_G.VirtualTime = os.time()

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

-- MOCKED TOKEN VALUES

_G.AoCredProcessId = 'AoCredToken'
_G.BarkTokenProcessId = 'BarkToken'

_G.OutboxLatest = {}
_G.ao = {
  id = _G.MainProcessId,
  env = {
    Module = {
      Id = "test_module_id"
    },
    Process = {
      Tags = {
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

local amm = require "amm.main" -- require so that process handlers are loaded, as well as global variables
local ammHandlers = require "amm.amm-handlers"

describe("subscriptions", function()
  before_each(function()
    _G.OutboxLatest = {}
  end)

  it('should return correct subscribable.Info', function()
    ammHandlers.handleGetInfo({
      From = _G.User,
      Target = ao.id,
      Tags = {
        Action = "Info",
      },
      reply = function(respMsg)
        respMsg.Target = _G.User
        ao.send(respMsg)
      end
    })

    local response = _G.OutboxLatest[_G.User]
    assert.Same("Info-Response", response.Action)
    local expectedSubscriptionsInfo = {
      paymentToken = _G.DexiTokenProcess,
      paymentTokenTicker = "DTST",
      topics = _G.TopicsAndChecks
    }
    assert.Same(expectedSubscriptionsInfo, json.decode(response.Data).Subscriptions)
  end)

  -- it("should register a subscriber", function()
  --   ao.send({
  --     From = _G.User,
  --     Target = ao.id,
  --     Action = "Register-Subscriber",
  --     ["Subscriber-Process-Id"] = "dexi_process",
  --     ["Owner-Id"] = _G.User,
  --     ['Topics'] = json.encode({ "order-confirmation", "liquidity-change" })
  --   })

  --   assert.Same(#_G.AllMessages, 3)
  --   assert.Same(_G.Subscribable._storage.getSubscriber("dexi_process"), {
  --     ownerId = _G.User,
  --     whitelisted = false,
  --     topics = { "order-confirmation", "liquidity-change" }
  --   })
  --   assert.Same(_G.AllMessages[2].Tags, {
  --     Action = "Subscriber-Registration-Confirmation",
  --     Process = "dexi_process",
  --     Whitelisted = "false",
  --     OK = "true",
  --     --
  --     Assignments = {
  --       "dexi_owner_id",
  --       "dexi_process"
  --     }
  --   })
  --   assert.Same(_G.AllMessages[3].Tags, {
  --     Action = "Subscribe-To-Topics",
  --     Process = "dexi_process",
  --     Topics = json.encode({ "order-confirmation", "liquidity-change" }),
  --     --
  --     Assignments = {
  --       "dexi_owner_id",
  --       "dexi_process"
  --     }
  --   })
  -- end)

  -- it("should accept a payment for subscriptions", function()
  --   ao.send({
  --     From = _G.BarkTokenProcessId,
  --     Target = ao.id,
  --     Action = "Credit-Notice",
  --     Quantity = "1",
  --     Tags = {
  --       ["X-Action"] = "Pay-For-Subscription",
  --       Sender = _G.User
  --     }
  --   })

  --   assert.Same(#_G.AllMessages, 2)
  --   assert.Same(_G.AllMessages[2].Tags, {
  --     ["OK"] = "true",
  --     ["Response-For"] = "Pay-For-Subscription",
  --   })
  --   assert.Same(#_G.AllMessages, 2)
  -- end)

  -- it("should notify subscribers on liquidity-change", function()
  --   ao.send({
  --     From = _G.BarkTokenProcessId,
  --     Target = ao.id,
  --     Action = "Credit-Notice",
  --     ["X-Action"] = "Provide",
  --     ["X-Slippage-Tolerance"] = "1",
  --     Quantity = "1000",
  --     Tags = {
  --       Sender = _G.User
  --     }
  --   })
  --   ao.send({
  --     From = _G.AoCredProcessId,
  --     Target = ao.id,
  --     Action = "Credit-Notice",
  --     ["X-Action"] = "Provide",
  --     ["X-Slippage-Tolerance"] = "1",
  --     Quantity = "1000",
  --     Tags = {
  --       Sender = _G.User
  --     }
  --   })

  --   assert.Same(#_G.AllMessages, 4)
  --   assert.Same(_G.AllMessages[3].Tags, {
  --     Action = "Provide-Confirmation",
  --     ["Provide-Id"] = "1234",
  --     ["Provided-" .. _G.AoCredProcessId] = "1000",
  --     ["Provided-" .. _G.BarkTokenProcessId] = "1000",
  --     ["Received-Pool-Tokens"] = "1000"
  --   })
  --   assert.Same(_G.AllMessages[4].Tags, {
  --     Action = "Notify-On-Topic",
  --     Topic = "liquidity-change",
  --     Assignments = {
  --       "dexi_process"
  --     },
  --   })
  --   assert.Same(json.decode(_G.AllMessages[4].Data), {
  --     ["Reserves-Token-A"] = "1000",
  --     ["Reserves-Token-B"] = "1000"
  --   })
  -- end)

  -- it("should notify subscribers on order-confirmation", function()
  --   -- Simulate a swap to trigger an order-confirmation
  --   ao.send({
  --     From = _G.AoCredProcessId,
  --     Target = ao.id,
  --     Tags = {
  --       Action = "Credit-Notice",
  --       Quantity = "10",
  --       ["X-Action"] = "Swap",
  --       ["X-Expected-Output"] = "10",
  --       ["X-Slippage-Tolerance"] = "50",
  --       Sender = _G.User
  --     }
  --   })

  --   assert.Same(#_G.AllMessages, 6)
  --   assert.Same(_G.AllMessages[6].Tags, {
  --     Action = "Notify-On-Topic",
  --     Topic = "order-confirmation",
  --     Assignments = { "dexi_process" }
  --   })
  --   assert.Same(json.decode(_G.AllMessages[6].Data), {
  --     ["Order-Id"] = "1234",
  --     ["From-Token"] = _G.AoCredProcessId,
  --     ["From-Quantity"] = "10",
  --     ["To-Token"] = _G.BarkTokenProcessId,
  --     ["To-Quantity"] = "8",
  --     Fee = "1",
  --     ["Reserves-Token-A"] = "1011",
  --     ["Reserves-Token-B"] = "992",
  --     ["Fee-Percentage"] = "0.25"
  --   })
  -- end)
end)
