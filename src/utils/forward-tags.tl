local utils = require "utils.tl-utils"
local mod = {}

-- Tags beginning with "X-" are forwarded
-- Exceptions: certain x- tags are excluded because these have
-- special usage within the AMM swap/provide logic
function mod.sendWithForwardedTags(toSend: SendMessagePayload, triggerMessage: Message): SentMessage
  -- Add forwarded tags to the credit and debit notice messages
  for tagName, tagValue in pairs(triggerMessage.Tags) do
    if string.sub(tagName, 1, 2) == "X-" then
      local reservedTags = {
        "X-Action",
        -- swap
        "X-Slippage-Tolerance",
        "X-Expected-Min-Output",
        -- provide
        "X-Slippage-Tolerance",
        "X-Token-A",
        "X-Reserves-Token-A",
        "X-Token-B",
        "X-Reserves-Token-B",
        "X-Swap-Timestamp",
        "X-Fee-Bps",

        -- credit notice error
        "X-Error",
        -- refund
        "X-Refund-Reason",
        "X-Refunded-Transfer",
        "X-Refunded-Order",
        "X-Refunded-Provide",
      }
      if not utils.includes(tagName, reservedTags) then
        toSend[tagName] = tagValue
      end
    end
  end

  return ao.send(toSend)
end

-- Tags beginning with "X-" are forwarded
function mod.sendWithAllForwardedTags(toSend: SendMessagePayload, triggerMessage: Message): SentMessage
  -- Add forwarded tags to the credit and debit notice messages
  for tagName, tagValue in pairs(triggerMessage.Tags) do
    if string.sub(tagName, 1, 2) == "X-" then
      toSend[tagName] = tagValue
    end
  end

  return ao.send(toSend)
end

return mod