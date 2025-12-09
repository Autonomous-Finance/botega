require("utils.tl-bint")

global Denomination: integer
global Balances: {string: BigInteger}
global Ticker: string
global Name: string
global Logo: string

global InitialSync: string

-- dummy return to prevent pruning
return {}