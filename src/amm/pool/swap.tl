local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local pool = require "amm.pool.pool"
local fwdTags = require "utils.forward-tags"
local state = require "amm.state"

require("amm.pool.globals")
require("subscriptions.subscribable")
local json = require "json"

local mod = {}

local record SwapResult
  outputQty: bint
  totalFeeQty: bint
  lpFeeQty: bint
  protocolFeeQty: bint
  hasDiscount: boolean
  outputToken: string
  inputToken: string
  inputQty: bint
  newReserves: {string: bint}
end


function mod.executeSwapWithMinOutput(inputToken: string, inputQty: BigInteger, expectedMinOutput: BigInteger, swapper: string) : SwapResult
  local pair = pool.getPair()
  local tokenA, tokenB = pair[1], pair[2]

  assert(
    inputQty:gt(bint.zero()),
    "Invalid input quantity"
  )


  assert(
    expectedMinOutput:gt(bint.zero()),
    "Invalid expected min output"
  )

  -- check if the reserves are empty
  assert(
    bint.ult(bint.zero(), Reserves[tokenA]) and bint.ult(bint.zero(), Reserves[tokenB]),
    "The reserves are empty"
  )
  
  -- retain fees for LPs and protocol, proceed with adjusted input qty
  local incomingQtyFeeAdjusted, lpFeeQty, protocolFeeQty, hasDiscount = pool.deductFees(inputQty, swapper)

  -- the ID of the token the AMM is going to send to the caller
  local outputToken = inputToken == tokenA and tokenB or tokenA

  -- calculate output
  local outputQty = pool.getOutput(
    incomingQtyFeeAdjusted,
    inputToken
  )

  -- calculate the reserves after the swap
  local newReserves = {
    [tokenA] = Reserves[tokenA],
    [tokenB] = Reserves[tokenB]
  }

  -- calculate new quantities
  -- lp fee enters reserves (this is how it becomes a fee for LPs eventually)
  -- protocol fee does not enter reserves (is currently part of pool balance, will be transferred to collector when swap is concluded)
  newReserves[inputToken] = newReserves[inputToken] + incomingQtyFeeAdjusted + lpFeeQty
  newReserves[outputToken] = newReserves[outputToken] - outputQty

  -- validate if the reserves hold enough tokens for the swap to execute (this should be impossible)
  assert(bint.ult(bint.zero(), newReserves[outputToken]), "This swap would drain the pool")

  -- validate the output qty, if it is 0 or less, then the pool does not have enought liquidity
  assert(
    bint.ult(bint.zero(), outputQty),
    "There isn't enough liquidity in the reserves to complete this order"
  )

  -- compare output qty to the expected min
  -- if the output is less, send back the tokens
  assert(
    bint.ule(expectedMinOutput, outputQty),
    "Could not swap with expected min output"
  )

  -- add to reserves
  Reserves[tokenA] = newReserves[tokenA]
  Reserves[tokenB] = newReserves[tokenB]

  return {
    outputQty = bint(outputQty),
    totalFeeQty = bint(lpFeeQty + protocolFeeQty),
    lpFeeQty = bint(lpFeeQty),
    protocolFeeQty = bint(protocolFeeQty),
    outputToken = outputToken,
    inputToken = inputToken,
    inputQty = bint(inputQty),
    newReserves = newReserves,
    hasDiscount = hasDiscount
  }
end

function mod.swapWithMinOutput(message: Message): SwapResult
  local expectedMinOutput = bint(message.Tags["X-Expected-Min-Output"]) -- ensures we have a bint here

  -- quantity was checked in the credit notice handler
  local inputQty = bint(message.Tags.Quantity)

  -- the ID of the token sent
  local inputToken = message.From
  local swapper = message.Tags.Sender

  local swapResult = mod.executeSwapWithMinOutput(inputToken, inputQty, bint(expectedMinOutput), swapper)

  return swapResult
end

-- Swap interaction
---@param message Message
function mod.swap(swapMsg: Message)
  local pair = pool.getPair()

  assert(not swapMsg.Tags["X-Expected-Output"], "X-Expected-Output is disabled, use X-Expected-Min-Output instead")
  assert(pair[1] == swapMsg.From or pair[2] == swapMsg.From, "This pool does not support this token")

  local swapResult: SwapResult
  if swapMsg.Tags["X-Expected-Min-Output"] then
    swapResult = mod.swapWithMinOutput(swapMsg)
  else
    error("X-Expected-Min-Output is not present")
  end

  local sender = swapMsg.Tags.Sender

  -- send out tokens to swapper
  local payload = {
    Target = swapResult.outputToken,
    Action = "Transfer",
    Recipient = sender,
    Quantity = tostring(swapResult.outputQty),
    -- mark this transfer as the output of a successful swap
    ['X-Action'] = "Swap-Output",
    -- include reserves information as fwd tags, in order to support 
    -- agents in taking immedate action when they receive the credit-notice
    ["X-Reserves-Token-A"] = tostring(Reserves[pair[1]]),
    ["X-Reserves-Token-B"] = tostring(Reserves[pair[2]]),
    ["X-Fee-Bps"] = tostring(pool.getFeeBps()),
    ["X-Token-A"] = pair[1],
    ["X-Token-B"] = pair[2],
    ["X-Swap-Timestamp"] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(payload, swapMsg)

  -- send out fee tokens to collector
  local feeCollector = pool.getCollector()
  local collectedFee = tostring(swapResult.protocolFeeQty)
  if feeCollector and collectedFee ~= "0" then
    -- only send the message if we currently have a protocol fee and an active collector
    local feeCollectPayload = {
      Target = swapResult.inputToken,
      Action = "Transfer",
      Recipient = feeCollector,
      Quantity = collectedFee
    }
    fwdTags.sendWithForwardedTags(feeCollectPayload, swapMsg)
  elseif collectedFee ~= "0" and not feeCollector then
    -- in this specific case we may have forgotten to set the fee collector
    -- we log the unsent message so that we can retroactively perform the transfers
    local unsentFeePayload = {
      Target = ao.id,
      Action = "Log-Missing-Fee-Collector",
      ["Fee-Not-Sent"] = collectedFee
    }
    fwdTags.sendWithForwardedTags(unsentFeePayload, swapMsg)
  end

  local orderPayload = {
    ["Order-Id"] = swapMsg.Id,
    ["From-Token"] = swapResult.inputToken,
    ["From-Quantity"] = tostring(swapResult.inputQty),
    ["To-Token"] = swapResult.outputToken,
    ["To-Quantity"] = tostring(swapResult.outputQty),
    ["Reserves-Token-A"] = tostring(Reserves[pair[1]]),
    ["Reserves-Token-B"] = tostring(Reserves[pair[2]]),
    ["Token-A"] = pair[1],
    ["Token-B"] = pair[2],
    ["Fee-Percentage"] = tostring(pool.getFeesAsPercentages(swapResult.hasDiscount)["Fee-Percentage"]),
    ["Total-Fee"] = tostring(swapResult.totalFeeQty),
    ["LP-Fee"] = tostring(swapResult.lpFeeQty),
    ["Protocol-Fee"] = tostring(swapResult.protocolFeeQty),
    ["User"] = sender
  }

  -- return result
  local confirmation = json.decode(json.encode(orderPayload)) as SendMessagePayload
  confirmation.Target = ao.env.Process.Tags["AMM-Factory"]
  confirmation["Relay-To"] = sender
  confirmation["Action"] = "Order-Confirmation"
  confirmation["Trigger-Timestamp"] = tostring(os.time())
  fwdTags.sendWithForwardedTags(confirmation, swapMsg)

  -- notify subscribers
  local topicPayload = json.decode(json.encode(orderPayload)) as SendMessagePayload
  Subscribable.notifyTopic('order-confirmation', topicPayload, os.time())
  state.updateReserves()


  -- print result
  print(
    outputs.prefix("Swap", sender) ..
    Colors.blue ..
    tostring(swapResult.inputQty) ..
    " " ..
    outputs.formatAddress(swapResult.inputToken) ..
    Colors.gray ..
    " → " ..
    Colors.blue ..
    tostring(swapResult.outputQty) ..
    " " ..
    outputs.formatAddress(swapResult.outputToken) ..
    Colors.reset
  )
end

return mod
