import { encodeAbiParameters, keccak256 } from 'viem'
import type { Address, Hex } from 'viem'
import { POOL_KEY, WAD } from './constants'

// ─── Position ID ──────────────────────────────────────────────────────────────

/**
 * Mirrors RecaptureHook._positionId:
 *   keccak256(abi.encode(poolId, owner, tickLower, tickUpper))
 */
export function computePositionId(
  poolId: Hex,
  owner: Address,
  tickLower: number,
  tickUpper: number,
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'int24'   },
        { type: 'int24'   },
      ],
      [poolId, owner, tickLower, tickUpper],
    ),
  )
}

// ─── HookData encoding ────────────────────────────────────────────────────────

/** addLiquidity hookData: abi.encode(address owner, uint40 lockDuration) */
export function encodeAddHookData(owner: Address, lockDuration: number): Hex {
  return encodeAbiParameters(
    [{ type: 'address' }, { type: 'uint40' }],
    [owner, lockDuration],
  )
}

/** removeLiquidity hookData: abi.encode(address owner) */
export function encodeRemoveHookData(owner: Address): Hex {
  return encodeAbiParameters(
    [{ type: 'address' }],
    [owner],
  )
}

// ─── v4 PositionManager action encoding ──────────────────────────────────────

// From lib/uniswap-hooks/lib/v4-periphery/src/libraries/Actions.sol
export const Actions = {
  INCREASE_LIQUIDITY: 0x00,
  DECREASE_LIQUIDITY: 0x01,
  MINT_POSITION:      0x02,
  BURN_POSITION:      0x03,
  SETTLE_PAIR:        0x0d,
  TAKE_PAIR:          0x11,
  SWEEP:              0x14,
} as const

function packActions(actions: number[]): Hex {
  return `0x${actions.map(a => a.toString(16).padStart(2, '0')).join('')}` as Hex
}

/**
 * Build `unlockData` for MINT_POSITION via modifyLiquidities.
 * Actions: MINT_POSITION → SETTLE_PAIR → SWEEP(c0) → SWEEP(c1)
 */
export function buildMintCalldata(params: {
  tickLower:  number
  tickUpper:  number
  liquidity:  bigint
  amount0Max: bigint
  amount1Max: bigint
  recipient:  Address
  hookData:   Hex
}): Hex {
  const actions = packActions([
    Actions.MINT_POSITION,
    Actions.SETTLE_PAIR,
    Actions.SWEEP,
    Actions.SWEEP,
  ])

  const mintParam = encodeAbiParameters(
    [
      {
        type: 'tuple',
        components: [
          { name: 'currency0',   type: 'address' },
          { name: 'currency1',   type: 'address' },
          { name: 'fee',         type: 'uint24'  },
          { name: 'tickSpacing', type: 'int24'   },
          { name: 'hooks',       type: 'address' },
        ],
      },
      { type: 'int24'   },  // tickLower
      { type: 'int24'   },  // tickUpper
      { type: 'uint256' },  // liquidity
      { type: 'uint256' },  // amount0Max
      { type: 'uint256' },  // amount1Max
      { type: 'address' },  // recipient
      { type: 'bytes'   },  // hookData
    ],
    [
      POOL_KEY,
      params.tickLower,
      params.tickUpper,
      params.liquidity,
      params.amount0Max,
      params.amount1Max,
      params.recipient,
      params.hookData,
    ],
  )

  const settlePairParam = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency0, POOL_KEY.currency1],
  )
  const sweep0Param = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency0, params.recipient],
  )
  const sweep1Param = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency1, params.recipient],
  )

  return encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes[]' }],
    [actions, [mintParam, settlePairParam, sweep0Param, sweep1Param]],
  )
}

/**
 * Build `unlockData` for DECREASE_LIQUIDITY via modifyLiquidities.
 * Actions: DECREASE_LIQUIDITY → TAKE_PAIR
 */
export function buildDecreaseCalldata(params: {
  tokenId:    bigint
  liquidity:  bigint
  amount0Min: bigint
  amount1Min: bigint
  recipient:  Address
  hookData:   Hex
}): Hex {
  const actions = packActions([Actions.DECREASE_LIQUIDITY, Actions.TAKE_PAIR])

  const decreaseParam = encodeAbiParameters(
    [
      { type: 'uint256' },  // tokenId
      { type: 'uint256' },  // liquidity
      { type: 'uint128' },  // amount0Min
      { type: 'uint128' },  // amount1Min
      { type: 'bytes'   },  // hookData
    ],
    [params.tokenId, params.liquidity, params.amount0Min, params.amount1Min, params.hookData],
  )

  const takePairParam = encodeAbiParameters(
    [{ type: 'address' }, { type: 'address' }, { type: 'address' }],
    [POOL_KEY.currency0, POOL_KEY.currency1, params.recipient],
  )

  return encodeAbiParameters(
    [{ type: 'bytes' }, { type: 'bytes[]' }],
    [actions, [decreaseParam, takePairParam]],
  )
}

// ─── Formatting ───────────────────────────────────────────────────────────────

/** Format a WAD-scaled value (1e18 = 100%) as a percentage string. */
export function formatWadPct(value: bigint, decimals = 2): string {
  const pct = Number((value * 10000n) / WAD) / 100
  return `${pct.toFixed(decimals)}%`
}

/** Format a WAD-scaled multiplier as e.g. "1.50x" */
export function formatMultiplier(value: bigint): string {
  const x = Number(value) / 1e18
  return `${x.toFixed(2)}x`
}

/** Format token amount with 18 decimals. */
export function formatToken(value: bigint, displayDecimals = 4): string {
  const whole = value / 10n ** 18n
  const frac  = value % 10n ** 18n
  const fracStr = frac.toString().padStart(18, '0').slice(0, displayDecimals)
  return `${whole}.${fracStr}`
}

/**
 * Convert sqrtPriceX96 to human-readable price (token1 per token0).
 * price = (sqrtPriceX96 / 2^96)^2
 */
export function sqrtPriceX96ToPrice(sqrtPriceX96: bigint): number {
  const Q96 = 2n ** 96n
  // Use integer math scaled by 1e18 to preserve precision before converting to float
  const priceWad = (sqrtPriceX96 * sqrtPriceX96 * 10n ** 18n) / (Q96 * Q96)
  return Number(priceWad) / 1e18
}

/**
 * Returns lock progress [0–100] for a position.
 * Uses DEFAULT_LOCK_DURATION (30 days) when lockDuration == 0.
 */
export function lockProgress(entryTimestamp: number, lockDuration: number): number {
  const DEFAULT = 30 * 24 * 3600
  const now = Math.floor(Date.now() / 1000)
  const held = now - entryTimestamp
  const effective = lockDuration === 0 ? DEFAULT : lockDuration
  return Math.min(100, Math.floor((held * 100) / effective))
}

export function formatDuration(seconds: number): string {
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  return `${m}m`
}

/** Truncate a tick to the nearest valid tickSpacing multiple (mirrors Solidity). */
export function truncateToTickSpacing(tick: number, tickSpacing: number): number {
  return Math.floor(tick / tickSpacing) * tickSpacing
}

/** Default deadline: now + 1 hour */
export function defaultDeadline(): bigint {
  return BigInt(Math.floor(Date.now() / 1000) + 3600)
}
