require('utils.tl-bint')
require('subscriptions.subscribable')

global OPERATOR: string

global record PendingProvideType
  id: string
  token: string
  quantity: BigInteger
  sender: string
end

global Reserves: {string: BigInteger}
global PendingProvides: {PendingProvideType}
global RefundError: string
global Subscribable: TSubscribable
global Owner: string

global FeeCollector: string


global type TFeeDiscountWhitelist = {
  string: boolean
}
global FeeDiscountWhitelist: TFeeDiscountWhitelist
global IsFeeDiscountDisabled: boolean

-- values represent basis points
global record AmmFees
  lpFee: number
  protocolFee: number
end

-- dummy return to prevent pruning
return {}