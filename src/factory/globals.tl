global Owner: string
global OPERATOR: string
global Initialized: boolean

global HB_CACHE_PROCESS: string

global record TFactory
  handleGetPool: function(Message)
  handleGetPoolById: function(Message)
  handleGetPools: function(Message)
  handleGetTokens: function(Message)
  handleGetPoolsByTokens: function(Message)
  handleAddPool: function(Message)
  handleDeletePool: function(Message)
  handleDeleteToken: function(Message)
  handleWhitelistForFeeDiscountInAmms: function(Message)
  validateAddPoolRequest: function(Message): (boolean, Message, Message)
  initializeAddPool: function(Message)
  createPool: function(addPool: Message, tokenAInfo: Message, tokenBInfo: Message): string
  autoSubscribeDexiToPool: function(processId: string)
  setFeeCollectorInPool: function(string)
  _spawnPool: function(addPool: Message, tokenAInfo: Message, tokenBInfo: Message): string
  _prepareEvalMessage: function(): string
  _recordSpawnedPool: function(msg: Message, processId: string)
  _awaitEvalConfirmation: function(string)
  sendPatchPools: function()
  sendPatchTokens: function()
end
global Factory: TFactory

-- Example: {"tokenA_ProcessId", "tokenB_ProcessId"}
global type TokenProcessPair = {string, string}

global Tokens: TokenProcessPair

-- Example: { "poolId" = { "tokenA_ProcessId", "tokenB_ProcessId" }
global Pools: {string : TokenProcessPair}

-- Example: { "tokenA:tokenB" = {"fee1":"poolId", "fee2": "poolId"}, "tokenC:tokenD" = {"fee1": "pending"} }
global PoolsByTokens: {string : {string : string}}

-- Example: {"poolId" : "25"}
global PoolFeesBps: {string: string}

global FeeCollector: string

global DexiTokenProcess: string
global AmmMonitor: string

-- who is allowed to whitelist an address so that is receives fee discounts
-- i.e. Portfolio Agent Factory, Botega Agent Factory
global TrustedWhitelistersForFeeDiscount: {string}

return {}