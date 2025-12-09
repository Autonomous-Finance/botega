local record SpawnPayload
  Data: string
  Tags : {string : string}
end

global type MessagePattern = string | table | function

global type SendMessagePayload = { string: (string | {string: string}) }

global type SendMessagePayloadUnencoded = {string : any}

global record SentMessage
  receive: function(pattern: MessagePattern): Message
end

global record ao
  id: string
  send: function(payload: SendMessagePayloadUnencoded): SentMessage
  spawn: function(moduleId: string, payload: SpawnPayload): SentMessage
  record env
    record Module
      Id: string
    end
    record Process
      Tags: { string: string }
      Owner: string
    end
  end
end

global type MatchedHandler = function(msg: Message): function | nil

global Receive: function(pattern: MessagePattern): Message

global record Handlers
  add: function
  record utils
    hasMatchingTag: function(tag: string, value: string): MatchedHandler
    hasMatchingTagOf: function(tag: string, values: {string}): MatchedHandler
    hasMatchingData: function(value: string): MatchedHandler
    reply: function(input: string | {string: string}): nil
    continue: function<F>(fn: F): F
  end
end

global record Message
  Id: string
  From: string
  Target: string
  Tags: { string: string }
  Data: string
  Owner: string
  Timestamp: number
  reply: function({string: string | {string: string} }) -- arg is actually a partial message table
end

global record TokenNotice
  Id: string
  From: string
  Tags: { string: string }
  Data: string
  Owner: string
  Target: string
  Action: string
  Sender: string
  Recipient: string
  Quantity: string
end

global record Colors
  red: string
  green: string
  blue: string
  reset: string
  gray: string
end