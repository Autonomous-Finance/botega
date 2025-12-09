local utils = require ".utils"

local mod = {}

--[[[
  Turns array into a map with key == value == arrayElement for each entry of the array
]]
mod.asKV = function(arrayTable)
  return utils.reduce(
    function(acc, val)
      acc[val] = val
      return acc
    end,
    {},
    arrayTable
  )
end

return mod
