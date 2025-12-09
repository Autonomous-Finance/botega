local bint = require("utils.tl-bint")(256)
local bint_large = require("utils.tl-bint")(512)

local mod = {}

-- Returns the square root of the provided bigint
-- using the babylonian/Heron's method (rounds down)
---@param x BigInteger Unsigned integer to get the sqrt for
---@return BigInteger
function mod.sqrt(x: BigInteger): BigInteger
  -- handle trivial cases
  if bint.eq(x, bint.zero()) then return bint.zero() end
  if bint.ule(x, bint(3)) then return bint.one() end

  -- apply the algorithm
  local res = x
  local nextVal = bint.udiv(x, bint(2)) + bint.one()

  while bint.ult(nextVal, res) do
    res = nextVal
    nextVal = bint.udiv(bint.udiv(x, nextVal) + nextVal, bint(2))
  end

  return res
end

function mod.sqrt_large(x: BigInteger): BigInteger
  -- handle trivial cases
  if bint_large.eq(x, bint_large.zero()) then return bint_large.zero() end
  if bint_large.ule(x, bint_large(3)) then return bint_large.one() end

  -- apply the algorithm
  local res = x
  local nextVal = bint_large.udiv(x, bint_large(2)) + bint_large.one()

  while bint_large.ult(nextVal, res) do
    res = nextVal
    nextVal = bint_large.udiv(bint_large.udiv(x, nextVal) + nextVal, bint_large(2))
  end

  return res
end

function mod.div_round_up(x: BigInteger, y: BigInteger): BigInteger
  local quot, rem = bint.tdivmod(x, y)
  if not rem:iszero() and (bint.ispos(x) == bint.ispos(y)) then
    quot:_inc()
  end
  return quot
end

function mod.div_round_up_large(x: BigInteger, y: BigInteger): BigInteger
  local quot, rem = bint_large.tdivmod(x, y)
  if not rem:iszero() and (bint_large.ispos(x) == bint_large.ispos(y)) then
    quot:_inc()
  end
  return quot
end


return mod