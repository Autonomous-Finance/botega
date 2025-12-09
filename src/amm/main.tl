local ammHandlers = require "amm.amm-handlers"
local incoming = require "amm.token.credit_notice"
local patterns = require "utils.patterns"
local transfer = require "amm.token.transfer"
local balance = require "amm.token.balance"
local outputs = require "utils.output"
local provide = require "amm.pool.provide"
local refund = require "amm.pool.refund"
local cancel = require "amm.pool.cancel"
local token = require "amm.token.token"
local burn = require "amm.pool.burn"
local pool = require "amm.pool.pool"
local swap = require "amm.pool.swap"
local utils = require "utils.tl-utils"
local json  = require "json"
local responses = require "utils.responses"
local assertions = require "utils.assertions"
local state = require "amm.state"
global DexiTokenProcess: string
DexiTokenProcess = DexiTokenProcess or ao.env.Process.Tags['Dexi-Token']
OPERATOR = "LjFZGDae9yM-yOj0Ei7ex0xy3Zdrbn8jo-7ZqVLT19E"

global InitialSync: string
InitialSync = InitialSync or 'COMPLETE'

assert(DexiTokenProcess, "DexiTokenProcess is not set")


token.init()
pool.init()
-- *initialize Handlers*

-- token functions

Handlers.add(
  "info",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  ammHandlers.handleGetInfo
)

Handlers.add(
  "Set-Fee-Collector",
  Handlers.utils.hasMatchingTag("Action", "Set-Fee-Collector"),
  function(msg: Message)
    assert(msg.From == Owner or msg.From == ao.id, "Only the owner or self can set the fee collector")
    FeeCollector = msg.Tags["Fee-Collector"]
    responses.sendConfirmation(msg, { ["Fee-Collector"] = FeeCollector })
  end
)

Handlers.add(
  "balance",
  Handlers.utils.hasMatchingTag("Action", "Balance"),
  balance.balance
)
Handlers.add(
  "balances",
  Handlers.utils.hasMatchingTag("Action", "Balances"),
  balance.balances
)
Handlers.add(
  "totalSupply",
  Handlers.utils.hasMatchingTag("Action", "Total-Supply"),
  function(msg: Message)
    local res = balance.totalSupply()

    local replyData = tostring(res)
    local replyTags = { ["Total-Supply"] = tostring(res), Ticker = Ticker }
    responses.sendReply(msg, replyData, replyTags)

    print(
      outputs.prefix("Total-Supply", msg.From) ..
      Colors.gray ..
      "Total-Supply = " ..
      Colors.blue ..
      tostring(res) ..
      Colors.reset
    )
  end
)

--- 
Handlers.add(
  "transfer",
  Handlers.utils.hasMatchingTag("Action", "Transfer"),
  transfer.transfer
)

Handlers.add(
  "getPair",
  Handlers.utils.hasMatchingTag("Action", "Get-Pair"),
  function(msg: Message)
    local res = pool.getPair()

    local replyData = nil
    local replyTags = {
      ["Token-A"] = res[1],
      ["Token-B"] = res[2]
    }
    responses.sendReply(msg, replyData, replyTags)
    print(
      outputs.prefix("Get-Pair", msg.From) ..
      Colors.gray ..
      "Pair = " ..
      outputs.formatAddress(res[1]) ..
      Colors.gray ..
      "/" ..
      outputs.formatAddress(res[2]) ..
      Colors.reset
    )
  end
)
Handlers.add(
  "getReserves",
  Handlers.utils.hasMatchingTag("Action", "Get-Reserves"),
  function(msg: Message)
    local res = pool.getReserves()
    local pair = pool.getPair()

    local replyData = nil
    local replyTags = {
      [pair[1]] = tostring(res[pair[1]]),
      [pair[2]] = tostring(res[pair[2]])
    }
    responses.sendReply(msg, replyData, replyTags)
    print(
      outputs.prefix("Get-Reserves", msg.From) ..
      Colors.gray ..
      "Reserves = [" ..
      outputs.formatAddress(pair[1]) ..
      Colors.gray ..
      "=" ..
      Colors.blue ..
      tostring(res[pair[1]]) ..
      Colors.gray ..
      ", " ..
      outputs.formatAddress(pair[2]) ..
      Colors.gray ..
      "=" ..
      Colors.blue ..
      tostring(res[pair[2]]) ..
      Colors.gray ..
      "]" ..
      Colors.reset
    )
  end
)
Handlers.add(
  "K",
  Handlers.utils.hasMatchingTag("Action", "Get-K"),
  function(msg: Message)
    local res = pool.K()

    local replyData = nil
    local replyTags = { ["K"] = tostring(res) }
    responses.sendReply(msg, replyData, replyTags)

    print(
      outputs.prefix("Get-K", msg.From) ..
      Colors.gray ..
      "K = " ..
      Colors.blue ..
      tostring(res) ..
      Colors.reset
    )
  end
)
Handlers.add(
  "getPrice",
  Handlers.utils.hasMatchingTag("Action", "Get-Price"),
  pool.getPrice
)

Handlers.add(
  "getSwapOutput",
  Handlers.utils.hasMatchingTag("Action", "Get-Swap-Output"),
  pool.getSwapOutput
)

Handlers.add(
  "getFeePercentage",
  Handlers.utils.hasMatchingTag("Action", "Get-Fee-Percentage"),
  function(msg: Message)
    local hasFeeDiscount = msg.Tags["Has-Fee-Discount"] == "true"
    local replyData = nil
    local replyTags = pool.getFeesAsPercentages(hasFeeDiscount)
    responses.sendReply(msg, replyData, replyTags)
  end
)

Handlers.add(
  "getPendingProvides",
  Handlers.utils.hasMatchingTag("Action", "Get-Pending-Provides"),
  function(msg: Message)
    local res = provide.findPendingProvide(msg.From)
    local replyData = nil
    local replyTags: { string: string }
    if(res) then
      res = res as PendingProvideType
      replyTags = {
        ['Provide-Found'] = "true",
        ['Provide-Id'] = res.id,
        ['Token'] = res.token,
        ['Quantity'] = tostring(res.quantity),
      }
    else
      replyTags = {
        ['Provide-Found'] = "false",
        ['Provide-Id'] = "0",
        ['Token'] = "0",
        ['Quantity'] = "0",
      }
    end

    responses.sendReply(msg, replyData, replyTags)
  end
)

Handlers.add(
  "getProtocolFeePercentage",
  Handlers.utils.hasMatchingTag("Action", "Get-Protocol-Fee-Percentage"),
  function(msg: Message)
    local res = pool.getProtocolFeePercentage()

    local replyData = nil
    local replyTags = { ["Protocol-Fee-Percentage"] = tostring(res) }
    responses.sendReply(msg, replyData, replyTags)

    print(
      outputs.prefix("Get-Protocol-Fee-Percentage", msg.From) ..
      Colors.gray ..
      "Protocol-Fee-Percentage = " ..
      Colors.blue ..
      tostring(res) ..
      Colors.gray ..
      "%" ..
      Colors.reset
    )
  end
)

-- AMM interactions
Handlers.add(
  "burn",
  Handlers.utils.hasMatchingTag("Action", "Burn"),
  burn.burnWithCatch
)

Handlers.add(
  "adminburn",
  Handlers.utils.hasMatchingTag("Action", "Admin-Burn"),
  burn.adminBurn
)


Handlers.add(
  "cancel",
  Handlers.utils.hasMatchingTag("Action", "Cancel"),
  cancel.cancel
)

-- the credit notice handler runs before Swap/Provide
-- it only checks if the tokens sent are in the pair
--
-- if they're not in the pair, it sends them back
-- in this case, we need to ensure that the Swap/Provide
-- actions don't run, that is why we add a pattern
-- to their handlers to check if the sent tokens are in
-- the AMM token pair
Handlers.add(
  "creditNotice",
  patterns.continue(Handlers.utils.hasMatchingTag("Action", "Credit-Notice")),
  incoming.creditNotice
)

-- the following interactions require the user to transfer one
-- or multiple amounts of tokens to the AMM
-- because of that, if they fail, these transfers need to be
-- sent back
-- "Provide" and "Swap" will let the process continue evaluating
-- handlers, so we can later verify if any of the interactions
-- failed and refund the user if needed
Handlers.add(
  "provide",
  patterns.continue(patterns._and({
    Handlers.utils.hasMatchingTag("Action", "Credit-Notice"),
    Handlers.utils.hasMatchingTag("X-Action", "Provide"),
    function(msg: Message): boolean return utils.includes(msg.From, pool.getPair()) end
  })),
  patterns.catchWrapper(
    function(msg: Message): provide.ProvideReturnType
      return provide.provide(msg)
    end,
    "Provide"
  )
)
Handlers.add(
  "swap",
  patterns.continue(patterns._and({
    Handlers.utils.hasMatchingTag("Action", "Credit-Notice"),
    Handlers.utils.hasMatchingTag("X-Action", "Swap"),
    function(msg: Message): boolean return utils.includes(msg.From, pool.getPair()) end
  })),
  patterns.catchWrapper(
    function(msg: Message): nil
      return swap.swap(msg)
    end,
    "Swap"
  )
)


-- IMPORTANT: there is a special variable called "RefundError"
-- when adding handlers that deal with incoming swaps, it is
-- necessary to wrap the handler function with the
-- "patterns.catchWrapper" wrapper function, to set this global
-- variable when an error is thrown, so the refund finalizer
-- refunds failed swaps, provides, etc.

-- this handler will refund the user if the provide/swap
-- interaction errored, like it is mentioned above
Handlers.add(
  "refundFinalizer",
  patterns._and({
    Handlers.utils.hasMatchingTag("Action", "Credit-Notice"),
    patterns.hasMatchingTagOf("X-Action", { "Provide", "Swap" }),
    function(msg: Message): boolean return utils.includes(msg.From, pool.getPair()) end
  }),
  refund.refund
)

Handlers.add(
  "whitelistForFeeDiscount",
  Handlers.utils.hasMatchingTag("Action", "Whitelist-For-Fee-Discount"),
  pool.handleWhitelistForFeeDiscount
)

Handlers.add(
  "getWhitelistedForFeeDiscount",
  Handlers.utils.hasMatchingTag("Action", "Get-Whitelisted-For-Fee-Discount"),
  pool.handleGetWhitelistedForFeeDiscount
)

Handlers.add(
  "disableFeeDiscount",
  Handlers.utils.hasMatchingTag("Action", "Disable-Fee-Discount"),
  pool.handleDisableFeeDiscount
)


-- ========= DEBUG ========= --

Handlers.add(
  'Get-Subscribers',
  Handlers.utils.hasMatchingTag('Action', 'Debug-Get-Subscribers'),
  function(msg: Message)
    local subscribers = Subscribable._storage.Subscribers
    local replyData = subscribers
    local replyTags = nil
    responses.sendReply(msg, replyData, replyTags)
  end
)

Handlers.add(
  'Get-Targets-For-Topic',
  Handlers.utils.hasMatchingTag('Action', 'Debug-Get-Targets-For-Topic'),
  function(msg: Message)
    local topic = msg.Tags['Topic']
    local targets = Subscribable._storage.getTargetsForTopic(topic)
    local replyData = targets
    local replyTags = nil
    responses.sendReply(msg, replyData, replyTags)
  end
)


Handlers.add(
  'Init-State',
  Handlers.utils.hasMatchingTag('Action', 'Init-State'),
  function(msg: Message)
    assert(msg.From == Owner or msg.From == ao.id, "Only the owner or self can initialize the state")
    state.init()
  end
)

package.loaded['subscriptions.subscribable'] = nil
local subscribableCreator = require("subscriptions.subscribable") -- also loads subscribable handlers

global Subscribable: TSubscribable 
if not Subscribable then
  Subscribable = subscribableCreator({
    useDB = false
  }) as TSubscribable
else
  Subscribable = require("subscriptions.subscribable")() as TSubscribable
end
Subscribable.PAYMENT_TOKEN = DexiTokenProcess
Subscribable.PAYMENT_TOKEN_TICKER = "DTST"

global TopicsAndChecks: {string: TopicInfo} = {
  ['order-confirmation'] = {
    description = 'Order confirmation details, after a swap has occurred',
    returns =
    '{ "Order-Id": string, "From-Token": string, "From-Quantity": string, "To-Token": string, "To-Quantity": string, "Fee-Percentage": string, "Reserves-Token-A": string, "Reserves-Token-B": string, "Token-A": string, "Token-B": string, "Total-Fee": string, "LP-Fee": string, "Protocol-Fee": string }',
  },
  ['liquidity-add-remove'] = {
    description = 'Latest reserves, after liquidity addition/removal',
    returns = '{ "Reserves-Token-A": bigint, "Reserves-Token-B": bigint }',
  },
  ['fee-change'] = {
    description = 'The total fee for swaps, after a fee update',
    returns = '{ "TotalFee": string }',
  }
}
Subscribable.configTopicsAndChecks(TopicsAndChecks)

-- Initial Sync Patch
if InitialSync ~= 'COMPLETE-V3' then
  local balances: {string: string} = {}
  for k, v in pairs(Balances) do
    balances[k] = tostring(v)
  end

  ao.send({
    device = "patch@1.0",
    method = "PATCH",
    ["token-info"] = token.info(),
    balances = balances
  })
  state.updateReserves()
  InitialSync = 'COMPLETE-V3'
end