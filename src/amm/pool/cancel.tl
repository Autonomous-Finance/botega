local assertions = require "utils.assertions"
local outputs = require "utils.output"
local provide = require "amm.pool.provide"
local utils = require "utils.tl-utils"
local fwdTags = require "utils.forward-tags"
require("amm.pool.globals")

local function cancel(message: Message)
  -- the incoming token transfer ID
  local transferID = message.Tags.Transfer

  assertions.isAddress(transferID)

  local transfer = utils.find(
    function(val: PendingProvideType): boolean return val.id == transferID end,
    PendingProvides
  ) as PendingProvideType

  assert(transfer ~= nil, "Could not find provided transfer")
  assert(transfer.sender == message.From, "Transfer owner is not the caller")

  -- send back the tokens
  local transferMsg = {
    Target = transfer.token,
    Action = "Transfer",
    Recipient = transfer.sender,
    Quantity = tostring(transfer.quantity),
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(transferMsg, message)

  -- remove the pending provide (transfer)
  provide.closePending({ id = transfer.id })

  -- send a notice about the refund
  local refundNotice = {
    Target = transfer.sender,
    Action = "Refund-Notice",
    Transfer = transfer.id,
    Quantity = tostring(transfer.quantity),
    ['Trigger-Timestamp'] = tostring(os.time())
  }
  fwdTags.sendWithForwardedTags(refundNotice, message)

  -- print result
  print(
    outputs.prefix("Cancel", message.From) ..
    Colors.gray ..
    "Sending back " ..
    Colors.blue ..
    tostring(transfer.quantity) ..
    " " ..
    outputs.formatAddress(transfer.token) ..
    Colors.gray ..
    " to " ..
    outputs.formatAddress(transfer.sender)
  )
end

return {
  cancel = cancel
}
