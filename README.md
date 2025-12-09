# 📊 Botega AMM

> ⚠️ **ARCHIVED PROJECT**
> 
> This project is **archived and no longer maintained**. It is provided as-is for educational and reference purposes. No support, updates, or bug fixes will be provided. It was originally developed by Autonomous Finance.


<div align="center">

![AO](https://img.shields.io/badge/AO-Arweave-blue?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSIxMCIgZmlsbD0id2hpdGUiLz48L3N2Zz4=)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)
![Teal](https://img.shields.io/badge/Teal-Typed_Lua-purple?style=for-the-badge&logo=lua)

**Constant product AMM with factory-spawned liquidity pools on AO**

*Swap tokens, provide liquidity, earn LP rewards, and subscribe to real-time market events*

[Features](#-features) • [Architecture](#-architecture) • [Pool Actions](#-pool-actions) • [Getting Started](#-getting-started) • [License](#-license)

</div>

---

## 🌟 Features

<table>
<tr>
<td width="50%">

### 🔄 Constant Product Swaps
Uniswap-style `x * y = K` formula. Execute token swaps with slippage protection and expected minimum output guarantees.

</td>
<td width="50%">

### 🏭 Factory Pattern
Single factory spawns and manages all pool processes. Automatic pool registration, fee configuration, and Dexi integration.

</td>
</tr>
<tr>
<td width="50%">

### 💧 LP Token System
Mint LP tokens proportional to liquidity provided. Burn to withdraw your share of reserves plus accrued fees.

</td>
<td width="50%">

### 📡 Real-Time Subscriptions
Subscribe to swap confirmations, liquidity events, and fee changes. Power autonomous agents with live market data.

</td>
</tr>
<tr>
<td width="50%">

### 💰 Configurable Fees
Split fees between LPs (enters reserves) and protocol (transferred to collector). Support for fee discounts on whitelisted addresses.

</td>
<td width="50%">

### 🏷️ Tag Forwarding
All `X-...` tags forwarded through swap/provide/burn flows. Trigger timestamps on every output for downstream processing.

</td>
</tr>
</table>

## 🏗️ Architecture

```
                         ┌───────────────────┐
                         │   POOL CREATORS   │
                         │   ─────────────   │
                         │   Add-Pool        │
                         │   Token-A/B       │
                         │   Fee-Bps         │
                         └─────────┬─────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                         AMM FACTORY                             │
├─────────────────────────────────────────────────────────────────┤
│  • Validate token compatibility (aos 2.0)                       │
│  • Spawn pool processes with configured fees                    │
│  • Auto-register pools with Dexi aggregator                     │
│  • Manage fee collectors & whitelists                           │
│  • Relay confirmations/errors to users                          │
│  • Batch patch AMM source code upgrades                         │
└─────────────────────────────────────────────────────────────────┘
         │                        │                        │
         │ Spawns                 │ Registers              │ Relays
         ▼                        ▼                        ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   AMM POOL 1    │      │   AMM POOL 2    │      │   AMM POOL N    │
│   ──────────    │      │   ──────────    │      │   ──────────    │
│   AO/wUSDC      │      │   wAR/wUSDC     │      │   PI/wAR        │
│   25 bps        │      │   25 bps        │      │   25 bps        │
└────────┬────────┘      └────────┬────────┘      └────────┬────────┘
         │                        │                        │
         └────────────────────────┼────────────────────────┘
                                  │
┌─────────────────────────────────────────────────────────────────┐
│                         AMM POOL CORE                           │
├─────────────────────────────────────────────────────────────────┤
│  • Constant product (x*y=K)     • LP token mint/burn            │
│  • Slippage protection          • Fee collection (LP+Protocol)  │
│  • Pending provide matching     • Tag forwarding                │
│  • Subscription notifications   • State patching (HyperBee)     │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Notifications & Transfers
                  ┌───────────────┼───────────────┐
                  ▼               ▼               ▼
          ┌───────────────┐ ┌───────────────┐ ┌───────────────┐
          │     DEXI      │ │  SUBSCRIBERS  │ │   TRADERS     │
          │  ──────────   │ │  ──────────   │ │  ──────────   │
          │  Candles      │ │  • Agents     │ │  • Wallets    │
          │  Stats        │ │  • Indexers   │ │  • Bots       │
          │  Analytics    │ │  • dApps      │ │  • Arbitrage  │
          └───────────────┘ └───────────────┘ └───────────────┘
```

### How It Works

1. **Pool Creation** — Factory validates token compatibility, spawns pool process with configured fee tier
2. **Liquidity Provision** — LPs transfer both tokens, receive LP tokens proportional to share of reserves
3. **Swapping** — Traders transfer input token with `X-Action: Swap`, receive output based on constant product
4. **Fee Accrual** — LP fees enter reserves (compounding), protocol fees transferred to collector
5. **Withdrawal** — LPs burn pool tokens, receive proportional share of both reserves

## 🔄 Pool Actions

### Swap Flow

```
┌──────────┐         ┌──────────┐         ┌──────────┐
│  Trader  │────────▶│  Token   │────────▶│   Pool   │
│          │ Transfer│ Process  │Credit-  │          │
│          │         │          │Notice   │          │
└──────────┘         └──────────┘         └──────────┘
                                                │
     ┌──────────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────┐
│  1. Validate slippage & reserves                   │
│  2. Calculate output (constant product)            │
│  3. Deduct LP fee (enters reserves)                │
│  4. Deduct protocol fee (sent to collector)        │
│  5. Transfer output tokens to trader               │
│  6. Notify subscribers on 'order-confirmation'     │
└────────────────────────────────────────────────────┘
```

### Provide Liquidity Flow

```
┌──────────┐    Transfer Token A    ┌──────────┐
│    LP    │───────────────────────▶│   Pool   │
│          │                        │          │
│          │    Transfer Token B    │  Pending │
│          │───────────────────────▶│  Provide │
└──────────┘                        └──────────┘
                                          │
     ┌────────────────────────────────────┘
     │
     ▼
┌────────────────────────────────────────────────────┐
│  1. Match pending provide for sender               │
│  2. Adjust quantities within slippage tolerance    │
│  3. Calculate LP tokens to mint (√(A*B) or ratio)  │
│  4. Add tokens to reserves                         │
│  5. Mint LP tokens to provider                     │
│  6. Refund excess tokens if adjusted               │
│  7. Notify subscribers on 'liquidity-add-remove'   │
└────────────────────────────────────────────────────┘
```

## 📡 Subscription Topics

All Botega AMMs offer a real-time subscription service powered by DEXI tokens.

| Topic | Description | Payload |
|-------|-------------|---------|
| **order-confirmation** | Emitted after every successful swap | Order ID, tokens, quantities, fees, reserves |
| **liquidity-add-remove** | Emitted on provide/burn | Reserves delta, pool token changes |
| **fee-change** | Emitted when swap fees are updated | New total fee percentage |

### Subscribe to an AMM

```lua
AMM = '<pool-process-id>'
DEXI_TOKEN = '<dexi-token-process>'

-- 1. Register as subscriber
ao.send({
  Target = AMM,
  Action = 'Register-Subscriber',
  Topics = json.encode({'order-confirmation', 'liquidity-add-remove'})
})

-- 2. Pay for subscription
ao.send({
  Target = DEXI_TOKEN,
  Action = 'Transfer',
  Recipient = AMM,
  Quantity = '<payment-amount>',
  ["X-Subscriber-Process-Id"] = ao.id
})
```

## 📋 Handler Reference

### Query Handlers

| Action | Description | Response Tags |
|--------|-------------|---------------|
| `Get-Pair` | Token addresses in the pair | `Token-A`, `Token-B` |
| `Get-Reserves` | Current reserve balances | `<Token-A>`, `<Token-B>` |
| `Get-K` | Current K constant | `K` |
| `Get-Price` | Price quote for swap | `Price`, `Expected-Output` |
| `Get-Swap-Output` | Detailed swap simulation | `Output`, `Fee`, `Price-Impact` |
| `Get-Fee-Percentage` | LP and protocol fee rates | `Fee-Percentage`, `LP-Fee`, `Protocol-Fee` |
| `Balance` | LP token balance for address | `Balance`, `Ticker` |
| `Balances` | All LP token balances | Data (JSON) |
| `Total-Supply` | Total LP tokens minted | `Total-Supply` |

### Action Handlers

| Action | Description | Tags Required |
|--------|-------------|---------------|
| `Swap` | Execute token swap | `X-Action: Swap`, `X-Expected-Min-Output` |
| `Provide` | Add liquidity | `X-Action: Provide`, `X-Slippage-Tolerance` |
| `Burn` | Remove liquidity | `Quantity` |
| `Cancel` | Cancel pending provide | — |
| `Transfer` | Transfer LP tokens | `Recipient`, `Quantity` |

## 🔄 Usage Examples

### Execute a Swap

```lua
-- Transfer input token with swap parameters
ao.send({
  Target = INPUT_TOKEN,
  Action = "Transfer",
  Recipient = POOL,
  Quantity = "1000000000000",  -- Amount to swap
  ["X-Action"] = "Swap",
  ["X-Expected-Min-Output"] = "950000000000"  -- Minimum acceptable output
})
```

### Provide Liquidity

```lua
-- Transfer first token
ao.send({
  Target = TOKEN_A,
  Action = "Transfer",
  Recipient = POOL,
  Quantity = "1000000000000",
  ["X-Action"] = "Provide",
  ["X-Slippage-Tolerance"] = "1"  -- 1% slippage tolerance
})

-- Transfer second token
ao.send({
  Target = TOKEN_B,
  Action = "Transfer",
  Recipient = POOL,
  Quantity = "2000000000000",
  ["X-Action"] = "Provide",
  ["X-Slippage-Tolerance"] = "1"
})
```

### Burn LP Tokens

```lua
ao.send({
  Target = POOL,
  Action = "Burn",
  Quantity = "500000000000"  -- LP tokens to burn
})
```

### Create a Pool (via Factory)

```lua
ao.send({
  Target = FACTORY,
  Action = "Add-Pool",
  ["Token-A"] = "<token-a-process-id>",
  ["Token-B"] = "<token-b-process-id>",
  ["Fee-Bps"] = "25"  -- 0.25% fee (25 basis points)
})
```

## 💸 Fee Mechanism

```
┌─────────────────────────────────────────────────────────┐
│                    INCOMING SWAP                        │
│                    ─────────────                        │
│                   1,000,000 tokens                      │
└─────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
   │  LP Fee     │ │ Protocol    │ │ Net Input   │
   │  ────────   │ │ Fee         │ │ ─────────   │
   │  0.20%      │ │ ────────    │ │ 99.75%      │
   │  (2,000)    │ │ 0.05%       │ │ (997,500)   │
   │             │ │ (500)       │ │             │
   │  → Reserves │ │ → Collector │ │ → Swap Calc │
   └─────────────┘ └─────────────┘ └─────────────┘
```

- **LP Fee** enters reserves → automatically compounds for liquidity providers
- **Protocol Fee** transferred to collector contract → does not affect K
- **Fee Discounts** available for whitelisted addresses (portfolio agents)

## 📁 Project Structure

```
bark-amm/
├── 📂 src/
│   ├── 📂 amm/                    # AMM pool logic
│   │   ├── main.tl                # Entry point, handler registration
│   │   ├── amm-handlers.tl        # Handler implementations
│   │   ├── state.tl               # State management
│   │   ├── 📂 pool/               # Core pool operations
│   │   │   ├── pool.tl            # Reserves, K, price calculations
│   │   │   ├── swap.tl            # Swap execution
│   │   │   ├── provide.tl         # Liquidity provision
│   │   │   ├── burn.tl            # LP token burning
│   │   │   ├── cancel.tl          # Cancel pending provides
│   │   │   ├── refund.tl          # Error refunds
│   │   │   └── globals.tl         # Global type definitions
│   │   └── 📂 token/              # LP token operations
│   │       ├── token.tl           # Token initialization
│   │       ├── balance.tl         # Balance queries
│   │       ├── transfer.tl        # LP transfers
│   │       └── credit_notice.tl   # Incoming transfer handling
│   ├── 📂 factory/                # Pool factory
│   │   ├── factory.tl             # Factory handlers & pool spawning
│   │   ├── factory_lib.tl         # Factory utilities
│   │   └── globals.tl             # Factory globals
│   ├── 📂 utils/                  # Shared utilities
│   │   ├── assertions.tl          # Input validation
│   │   ├── bintmath.tl            # Big integer math
│   │   ├── forward-tags.tl        # Tag forwarding
│   │   ├── patterns.tl            # Handler patterns
│   │   ├── responses.tl           # Response helpers
│   │   └── tl-bint.tl             # Bint wrapper
│   └── 📂 typedefs/               # Type definitions
│       ├── ao.d.tl                # AO types
│       └── json.d.tl              # JSON types
├── 📂 packages/
│   └── 📂 subscriptions/          # Subscription module
│       └── subscribable.lua       # Real-time notifications
├── 📂 build/                      # Compiled Lua output
│   ├── factory.lua                # Deployed factory code
│   ├── amm.lua                    # Standalone AMM (testing)
│   └── amm_as_template.lua        # AMM template for spawning
├── 📂 test/                       # Test suites
│   ├── swap_test_pool.lua         # Swap tests
│   ├── provide_burn_test_pool.lua # Provide/burn tests
│   └── integration_test_*.lua     # Integration tests
├── 📂 scripts/                    # Build & deploy scripts
│   ├── build.sh                   # Compile Teal to Lua
│   └── deploy.sh                  # Deploy to AO
├── processes.dev.yaml             # Dev deployment config
├── processes.prod.yaml            # Production deployment config
└── tlconfig.lua                   # Teal compiler config
```

## 🚀 Getting Started

### Prerequisites

- **Lua** 5.3+
- **LuaRocks** 3.11+
- **Node.js** 18+
- **Teal** (cyan)
- **aoform** (AO deployment)

### Installation

```bash
# Install Lua dependencies
luarocks install --local cyan
luarocks install --local amalg
luarocks install --local busted

# Clone the repository
git clone https://github.com/Autonomous-Finance/bark-amm.git
cd bark-amm

# Install Node dependencies
npm install

# Build the project
npm run build

# Deploy to AO (dev)
npm run deploy-dev
```

### Build Output

The build process produces:

- `build/factory.lua` — Factory process code
- `build/amm.lua` — Standalone AMM (for testing)
- `build/amm_as_template.lua` — AMM template embedded in factory

### Running Tests

```bash
# Run all tests
npm test

# Run pool tests only
npm run test-pool

# Run factory tests only
npm run test-factory
```

## ⚙️ Configuration

### Factory Process Tags

| Tag | Description |
|-----|-------------|
| `Operator` | Authorized operator address |
| `Dexi-Token` | Payment token for subscriptions |
| `Dexi` | Dexi aggregator process for auto-registration |
| `HB-Cache-Process` | HyperBee cache for state sync |

### Pool Process Tags

| Tag | Description |
|-----|-------------|
| `Token-A` | First token in the pair |
| `Token-B` | Second token in the pair |
| `Fee-Bps` | Fee in basis points (default: 25 = 0.25%) |
| `AMM-Factory` | Parent factory process |
| `Dexi-Token` | Payment token for subscriptions |

## 🏷️ Tag Forwarding

All `X-...` tags are forwarded through AMM operations (swap, provide, burn) to enable downstream tracking and automation.

### Reserved Tags (Not Forwarded)

```
X-Action                    # AMM action type
X-Slippage-Tolerance        # Provide slippage
X-Expected-Min-Output       # Swap minimum output
X-Token-A, X-Token-B        # Token identifiers
X-Reserves-Token-A/B        # Reserve snapshots
X-Error                     # Error details
X-Refund-Reason             # Refund context
```

### Trigger Timestamps

All outgoing messages include `Trigger-Timestamp` for event ordering and latency tracking.

## 🛠️ Tech Stack

| Technology | Purpose |
|------------|---------|
| [**Teal**](https://github.com/teal-language/tl) | Typed Lua for compile-time safety |
| [**Lua**](https://www.lua.org/) | Runtime process logic |
| [**AO**](https://ao.arweave.dev/) | Decentralized compute on Arweave |
| [**aoform**](https://github.com/Autonomous-Finance/aoform) | Deployment management |
| [**amalg**](https://github.com/siffiejoe/lua-amalg) | Lua module bundling |
| [**bint**](https://github.com/andrewchambers/lua-bint) | Arbitrary precision integers |

## ⚠️ Disclaimer

This software is provided "as is" without warranty of any kind. Use at your own risk. The authors are not responsible for any financial losses incurred through the use of this software.

**This is experimental DeFi infrastructure.** Always:

- Test integrations thoroughly before production use
- Understand slippage and impermanent loss risks
- Review the code before providing significant liquidity

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.
