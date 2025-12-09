local assertions = require "utils.assertions"
local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local utils = require "utils.tl-utils"
local bintmath = require "utils.bintmath"
local responses = require "utils.responses"

require('amm.pool.globals')

-- temporary, for portfolio agents
global DISCOUNTED_FEE: number = 2
IsFeeDiscountDisabled = IsFeeDiscountDisabled or false

local pool = {}

-- Get pool token pair
---@return {string}
function pool.getPair(): {string}
  -- token A
  local tokenA: string = ao.env.Process.Tags["Token-A"]

  -- token B
  local tokenB: string = ao.env.Process.Tags["Token-B"]

  return { tokenA, tokenB }
end

-- Get reserves
function pool.getReserves(): {string: BigInteger}
  return Reserves
end

-- Get constant K of the AMM formula
---@return BigInteger
function pool.K(): BigInteger
  local pair = pool.getPair()

  return Reserves[pair[1]] * Reserves[pair[2]]
end

function pool.getLPFeePercentage(discounted: boolean): number
  local regularFee = tonumber(ao.env.Process.Tags["Fee-Bps"] or '25') / 100
  local discountedFee = DISCOUNTED_FEE / 100
  
  if IsFeeDiscountDisabled then
    return regularFee
  end
  
  return discounted and discountedFee or regularFee
end

function pool.getProtocolFeePercentage(): number
  return 0
end

function pool.getFeesAsPercentages(discounted: boolean): {string: string}
  local lp = pool.getLPFeePercentage(discounted)
  local protocol = pool.getProtocolFeePercentage()
  local total = lp + protocol

  return {
    ["LP-Fee-Percentage"] = tostring(lp),
    ["Protocol-Fee-Percentage"] = tostring(protocol),
    ["Fee-Percentage"] = tostring(total)
  }
end

function pool.getFeeBps(): number
  return tonumber(pool.getFeesAsPercentages(false)["Fee-Percentage"]) * 100
end

global record TotalFeeForSubscriber
  TotalFee: string
end

function pool.getTotalFeeForSubscriber() : TotalFeeForSubscriber
  return {
    TotalFee = tostring(pool.getLPFeePercentage() + pool.getProtocolFeePercentage())
  }
end

global record ReservesForSubscriber
  ["Reserves-Token-A"]: string
  ["Reserves-Token-B"]: string
  ["Token-A"]: string
  ["Token-B"]: string
end

function pool.getReservesForSubscriber() : ReservesForSubscriber
  local pair = pool.getPair()

  return {
    ["Reserves-Token-A"] = tostring(Reserves[pair[1]]),
    ["Reserves-Token-B"] = tostring(Reserves[pair[2]]),
    ["Token-A"] = pair[1],
    ["Token-B"] = pair[2],
  }
end


function pool.getCollector(): string
  return FeeCollector
end

-- Raw token output qty function
---@param input BigInteger Input qty (in base amount)
---@param token string Token address
---@return BigInteger
function pool.getOutput(input: BigInteger, token: string): BigInteger
  -- the token pair of this pool
  local pair = pool.getPair()

  -- constant K
  local K = pool.K()

  -- find the other token in the pair
  local otherToken: string = utils.find(
    function(val: string): boolean return val ~= token end,
    pair
  ) as string

  -- x * y = k
  -- (x + in) * (y - out) = k
  -- y - out = k / (x + in)
  -- -out = k / (x + in) - y
  -- out = y - k / (x + in)

  local out = Reserves[otherToken] as BigInteger - bintmath.div_round_up(K, (Reserves[token] + input))

  return out
end

function pool.deductFees(inputQty: BigInteger, swapper: string): (BigInteger, BigInteger, BigInteger, boolean)
  local hasDiscount = FeeDiscountWhitelist[swapper] == true
  local lpFeePercent = pool.getLPFeePercentage(hasDiscount)
  local protocolFeePercent = pool.getProtocolFeePercentage()

  local precisionMultiplier = 100

  -- fee adjusted incoming token qty (2 fractions of precision)
  local qtyExcludingFees = inputQty * bint(math.floor((100 - lpFeePercent - protocolFeePercent) * precisionMultiplier))

  local incomingQtyFeeAdjusted = bint.udiv(
    qtyExcludingFees,
    bint(100 * precisionMultiplier)
  )

  local totalFees = inputQty - incomingQtyFeeAdjusted
  local totalFeePercent = protocolFeePercent + lpFeePercent
  local lpFeeRatio = totalFeePercent == 0 and 1 or lpFeePercent / totalFeePercent
  local lpFee = bint.udiv(totalFees * bint(math.ceil(100 * lpFeeRatio)), bint(100)) -- lp fee rounded up for benefit of LP providers
  local protocolFee = totalFees - lpFee
  return incomingQtyFeeAdjusted, lpFee, protocolFee, hasDiscount
end

-- Get the price of one token in the units of the other
---@param msg Message
function pool.getPrice(msg: Message)
  -- token to get the price for
  local token: string = msg.Tags.Token

  -- the token pair of this pool
  local pair = pool.getPair()

  if not utils.includes(token, pair) then
    local replyData = nil
    local replyTags = { Price = "0"}
    responses.sendReply(msg, replyData, replyTags)

    print(
      outputs.prefix("Get-Price", msg.From) ..
      Colors.gray ..
      "Price = " ..
      Colors.blue ..
      "0" ..
      Colors.reset
    )
    return
  end

  -- verify optional quantity
  assert(
    msg.Tags.Quantity == nil or assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid quantity"
  )

  -- optional quantity
  local quantity = msg.Tags.Quantity and bint(msg.Tags.Quantity) or bint.one()

  -- final price
  local price = pool.getOutput(quantity, token)

  local replyData = nil
  local replyTags = { Price = tostring(price)}
  responses.sendReply(msg, replyData, replyTags)
  print(
    outputs.prefix("Get-Price", msg.From) ..
    Colors.gray ..
    "Price = " ..
    Colors.blue ..
    tostring(price) ..
    Colors.reset
  )
end

-- Get expected output for given swap input and swapper account
function pool.getSwapOutput(msg: Message)
  -- input token
  local tokenIn: string = msg.Tags.Token

  -- the token pair of this pool
  local pair = pool.getPair()

  if not utils.includes(tokenIn, pair) then
    responses.sendError(msg, "Unknown token")

    print(
      outputs.prefix("Get-Output", msg.From) ..
      Colors.gray ..
      "Error = " ..
      Colors.blue ..
      "Unknown Token" ..
      Colors.reset
    )
    return
  end

  local quantityAsString = msg.Tags.Quantity
  if not assertions.isTokenQuantity(quantityAsString) then
    error("Please provide a valid 'Quantity' tag for the swap input")
  end
  local quantity = bint(quantityAsString)

  local swapper = msg.Tags.Swapper
  assertions.isAddress(
    swapper,
    "'Swapper' tag must contain a valid address. Use address '0000000000000000000000000000000000000000000' if you need the output for an account without fee discounts"
  )

  local qtyAfterFees, lpFeeQty, protocolFeeQty, hasDiscount = pool.deductFees(quantity, swapper)

  -- final output
  local output = pool.getOutput(qtyAfterFees, tokenIn)

  local replyData = nil
  local replyTags = {
    Output = tostring(output),
    ["Quantity-After-Fees"] = tostring(qtyAfterFees),
    ["LP-Fee-Quantity"] = tostring(lpFeeQty),
    ["Protocol-Fee-Quantity"] = tostring(protocolFeeQty),
    ["Has-Fee-Discount"] = tostring(hasDiscount)
  }
  responses.sendReply(msg, replyData, replyTags)
  print(
    outputs.prefix("Get-Swap-Output", msg.From) ..
    Colors.gray ..
    "Output = " ..
    Colors.blue ..
    tostring(output) ..
    Colors.reset
  )
end

-- Initialize the pool
function pool.init()
  local pair = pool.getPair()

  ---@type {string: BigInteger}
  if Reserves then
    Reserves = {
      [pair[1]] = bint(tostring(Reserves[pair[1]])),
      [pair[2]] = bint(tostring(Reserves[pair[2]]))
    }
  else
    Reserves = {
      [pair[1]] = bint.zero(),
      [pair[2]] = bint.zero()
    }
  end

  if PendingProvides then
    for _, pp in ipairs(PendingProvides) do
      pp.quantity = bint(tostring(pp.quantity))
    end
  else
    PendingProvides = {}
  end

  FeeDiscountWhitelist = FeeDiscountWhitelist or {}

  print(
    Colors.gray ..
    "Pool was set up for pair: " ..
    outputs.formatAddress(pair[1]) ..
    Colors.gray ..
    "/" ..
    outputs.formatAddress(pair[2])
  )
end

-- Calculate the slippage limit for a provided tolerance and
-- expected output
---@param tolerance number Slippage tolerance percentage
---@param expected BigInteger Expected output
---@param limit "lower"|"upper" Limit type (always required for readability)
---@return BigInteger
function pool.slippageLimit(tolerance: number, expected: BigInteger, limit: string): BigInteger
  -- validate limit
  assert(limit == "lower" or limit == "upper", "Invalid limit type")

  -- account for lower limit
  if limit == "lower" then tolerance = -tolerance end

  -- account for precision
  local multiplier = 100
  local multipliedPercentage = (100 + tolerance) * multiplier

  -- calculate limit
  return bint.udiv(
    expected * bint(multipliedPercentage),
    bint(100 * multiplier)
  )
end

-- WHITELISTING FOR FEE DISCOUNTS

function pool.handleWhitelistForFeeDiscount(msg: Message)
  assert(
    msg.From == Owner or msg.From == ao.id, "Only the owner or self can operate the whitelist"
  )
  local address = msg.Tags["Address"]
  FeeDiscountWhitelist[address] = true
end

function pool.handleGetWhitelistedForFeeDiscount(msg: Message)
  local address = msg.Tags["Address"]
  local isWhitelisted = FeeDiscountWhitelist[address] == true
  msg.reply({
    Target = msg.From,
    Action = "Resp-Whitelisted-For-Fee-Discount",
    ["Whitelisted-For-Fee-Discount"] = isWhitelisted and "true" or "false"
  })
end

function pool.handleDisableFeeDiscount(msg: Message)
  assert(
    msg.From == Owner or msg.From == ao.id, "Only the owner or self can disable fee discounts"
  )
  IsFeeDiscountDisabled = true
end

return pool