local outputs = require "utils.output"
local provide = require "amm.pool.provide"
local pool = require "amm.pool.pool"
local utils = require "utils.tl-utils"
local bintModule = require "utils.tl-bint"
local bint = bintModule(256)
local fwdTags = require "utils.forward-tags"

local mod = {}

local enum SupportedRefundAction
   "Swap"
   "Provide"
end

-- This function refunds the user if the swap/provide interaction failed
function mod.refund(creditNotice: Message)
  -- if the refund error is undefined, we don't need
  -- to refund the user
  if not RefundError then return end

  -- message action
  ---@type SupportedRefundActions
  assert(creditNotice.Tags["X-Action"] == "Swap" or creditNotice.Tags["X-Action"] == "Provide", 'invalid refund action')
  local action: SupportedRefundAction = creditNotice.Tags["X-Action"] as SupportedRefundAction
  

  ---@type table<SupportedRefundActions, string>
  local sourceInteractionIDs = {
    Swap = "Order",
    Provide = "Provide"
  }

  -- sender of the transfer
  local sender = creditNotice.Tags.Sender

  -- refund this transfer (that the credit-notice indicated)
  local refundMsg = {
    Target = creditNotice.From,
    Tags = {
      Action = "Transfer",
      Recipient = sender,
      Quantity = creditNotice.Tags.Quantity,
      ["X-Refund-Reason"] = RefundError,
      ["X-Refunded-Transfer"] = creditNotice.Tags["Pushed-For"],
      ["X-Refunded-" .. sourceInteractionIDs[action]] = creditNotice.Id,
      ['Trigger-Timestamp'] = tostring(os.time())
    }
  }
  fwdTags.sendWithForwardedTags(refundMsg, creditNotice)

  -- the error message is the global RefundError variable set by 
  -- one of the failed assertions in swap/provide
  local errorMessage: SendMessagePayload = {
    Target = ao.env.Process.Tags["AMM-Factory"],
    ["Relay-To"] = sender,
    ["Response-For"] = action,
    [sourceInteractionIDs[action] .. "-Id"] = creditNotice.Id,
    Result = RefundError
  }

  -- if this is a provide interaction, we also need to
  -- refund the provide 
  if action == "Provide" then
    -- find pending provide
    local pendingProvide = utils.find(
      ---@param val PendingProvide
      function (val: PendingProvideType): boolean return val.sender == sender end,
      PendingProvides
    )

    -- pending provide for this user was found,
    -- refund and remove it from the list of
    -- pending provides
    if pendingProvide then
      -- refund
      local foundPendingProvide = pendingProvide as PendingProvideType
      local pendingProvideRefundMsg = {
        Target = foundPendingProvide.token,
        Tags = {
          Action = "Transfer",
          Recipient = sender,
          Quantity = tostring(foundPendingProvide.quantity),
          ["X-Refunded-Transfer"] = foundPendingProvide.id,
          ["X-Refunded-" .. sourceInteractionIDs[action as SupportedRefundAction]] = creditNotice.Id,
          ['Trigger-Timestamp'] = tostring(os.time())
        }
      }
      fwdTags.sendWithForwardedTags(pendingProvideRefundMsg, creditNotice)

      errorMessage.Action = "Provide-Error"
      errorMessage['Token-A'] = creditNotice.From
      errorMessage['Token-B'] = foundPendingProvide.token
      errorMessage['Token-A-Quantity'] = creditNotice.Tags.Quantity
      errorMessage['Token-B-Quantity'] = tostring(bint(foundPendingProvide.quantity))
      errorMessage["Trigger-Timestamp"] = tostring(os.time())

      -- remove
      provide.closePending({ id = foundPendingProvide.id })
    end
  else 
    local pair = pool.getPair()

    errorMessage.Action = "Order-Error"
    errorMessage['From-Token'] = creditNotice.From
    errorMessage['From-Quantity'] = creditNotice.Tags.Quantity
    errorMessage['To-Token'] = creditNotice.From == pair[1] and pair[2] or pair[1]
    errorMessage['To-Quantity'] = creditNotice.Tags["X-Expected-Min-Output"]
    errorMessage["Trigger-Timestamp"] = tostring(os.time())

  end

  -- send error message to the sender of the swap/provide message
  fwdTags.sendWithForwardedTags(errorMessage, creditNotice)

  -- print refund result
  print(
    outputs.prefix("Refund", sender) ..
    Colors.gray ..
    "Refunding " ..
    Colors.blue ..
    action ..
    " " ..
    Colors.gray ..
    "(" ..
    RefundError ..
    ")" ..
    Colors.reset
  )

  -- reset refund error
  -- this is IMPORTANT, so the handler won't interpret
  -- future messages/interactions as failed
  RefundError = nil
end

return mod
