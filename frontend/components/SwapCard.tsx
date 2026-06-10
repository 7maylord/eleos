'use client'

import { useState, useMemo, useCallback } from 'react'
import { useAccount } from 'wagmi'
import {
  useTokenBalances,
  useSwapRouterAllowances,
  useApproveTokenToSwapRouter,
  useSwap,
  usePoolSqrtPrice,
} from '@/lib/eleos'
import { parseTokenInput, formatToken, sqrtPriceX96ToPrice } from '@/lib/eleos/utils'
import { CONTRACTS, POOL_CONFIG } from '@/lib/eleos/constants'

const SLIPPAGE_BPS = 200n   // 2% — extra room because hook diversion reduces output slightly

export function SwapCard() {
  const { isConnected } = useAccount()
  const [zeroForOne, setZeroForOne] = useState(true)   // true = ELOB→ELOA
  const [amountIn, setAmountIn] = useState('')

  const { token0Balance, token1Balance, refetch: refetchBalances } = useTokenBalances()
  const { token0Approved, token1Approved, refetch: refetchAllowances } = useSwapRouterAllowances()
  const { sqrtPriceX96 } = usePoolSqrtPrice()
  const approveElob = useApproveTokenToSwapRouter(CONTRACTS.TOKEN0)
  const approveEloa = useApproveTokenToSwapRouter(CONTRACTS.TOKEN1)
  const { swap, isPending, isConfirming, isSuccess, error, reset } = useSwap()

  const inputSymbol  = zeroForOne ? 'ELOB' : 'ELOA'
  const outputSymbol = zeroForOne ? 'ELOA' : 'ELOB'
  const inputBalance  = zeroForOne ? token0Balance : token1Balance
  const inputApproved = zeroForOne ? token0Approved : token1Approved

  const parsedIn = useMemo(() => parseTokenInput(amountIn), [amountIn])

  const price = useMemo(
    () => sqrtPriceX96 ? sqrtPriceX96ToPrice(sqrtPriceX96) : null,
    [sqrtPriceX96],
  )

  // Estimated output using spot price × fee adjustment (display only)
  const estimatedOut = useMemo(() => {
    if (!parsedIn || parsedIn === 0n || !price) return null
    const feeMultiplier = (1_000_000 - POOL_CONFIG.fee) / 1_000_000
    const raw = zeroForOne
      ? (Number(parsedIn) / 1e18) * price * feeMultiplier
      : (Number(parsedIn) / 1e18) / price * feeMultiplier
    return raw > 0 ? BigInt(Math.floor(raw * 1e18)) : null
  }, [parsedIn, price, zeroForOne])

  const amountOutMin = estimatedOut
    ? (estimatedOut * (10_000n - SLIPPAGE_BPS)) / 10_000n
    : 0n

  const insufficient = inputBalance !== undefined && parsedIn !== null && parsedIn > inputBalance

  const needsApproval = !inputApproved
  const approveHook   = zeroForOne ? approveElob : approveEloa

  const canSwap =
    !isPending && !isConfirming &&
    inputApproved &&
    !!parsedIn && parsedIn > 0n &&
    !insufficient

  const handleFlip = () => {
    setZeroForOne(v => !v)
    setAmountIn('')
    reset()
  }

  const handleSwap = () => {
    if (!parsedIn) return
    swap({ amountIn: parsedIn, amountOutMin, zeroForOne })
  }

  const handleSuccess = () => {
    refetchBalances()
    refetchAllowances()
  }

  if (!isConnected) return null

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Swap</h2>
        {price && (
          <span className="text-xs text-zinc-500">
            1 ELOB = <span className="text-zinc-300 font-mono">{price.toFixed(6)}</span> ELOA
          </span>
        )}
      </div>

      {/* You pay */}
      <div className="flex flex-col gap-1">
        <div className="flex items-center justify-between text-xs text-zinc-500">
          <span>You pay</span>
          {inputBalance !== undefined && (
            <button
              className="hover:text-zinc-300 transition-colors"
              onClick={() => {
                setAmountIn(formatToken(inputBalance, 6).replace(/\.?0+$/, ''))
                reset()
              }}
            >
              Balance: {formatToken(inputBalance, 2)}
            </button>
          )}
        </div>
        <div className="flex items-center gap-2">
          <span className="rounded-lg bg-zinc-800 px-3 py-3 text-sm font-semibold text-zinc-200 w-20 text-center shrink-0">
            {inputSymbol}
          </span>
          <input
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={amountIn}
            onChange={e => { setAmountIn(e.target.value); reset() }}
            className={[
              'flex-1 rounded-xl border px-4 py-3 bg-zinc-950 text-zinc-100 font-mono text-sm',
              'outline-none transition-colors placeholder:text-zinc-600',
              insufficient
                ? 'border-red-700 focus:border-red-500'
                : 'border-zinc-700 focus:border-violet-600',
            ].join(' ')}
          />
        </div>
        {insufficient && <p className="text-xs text-red-400">Insufficient {inputSymbol} balance</p>}
      </div>

      {/* Flip button */}
      <div className="flex justify-center -my-1">
        <button
          onClick={handleFlip}
          className="rounded-full bg-zinc-800 border border-zinc-700 p-2 hover:bg-zinc-700 hover:border-zinc-600 transition-colors"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" className="text-zinc-400">
            <path d="M8 2v12M4 10l4 4 4-4M4 6l4-4 4 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </button>
      </div>

      {/* You receive */}
      <div className="flex flex-col gap-1">
        <span className="text-xs text-zinc-500">You receive (estimated)</span>
        <div className="flex items-center gap-2">
          <span className="rounded-lg bg-zinc-800 px-3 py-3 text-sm font-semibold text-zinc-200 w-20 text-center shrink-0">
            {outputSymbol}
          </span>
          <div className="flex-1 rounded-xl border border-zinc-800 bg-zinc-950/50 px-4 py-3 font-mono text-sm text-zinc-400">
            {estimatedOut ? `~${formatToken(estimatedOut, 6)}` : '0.0'}
          </div>
        </div>
      </div>

      {/* Fee info */}
      <div className="rounded-lg bg-zinc-800/50 px-3 py-2 text-xs text-zinc-500 flex flex-col gap-0.5">
        <div className="flex justify-between">
          <span>Pool fee</span>
          <span className="text-zinc-400">0.30%</span>
        </div>
        <div className="flex justify-between">
          <span>Vault diversion</span>
          <span className="text-zinc-400">0.06% of swap → IL vault</span>
        </div>
        <div className="flex justify-between">
          <span>Slippage tolerance</span>
          <span className="text-zinc-400">2%</span>
        </div>
      </div>

      {/* Approve if needed */}
      {needsApproval && (
        <button
          onClick={() => {
            approveHook.approve()
            approveHook.isSuccess && refetchAllowances()
          }}
          disabled={approveHook.isPending || approveHook.isConfirming}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-800 py-3 text-sm font-semibold text-zinc-200
            hover:bg-zinc-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {approveHook.isPending
            ? 'Confirm in wallet…'
            : approveHook.isConfirming
            ? 'Approving…'
            : approveHook.isSuccess
            ? `✓ ${inputSymbol} approved`
            : `Approve ${inputSymbol} for swap`}
        </button>
      )}

      {/* Swap button */}
      <button
        onClick={handleSwap}
        disabled={!canSwap}
        className="w-full rounded-xl bg-linear-to-r from-violet-600 to-fuchsia-600 py-3 text-sm font-semibold text-white
          hover:from-violet-500 hover:to-fuchsia-500 transition-all disabled:opacity-40 disabled:cursor-not-allowed"
        onTransitionEnd={isSuccess ? handleSuccess : undefined}
      >
        {isPending
          ? 'Confirm in wallet…'
          : isConfirming
          ? 'Swapping…'
          : isSuccess
          ? `✓ Swapped!`
          : `Swap ${inputSymbol} → ${outputSymbol}`}
      </button>

      {error && (
        <p className="text-xs text-red-400 text-center break-all">
          {(error as Error).message?.split('\n')[0] ?? 'Swap failed'}
        </p>
      )}
    </div>
  )
}
