local json = require("json")

AMM_FACTORY_PROCESS = ao.env.Process.Tags['AmmFactory-Process'] or "50U3BcLrRF2Bq51eeJdVdoMzrQMgjCeVai7LWY4Wm_s"

Handlers.add("Pools/Patch-Pools", { Action = "Pools/Patch-Pools" }, function(msg)
    assert(msg.From == AMM_FACTORY_PROCESS, "Pools/Patch-Pools: Invalid sender")

    ao.send({
        device = "patch@1.0",
        pools = {}
    })

    ao.send({
        device = "patch@1.0",
        pools = json.decode(msg.Data)
    })
end)

Handlers.add("Pools/Patch-Pool", { Action = "Pools/Patch-Pool" }, function(msg)
    assert(msg.From == AMM_FACTORY_PROCESS, "Pools/Patch-Pool: Invalid sender")

    -- @field poolId Extracted from processId
    local pool = json.decode(msg.Data)

    ao.send({
        device = "patch@1.0",
        pools = {
            [pool.poolId] = {
                pool.tokenA,
                pool.tokenB
            },
        },
        pools_by_tokens = {
            [pool.tokenA .. ":" .. pool.tokenB] = {
                [pool.feeBps] = pool.poolId,
            },
        },
    })
end)


Handlers.add("Pools-By-Tokens/Patch", { Action = "Pools-By-Tokens/Patch" }, function(msg)
    assert(msg.From == AMM_FACTORY_PROCESS, "Pools-By-Tokens/Patch: Invalid sender")

    ao.send({
        device = "patch@1.0",
        pools_by_tokens = {}
    })

    ao.send({
        device = "patch@1.0",
        pools_by_tokens = json.decode(msg.Data)
    })
end)

Handlers.add("Tokens/Patch", { Action = "Tokens/Patch" }, function(msg)
    assert(msg.From == AMM_FACTORY_PROCESS, "tokens/Patch: Invalid sender")

    ao.send({
        device = "patch@1.0",
        tokens = {}
    })

    ao.send({
        device = "patch@1.0",
        tokens = msg.Data
    })
end)
