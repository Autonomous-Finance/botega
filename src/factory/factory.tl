require "factory.globals"
local utils = require "utils.tl-utils"
local json = require "json"
local factory_lib = require "factory.factory_lib"
local assertions = require "utils.assertions"
local responses = require "utils.responses"
local amm_source_code = require "amm_as_template"
local reset_modules_code = require "utils.reset-modules-code"
local set_dexi_token_code = require "utils.set-dexi-token-code"

OPERATOR = OPERATOR or ao.env.Process.Tags.Operator

Owner = Owner or ao.env.Process.Owner
DexiTokenProcess = DexiTokenProcess or ao.env.Process.Tags["Dexi-Token"] or nil
AmmMonitor = AmmMonitor or ao.env.Process.Tags["Dexi"] or nil
Initialized = Initialized or false

FeeCollector = FeeCollector or nil
TrustedWhitelistersForFeeDiscount = TrustedWhitelistersForFeeDiscount or {}

Tokens = Tokens or {}

Pools = Pools or {}

PoolsByTokens = PoolsByTokens or {}
PoolFeesBps = PoolFeesBps or {}

Factory = Factory or {}

HB_CACHE_PROCESS = HB_CACHE_PROCESS or ao.env.Process.Tags["HB-Cache-Process"] or "3wzT1RDOlXQO-gX3CLq9XV1yGUtK5RE3W_p3kqhByWg"

global DEFAULT_LP_FEE = '25'

Handlers.add(
  "Initialize",
  function(msg: Message)
      if msg.From ~= OPERATOR then
        error('Unauthorized')
      end
    
      assert(msg.Tags.PaymentTokenProcess, 'PaymentTokenProcess is required for Dexi initialization')
      assert(msg.Tags.DexiProcess, 'DexiProcess is required for Dexi initialization')
    
      DexiTokenProcess = msg.Tags.PaymentTokenProcess
      AmmMonitor = msg.Tags.DexiProcess
    
      Initialized = true
      ao.send({
        Target = ao.id,
        Event = 'Initialized'
    })
  end
)

Handlers.add(
  "Set-Fee-Collector",
  Handlers.utils.hasMatchingTag("Action", "Set-Fee-Collector"),
  function(msg: Message)
    assert(msg.From == Owner or msg.From == ao.id, "Only the owner or self can set the fee collector")
    assertions.isAddress(msg.Tags["Fee-Collector"], "Invalid Tag Fee-Collector")
    FeeCollector = msg.Tags["Fee-Collector"]
    
    local replyData = nil
    local replyTags = {
      ["Fee-Collector"] = FeeCollector,
      Status = "OK"
    }
    responses.sendReply(msg, replyData, replyTags)
  end
)
-- ================ ADDING POOLS =================

-- HELPERS

function Factory.handleAddPool(msg: Message)
  local isValidRequest, tokenAInfo, tokenBInfo = Factory.validateAddPoolRequest(msg)
  if not isValidRequest then
    return
  end

  Factory.initializeAddPool(msg)

  local processId = Factory.createPool(msg, tokenAInfo, tokenBInfo)

  Factory.autoSubscribeDexiToPool(processId)
  
  Factory.setFeeCollectorInPool(processId)

  local confirmationTags = { 
    ["Pool-Id"] = processId, 
    ["Token-A"] = msg.Tags["Token-A"], 
    ["Token-B"] = msg.Tags["Token-B"],
    ["Trigger-Timestamp"] = tostring(os.time()),
    ["Fee-Bps"] = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE
  }
  responses.sendConfirmation(msg, confirmationTags)

  ao.send({
    Target = HB_CACHE_PROCESS,
    Action = "Pools/Patch-Pool",
    Data = json.encode({
      poolId = processId,
      tokenA = msg.Tags["Token-A"],
      tokenB = msg.Tags["Token-B"],
      feeBps = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE,
    })
  })

  ao.send({
    Target = HB_CACHE_PROCESS,
    Action = "Tokens/Patch",
    Data = json.encode(Tokens)
  })
end

function Factory.validateAddPoolRequest(msg: Message): (boolean, Message, Message)
  -- Fee configuration
  assertions.isValidFee(msg.Tags["Fee-Bps"])

  -- ADDRESS VALIDATION

  local tokenA: string = msg.Tags["Token-A"]
  local isValidTokenA, errorA = assertions.checkIsAddress(tokenA)
  if not isValidTokenA then
    responses.sendError(msg, "Invalid Token-A :" .. errorA, {
      ["Token-A"] = msg.Tags["Token-A"],
      ["Token-B"] = msg.Tags["Token-B"],
      ["Trigger-Timestamp"] = tostring(os.time())
    })
    return false
  end
  
  local tokenB: string = msg.Tags["Token-B"]
  local isValidTokenB, errorB = assertions.checkIsAddress(tokenB)
  if not isValidTokenB then
    responses.sendError(msg, "Invalid Token-B :" .. errorB, {
      ["Token-A"] = msg.Tags["Token-A"],
      ["Token-B"] = msg.Tags["Token-B"],
      ["Trigger-Timestamp"] = tostring(os.time())
    })
    return false
  end

  assert(tokenA ~= tokenB, "Tokens A and B must be different")

  -- POOL DUPLICATION

  local feeToUse = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE
  if factory_lib.poolExists(tokenA, tokenB, feeToUse) or factory_lib.poolExists(tokenB, tokenA, feeToUse) then 
    responses.sendError(msg, "Pool with these tokens and this fee already exists", {
      ["Token-A"] = msg.Tags["Token-A"],
      ["Token-B"] = msg.Tags["Token-B"],
      ["Fee-Bps"] = msg.Tags["Fee-Bps"],
      ["Trigger-Timestamp"] = tostring(os.time())
    })
    return false
  end

  -- COMPATIBLITY (aos 2.0)

  local compatCheck = factory_lib.checkTokenCompatibility(tokenA, tokenB)
  local areCompatible = compatCheck.isCompatibleA and compatCheck.isCompatibleB
  
  if not areCompatible then
    local respTags = {
      ["Compatible-A"] = tostring(compatCheck.isCompatibleA),
      ["Compatible-B"] = tostring(compatCheck.isCompatibleB),
      ["Token-A"] = msg.Tags["Token-A"],
      ["Token-B"] = msg.Tags["Token-B"],
      ["Trigger-Timestamp"] = tostring(os.time())
    }
    local respError = "Tokens are not supported (aos 2.0 replies)"
    responses.sendError(msg, respError, respTags)
    return false
  end
  
  return true, compatCheck.tokenAInfo, compatCheck.tokenBInfo
end

function Factory.initializeAddPool(msg: Message)
  local tokenA: string = msg.Tags["Token-A"]
  local tokenB: string = msg.Tags["Token-B"]
  local feeBps = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE
  
  -- While a pool is spawning or evaluating, we don't store it in Pools
  local poolPairs = PoolsByTokens[tokenA .. ":" .. tokenB] or {}
  poolPairs[feeBps] = 'pending'
  PoolsByTokens[tokenA .. ":" .. tokenB] = poolPairs

  local updateTags = { ["Pending"] = "true" }
  responses.sendProgressUpdate(msg, updateTags)
end

function Factory.createPool(msg: Message, tokenAInfo: Message, tokenBInfo: Message): string
  local processId = Factory._spawnPool(msg, tokenAInfo, tokenBInfo)

  Factory._recordSpawnedPool(msg, processId)

  local updateTags = {
    ["Eval-Successful"] = "true",
    ["Pool-Id"] = processId
  }
  responses.sendProgressUpdate(msg, updateTags)

  return processId
end

function Factory._spawnPool(msg: Message, tokenAInfo: Message, tokenBInfo: Message): string
  local tokenA: string = msg.Tags["Token-A"]
  local tokenB: string = msg.Tags["Token-B"]
  local feeBps = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE

  assert(tokenAInfo.Tags.Ticker ~= nil, "Token A has no Ticker")
  assert(tokenBInfo.Tags.Ticker ~= nil, "Token B has no Ticker")

  ao.send({
    Target = ao.id,
    Action = "LOG-SPAWN-INITIATE",
    Time = tostring(msg.Timestamp),
  })

  -- Spawn process
  local evalConfirmation = [[
      ao.send({
      Target = ']] .. ao.id .. [[',
      Action = 'Eval-Confirmation',
      })
  ]]

  local stringsource = amm_source_code as string

  local spawnSuccessMsg: Message = ao.spawn('JArYBF-D8q2OmZ4Mok00sD2Y_6SYEQ7Hjx-6VZ_jl3g', {
    Tags = {
      Name = "Botega LP " .. tokenAInfo.Tags.Ticker .. "/" .. tokenBInfo.Tags.Ticker,
      ['Token-A'] = tokenA,
      ['Token-B'] = tokenB,
      ['Token-A-Ticker'] = tokenAInfo.Tags.Ticker,
      ['Token-B-Ticker'] = tokenBInfo.Tags.Ticker,
      ['Fee-Bps'] = feeBps,
      ['Dexi-Token'] = DexiTokenProcess,
      ['AMM-Factory'] = ao.id,
      ['Authority'] = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY',
      ['On-Boot'] = 'Data',
    },
    Data = stringsource .. evalConfirmation,
  }).receive()

  ao.send({
    Target = ao.id,
    Action = "LOG-SPAWN-SUCCESS",
    Time = tostring(spawnSuccessMsg.Timestamp),
    Process = spawnSuccessMsg.Tags['Process']
  })
  local processId = spawnSuccessMsg.Tags['Process']

  return processId
end

function Factory._recordSpawnedPool(msg: Message, processId: string)
  local tokenA: string = msg.Tags["Token-A"]
  local tokenB: string = msg.Tags["Token-B"]
  local feeBps: string = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE
  
  local poolPairs = PoolsByTokens[tokenA .. ":" .. tokenB] or PoolsByTokens[tokenB .. ":" .. tokenA] or {}

  -- add the new pool to the list of pools for these tokens
  poolPairs[feeBps] = processId

  PoolsByTokens[tokenA .. ":" .. tokenB] = poolPairs
  Pools[processId] = { tokenA, tokenB }
  PoolFeesBps[processId] = feeBps
  
  if not utils.includes(tokenA, Tokens) then
    table.insert(Tokens, tokenA)
  end
  
  if not utils.includes(tokenB, Tokens) then
    table.insert(Tokens, tokenB)
  end
end

function Factory.autoSubscribeDexiToPool(processId: string)
  ao.send({
    Target = DexiTokenProcess,
    Action = "Transfer",
    Quantity = "100",
    Recipient = AmmMonitor,
    ["X-Action"] = "Register-AMM",
    ["X-AMM-Process"] = processId
  })
end

function Factory.setFeeCollectorInPool(processId: string)
  ao.send({
    Target = processId,
    Action = "Set-Fee-Collector",
    ["Fee-Collector"] = FeeCollector
  })
end

function Factory.handleWhitelistForFeeDiscountInAmms(msg: Message)
  local from = msg.From
  local isTrustedWhitelister = utils.includes(from, TrustedWhitelistersForFeeDiscount)
  local mayWhitelist = isTrustedWhitelister or from == Owner or from == OPERATOR or from == ao.id
  if not mayWhitelist then 
    error("Only the owner, operator, self or trusted whitelisters can update whitelists for fee discounts")
  end

  local address = msg.Tags['Address'] as string
  assertions.isAddress(address)

  local targetPools = json.decode(msg.Tags['Target-AMMs']) as { string }
  local allPools = targetPools == nil
  if allPools then
    targetPools = utils.keys(Pools) -- all pools
  end
  
  for _, pool in ipairs(targetPools) do
    ao.send({
      Target = pool,
      Action = "Whitelist-For-Fee-Discount",
      ["Address"] = address
    })
  end

  msg.reply({
    Status = "OK",
    Action = "Resp-Update-Whitelists-For-Fee-Discount",
    Data = json.encode({
      ["Whitelist-Address"] = address,
      ["Target-AMMs"] = not allPools and targetPools,
      ["Target-All-AMMs"] = allPools and "true"
    })
  })

end

-- HANDLERS

Handlers.add(
  "addPool",
  Handlers.utils.hasMatchingTag("Action", "Add-Pool"),
  Factory.handleAddPool
)

-- ========================================


function Factory.handleDeletePool(msg: Message)
  if msg.From ~= Owner and msg.From ~= OPERATOR and msg.From ~= ao.id then
    error("Only the owner, operator, or self can delete pools")
  end
  local tokenA = msg.Tags["Token-A"]
  local tokenB = msg.Tags["Token-B"]
  local feeBps = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE

  assertions.isAddress(tokenA, "Invalid Token-A")
  assertions.isAddress(tokenB, "Invalid Token-B")
  assertions.isValidFee(feeBps)

  local poolPairs = PoolsByTokens[tokenA .. ":" .. tokenB]

  assert(poolPairs ~= nil, "Pool pairs not found. Checked " .. tokenA .. ":" .. tokenB)

  local pool = poolPairs[feeBps]

  assert(pool ~= nil, "Pool not found. Checked " .. tokenA .. ":" .. tokenB .. " with fee " .. feeBps)

  PoolsByTokens[tokenA .. ":" .. tokenB] = nil
  PoolFeesBps[pool] = nil
  Pools[pool] = nil

  local confirmationTags = { ["Deleted"] = pool }
  responses.sendConfirmation(msg, confirmationTags)

  -- patch pools
  ao.send({
    device = "patch@1.0",
    method = "PATCH",
    pools = {
      [pool] = nil
    },
    pools_by_tokens = {
      [tokenA .. ":" .. tokenB] = nil
    },
  })
end

Handlers.add(
  "deletePool",
  Handlers.utils.hasMatchingTag("Action", "Delete-Pool"),
  Factory.handleDeletePool
)

function Factory.handleGetPool(msg: Message)
  assertions.isAddress(msg.Tags["Token-A"], "Invalid Token-A")
  assertions.isAddress(msg.Tags["Token-B"], "Invalid Token-B")

  local tokenA = msg.Tags["Token-A"]
  local tokenB = msg.Tags["Token-B"]
  local feeBps = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE

  assertions.isValidFee(feeBps)

  local poolPairsA = PoolsByTokens[tokenA .. ":" .. tokenB] or {}
  local poolPairsB = PoolsByTokens[tokenB .. ":" .. tokenA] or {}

  -- combine the pools for both token orders
  local poolPairs = {}

  for fee, pool in pairs(poolPairsA) do
    poolPairs[fee] = pool
  end

  for fee, pool in pairs(poolPairsB) do
    poolPairs[fee] = pool
  end

  assert(poolPairs ~= nil, "Pool not found")

  local pool = poolPairs[feeBps]

  assert(pool ~= nil, "Pool not found")

  local replyData = nil
  local replyTags = {
    ["Pool-Id"] = pool,
    ["Pending"] = tostring(pool == 'pending')
  }
  responses.sendReply(msg, replyData, replyTags)
end

function Factory.handleGetPoolById(msg: Message)
  assertions.isAddress(msg.Tags["Process-Id"], "Invalid Process-Id")

  local pool = Pools[msg.Tags["Process-Id"]]

  local replyData = pool
  responses.sendReply(msg, replyData)
end

Handlers.add(
  "getPool",
  Handlers.utils.hasMatchingTag("Action", "Get-Pool"),
  Factory.handleGetPool
)

Handlers.add(
  "getPoolById",
  Handlers.utils.hasMatchingTag("Action", "Get-Pool-By-Id"),
  Factory.handleGetPoolById
)

function Factory.handleGetPools(msg: Message)
  local replyData = Pools
  responses.sendReply(msg, replyData)
end

function Factory.handleGetPoolsByTokens(msg: Message)
  local replyData = PoolsByTokens
  responses.sendReply(msg, replyData)
end

Handlers.add(
  "getPools",
  Handlers.utils.hasMatchingTag("Action", "Get-Pools"),
  Factory.handleGetPools
)

Handlers.add(
  "getPoolsByTokens",
  Handlers.utils.hasMatchingTag("Action", "Get-Pools-By-Tokens"),
  Factory.handleGetPoolsByTokens
)

function Factory.handleGetTokens(msg: Message)
  local replyData = Tokens
  responses.sendReply(msg, replyData)
end

Handlers.add(
  "getTokens",
  Handlers.utils.hasMatchingTag("Action", "Get-Tokens"),
  Factory.handleGetTokens
)


function Factory.handleDeleteToken(msg: Message)
  if msg.From ~= Owner and msg.From ~= ao.id then 
    error("Only the owner or self can delete tokens")
  end

  assertions.isAddress(msg.Tags["Token"], "Invalid Token")

  local token = msg.Tags["Token"]

  -- ensure no pool uses this token
  for poolId, tokens in pairs(Pools) do
    if utils.includes(token, tokens) then
      error("Token is still in use by pool " .. poolId)
    end
  end

  Tokens = utils.filter(
    function(t: string): boolean return t ~= token end,
    Tokens
  )
  
  local confirmationTags = { ["Deleted"] = token }
  responses.sendConfirmation(msg, confirmationTags)

  -- patch tokens
  ao.send({
    device = "patch@1.0",
    method = "PATCH",
    tokens = json.encode(Tokens),
  })
end

-- should be called only after all the pools that were using this token were deleted
Handlers.add(
  "deleteToken",
  Handlers.utils.hasMatchingTag("Action", "Delete-Token"),
  Factory.handleDeleteToken
)

Handlers.add(
  "relayMessage",
  function(msg: Message): boolean return msg.Tags['Relay-To'] ~= nil end,
  function(msg: Message)
    -- check if the pool exists in our records
    assert(Pools[msg.From] ~= nil, "Pool not found")

    local clonedMessage = json.decode(json.encode(msg.Tags)) as SendMessagePayload
    clonedMessage.Target = msg.Tags["Relay-To"]
    clonedMessage['Relayed-From'] = msg.From
    clonedMessage['Data'] = msg.Data
    clonedMessage['Trigger-Timestamp'] = msg.Tags['Trigger-Timestamp']
    ao.send(clonedMessage)
  end
)


Handlers.add(
  "deletePools",
  Handlers.utils.hasMatchingTag("Action", "Delete-Pools"),
  function(msg: Message)
    if msg.From ~= Owner and msg.From ~= ao.id then 
      error("Only the owner or self can delete pools")
    end

    Tokens = {}
    Pools = {}
    PoolsByTokens = {}

    responses.sendConfirmation(msg)

    -- Send a patch to the HB with the empty pools table
    ao.send({
      device = "patch@1.0",
      method = "PATCH",
      pools = Pools,
      pools_by_tokens = PoolsByTokens,
      tokens = json.encode(Tokens),
    })
  end
)

-- ============== WHITELISTING FOR FEE DISCOUNTS

--[[
  The factory can instruct the AMMs to whitelist an address for fee discounts (portfolio agents)

  Only trusted whitelisters (portfolio agent factories) should be able to trigger this in the factory.

  A portfolio agent factory would trigger a whitelisting of every spawned agent wihin its related AMMs,
  so that the agent can swap for a discounted fee.
]] 

-- i.e. add portfolio agent factory that we trust, so that it may trigger a whitelisting for its spawned agents
Handlers.add(
  'addTrustedWhitelisterForFeeDiscount',
  Handlers.utils.hasMatchingTag('Action', 'Add-Trusted-Whitelister-For-Fee-Discount'),
  function(msg: Message)
    assert(
      msg.From == Owner or msg.From == OPERATOR or msg.From == ao.id,
      "Only the owner, operator or self can add trusted whitelisters for fee discounts"
    )
    local address = msg.Tags['Process-Id']
    assertions.isAddress(address)

    local asTrustedWhitelister = utils.find(
      function(v: string): boolean return v == address end,
      TrustedWhitelistersForFeeDiscount
    )

    if asTrustedWhitelister then
      return
    end
    table.insert(TrustedWhitelistersForFeeDiscount, address)
  end
)

Handlers.add(
  'getTrustedWhitelistersForFeeDiscount',
  Handlers.utils.hasMatchingTag('Action', 'Get-Trusted-Whitelisters-For-Fee-Discount'),
  function(msg: Message)
    local replyData = TrustedWhitelistersForFeeDiscount
    responses.sendReply(msg, replyData)
  end
)

-- to be called by the portfolio agent factory 
-- for a specific portfolio agent to become whitelisted
-- in a specific set of AMMs
Handlers.add(
  "whitelistForFeeDiscountsInAmms",
  Handlers.utils.hasMatchingTag("Action", "Whitelist-For-Fee-Discount-In-AMMs"),
  Factory.handleWhitelistForFeeDiscountInAmms
)

-- ============ OPERATIONS ON AMMS

--[[
We create a patch handler in the AMM factory. This handler is to be called by our OPERATOR account. 
It will Eval the upgraded source code on all its AMMs, 
so that they have the Whitelist-For-Fee-Discount handler.
]]

Handlers.add(
  'patchAMMs',
  Handlers.utils.hasMatchingTag('Action', 'Patch-AMMs'),
  function(msg: Message)
    if msg.From ~= OPERATOR and msg.From ~= ao.id and msg.From ~= Owner then
      error('Unauthorized - only the operator, owner or self can patch AMMs')
    end

    local doAll = msg.Tags['All'] == 'true'

    -- specfic pools vs all pools
    local pools = doAll and utils.keys(Pools) or json.decode(msg.Tags['AMMs']) as {string}

    if #pools < 50 then
      print('Patching the following AMMs: \n' .. json.encode(pools))
    else
      print('Patching ' .. #pools .. ' AMMs')
    end

    local source_code = msg.Tags["Custom"] == "true"
      and msg.Data as string
      or (reset_modules_code .. set_dexi_token_code(DexiTokenProcess) .. amm_source_code as string) -- some older pools in prod may have no DexiTokenProcess set yet, patching here

    local BATCH_SIZE = 50
    local totalPools = #pools
    
    -- Separate computation of batches, in order to not overwhelm the system

    for i = 1, totalPools, BATCH_SIZE do
      local endIndex = math.min(i + BATCH_SIZE - 1, totalPools)
      print('Patching AMMs batch ' .. i .. ' to ' .. endIndex .. ' of ' .. totalPools)
      
      for j = i, endIndex do
        local poolId = pools[j]
        ao.send({
          Target = poolId,
          Action = 'Eval',
          Data = source_code,
        })
      end
      
      local action = "Batch-Complete-" .. i .. "-" .. endIndex
      ao.send({
        Target = ao.id,
        Action = action
      })
      Receive(function(m: Message): boolean
        return m.From == ao.id and m.Tags.Action == action
      end)
    end
  end
)

-- set the PoolFeesBps value for existing pools
Handlers.add(
  'patchPoolFees',
  Handlers.utils.hasMatchingTag('Action', 'Patch-Pool-Fees'),
  function(msg: Message)
    if msg.From ~= OPERATOR and msg.From ~= ao.id and msg.From ~= Owner then
      error('Unauthorized - only the operator, owner or self can patch AMMs')
    end

    local pools = utils.keys(Pools)

    print('Patching pool fee for all AMMs')

    for _, poolId in ipairs(pools) do
      PoolFeesBps[poolId] = DEFAULT_LP_FEE
    end
  end
)

Handlers.add(
  'Exists-Pool',
  Handlers.utils.hasMatchingTag('Action', 'Exists-Pool'),
  function(msg: Message)
    assertions.isValidFee(msg.Tags["Fee-Bps"])
    local tokenA: string = msg.Tags["Token-A"]
    local tokenB: string = msg.Tags["Token-B"]
    local feeToUse = msg.Tags["Fee-Bps"] or DEFAULT_LP_FEE
    local exists = factory_lib.poolExists(tokenA, tokenB, feeToUse)
    local existsSymmetrical = factory_lib.poolExists(tokenB, tokenA, feeToUse)
    msg.reply({
      Exists = tostring(exists),
      ExistsSymmetrical = tostring(existsSymmetrical)
    })
  end
)

Handlers.add(
  'Patch-Pools-Table', 
  Handlers.utils.hasMatchingTag('Action', 'Patch-Pools-Table'),
  function(msg: Message)
    if msg.From ~= OPERATOR and msg.From ~= ao.id and msg.From ~= Owner then
      error('Unauthorized - only the operator, owner or self can patch AMMs')
    end

    for key, pool in pairs(PoolsByTokens) do
      if type(pool) == 'string' then
        local poolId = pool as string
        PoolsByTokens[key] = { [DEFAULT_LP_FEE] = poolId }
      end
    end
  end
)


-- ============ HANDLER FOR HB
Handlers.add("Manual-Patch-Pools", {Action = "Manual-Patch-Pools"}, function(msg: Message)
  if msg.From ~= OPERATOR and msg.From ~= ao.id and msg.From ~= Owner and msg.From ~= "yqRGaljOLb2IvKkYVa87Wdcc8m_4w6FI58Gej05gorA" then
    error('Unauthorized - only the operator, owner or self can patch AMMs')
  end

  ao.send({
    Target = HB_CACHE_PROCESS,
    Action = "Pools/Patch-Pools",
    Data = json.encode(Pools)
  })

  ao.send({
    Target = HB_CACHE_PROCESS,
    Action = "Pools-By-Tokens/Patch",
    Data = json.encode(PoolsByTokens)
  })

  ao.send({
    Target = HB_CACHE_PROCESS,
    Action = "Tokens/Patch",
    Data = json.encode(Tokens)
  })
end)