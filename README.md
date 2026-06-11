# Eleos — Uniswap v4 IL Recapture Hook

> *Making impermanent loss actually impermanent.*

**[Live Demo → eleos-gold.vercel.app](https://eleos-gold.vercel.app)** · Deployed on Unichain Sepolia

---

## The Problem

Every liquidity provider on Uniswap faces the same silent tax: **impermanent loss**.

When prices diverge from your entry point, you end up holding more of the falling token and less of the rising one — compared to simply holding your tokens in a wallet. In volatile markets, this loss regularly exceeds fee earnings. Studies on Uniswap v3 data show **over 50% of LPs would have been better off just holding** than providing liquidity.

The options today are grim:
- **Hedge manually** — complex, expensive, and requires constant management
- **Run a rebalancing bot** — gas-heavy, reactive, never perfect
- **Accept the loss** — and hope fees eventually compensate

There is no native, automated safety net for LPs. Eleos is built to be that safety net.

---

## What is Eleos?

Eleos is a **Uniswap v4 hook** that automatically recaptures impermanent loss for liquidity providers — funded by a portion of the swap fees traders are already paying.

No external capital. No protocol tokens. No oracles. Pure on-chain mechanics.

---

## How It Works

### 1. Fee Diversion — Every Swap Funds the Vault

On every swap through the pool, `feeDiversionBps` (default 20%) of the LP fee is physically redirected into the `RecaptureVault`:

```
Trader swaps → 0.30% fee collected
  └─ 80% → LP wallets (normal earnings, unchanged)
  └─ 20% → RecaptureVault (IL insurance reserve)
```

LPs still earn 80% of fees as normal. The 20% is the insurance premium — paid by traders, not LPs.

### 2. IL Tracking — Your Entry Price, Remembered Forever

When you add liquidity, Eleos snapshots:
- Your entry `sqrtPrice` (used to calculate IL in real time)
- Your entry timestamp (for time-based recapture curve)
- Your liquidity and deposit value
- An optional `lockDuration` — longer commitments unlock faster recapture

Every time the pool price moves away from your entry, your recapture entitlement grows. No manual tracking required.

### 3. Loyalty Multiplier — Patience is Rewarded

This is what makes Eleos different from a simple rebate:

```
Recapture = IL_amount × time_ratio × loyalty_multiplier

Where:
  time_ratio  = min(time_held / lock_duration, 1.0)   — linear, 0→100%
  loyalty_mult = 1.0 + bonus × time_ratio              — up to 2×
```

Exit on day 1? You recover very little and forfeit the rest. Exit at day 30? You recover up to 100% of your IL with a full loyalty bonus.

**The forfeited amounts from early exiters are redistributed to patient LPs** — creating a direct incentive transfer from mercenary capital to long-term providers.

### 4. Claim Without Exiting

`claimRecapture(key, tickLower, tickUpper)` lets LPs collect their accrued recapture at any time without removing liquidity. The position clock resets, and they keep earning fees.

### 5. ERC-4626 Yield Strategy — The Vault Funds Itself

Idle vault capital can be deployed to any ERC-4626 protocol (Aave, Morpho, etc.) via `setYieldVault(poolId, yieldVault)`.

Three income streams keep the vault healthy:

| Source | Description |
|---|---|
| Fee diversion | 20% of every swap fee, automatically |
| Forfeit redistribution | Early exiters' unclaimed recapture |
| ERC-4626 yield | Aave / Morpho returns on idle capital |

A 50,000 ELOA vault at 5% APY earns 2,500 ELOA/year — before a single swap happens. The vault can sustain itself even in low-volume periods.

---

## Why This Matters

Eleos changes the risk calculus of being an LP:

| | Without Eleos | With Eleos |
|---|---|---|
| IL | Permanent on exit | Partially or fully recaptured |
| Loyalty | No reward for patience | Up to 2× multiplier |
| Early exit | No penalty for leaving | Forfeit goes to patient LPs |
| Vault | N/A | Self-sustaining via fees + yield |
| Liquidity depth | Mercenary, shallow | Stickier, deeper |

Deeper, stickier liquidity means better prices for traders. Better risk-adjusted returns mean more LPs are willing to provide it. Eleos makes the whole ecosystem more efficient.

---

## Architecture

```
RecaptureHook (Uniswap v4 Hook)
│
│  afterAddLiquidity      → snapshot position (entry price, timestamp, liquidity)
│  afterSwap              → divert feeDiversionBps to vault, update feeGrowthGlobal
│  afterSwapReturnDelta   → physically move diverted tokens via hook delta
│  beforeRemoveLiquidity  → compute IL, pay recapture, record forfeit
│  claimRecapture()       → external claim without removing liquidity
│
└── RecaptureVault (ERC-4626 compatible reserve)
    │
    │  seedPool()         → admin seeds initial capital
    │  credit()           → called by hook on every fee diversion
    │  payRecapture()     → transfers recapture to LP wallet
    │  recordForfeit()    → records early-exit forfeit for redistribution
    │  setYieldVault()    → plug in ERC-4626 yield strategy (Aave, Morpho)
    │
    └── IYieldVault (ERC-4626)   e.g. AaveV3, MorphoBlue

RecaptureMath (pure library — all WAD-scaled, no floating point)
    calculateIL()                → (r−1)² / (r²+1)
    recaptureRatio()             → linear time curve
    calculateLoyaltyMultiplier() → up to 2× bonus
    calculateEarlyExitForfeit()  → forfeit on early exit
```

---

## Deployed Contracts — Unichain Sepolia (chain 1301)

| Contract | Address |
|---|---|
| RecaptureHook | [`0x6B02d68B812752A032c52796281C039B2e24c6c4`](https://sepolia.uniscan.xyz/address/0x6B02d68B812752A032c52796281C039B2e24c6c4) |
| RecaptureVault | [`0x2D697C39bFabd18c878A5d460c4579BCAC753DC3`](https://sepolia.uniscan.xyz/address/0x2D697C39bFabd18c878A5d460c4579BCAC753DC3) |
| ELOB (token0) | [`0x1c422b32b77BFFDdBA4e0D632d30A5E400A03033`](https://sepolia.uniscan.xyz/address/0x1c422b32b77BFFDdBA4e0D632d30A5E400A03033) |
| ELOA (token1) | [`0x6669CAa4C053903926DDA50446306EBCA354Da56`](https://sepolia.uniscan.xyz/address/0x6669CAa4C053903926DDA50446306EBCA354Da56) |
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |

**Pool ID:** `0xe5430c0a367d7890fb11f6c02c6a3c26318241537584a9e7fd1599706e443196`
**Fee:** 0.30% · **Tick spacing:** 60 · **Range:** −45,000 / +45,000

> Uniswap v4 requires `currency0 < currency1` by address. ELOB has the lower address and is therefore token0.

---

## Frontend

**Live at [eleos-gold.vercel.app](https://eleos-gold.vercel.app)**

Built with Next.js 16, wagmi v2, viem v2. Connect MetaMask to Unichain Sepolia to:
- View your LP position with real-time IL tracking
- Add liquidity and complete Permit2 approvals
- Swap ELOB ↔ ELOA directly (generates fee diversions into the vault)
- Claim IL recapture without removing liquidity
- Monitor vault health and fee growth in real time
- Mint test tokens from the built-in faucet

---

## Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) (forge ≥ 0.3)
- [Medusa](https://github.com/crytic/medusa) (optional, for fuzzing)

### Install
```bash
git clone <repo>
cd eleos
forge install
```

### Environment
```bash
cp .env.example .env
# Fill in UNICHAIN_RPC_URL, DEPLOYER_PRIVATE_KEY
```

### Build & Test
```bash
forge build
forge test --via-ir
```

### Coverage
```bash
forge coverage --ir-minimum --report summary
```

| File | Lines | Functions |
|---|---|---|
| RecaptureHook.sol | ~97% | 100% |
| RecaptureVault.sol | ~98% | 100% |
| RecaptureMath.sol | 100% | 100% |

### Fuzz Testing
```bash
medusa fuzz
```
5 property invariants + 12 assertion checks across `MedusaMathTest` and `MedusaVaultTest`.

### Run Swaps (for testing)
```bash
source .env
forge script script/07_RunSwaps.s.sol \
  --rpc-url $UNICHAIN_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast -vvv
```

---

## Key Design Decisions

**Why `afterSwapReturnDelta`?**
`AFTER_SWAP_RETURNS_DELTA_FLAG` lets the hook take a delta from the swap output directly. The hook calls `poolManager.take()` to physically move diverted tokens to the vault — no separate transfer step, no reentrancy risk. The trade-off is that native Uniswap routing skips pools with this flag set; swaps must go through a direct router call.

**Why a separate `forfeitGrowthGlobal` accumulator?**
Mirrors Uniswap's own `feeGrowthGlobal` pattern. It keeps `PositionInfo` immutable after registration and enables per-position forfeit redistribution without iterating over all positions.

**Why a linear recapture curve?**
Simple to reason about and audit. No cliff effects — LPs always benefit from holding one more day. The lock duration gives LPs a clear, predictable commitment target.

**Why WAD-scaled fixed-point math?**
All IL percentages, ratios, and multipliers are WAD-scaled (1e18 = 100%). This avoids floating point entirely, keeps the math auditable, and prevents precision loss at small IL values.

---

## Security

- `setHook()` callable only once — vault is permanently bound to the hook
- `payRecapture` capped at available pool balance — vault never over-pays
- `Pausable` + `emergencyRescue` for incident response
- `nonReentrant` on remove-liquidity path
- Yield vault integration guarded: shares must be redeemed before switching strategies
- IL calculation guarded against FullMath overflow at extreme price ratios (r > 1000×)

---

## License

MIT
