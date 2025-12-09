require "factory.globals"

local mod = {}

-- Sort tokens to maintain order and prevent inverse duplicates
function mod.sortTokens(tokenA: string, tokenB: string): string, string
  if tokenA < tokenB then
    return tokenA, tokenB
  else
    return tokenB, tokenA
  end
end

-- Check if pool already exists
-- Note: the tokens should be sorted before calling this function
function mod.poolExists(tokenA: string, tokenB: string, feeBps: string): boolean
  local poolPairs = PoolsByTokens[tokenA .. ":" .. tokenB]

  if not poolPairs then return false end

  local poolId = poolPairs[feeBps]

  if not poolId then return false end

  return true
end

local record CompatibilityInfo
  isCompatibleA: boolean
  isCompatibleB: boolean
  tokenAInfo: Message
  tokenBInfo: Message
end
function mod.checkTokenCompatibility(tokenA: string, tokenB: string): CompatibilityInfo
  
  local checkToken = function(processId: string): (boolean, Message)
    ao.send({
      Target = processId,
      Action = 'Info'
    })
    local resp = Receive(
      function (m : Message) : boolean
        return m.Tags['From-Process'] == processId
          and m.Tags.Ticker ~= nil
          and m.Tags.Denomination ~= nil
          and m.Tags.Name ~= nil
      end
    )
    local denomination = tonumber(resp.Tags.Denomination)
    local isOK = resp.Tags['X-Reference'] ~= nil
      and denomination ~= nil
      and denomination > 0 and denomination <= 18
    return isOK, resp
  end

  local isOKA, tokenAInfo = checkToken(tokenA)
  local isOKB, tokenBInfo = checkToken(tokenB)

  return {
    isCompatibleA = isOKA,
    isCompatibleB = isOKB,
    tokenAInfo = tokenAInfo,
    tokenBInfo = tokenBInfo
  }
end

return mod
