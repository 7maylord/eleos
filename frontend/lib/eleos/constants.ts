import type { Address } from 'viem'

// ─── Deployed on Unichain Sepolia (chain 1301) ────────────────────────────────

export const CONTRACTS = {
  HOOK:             '0x6B02d68B812752A032c52796281C039B2e24c6c4' as Address,
  VAULT:            '0x2D697C39bFabd18c878A5d460c4579BCAC753DC3' as Address,
  // TOKEN0 = ELOB (lower address wins currency0 in v4)
  TOKEN0:           '0x1c422b32b77BFFDdBA4e0D632d30A5E400A03033' as Address,
  // TOKEN1 = ELOA
  TOKEN1:           '0x6669CAa4C053903926DDA50446306EBCA354Da56' as Address,
  POOL_MANAGER:     '0x00B036B58a818B1BC34d502D3fE730Db729e62AC' as Address,
  // StateView — v4-periphery view contract wrapping StateLibrary (getSlot0, etc.)
  STATE_VIEW:       '0xc199f1072a74d4e905aba1a84d9a45e2546b6222' as Address,
  POSITION_MANAGER: '0xf969Aee60879C54bAAed9F3eD26147Db216Fd664' as Address,
  SWAP_ROUTER:      '0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba' as Address,
  // Permit2 — deterministic across all chains
  PERMIT2:          '0x000000000022D473030F116dDEE9F6B43aC78BA3' as Address,
} as const

// ─── Pool configuration ───────────────────────────────────────────────────────

export const POOL_CONFIG = {
  fee:          3000,  // 0.30%
  tickSpacing:  60,
  // Tick range from the initial liquidity position (±750 ticks from 0 at 1:1 price)
  tickLower:   -45000,
  tickUpper:    45000,
  // Default lock duration for new positions (30 days)
  lockDuration: 30 * 24 * 60 * 60,
  // Starting price: sqrtPriceX96 = 2^96 (1:1 ratio)
  startingPrice: 2n ** 96n,
} as const

// PoolKey struct — matches what was used to deploy the pool
export const POOL_KEY = {
  currency0:   CONTRACTS.TOKEN0,
  currency1:   CONTRACTS.TOKEN1,
  fee:         POOL_CONFIG.fee,
  tickSpacing: POOL_CONFIG.tickSpacing,
  hooks:       CONTRACTS.HOOK,
} as const

// Pool ID = keccak256(abi.encode(poolKey)), emitted by SeedVault script
export const POOL_ID =
  '0xe5430c0a367d7890fb11f6c02c6a3c26318241537584a9e7fd1599706e443196' as `0x${string}`

// WAD = 1e18, used for WAD-scaled math (IL%, ratios, multipliers)
export const WAD = 10n ** 18n

export const MAX_UINT160 = 2n ** 160n - 1n
// uint48 maps to number in viem (fits in JS safe-integer range)
export const MAX_UINT48  = 2 ** 48 - 1
