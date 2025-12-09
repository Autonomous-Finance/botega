local token = require "amm.token.token"
local responses = require "utils.responses"
require("subscriptions.subscribable")
global Subscribable: TSubscribable 

local mod = {}

function mod.handleGetInfo(msg: Message)
  local replyData = { Subscriptions = Subscribable.getInfo() }
  local replyTags = token.info()
  responses.sendReply(msg, replyData, replyTags)
end

return mod