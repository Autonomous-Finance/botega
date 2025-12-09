local outputs = require "utils.output"
local bint = require "utils.tl-bint" (256)
local balance = require "amm.token.balance"
local pool = require "amm.pool.pool"

require("amm.token.globals")

local record TokenInfo
  Name: string
  Ticker: string
  Logo: string
  Denomination: string
  TotalSupply: string
  TokenA: string
  TokenB: string
  FeeBps: string
  Type: string
  supply: string | nil
  InitialSync: string | nil
end

-- Init token globals
local function init()
  ---@type Balances
  if Balances then 
    for k, v in pairs(Balances) do
      Balances[k] = bint(tostring(v))
    end
  else
    Balances = {
      [ao.id] = bint.zero()
    }
  end

  Name = Name or ao.env.Process.Tags["Name"]
  Ticker = Ticker or ao.env.Process.Tags["Name"]
  Denomination = Denomination or 12
  Logo = Logo or "fTKfocxQs94bj444uVDiVKSZQ8bKu4rqkx5hHhjIYrw"

  print(
    Colors.gray ..
    "Token was set up: " ..
    outputs.formatAddress(ao.id)
  )
end

local function info(): TokenInfo
  -- summarize token info in a table
  return {
    InitialSync = InitialSync or "nope",
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination),
    TotalSupply = tostring(balance.totalSupply()),
    Type = "AMM",
    TokenA  = ao.env.Process.Tags["Token-A"],
    TokenB = ao.env.Process.Tags["Token-B"],
    FeeBps = tostring(pool.getFeeBps())
  }
end

return {
  init = init,
  info = info
}
