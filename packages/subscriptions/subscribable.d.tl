-- subscribable.d.tl

local record SubscriberData
    process_id: string
    topics: {string}
    balance: string
    whitelisted: boolean
end

local record RawSubscriberData
  process_id: string
  topics: {string}
  balance: string
  whitelisted: number
end
  
global record TopicInfo
  description: string
  returns: string
  subscriptionBasis: string
end

local record PackageInfo
  paymentTokenTicker: string
  paymentToken: string
  topics: {string:TopicInfo}
end

local record StorageInterface
    Subscribers: {string: RawSubscriberData}

    registerSubscriber: function(processId: string, whitelisted: boolean)
    getSubscriber: function(processId: string): SubscriberData
    updateBalance: function(processId: string, amount: number, isCredit: boolean)
    subscribeToTopics: function(processId: string, topics: {string})
    unsubscribeFromTopics: function(processId: string, topics: {string})
    getTargetsForTopic: function(topic: string): {string}
    activationCondition: function(): string -- only because we're using the db version
    getBalance: function(processId: string): string
end

global record TSubscribable
    -- Constants
    PAYMENT_TOKEN: string
    PAYMENT_TOKEN_TICKER: string
  
    -- Main functions
    registerSubscriber: function(processId: string, whitelisted: boolean)
    handleRegisterSubscriber: function(msg: Message)
    handleRegisterWhitelistedSubscriber: function(msg: Message)
    handleGetSubscriber: function(msg: Message)
    updateBalance: function(processId: string, amount: number, isCredit: boolean)

    handleReceivePayment: function(msg: Message)
    handleSetPaymentToken: function(msg: Message)
    configTopicsAndChecks: function(cfg: {string: TopicInfo})
    getTopicsInfo: function(): {string:TopicInfo}
    getInfo: function(): PackageInfo
    subscribeToTopics: function(processId: string, topics: {string})
    handleSubscribeToTopics: function(msg: Message)
    unsubscribeFromTopics: function(processId: string, topics: {string})
    handleUnsubscribeFromTopics: function(msg: Message)
    notifySubscribers: function(topic: string, payload: SendMessagePayload)
    notifyTopics: function(topicsAndPayloads: {string: any}, timestamp: number)
    notifyTopic: function(topic: string, payload: any, timestamp: number)
    checkNotifyTopics: function(topics: {string}, timestamp: number)
    checkNotifyTopic: function(topic: string, timestamp: number)
  
    -- Helper functions
    onlyRegisteredSubscriber: function(processId: string, ownerId: string)
  
    -- Storage interface
    _storage: StorageInterface
end
  
  local record Config
    initial: boolean
    useDB: boolean
  end
  
  local function newmodule(cfg: Config): TSubscribable
  end
  
  return newmodule