'use client'

import { useAccount } from 'wagmi'
import { usePosition, usePreviewRecapture, usePoolState, usePoolSqrtPrice } from '@/lib/eleos'
import { useClaimRecapture } from '@/lib/eleos/hooks'
import {
  formatToken,
  formatWadPct,
  formatMultiplier,
  formatDuration,
  lockProgress,
  sqrtPriceX96ToPrice,
} from '@/lib/eleos/utils'
import { POOL_CONFIG } from '@/lib/eleos/constants'

function Row({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="flex items-center justify-between py-2.5 border-b border-zinc-800 last:border-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <div className="text-right">
        <span className="text-sm font-medium text-zinc-100">{value}</span>
        {sub && <div className="text-xs text-zinc-500">{sub}</div>}
      </div>
    </div>
  )
}

function LockBar({ pct }: { pct: number }) {
  return (
    <div className="mt-1">
      <div className="flex justify-between text-xs text-zinc-500 mb-1">
        <span>Lock progress</span>
        <span>{pct}%</span>
      </div>
      <div className="h-1.5 w-full rounded-full bg-zinc-800 overflow-hidden">
        <div
          className="h-full rounded-full bg-linear-to-r from-violet-500 to-fuchsia-500 progress-fill"
          style={{ '--target-width': `${pct}%`, width: `${pct}%` } as React.CSSProperties}
        />
      </div>
    </div>
  )
}

export function PositionCard() {
  const { isConnected } = useAccount()
  const pos = usePosition(POOL_CONFIG.tickLower, POOL_CONFIG.tickUpper)
  const poolState = usePoolState()
  const { claim, isPending, isConfirming, isSuccess, error } = useClaimRecapture(
    POOL_CONFIG.tickLower,
    POOL_CONFIG.tickUpper,
  )
  const { sqrtPriceX96: currentSqrtPrice } = usePoolSqrtPrice()
  const preview = usePreviewRecapture(pos.posId, currentSqrtPrice)

  if (!isConnected) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col items-center justify-center gap-3 min-h-48">
        <div className="text-4xl">🔗</div>
        <p className="text-zinc-400 text-sm text-center">Connect your wallet to view your position</p>
      </div>
    )
  }

  const hasPosition = pos.entryTimestamp && pos.entryTimestamp > 0

  if (!hasPosition) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6">
        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-4">Your Position</h2>
        <div className="flex flex-col items-center justify-center gap-3 py-8">
          <div className="text-4xl">📭</div>
          <p className="text-zinc-400 text-sm text-center">No open position found for this pool</p>
          <p className="text-xs text-zinc-600 text-center">
            Tick range: {POOL_CONFIG.tickLower} → {POOL_CONFIG.tickUpper}
          </p>
        </div>
      </div>
    )
  }

  const timeHeld = Math.floor(Date.now() / 1000) - Number(pos.entryTimestamp)
  const progress = lockProgress(Number(pos.entryTimestamp), Number(pos.lockDuration))
  const entryPrice = pos.entrySqrtPriceX96 ? sqrtPriceX96ToPrice(pos.entrySqrtPriceX96) : null
  const currPrice  = currentSqrtPrice ? sqrtPriceX96ToPrice(currentSqrtPrice) : null

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Your Position</h2>
        <span className="rounded-full bg-emerald-950 border border-emerald-800 px-2.5 py-0.5 text-xs text-emerald-400">
          Active
        </span>
      </div>

      <div>
        <Row label="Deposit Value"  value={pos.depositValue !== undefined ? `${formatToken(pos.depositValue)} ELOA` : '—'} />
        <Row label="Liquidity"      value={pos.liquidityAdded?.toString() ?? '—'} />
        <Row label="Entry Price"    value={entryPrice ? `${entryPrice.toFixed(6)}` : '—'} sub="ELOA per ELOB" />
        <Row label="Current Price"  value={currPrice  ? `${currPrice.toFixed(6)}`  : '—'} sub="ELOA per ELOB" />
        <Row label="Time Held"      value={formatDuration(timeHeld)} />
        <Row
          label="Lock Duration"
          value={Number(pos.lockDuration) > 0 ? formatDuration(Number(pos.lockDuration)) : '30d (default)'}
        />
        <Row
          label="Fee Diversion"
          value={poolState.feeDiversionBps !== undefined ? `${poolState.feeDiversionBps / 100}%` : '—'}
          sub="of LP fees → vault"
        />
      </div>

      <LockBar pct={progress} />

      {/* Recapture Preview */}
      {preview.recapturedTokens !== undefined && (
        <div className="rounded-xl border border-violet-800/40 bg-violet-950/20 p-4 flex flex-col gap-2">
          <p className="text-xs font-semibold text-violet-400 uppercase tracking-wider">Recapture Preview</p>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <div>
              <p className="text-zinc-500 text-xs">IL</p>
              <p className="text-zinc-100 font-medium">{preview.ilPct !== undefined ? formatWadPct(preview.ilPct) : '—'}</p>
            </div>
            <div>
              <p className="text-zinc-500 text-xs">Ratio</p>
              <p className="text-zinc-100 font-medium">{preview.ratio !== undefined ? formatWadPct(preview.ratio) : '—'}</p>
            </div>
            <div>
              <p className="text-zinc-500 text-xs">Loyalty</p>
              <p className="text-zinc-100 font-medium">{preview.loyaltyMult !== undefined ? formatMultiplier(preview.loyaltyMult) : '—'}</p>
            </div>
            <div>
              <p className="text-zinc-500 text-xs">You receive</p>
              <p className="text-emerald-400 font-semibold">{formatToken(preview.recapturedTokens)} ELOA</p>
            </div>
          </div>
          {preview.forfeitedTokens !== undefined && preview.forfeitedTokens > 0n && (
            <p className="text-xs text-amber-500">
              Early exit forfeit: {formatToken(preview.forfeitedTokens)} ELOA redistributed to patient LPs
            </p>
          )}
        </div>
      )}

      {/* Claim Button */}
      <button
        onClick={claim}
        disabled={isPending || isConfirming || !preview.recapturedTokens}
        className="w-full rounded-xl bg-linear-to-r from-violet-600 to-fuchsia-600 py-3 text-sm font-semibold text-white
          hover:from-violet-500 hover:to-fuchsia-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isPending
          ? 'Confirm in wallet…'
          : isConfirming
          ? 'Confirming…'
          : isSuccess
          ? '✓ Claimed!'
          : 'Claim Recapture'}
      </button>
      {error && (
        <p className="text-xs text-red-400 text-center">
          {(error as Error).message?.split('\n')[0] ?? 'Transaction failed'}
        </p>
      )}
    </div>
  )
}
