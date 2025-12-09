local assertions = require "utils.assertions"
local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local pool = require("amm.pool.pool")
local balance = require "amm.token.balance"
local fwdTags = require "utils.forward-tags"

require("amm.token.globals")

local mod = {}

-- Transfer tokens to another user
function mod.transfer(transferMsg: Message)
  -- transfer target
  local target = transferMsg.Tags.Recipient or transferMsg.Target

  -- validate target address
  assertions.isAddress(target)

  -- check if the target and the sender are the same
  assert(target ~= transferMsg.From, "Target cannot be the sender")

  -- validate quantity
  assert(
    assertions.isTokenQuantity(transferMsg.Tags.Quantity),
    "Invalid transfer quantity"
  )

  -- transfer quantity
  local quantity = bint(transferMsg.Tags.Quantity)

  -- validate if the user has enough tokens
  assert(Balances[transferMsg.From] ~= nil, "No balance for this user")
  assert(bint.ule(quantity, Balances[transferMsg.From]), "Not enought tokens for this transfer")

  -- move qty
  Balances[target] = (Balances[target] or bint.zero()) + quantity
  Balances[transferMsg.From] = Balances[transferMsg.From] - quantity

  if not transferMsg.Tags.Cast then
    -- credit and debit notices
    local debitNotice: SendMessagePayload = {
      Target = transferMsg.From,
      Action = "Debit-Notice",
      Recipient = target,
      Quantity = tostring(quantity),
    }
    local creditNotice: SendMessagePayload = {
      Target = target,
      Action = "Credit-Notice",
      Sender = transferMsg.From,
      Quantity = tostring(quantity),
    }

    -- send credit and debit notices
    fwdTags.sendWithAllForwardedTags(debitNotice, transferMsg)
    fwdTags.sendWithAllForwardedTags(creditNotice, transferMsg)

    local pair: {string, string} = pool.getPair()
    local tokenA, tokenB = pair[1], pair[2]
    local liquidityChangePayload = {
      ["Reserves-Token-A"] = tostring(Reserves[tokenA]),
      ["Reserves-Token-B"] = tostring(Reserves[tokenB]),
      ["Delta-Token-A"] = tostring(0),
      ["Delta-Token-B"] = tostring(0),
      ["Action"] = "Transfer",
      ["Delta-Pool-Tokens"] = tostring(0),
      ["Total-Pool-Tokens"] = tostring(balance.totalSupply()),
      ["Token-A"] = tokenA,
      ["Token-B"] = tokenB,
      ["Original-Message-Id"] = transferMsg.Id,
      ["Transfer-Quantity"] = tostring(quantity),
      ["Recipient"] = target,
      ["Sender"] = transferMsg.From,
    }
    Subscribable.notifyTopic('liquidity-add-remove', liquidityChangePayload, os.time())
  end

  -- Patch Balances
  ao.send({
    method = "PATCH",
    device = "patch@1.0",
    balances = {
      [target] = tostring(Balances[target]),
      [transferMsg.From] = tostring(Balances[transferMsg.From])
    }
  })

  print(
    outputs.prefix("Transfer", transferMsg.From) ..
    Colors.blue ..
    tostring(quantity) ..
    Colors.gray ..
    " " ..
    Ticker ..
    " to " ..
    outputs.formatAddress(target) ..
    Colors.reset
  )
end

return mod
