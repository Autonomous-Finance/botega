local assertions = require "utils.assertions"
local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local utils = require "utils.tl-utils"
local json = require "json"
local responses = require "utils.responses"

require("amm.token.globals")


-- Balance of a specific account
---@param msg Message
local function balance(msg: Message)
  -- find account
  local account = msg.Tags.Recipient or msg.Tags.Target or msg.From

  -- check address
  assertions.isAddress(account)

  local bal = Balances[account] or bint.zero()

  local replyData = tostring(bal)
  local replyTags = {
    Balance = tostring(bal),
    Ticker = Ticker
  }
  responses.sendReply(msg, replyData, replyTags)

  print(
    outputs.prefix("Balance", msg.From) ..
    Colors.gray ..
    "Balance = " ..
    Colors.blue ..
    tostring(bal) ..
    Colors.reset
  )
end

-- All holders and their balances
---@param msg Message
local function balances(msg: Message)
  -- Convert balances object into raw bigint balances
  ---@type table<string, string>
  local rawBalances = {}

  for addr, bal in pairs(Balances) do
    rawBalances[addr] = tostring(bal)
  end

  local replyData = rawBalances
  local replyTags = { Ticker = Ticker }
  responses.sendReply(msg, replyData, replyTags)
  
  print(
    outputs.prefix("Balances", msg.From) ..
    Colors.gray ..
    "See response data" ..
    Colors.reset
  )
end

-- Calculate total supply
local function totalSupply(): BigInteger
  local r = utils.reduce(
    function(acc: BigInteger, val: BigInteger) : BigInteger return acc + val end,
    bint.zero(),
    utils.values(Balances)
  )
  return r
end

-- Calculate the integer amount of tokens using the token decimals
-- (balances are stored with the *10^decimals* multiplier)
local function toSubUnits(val: BigInteger): BigInteger
  return val * bint.ipow(bint(10), bint(Denomination))
end

return {
  balance = balance,
  balances = balances,
  totalSupply = totalSupply,
  toSubUnits = toSubUnits
}
