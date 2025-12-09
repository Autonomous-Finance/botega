local assertions = require("utils.assertions")
local balances = require("amm.token.balance")
local outputs = require("utils.output")
local bint = require("utils.tl-bint")(256)
local pool = require("amm.pool.pool")
local json = require "json"
local fwdTags = require "utils.forward-tags"
local state = require "amm.state"
require("amm.pool.globals")


local record BurnResult 
  burnedPoolTokens: BigInteger
  withdrawnTokenA: BigInteger
  withdrawnTokenB: BigInteger
  totalSupply: BigInteger
end

local function executeBurn(quantity: BigInteger, sender: string): BurnResult
  local totalSupply: BigInteger = balances.totalSupply()
  local pair: {string, string} = pool.getPair()
  local tokenA, tokenB = pair[1], pair[2]

  assert(
    assertions.isTokenQuantity(quantity),
    "Invalid burn quantity"
  )

  assert(Balances[sender] ~= nil, "No balance for this user")
  assert(bint.ule(quantity, Balances[sender]), "Not enough tokens to burn")

  -- assert(bint.ult(quantity, totalSupply), "This action would drain the pool")

  local function burnRatioOf(inReserve: BigInteger): BigInteger
    return bint.udiv(quantity * inReserve, totalSupply)
  end

  local tokenAQty: BigInteger = burnRatioOf(Reserves[tokenA])
  Reserves[tokenA] = Reserves[tokenA] - tokenAQty

  local tokenBQty: BigInteger = burnRatioOf(Reserves[tokenB])
  Reserves[tokenB] = Reserves[tokenB] - tokenBQty

  Balances[sender] = Balances[sender] - quantity

  return {
    burnedPoolTokens = quantity,
    withdrawnTokenA = tokenAQty,
    withdrawnTokenB = tokenBQty,
    totalSupply = totalSupply
  }
end

local function burn(burnMsg: Message): string | nil
  local quantity: BigInteger = bint(burnMsg.Tags.Quantity)
  local sender: string = burnMsg.From
  local pair: {string, string} = pool.getPair()
  local tokenA, tokenB = pair[1], pair[2]

  local burnResult = executeBurn(quantity, sender)

  local transferBPayload = {
    Target = tokenB,
    Action = "Transfer",
    Recipient = sender,
    Quantity = tostring(burnResult.withdrawnTokenB),
    ["X-Action"] = "Burn-LP-Output",
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(transferBPayload, burnMsg)

  local transferAPayload = {
    Target = tokenA,
    Action = "Transfer",
    Recipient = sender,
    Quantity = tostring(burnResult.withdrawnTokenA),
    ["X-Action"] = "Burn-LP-Output",
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(transferAPayload, burnMsg)

  local confirmationPayload = {
    Target = ao.env.Process.Tags["AMM-Factory"],    Tags = {
      ["Relay-To"] = sender,
      Action = "Burn-Confirmation",
      ["Burn-Quantity"] = tostring(burnResult.burnedPoolTokens),
      ["Burned-Pool-Tokens"] = tostring(burnResult.burnedPoolTokens),
      ["Withdrawn-" .. tokenA] = tostring(burnResult.withdrawnTokenA),
      ["Withdrawn-" .. tokenB] = tostring(burnResult.withdrawnTokenB),
      ["Token-A"] = tokenA,
      ["Token-B"] = tokenB,
      ['Token-A-Quantity'] = tostring(burnResult.withdrawnTokenA),
      ['Token-B-Quantity'] = tostring(burnResult.withdrawnTokenB),
      ['Trigger-Timestamp'] = tostring(os.time())
    }
  }
  fwdTags.sendWithForwardedTags(confirmationPayload, burnMsg)

  local debitNoticePayload = {
    Target = sender,
    Action = "Debit-Notice",
    Recipient = ao.id,
    Quantity = tostring(burnResult.burnedPoolTokens),
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(debitNoticePayload, burnMsg)

  
  local liquidityChangePayload = {
    ["Reserves-Token-A"] = tostring(Reserves[tokenA]),
    ["Reserves-Token-B"] = tostring(Reserves[tokenB]),
    ["Delta-Token-A"] = tostring(-burnResult.withdrawnTokenA),
    ["Delta-Token-B"] = tostring(-burnResult.withdrawnTokenB),
    ["Action"] = "Burn",
    ["Delta-Pool-Tokens"] = tostring(-burnResult.burnedPoolTokens),
    ["Total-Pool-Tokens"] = tostring(balances.totalSupply()),
    ["Token-A"] = tokenA,
    ["Token-B"] = tokenB,
    ["Original-Message-Id"] = burnMsg.Id,
    ["Address"] = sender,
    ["Transfer-Quantity"] = tostring(burnResult.burnedPoolTokens),
    ["Recipient"] = sender,
    ["Sender"] = ao.id,
  }

  Subscribable.notifyTopic('liquidity-add-remove', liquidityChangePayload, os.time())

  -- Patch Reserves
  state.updateReserves()

  -- Patch Balances
  ao.send({
    device = "patch@1.0",
    method = "PATCH",
    balances = {
      [sender] = tostring(Balances[sender]),
    }
  })

  print(
    outputs.prefix("Burn", burnMsg.From) ..
    Colors.blue ..
    tostring(quantity) ..
    " " ..
    Colors.green ..
    "POOL TOKENS" ..
    Colors.gray ..
    " → " ..
    Colors.blue ..
    tostring(burnResult.withdrawnTokenA) ..
    " " ..
    outputs.formatAddress(tokenA) ..
    Colors.gray ..
    " + " ..
    Colors.blue ..
    tostring(burnResult.withdrawnTokenB) ..
    " " ..
    outputs.formatAddress(tokenB)
  )
end

local function burnWithCatch(message: Message)
  local status, result = pcall(burn, message)

  if not status then
    local traceback = debug.traceback()
    print("!!! Error: " .. 'burn' .. json.encode(traceback))

    local err = string.gsub(result as string, "%[[%w_.\" ]*%]:%d*: ", "")

    local burnErrorMsg = {
      Target = ao.env.Process.Tags["AMM-Factory"],
      Tags = {
        ["Relay-To"] = message.From,
        Action = "Burn-Error",
        ["Result"] = err,
        ["Burn-Id"] = message.Id,
        ["Burn-Quantity"] = message.Tags.Quantity,
        ['Trigger-Timestamp'] = tostring(os.time())
      }
    }
    fwdTags.sendWithForwardedTags(burnErrorMsg, message)
  end
end

local function adminBurn(burnMsg: Message): string | nil
  assert(burnMsg.From == OPERATOR, "Only the operator can perform an admin burn")

  local sender: string = burnMsg.Tags["Burn-Sender"]
  local pair: {string, string} = pool.getPair()
  local tokenA, tokenB = pair[1], pair[2]

  local quantity = Balances[sender]

  local burnResult = executeBurn(quantity, sender)

  local transferBPayload = {
    Target = tokenB,
    Action = "Transfer",
    Recipient = sender,
    Quantity = tostring(burnResult.withdrawnTokenB),
    ["X-Action"] = "Burn-LP-Output",
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(transferBPayload, burnMsg)

  local transferAPayload = {
    Target = tokenA,
    Action = "Transfer",
    Recipient = sender,
    Quantity = tostring(burnResult.withdrawnTokenA),
    ["X-Action"] = "Burn-LP-Output",
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(transferAPayload, burnMsg)

  local confirmationPayload = {
    Target = ao.env.Process.Tags["AMM-Factory"],    Tags = {
      ["Relay-To"] = sender,
      Action = "Burn-Confirmation",
      ["Burn-Quantity"] = tostring(burnResult.burnedPoolTokens),
      ["Burned-Pool-Tokens"] = tostring(burnResult.burnedPoolTokens),
      ["Withdrawn-" .. tokenA] = tostring(burnResult.withdrawnTokenA),
      ["Withdrawn-" .. tokenB] = tostring(burnResult.withdrawnTokenB),
      ["Token-A"] = tokenA,
      ["Token-B"] = tokenB,
      ['Token-A-Quantity'] = tostring(burnResult.withdrawnTokenA),
      ['Token-B-Quantity'] = tostring(burnResult.withdrawnTokenB),
      ['Trigger-Timestamp'] = tostring(os.time())
    }
  }
  fwdTags.sendWithForwardedTags(confirmationPayload, burnMsg)

  local debitNoticePayload = {
    Target = sender,
    Action = "Debit-Notice",
    Recipient = ao.id,
    Quantity = tostring(burnResult.burnedPoolTokens),
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(debitNoticePayload, burnMsg)

  
  local liquidityChangePayload = {
    ["Reserves-Token-A"] = tostring(Reserves[tokenA]),
    ["Reserves-Token-B"] = tostring(Reserves[tokenB]),
    ["Delta-Token-A"] = tostring(-burnResult.withdrawnTokenA),
    ["Delta-Token-B"] = tostring(-burnResult.withdrawnTokenB),
    ["Action"] = "Burn",
    ["Delta-Pool-Tokens"] = tostring(-burnResult.burnedPoolTokens),
    ["Total-Pool-Tokens"] = tostring(balances.totalSupply()),
    ["Token-A"] = tokenA,
    ["Token-B"] = tokenB,
    ["Original-Message-Id"] = burnMsg.Id,
    ["Address"] = sender,
    ["Transfer-Quantity"] = tostring(burnResult.burnedPoolTokens),
    ["Recipient"] = sender,
    ["Sender"] = ao.id,
  }

  Subscribable.notifyTopic('liquidity-add-remove', liquidityChangePayload, os.time())

  -- Patch Reserves
  state.updateReserves()

  -- Patch Balances
  ao.send({
    device = "patch@1.0",
    method = "PATCH",
    balances = {
      [sender] = tostring(Balances[sender]),
    }
  })

  print(
    outputs.prefix("Burn", burnMsg.From) ..
    Colors.blue ..
    tostring(quantity) ..
    " " ..
    Colors.green ..
    "POOL TOKENS" ..
    Colors.gray ..
    " → " ..
    Colors.blue ..
    tostring(burnResult.withdrawnTokenA) ..
    " " ..
    outputs.formatAddress(tokenA) ..
    Colors.gray ..
    " + " ..
    Colors.blue ..
    tostring(burnResult.withdrawnTokenB) ..
    " " ..
    outputs.formatAddress(tokenB)
  )
end

return {
  executeBurn = executeBurn, 
  burn = burn,
  burnWithCatch = burnWithCatch,
  adminBurn = adminBurn
}
