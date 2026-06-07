'use client'

import { useState, useMemo, useCallback } from 'react'
import { useAccount } from 'wagmi'
import {
  useTokenBalances,
  usePermit2Allowances,
  useAddLiquidity,
  usePoolSqrtPrice,
} from '@/lib/eleos'
import {
  getSqrtRatioAtTick,
  getLiquidityForAmounts,
  getAmountsForLiquidity,
  parseTokenInput,
  formatToken,
} from '@/lib/eleos/utils'
import { POOL_CONFIG } from '@/lib/eleos/constants'

// Fallback to 1:1 starting price if pool price hasn't loaded yet
const STARTING_PRICE = 2n ** 96n

const SLIPPAGE = 101n  // 1% — numerator over 100

const sqrtA = getSqrtRatioAtTick(POOL_CONFIG.tickLower)
const sqrtB = getSqrtRatioAtTick(POOL_CONFIG.tickUpper)

function tokenInputClass(insufficient: boolean) {
  return [
    'w-full rounded-xl border px-4 py-3 bg-zinc-950 text-zinc-100 font-mono text-sm outline-none',
    'transition-colors placeholder:text-zinc-600',
    insufficient
      ? 'border-red-700 focus:border-red-500'
      : 'border-zinc-700 focus:border-violet-600',
  ].join(' ')
}

export function AddLiquidityCard() {
  const { isConnected } = useAccount()
  const [elob, setElob] = useState('')
  const [eloa, setEloa] = useState('')

  const { token0Balance, token1Balance } = useTokenBalances()
  const { token0Approved, token1Approved } = usePermit2Allowances()
  const { sqrtPriceX96 } = usePoolSqrtPrice()
  const { addLiquidity, isPending, isConfirming, isSuccess, error, reset } = useAddLiquidity()

  const effectivePrice = sqrtPriceX96 ?? STARTING_PRICE

  // When ELOB changes → recompute ELOA from it
  const handleElobChange = useCallback((raw: string) => {
    setElob(raw)
    reset()
    const a0 = parseTokenInput(raw)
    if (!a0 || a0 === 0n) { setEloa(''); return }
    // Compute liquidity assuming all token0, then derive token1
    const liq = getLiquidityForAmounts(effectivePrice, sqrtA, sqrtB, a0, 2n ** 128n)
    const { amount1 } = getAmountsForLiquidity(effectivePrice, sqrtA, sqrtB, liq)
    setEloa(amount1 > 0n ? formatToken(amount1, 6).replace(/\.?0+$/, '') : '')
  }, [effectivePrice])

  // When ELOA changes → recompute ELOB from it
  const handleEloaChange = useCallback((raw: string) => {
    setEloa(raw)
    reset()
    const a1 = parseTokenInput(raw)
    if (!a1 || a1 === 0n) { setElob(''); return }
    const liq = getLiquidityForAmounts(effectivePrice, sqrtA, sqrtB, 2n ** 128n, a1)
    const { amount0 } = getAmountsForLiquidity(effectivePrice, sqrtA, sqrtB, liq)
    setElob(amount0 > 0n ? formatToken(amount0, 6).replace(/\.?0+$/, '') : '')
  }, [effectivePrice])

  const amount0 = useMemo(() => parseTokenInput(elob), [elob])
  const amount1 = useMemo(() => parseTokenInput(eloa), [eloa])

  const liquidity = useMemo(() => {
    if (!amount0 || !amount1 || amount0 === 0n || amount1 === 0n) return 0n
    return getLiquidityForAmounts(effectivePrice, sqrtA, sqrtB, amount0, amount1)
  }, [amount0, amount1, effectivePrice])

  const approvalsReady = token0Approved && token1Approved
  const insufficient0 = token0Balance !== undefined && amount0 !== null && amount0 > token0Balance
  const insufficient1 = token1Balance !== undefined && amount1 !== null && amount1 > token1Balance

  const canSubmit =
    !isPending &&
    !isConfirming &&
    approvalsReady &&
    !!amount0 && amount0 > 0n &&
    !!amount1 && amount1 > 0n &&
    !insufficient0 &&
    !insufficient1

  const handleAdd = () => {
    if (!amount0 || !amount1) return
    addLiquidity({
      liquidity,
      amount0Max: (amount0 * SLIPPAGE) / 100n,
      amount1Max: (amount1 * SLIPPAGE) / 100n,
    })
  }

  if (!isConnected) return null

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-4">
      <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Add Liquidity</h2>

      {!approvalsReady && (
        <div className="rounded-lg bg-amber-950/30 border border-amber-800/40 px-3 py-2 text-xs text-amber-400">
          Complete the Permit2 approvals in Token Balances before adding liquidity.
        </div>
      )}

      {/* ELOB input */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between text-xs text-zinc-500">
          <span>ELOB (token0)</span>
          {token0Balance !== undefined && (
            <button
              className="hover:text-zinc-300 transition-colors"
              onClick={() => handleElobChange(formatToken(token0Balance, 6).replace(/\.?0+$/, ''))}
            >
              Balance: {formatToken(token0Balance, 2)}
            </button>
          )}
        </div>
        <input
          type="text"
          inputMode="decimal"
          placeholder="0.0"
          value={elob}
          onChange={(e) => handleElobChange(e.target.value)}
          className={tokenInputClass(!!insufficient0)}
        />
        {insufficient0 && <p className="text-xs text-red-400">Insufficient ELOB balance</p>}
      </div>

      {/* ELOA input */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between text-xs text-zinc-500">
          <span>ELOA (token1)</span>
          {token1Balance !== undefined && (
            <button
              className="hover:text-zinc-300 transition-colors"
              onClick={() => handleEloaChange(formatToken(token1Balance, 6).replace(/\.?0+$/, ''))}
            >
              Balance: {formatToken(token1Balance, 2)}
            </button>
          )}
        </div>
        <input
          type="text"
          inputMode="decimal"
          placeholder="0.0"
          value={eloa}
          onChange={(e) => handleEloaChange(e.target.value)}
          className={tokenInputClass(!!insufficient1)}
        />
        {insufficient1 && <p className="text-xs text-red-400">Insufficient ELOA balance</p>}
      </div>

      {/* Pool info */}
      <div className="rounded-lg bg-zinc-800/50 px-3 py-2 text-xs text-zinc-500 flex flex-col gap-0.5">
        <div className="flex justify-between">
          <span>Tick range</span>
          <span className="text-zinc-400 font-mono">{POOL_CONFIG.tickLower} / {POOL_CONFIG.tickUpper}</span>
        </div>
        <div className="flex justify-between">
          <span>Lock duration</span>
          <span className="text-zinc-400">30 days</span>
        </div>
        <div className="flex justify-between">
          <span>Slippage</span>
          <span className="text-zinc-400">1%</span>
        </div>
        <div className="flex justify-between">
          <span>Price feed</span>
          <span className={sqrtPriceX96 ? 'text-emerald-500' : 'text-amber-500'}>
            {sqrtPriceX96 ? 'live' : 'fallback 1:1'}
          </span>
        </div>
      </div>

      <button
        onClick={handleAdd}
        disabled={!canSubmit}
        className="w-full rounded-xl bg-linear-to-r from-violet-600 to-fuchsia-600 py-3 text-sm font-semibold text-white
          hover:from-violet-500 hover:to-fuchsia-500 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
      >
        {isPending
          ? 'Confirm in wallet…'
          : isConfirming
          ? 'Adding liquidity…'
          : isSuccess
          ? '✓ Liquidity added!'
          : 'Add Liquidity'}
      </button>

      {error && (
        <p className="text-xs text-red-400 text-center break-all">
          {(error as Error).message?.split('\n')[0] ?? 'Transaction failed'}
        </p>
      )}
    </div>
  )
}
