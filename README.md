# Eleos — IL Recapture Hook for Uniswap v4

> *"IL is not lost — it is only deferred."*

Eleos is a Uniswap v4 hook that recaptures Impermanent Loss (IL) for patient liquidity providers. It combines real-time fee diversion, time-based recapture curves, a loyalty multiplier, and an on-chain yield strategy to make LP positions sustainably profitable over time.

---

## How It Works

### 1. Position Snapshotting (afterAddLiquidity)
When an LP adds liquidity, the hook records:
- Entry `sqrtPrice` (for IL calculation)
- Entry timestamp (for time-based recapture)
- Liquidity amount and deposit value
- Optional `lockDuration` — longer locks unlock faster recapture

### 2. Fee Diversion (afterSwapReturnDelta)
On every swap, `feeDiversionBps` (default 20%) of the LP fee is physically moved into the `RecaptureVault`:
```
poolManager.take(currency1, vault, diverted)
vault.credit(poolId, diverted)
```
The swapper pays a small surcharge; LP fees are unchanged.

### 3. Recapture on Exit (beforeRemoveLiquidity)
When an LP removes liquidity, the hook:
1. Computes IL: `IL = (r−1)² / (r²+1)` where `r = currentSqrt / entrySqrt`
2. Applies a linear recapture ratio: `min(timeHeld / lockDuration, 1)`
3. Multiplies by a loyalty bonus: up to 2× for long-term holders
4. Adds accumulated forfeit share from earlier exits
5. Pays recaptured IL from the `RecaptureVault`
6. Records any forfeit (early-exit penalty) for redistribution

### 4. Forfeit Redistribution (Feature 3)
Early exits forfeit their unrealised recapture to a pool-level `forfeitGrowthGlobal` accumulator. Patient LPs automatically collect this surplus on their next settlement.

### 5. Claim Without Exit (Feature 5)
`claimRecapture(key, tickLower, tickUpper)` lets an LP collect their accrued recapture without removing liquidity, resetting the position clock.

### 6. ERC-4626 Yield Strategy (Feature 2)
The `RecaptureVault` can route idle capital to any ERC-4626 vault (Aave, Morpho, etc.) via `setYieldVault(poolId, yieldVault)`. Yield accrues on top of diverted fees, making the vault self-sustaining.

---

## Architecture

```
RecaptureHook
│  afterAddLiquidity  → snapshot position
│  beforeSwap         → reads fee params
│  afterSwap          → diverts feeDiversionBps to vault, updates feeGrowthGlobal
│  afterSwapReturnDelta → physically moves tokens (hook delta)
│  beforeRemoveLiquidity → compute IL, pay recapture, record forfeit
│  claimRecapture()   → external claim without removing liquidity
│
└── RecaptureVault
    │  seedPool()      → admin seeds initial capital
    │  credit()        → called by hook after fee diversion
    │  payRecapture()  → transfers recapture to LP
    │  recordForfeit() → records early-exit forfeit
    │  setYieldVault() → plug in ERC-4626 strategy
    │
    └── IYieldVault (ERC-4626)   e.g. AaveV3, MorphoBlue

RecaptureMath (pure library)
    calculateIL()               → (r-1)²/(r²+1)
    recaptureRatio()            → linear time curve
    calculateLoyaltyMultiplier()→ up to 2× bonus
    calculateEarlyExitForfeit() → forfeit on early exit
```

---

## Deployed Contracts (Unichain Sepolia — chain 1301)

| Contract | Address |
|---|---|
| TOKEN0 (ELOB) | `0x1c422b32b77BFFDdBA4e0D632d30A5E400A03033` |
| TOKEN1 (ELOA) | `0x6669CAa4C053903926DDA50446306EBCA354Da56` |
| RecaptureVault | `0x2D697C39bFabd18c878A5d460c4579BCAC753DC3` |
| RecaptureHook | `0x6B02d68B812752A032c52796281C039B2e24c6c4` |
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |

Pool ID: `0xe5430c0a367d7890fb11f6c02c6a3c26318241537584a9e7fd1599706e443196`

> Note: Uniswap v4 requires `currency0 < currency1` by address. Addresses are assigned by the EVM at deploy time, so which token becomes token0/token1 depends on deployment order — not the token name.

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

### Build
```bash
forge build
```

### Test
```bash
forge test --via-ir
```

### Coverage
```bash
# --ir-minimum required due to stack depth in RecaptureHook
forge coverage --ir-minimum --report summary
```

Expected coverage on `src/` contracts:
| File | Lines | Functions |
|---|---|---|
| RecaptureHook.sol | ~97% | 100% |
| RecaptureVault.sol | ~98% | 100% |
| RecaptureMath.sol | 100% | 100% |

### Medusa Fuzzing
```bash
medusa fuzz
```
Targets `MedusaMathTest` and `MedusaVaultTest` with 5 property invariants and 12 assertion checks.

---

## Key Design Decisions

**Why afterSwapReturnDelta?**
Uniswap v4's `afterSwapReturnDelta` hook flag lets the hook take a delta from the swap output. The hook takes `diverted` tokens via `poolManager.take()`, reducing the swapper's output by that amount without touching LP fees.

**Why separate forfeitGrowthGlobal accumulator?**
Mirrors Uniswap's `feeGrowthGlobal` pattern. Keeps the `PositionInfo` struct stable (no breaking changes to existing callers) while enabling per-position forfeit redistribution.

**Why linear recapture curve?**
Simple to reason about and audit. The lock duration gives LPs a clear commitment period. A linear curve means LPs always benefit from holding longer, with no cliff effects.

---

## Security Notes

- `setHook()` is callable only once (immutable after first set)
- `payRecapture` is capped at available pool balance — vault never over-pays
- Vault has `Pausable` + `emergencyRescue` for incident response
- Hook has `nonReentrant` on remove-liquidity to prevent re-entrancy attacks
- Yield vault integration guarded: must redeem shares before switching strategies
- IL calculation guarded against FullMath overflow at extreme price ratios

---

## License

MIT
