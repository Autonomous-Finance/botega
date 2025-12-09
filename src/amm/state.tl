local token = require "amm.token.token"
local pool = require "amm.pool.pool"
local json = require "json"

local mod = {}

function mod.init()
    local tokenInfo = token.info()

    local patchMsg = {
        device = "patch@1.0",
        method = "INIT",
        ["token-info"] = tokenInfo
    }

    patchMsg["token-info"].supply = tostring(tokenInfo.TotalSupply)

    ao.send(patchMsg)
end

function mod.updateReserves()
    local reserves = pool.getReserves()
    local pair = pool.getPair()
    local tokenInfo = token.info()

    local formattedReserves = {
        ['TokenA'] = tostring(reserves[tokenInfo.TokenA]),
        ['TokenB'] = tostring(reserves[tokenInfo.TokenB]),
        ['K'] = tostring(pool.K()),
        [tokenInfo.TokenA] = tostring(reserves[tokenInfo.TokenA]),
        [tokenInfo.TokenB] = tostring(reserves[tokenInfo.TokenB])
    }

    ao.send({ device = "patch@1.0", reserves = json.encode(formattedReserves)})
end

return mod