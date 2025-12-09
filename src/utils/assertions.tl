local bint = require "utils.tl-bint" (256)
local utils = require "utils.tl-utils" 
local mod = {}

-- Validates if the provided value can be parsed as a Bint
---@param val any Value to validate
---@return boolean
function mod.isBintRaw(val: any): boolean
  local success, result = pcall(
    function(): boolean
      -- check if the value is convertible to a Bint
      if type(val) ~= "number" and type(val) ~= "string" and not bint.isbint(val) then
        return false
      end

      -- check if the val is an integer and not infinity, in case if the type is number
      if type(val) == "number" and (val ~= val or val as number % 1 ~= 0) then
        return false
      end

      return true
    end
  )

  return success and result
end

-- Verify if the provided value can be converted to a valid token quantity
---@param qty any Raw quantity to verify
---@return boolean
function mod.isTokenQuantity(qty: BigInteger | string | number): boolean
  if type(qty) == "nil" then 
    return false 
  end

  -- If it's a Lua number, reject if negative
  if type(qty) == "number" and qty as number < 0 then 
    return false 
  end

  -- If it's a string, reject if it starts with a minus sign
  if type(qty) == "string" and string.sub(qty as string, 1, 1) == "-" then
    return false
  end

  -- Make sure it's convertible to a bint
  if not mod.isBintRaw(qty) then
    return false
  end

  if bint.isbint(qty) and (qty as BigInteger):lt(bint(0)) then
    return false
  end

  -- If we got here, it's non-negative, bint-compatible, etc.
  return true
end

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function mod.isAddress(addr: string, prependMsg: string): boolean
  local prepended = prependMsg and (prependMsg .. ": ") or ""

  assert(type(addr) == "string", prepended .. "Invalid type for Arweave address (must be string)")
  assert(addr:len() == 43, prepended .. "Invalid length for Arweave address")
  assert(addr:match("[A-z0-9_-]+"), prepended .. "Invalid characters in Arweave address")
  return true
end

-- Same as isAddress, but doesn't erorr out
function mod.checkIsAddress(addr: string): (boolean, string)
  if type(addr) ~= "string" then return false, "Invalid type for Arweave address (must be string)" end
  if addr:len() ~= 43 then return false, "Invalid length for Arweave address" end
  if not addr:match("[A-z0-9_-]+") then return false, "Invalid characters in Arweave address" end
  return true
end

-- Verify if the provided value is a valid percentage for slippages
-- Allowed precision is 2 decimals (min is 0.01)
---@param percentage any Percentage to verify
---@return boolean
function mod.isSlippagePercentage(percentage: number): boolean
  return type(percentage) == "number" and
      percentage > 0 and
      (percentage * 100) % 1 == 0 and
      percentage < 100
end

function mod.isFeeDiscountTier(tier: string)
  local isValid = tier == 'portfolio-agent'
  -- add other cases as they come
  assert(isValid, 'Invalid Fee Discount Tier: ' .. tier)
end

function mod.isValidFee(feeBps: string): boolean
  if not feeBps then return end

  local feeBpsNum = tonumber(feeBps)
  if feeBpsNum then
    local validFeeTiers = {25, 75, 125, 300}
    assert(utils.includes(feeBpsNum, validFeeTiers), "Fee-Bps, if provided, must be one of [25, 75, 125, 300]")
  else
    error("Fee-Bps, if provided, must be an integer")
  end

end

return mod
