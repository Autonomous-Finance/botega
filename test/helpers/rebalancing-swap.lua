local bint = require "utils.tl-bint" (256)
local bintmath = require "utils.bintmath"
local pool = require "amm.pool.pool"

local mod = {}

--[[
    swap 1 was from A to B, we now calculate the necessary input so that swap 2 has a balancing effect

    Approach based on preserving the reserves ratio
    reserve_A_pre_swaps / reserve_B_pre_swaps == reserve_A_post_swaps / reserve_B_post_swaps
]]
function mod.getInputForBalancingSwap(reservesA_PreSwap, reservesB_PreSwap, reservesA_PostSwap,
                                      reservesB_PostSwap)
  local Bint = require "utils.tl-bint" (512)

  -- need larger numbers for these calculations
  reservesA_PreSwap = Bint(tostring(reservesA_PreSwap))
  reservesB_PreSwap = Bint(tostring(reservesB_PreSwap))
  reservesA_PostSwap = Bint(tostring(reservesA_PostSwap))
  reservesB_PostSwap = Bint(tostring(reservesB_PostSwap))

  local lpFee = pool.getLPFeePercentage()
  local protocolFee = pool.getProtocolFeePercentage()

  -- printVerb(1)('----- CALC WITH RESERVES')
  -- printVerb(1)(tostring(reservesA_PreSwap))
  -- printVerb(1)(tostring(reservesB_PreSwap))
  -- printVerb(1)(tostring(reservesA_PostSwap))
  -- printVerb(1)(tostring(reservesB_PostSwap))
  -- printVerb(1)('------------------------')

  -- solving quadratic equation a * x^2 + b * x + c = 0

  -- local a = (1 - protocolFee / 100 ) * (1 - (lpFee + protocolFee) / 100)
  -- local b = reservesB_PostSwap * (2 - 2 * protocolFee / 100 - lpFee / 100)
  -- local c = reservesB_PostSwap ^ 2 - reservesB_PostSwap * reservesA_PostSwap * reservesB_PreSwap / reservesA_PreSwap


  -- we return (-b + sqr (b ^ 2 - 4 * a * c) ) / (2 * a)


  -- 'a' would be expressed as follows
  -- local a = bint.udiv(
  --     bint(math.floor(100 * (100 - lpFee))),
  --     bint(100 * 100)
  -- )
  -- we don't calculate 'a' separately due to its value being 0 as a separate calculation
  -- instead, we embed the 'a' calculation in the sqrArg calculation further down
  local a_num = Bint(
    math.floor(100 * (100 - protocolFee)) *
    math.floor(100 * (100 - lpFee - protocolFee))
  )
  local a_den = Bint(
    100 * 100 *
    100 * 100
  )


  local b = Bint.udiv(
    reservesB_PostSwap * Bint(math.floor(100 * (200 - 2 * protocolFee - lpFee))),
    Bint(100 * 100)
  )

  local c = reservesB_PostSwap * reservesB_PostSwap -
      Bint.udiv(
        reservesB_PostSwap * reservesA_PostSwap * reservesB_PreSwap,
        reservesA_PreSwap
      )

  -- local sqrArg = b * b - 4 * c * a
  local sign_c = Bint.ispos(c) and Bint(1) or
      Bint(-1) -- must extract the sign of c for bint.udiv to work correctly
  local sqrArg = b * b - sign_c * Bint.udiv(
  -- numerator
    Bint(4) *
    Bint.abs(c) *
    a_num
    ,
    -- denominator
    a_den
  )

  local sqr = bintmath.sqrt_large(sqrArg)

  -- print('b', tostring(b))
  -- print('c', tostring(c))
  -- print('sqr', tostring(sqr))

  -- local result = (-b + sqr) / 2 * a
  local result = Bint.udiv(
  -- numerator
    (-b + sqr) *
    a_den
    ,
    -- denominator
    Bint(2) *
    a_num
  )
  return bint(tostring(result)) -- return to bint(256)
end

return mod
