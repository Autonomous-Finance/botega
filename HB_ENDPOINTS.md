# AMM Factory - API Endpoints Summary

| **Endpoint**                    | **Path**                                                                                  | **Data Type**           |
|--------------------------------|-------------------------------------------------------------------------------------------|-------------------------|
| **Pools List**                 | `/pools/`                                                               | Nested Lua Table |
| **Tokens List**                | `/tokens`                                                                                 | JSON       |
| **Pools By Tokens (All)**      | `/pools_by_tokens/`                                                     | Nested Lua Table |
| **Pools By Tokens (Specific)** | `/pools_by_tokens/{tokenA}:{tokenB}/`                                   | Nested Lua Table |

***Nested Lua Tables need to be called with `/serialize~json@1.0` device**

# AMM Process - API Endpoints Summary

| **Endpoint**     | **Path**         | **Data Type**         |
|------------------|------------------|------------------------|
| **General Info** | `/general`       | JSON           |
| **Reserves**     | `/reserves`      | JSON           |
