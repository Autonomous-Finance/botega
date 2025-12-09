local assertions = require "utils.assertions"
local bintmath = require "utils.bintmath"
local balance = require "amm.token.balance"
local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local pool = require "amm.pool.pool"
local utils = require "utils.tl-utils"
local fwdTags = require "utils.forward-tags"
local state = require "amm.state"

require("amm.pool.globals")
require("subscriptions.subscribable")


local record ProvideResult
  Reserves: {string:BigInteger}
  Balances: {string:BigInteger}
  lpTokensMinted: BigInteger
  actualQuantityA: BigInteger
  actualQuantityB: BigInteger
end


local function findPendingProvide(sender: string): PendingProvideType | nil
  return utils.find(
    function(val: PendingProvideType): boolean
      return val.sender == sender
    end,
    PendingProvides
  )
end

local record ClosePendingData
  sender: string
  id: string
end

local function closePending(data: ClosePendingData)
  if not data.sender and not data.id then return end

  global PendingProvides: {PendingProvideType} = utils.filter(
    function(val: PendingProvideType): boolean
      if data.id then
        return val.id ~= data.id
      end

      return val.sender ~= data.sender
    end,
    PendingProvides
  ) as {PendingProvideType} or {} as {PendingProvideType}
end

local function replacePendingProvide(pendingProvide: PendingProvideType, qtyB: BigInteger, sender: string, tokenB: string)
  local newPendingProvide = {
    id = pendingProvide.id,
    token = tokenB,
    quantity = pendingProvide.quantity + qtyB,
    sender = sender
  }
  closePending({ id = pendingProvide.id })
  table.insert(PendingProvides, newPendingProvide)
end

local function createNewPendingProvide(message: Message, qtyB: BigInteger, sender: string, tokenB: string)
  table.insert(PendingProvides, {
    id = message.Id,
    token = tokenB,
    quantity = qtyB,
    sender = sender
  })
end

local function attemptAdjustBalances(qtyA: BigInteger, qtyB: BigInteger, tokenA: string, tokenB: string, slippageTolerance: number): BigInteger, BigInteger
  -- slippage limits for B tokens
  local limitB = pool.slippageLimit(slippageTolerance, qtyB, "lower")
  local optimalB = bint.udiv(Reserves[tokenB] * qtyA, Reserves[tokenA])

  -- check if it is possible to execute the provide interaction
  -- by adjusting qtyB and if it is within the slippage tolerance
  -- if it is not, we try the same thing by adjusting qtyA
  if bint.ule(optimalB, qtyB) and bint.ule(limitB, optimalB) then
    -- update qtyB to optimal value
    qtyB = optimalB
  else
    -- slippage limits for A
    local limitA = pool.slippageLimit(slippageTolerance, qtyA, "lower")
    local optimalA = bint.udiv(Reserves[tokenA] * qtyB, Reserves[tokenB])

    -- make sure it is possible to execute the provide interaction
    -- with the provided slippage limit by adjusting qtyA
    -- if it is not possible, the provide interaction cannot be
    -- executed and the tokens will be refunded within the refund
    -- finalizer
    assert(
      bint.ule(optimalA, qtyA) and bint.ule(limitA, optimalA),
      "Could not provide liquidity within the given slippage tolerance"
    )

    -- update qtyA to optimal value
    qtyA = optimalA
  end

  return qtyA, qtyB
end

local refundExtraTokens = function(initialQuantity: BigInteger, actualQuantity: BigInteger, token: string, sender: string, contextMsg: Message)
  if bint.ult(actualQuantity, initialQuantity) then
    local refundMsg = {
      Target = token,
      Action = "Transfer",
      Recipient = sender,
      Quantity = tostring(initialQuantity - actualQuantity),
      ['Trigger-Timestamp'] = tostring(os.time())
    }
    fwdTags.sendWithForwardedTags(refundMsg, contextMsg)
  end
end

local function calculateLpTokensToMint(qtyA: BigInteger, tokenA: string): BigInteger
  -- if this was not the initial provide interaction, we need to
  -- calculate the amount of pool tokens the user receives
  -- the LP receives pool tokens in the ratio of the incoming tokens
  -- and the tokens in the reserves
  -- this NEEDS to be calculated before adding the incoming tokens
  -- to the reserves
  return bint.udiv(
    balance.totalSupply() * qtyA,
    Reserves[tokenA]
  )
end


local function executeProvide(tokenA: string, tokenB: string, qtyA: BigInteger, qtyB: BigInteger, sender: string, slippageTolerance: number): ProvideResult
  -- verify slippage percentage
  assert(
    assertions.isSlippagePercentage(slippageTolerance),
    "Invalid slippage tolerance percentage"
  )
  ---@cast slippageTolerance number

  assert(
    bint.isbint(qtyA) and bint.isbint(qtyB),
    "Quantity is not bint"
  )

  assert(
    Reserves[tokenA] ~= nil and Reserves[tokenB] ~= nil,
    "Token not found in reserves"
  )

  assert(
    qtyA:gt(bint.zero()) and qtyB:gt(bint.zero()),
    "Quantity is not greater than 0"
  )

  -- whether or not the pool is empty (if it is, then this is the first provide interaction)
  local poolIsEmpty = bint.eq(Reserves[tokenA], bint.zero()) and bint.eq(Reserves[tokenB], bint.zero())

  -- whether or not the ratio matches
  local ratioMatches = bint.eq(
    qtyA * Reserves[tokenB],
    qtyB * Reserves[tokenA]
  )

  local lpTokensToMint = bint.zero()

  if poolIsEmpty then
    -- if this is the initial provide interaction,
    -- we mint the user the sqrt of the two qtys
    -- multiplied
    lpTokensToMint = bintmath.sqrt(qtyA * qtyB)
  elseif ratioMatches then
    -- adding to the pool in the correct ratio
    lpTokensToMint = calculateLpTokensToMint(qtyA, tokenA)
  else
    -- pool is not empty and also the ratio does not match
    -- adjust the qtys to match the ratio (within slippage tolerance)
    qtyA, qtyB = attemptAdjustBalances(qtyA, qtyB, tokenA, tokenB, slippageTolerance)
    lpTokensToMint = calculateLpTokensToMint(qtyA, tokenA)
  end

  -- check if the received pool tokens are > 0
  assert(lpTokensToMint:ge(bint.zero()), "Too little liquidity provided")

  -- mint tokens
  Balances[sender] = (Balances[sender] or bint.zero()) + lpTokensToMint

  -- add to reserves
  Reserves[tokenA] = Reserves[tokenA] + qtyA
  Reserves[tokenB] = Reserves[tokenB] + qtyB

  return {
    lpTokensMinted = bint(lpTokensToMint),
    actualQuantityA = bint(qtyA),
    actualQuantityB = bint(qtyB)
  }
end



local record ProvideReturnType
  Reserves: {string:BigInteger}
  Balances: {string:BigInteger}
  lpTokensToMint: BigInteger
  qtyA: BigInteger
  qtyB: BigInteger
  ['Provide-Id']: string
end


local function notifySubscribers(message: Message, provideTokenA: string, provideResult: ProvideResult, recipient: string)
  local pair: {string, string} = pool.getPair()
  local tokenA, tokenB = pair[1], pair[2]

  local deltaTokenA: BigInteger
  local deltaTokenB: BigInteger

  if provideTokenA == tokenA then
    deltaTokenA = provideResult.actualQuantityA
    deltaTokenB = provideResult.actualQuantityB
  else
    deltaTokenA = provideResult.actualQuantityB
    deltaTokenB = provideResult.actualQuantityA
  end

  local liquidityChangeMessage = {
    ["Reserves-Token-A"] = tostring(Reserves[tokenA]),
    ["Reserves-Token-B"] = tostring(Reserves[tokenB]),
    ["Delta-Token-A"] = tostring(deltaTokenA),
    ["Delta-Token-B"] = tostring(deltaTokenB),
    ["Action"] = "Provide",
    ["Delta-Pool-Tokens"] = tostring(provideResult.lpTokensMinted),
    ["Total-Pool-Tokens"] = tostring(balance.totalSupply()),
    ["Token-A"] = tokenA,
    ["Token-B"] = tokenB,
    ["Original-Message-Id"] = message.Id,
    ["Address"] = recipient,
    ["Transfer-Quantity"] = tostring(provideResult.lpTokensMinted),
    ["Recipient"] = recipient,
    ["Sender"] = ao.id,
  }

  -- Notify subscribers about liquidity change
  Subscribable.notifyTopic('liquidity-add-remove', liquidityChangeMessage, os.time())
  state.updateReserves()
  state.init()

end

-- Provide interaction
---@param message Message
local function provide(provideMsg: Message): ProvideReturnType
  -- IMPORTANT: tokenA and tokenB are NOT pool tokenA and tokenB but rather user defined 
  -- incoming token ID
  local tokenB: string = provideMsg.From

  -- sender address
  local sender: string = provideMsg.Tags.Sender

  local initialQuantityB: BigInteger = bint(provideMsg.Tags.Quantity)
  -- slippage tolerance in %
  local slippageTolerance = tonumber(provideMsg.Tags["X-Slippage-Tolerance"]) or 0


  -- find pending provide (other token's transfer)
  ---@type PendingProvide|nil
  local pendingProvide = findPendingProvide(sender)

  if not pendingProvide then
    createNewPendingProvide(provideMsg, initialQuantityB, sender, tokenB)
    return
  end

  local foundPendingProvide = pendingProvide as PendingProvideType
  if foundPendingProvide and foundPendingProvide.token == tokenB then
    replacePendingProvide(pendingProvide, initialQuantityB, sender, tokenB)
    return
  end

  local initialQuantityA = foundPendingProvide.quantity
  local tokenA = foundPendingProvide.token


  local provideResult = executeProvide(
    tokenA, tokenB, initialQuantityA, initialQuantityB, sender, slippageTolerance
  )

  -- see if we need to transfer back any tokens, this is needed if
  -- the rate was adjusted compared to the incoming token qtys
  --
  refundExtraTokens(initialQuantityA, provideResult.actualQuantityA, tokenA, sender, provideMsg)
  refundExtraTokens(initialQuantityB, provideResult.actualQuantityB, tokenB, sender, provideMsg)

  -- remove pending provide(s)
  closePending({ sender = sender })

  -- Confirm success
  local pair = pool.getPair()
  local confirmation = {
    Target = ao.env.Process.Tags["AMM-Factory"],
    Tags = {
      ["Relay-To"] = sender,
      Action = "Provide-Confirmation",
      ["Provide-Id"] = provideMsg.Id,
      ["Received-Pool-Tokens"] = tostring(provideResult.lpTokensMinted),
      ['Token-A'] = tokenA,
      ['Token-B'] = tokenB,
      ["Provided-" .. tokenA] = tostring(provideResult.actualQuantityA),
      ["Provided-" .. tokenB] = tostring(provideResult.actualQuantityB),
      ['Token-A-Quantity'] = tostring(provideResult.actualQuantityA),
      ['Token-B-Quantity'] = tostring(provideResult.actualQuantityB),
      ["X-Reserves-Token-A"] = tostring(Reserves[pair[1]]),
      ["X-Reserves-Token-B"] = tostring(Reserves[pair[2]]),
      ["X-Fee-Bps"] = tostring(pool.getFeeBps()),
      ["X-Token-A"] = pair[1],
      ["X-Token-B"] = pair[2],
      ["Trigger-Timestamp"] = tostring(os.time()),
    }
  }
  fwdTags.sendWithForwardedTags(confirmation, provideMsg)

  local creditNotice = {
    Target = sender,
    Action = "Credit-Notice",
    Sender = ao.id,
    Quantity = tostring(provideResult.lpTokensMinted),
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(creditNotice, provideMsg)
  
  notifySubscribers(provideMsg, tokenA, provideResult, sender)

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

  -- print result
  print(
    outputs.prefix("Provide", sender) ..
    Colors.blue ..
    tostring(provideResult.actualQuantityA) ..
    " " ..
    outputs.formatAddress(tokenA) ..
    Colors.gray ..
    " + " ..
    Colors.blue ..
    tostring(provideResult.actualQuantityB) ..
    " " ..
    outputs.formatAddress(tokenB) ..
    Colors.gray ..
    " → " ..
    Colors.blue ..
    tostring(provideResult.lpTokensMinted) ..
    " " ..
    Colors.green ..
    "POOL TOKENS" ..
    Colors.reset
  )

  return {
    Reserves = Reserves,
    Balances = Balances,
    lpTokensToMint = provideResult.lpTokensMinted,
    qtyA = provideResult.actualQuantityA,
    qtyB = provideResult.actualQuantityB,
    ['Provide-Id'] = provideMsg.Id
  }
end



return {
  provide = provide,
  executeProvide = executeProvide,
  findPendingProvide = findPendingProvide,
  closePending = closePending,
  replacePendingProvide = replacePendingProvide,
  createNewPendingProvide = createNewPendingProvide,
  ProvideReturnType = ProvideReturnType
}
