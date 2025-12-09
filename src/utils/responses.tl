local json = require "json"

local mod = {}

function mod.sendReply(msg: Message, data: any, tags: {string: string})
  msg.reply({
      Action = msg.Tags.Action .. "-Response",
      Tags = tags,
      Data = json.encode(data)
  })
end

function mod.sendConfirmation(msg: Message, tags: {string: string})
  msg.reply({
      Action = msg.Tags.Action .. "-Confirmation",
      Tags = tags,
      Status = "OK"
  })
end

function mod.sendProgressUpdate(msg: Message, tags: {string: string})
  ao.send({
      Target = msg.From,
      Action = msg.Tags.Action .. "-Progress",
      Tags = tags
  })
end

function mod.sendError(msg: Message, errorMessage: string, tags: {string: string})
  ao.send({
      Target = msg.From,
      Action = msg.Tags.Action .. "-Error",
      Status = "Error",
      Tags = tags,
      Error = errorMessage
  })
end

return mod
