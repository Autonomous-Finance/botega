local assertions = require "utils.assertions"
local pool = require "amm.pool.pool"
local utils = require "utils.tl-utils"
local fwdTags = require "utils.forward-tags"

local mod = {}

-- Handle incoming transfers
---@param message Message
function mod.creditNotice(creditNotice: Message)
  -- quantity in string format
  local rawQuantity = creditNotice.Tags.Quantity

  -- validate quantity
  assert(
    assertions.isTokenQuantity(rawQuantity),
    "Invalid token quantity"
  )

  -- received token process ID
  local token = creditNotice.From

  -- forwarded action
  local XAction = creditNotice.Tags["X-Action"] or "No-Action"

  -- token pair
  local pair = pool.getPair()

  -- supported forwarded actions
  local actions = { "Swap", "Provide", "Operational" }

  -- ensure that the token sent is in the pair
  -- and the sender provided a forwarded action
  if utils.includes(token, pair) and utils.includes(XAction, actions) then
    return
  end

  if (token == Subscribable.PAYMENT_TOKEN and XAction == "Pay-For-Subscription") then
    return
  end

  -- transfer sender in receipt
  local sender = creditNotice.Tags.Sender

  -- the token is not in the pair, or the forwarded
  -- action is invalid, refund the tokens
  local errorMsg = {
    Target = token,
    Action = "Transfer",
    Recipient = sender,
    Quantity = rawQuantity,
    ["X-Action"] = utils.includes(XAction, actions) and (XAction .. "-Error") or "Credit-Notice-Error",
    ["X-Error"] = utils.includes(XAction, actions) and "Token is not in pair" or "Invalid forwarded action",
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(errorMsg, creditNotice)
end

return mod
