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

// ─── Tick math (port of Uniswap v3 TickMath.sol) ─────────────────────────────

const Q96 = 2n ** 96n

/** Returns the sqrtPriceX96 for a given tick. Matches TickMath.getSqrtPriceAtTick. */
export function getSqrtRatioAtTick(tick: number): bigint {
  const absTick = BigInt(Math.abs(tick))

  let ratio = (absTick & 1n) !== 0n
    ? 0xfffcb933bd6fad37aa2d162d1a594001n
    : 0x100000000000000000000000000000000n

  if ((absTick & 0x2n)      !== 0n) ratio = (ratio * 0xfff97272373d413259a46990580e213an)     >> 128n
  if ((absTick & 0x4n)      !== 0n) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdccn)     >> 128n
  if ((absTick & 0x8n)      !== 0n) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0n)     >> 128n
  if ((absTick & 0x10n)     !== 0n) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644n)     >> 128n
  if ((absTick & 0x20n)     !== 0n) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0n)     >> 128n
  if ((absTick & 0x40n)     !== 0n) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861n)     >> 128n
  if ((absTick & 0x80n)     !== 0n) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053n)     >> 128n
  if ((absTick & 0x100n)    !== 0n) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4n)    >> 128n
  if ((absTick & 0x200n)    !== 0n) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54n)     >> 128n
  if ((absTick & 0x400n)    !== 0n) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3n)     >> 128n
  if ((absTick & 0x800n)    !== 0n) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9n)     >> 128n
  if ((absTick & 0x1000n)   !== 0n) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825n)    >> 128n
  if ((absTick & 0x2000n)   !== 0n) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5n)    >> 128n
  if ((absTick & 0x4000n)   !== 0n) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7n)    >> 128n
  if ((absTick & 0x8000n)   !== 0n) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6n)    >> 128n
  if ((absTick & 0x10000n)  !== 0n) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9n)     >> 128n
  if ((absTick & 0x20000n)  !== 0n) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604n)      >> 128n
  if ((absTick & 0x40000n)  !== 0n) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98n)        >> 128n
  if ((absTick & 0x80000n)  !== 0n) ratio = (ratio * 0x48a170391f7dc42444e8fa2n)             >> 128n

  if (tick > 0) ratio = (2n ** 256n - 1n) / ratio

  return (ratio >> 32n) + (ratio % (2n ** 32n) === 0n ? 0n : 1n)
}

// ─── Liquidity math (port of Uniswap v3 LiquidityAmounts.sol) ─────────────────

function _liqForAmount0(sqrtA: bigint, sqrtB: bigint, amount0: bigint): bigint {
  if (sqrtA > sqrtB) [sqrtA, sqrtB] = [sqrtB, sqrtA]
  return (amount0 * ((sqrtA * sqrtB) / Q96)) / (sqrtB - sqrtA)
}

function _liqForAmount1(sqrtA: bigint, sqrtB: bigint, amount1: bigint): bigint {
  if (sqrtA > sqrtB) [sqrtA, sqrtB] = [sqrtB, sqrtA]
  return (amount1 * Q96) / (sqrtB - sqrtA)
}

/** Given a current sqrtPrice and tick range, compute liquidity from token amounts. */
export function getLiquidityForAmounts(
  sqrtRatio: bigint,
  sqrtRatioA: bigint,
  sqrtRatioB: bigint,
  amount0: bigint,
  amount1: bigint,
): bigint {
  if (sqrtRatioA > sqrtRatioB) [sqrtRatioA, sqrtRatioB] = [sqrtRatioB, sqrtRatioA]
  if (sqrtRatio <= sqrtRatioA) return _liqForAmount0(sqrtRatioA, sqrtRatioB, amount0)
  if (sqrtRatio >= sqrtRatioB) return _liqForAmount1(sqrtRatioA, sqrtRatioB, amount1)
  const liq0 = _liqForAmount0(sqrtRatio, sqrtRatioB, amount0)
  const liq1 = _liqForAmount1(sqrtRatioA, sqrtRatio, amount1)
  return liq0 < liq1 ? liq0 : liq1
}

/** Given liquidity and a tick range, compute the token amounts required. */
export function getAmountsForLiquidity(
  sqrtRatio: bigint,
  sqrtRatioA: bigint,
  sqrtRatioB: bigint,
  liquidity: bigint,
): { amount0: bigint; amount1: bigint } {
  if (sqrtRatioA > sqrtRatioB) [sqrtRatioA, sqrtRatioB] = [sqrtRatioB, sqrtRatioA]

  const amt0 = (sqrtRatio: bigint, sqrtRatioB: bigint) =>
    ((liquidity << 96n) * (sqrtRatioB - sqrtRatio) / sqrtRatioB) / sqrtRatio
  const amt1 = (sqrtRatioA: bigint, sqrtRatio: bigint) =>
    (liquidity * (sqrtRatio - sqrtRatioA)) / Q96

  if (sqrtRatio <= sqrtRatioA) {
    return { amount0: amt0(sqrtRatioA, sqrtRatioB), amount1: 0n }
  } else if (sqrtRatio >= sqrtRatioB) {
    return { amount0: 0n, amount1: amt1(sqrtRatioA, sqrtRatioB) }
  }
  return { amount0: amt0(sqrtRatio, sqrtRatioB), amount1: amt1(sqrtRatioA, sqrtRatio) }
}

// ─── Input parsing ────────────────────────────────────────────────────────────

/** Parse a user-typed decimal string (e.g. "100.5") into a bigint with 18 decimals. */
export function parseTokenInput(input: string): bigint | null {
  const trimmed = input.trim()
  if (!trimmed || trimmed === '.') return null
  const parts = trimmed.split('.')
  if (parts.length > 2) return null
  const whole = parts[0] || '0'
  const frac  = (parts[1] ?? '').padEnd(18, '0').slice(0, 18)
  try {
    return BigInt(whole) * 10n ** 18n + BigInt(frac)
  } catch {
    return null
  }
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
