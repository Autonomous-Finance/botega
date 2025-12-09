local mod = {}

local json = require "json"
require("amm.pool.globals")

local type Handler = function(msg: Message, env: any): any
local type Pattern = function(msg: Message): any


-- This function allows the wrapped pattern function
-- to continue the execution after the handler
---@param fn: function(msg: Message): any
---@return function(msg: Message): any
function mod.continue(fn: function(msg: Message): any): function(msg: Message): number
  return function(msg: Message): number
    local patternResult = fn(msg)
    if not patternResult or patternResult == 0 or patternResult == "skip" then
      return 0
    end
    return 1
  end
end

-- The "hasMatchingTag" utility function, but it supports
-- multiple values for the tag
---@param name: string
---@param values: {string}
---@return function(msg: Message): any
function mod.hasMatchingTagOf(name: string, values: {string}): function(msg: Message): number
  return function(msg: Message): number
    for _, value in ipairs(values) do
      local patternResult = Handlers.utils.hasMatchingTag(name, value)(msg)

      -- Teal type coercion needed for pattern result evaluation
      if patternResult as number ~= 0 and patternResult as boolean ~= false and patternResult as string ~= "skip" then
        return 1
      end
    end

    return 0
  end
end

-- Adds support to chain multiple patterns together
-- to use in one handler
---@param ...: {function(msg: Message): any}
---@return function(msg: Message): any
function mod._and(patterns: {Pattern}): function(msg: Message): number
  return function(msg: Message): number
    for _, pattern in ipairs(patterns) do
      local patternResult = pattern(msg)

      if not patternResult or patternResult == 0 or patternResult == "skip" then
        return 0
      end
    end

    return -1
  end
end



-- Handlers wrapped with this function will not throw Lua errors.
-- Instead, if the handler throws an error, the wrapper will
-- catch that and set the global RefundError to the error message.
-- We use this to refund the user if anything goes wrong with an
-- interaction that involves incoming transfers (such as swap or
-- provide)
function mod.catchWrapper(handler: Handler, handlerName: string): function(msg: Message, env: any): any
  -- return the wrapped handler
  local nameString = handlerName and handlerName .. " - " or ""

  return function(msg: Message, env: any): any
    -- execute the provided handler
    local status: boolean
    local result: any

    status, result = pcall(handler, msg, env)

    -- validate the execution result
    if not status then
      local traceback = debug.traceback()

      print("!!! Error: " .. nameString .. json.encode(traceback))
      local err = string.gsub(result as string, "%[[%w_.\" ]*%]:%d*: ", "")

      -- set the global RefundError variable
      -- this needs to be reset in the refund later
      RefundError = err

      return nil
    end

    return result
  end
end

-- If the passed-in handler throws an error, this wrapper will
-- catch that and instead error with the complete stack trace.
-- Use with handlers (top-level)
---@param handler: function(msg: Message, env: any): any
---@param handlerName: string?
---@return function(msg: Message, env: any): any
function mod.traceError(handler: Handler, handlerName: string): function(msg: Message, env: any): any
  local nameString = handlerName and handlerName .. " - " or ""
  -- return the wrapped handler
  return function(msg: Message, env: any): any
    -- execute the provided handler
    local status, result = pcall(handler, msg, env)
    if not status then
      local traceback = debug.traceback()

      local errorInfo = {
        message = "Error: " .. nameString .. tostring(traceback),
        originalError = result,
        handlerName = handlerName,
        messageType = type(msg),
        envType = type(env),
        -- Add more context information
        messageContent = msg and json.encode(msg) or "nil",
        envContent = env and json.encode(env) or "nil",
        -- Include the line number where the error occurred
        errorLine = traceback:match(":(%d+):"),
        -- Try to extract the specific error message
        specificError = traceback:match(":%d+:%s(.+)")
      }
      print("Detailed error information:")
      -- print(json.encode(errorInfo, { indent = true }))
      error(json.encode(errorInfo))
      print(result)
    end
    return result
  end
end

return mod