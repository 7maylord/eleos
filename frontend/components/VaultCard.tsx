'use client'

import { useVaultStats, usePoolState } from '@/lib/eleos'
import { formatToken } from '@/lib/eleos/utils'

function Stat({
  label,
  value,
  highlight,
}: {
  label: string
  value: string
  highlight?: 'green' | 'amber' | 'violet'
}) {
  const color =
    highlight === 'green'  ? 'text-emerald-400' :
    highlight === 'amber'  ? 'text-amber-400'   :
    highlight === 'violet' ? 'text-violet-400'  :
    'text-zinc-100'

  return (
    <div className="flex items-center justify-between py-2.5 border-b border-zinc-800 last:border-0">
      <span className="text-sm text-zinc-400">{label}</span>
      <span className={`text-sm font-semibold tabular-nums ${color}`}>{value}</span>
    </div>
  )
}

export function VaultCard() {
  const {
    poolBalance, totalSeeded, totalCredited, totalPaid, totalForfeited,
    yieldVault, vaultPaused, isLoading,
  } = useVaultStats()
  const { feeDiversionBps, feeGrowthGlobal, forfeitGrowthGlobal } = usePoolState()

  if (isLoading) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6">
        <div className="h-4 w-32 animate-pulse rounded bg-zinc-800 mb-4" />
        {[1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="h-8 animate-pulse rounded bg-zinc-800 mb-2" />
        ))}
      </div>
    )
  }

  // Scale by 1e6 before dividing to preserve sub-percent precision, then shift back
  const utilisation =
    totalSeeded && totalSeeded > 0n && totalPaid !== undefined
      ? Number(totalPaid * 1_000_000n / totalSeeded) / 10_000
      : 0

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Vault Health</h2>
        <div className="flex items-center gap-2">
          {vaultPaused && (
            <span className="rounded-full bg-red-950 border border-red-800 px-2.5 py-0.5 text-xs text-red-400">
              Paused
            </span>
          )}
          <span className="rounded-full bg-zinc-800 px-2.5 py-0.5 text-xs text-zinc-400">
            Unichain Sepolia
          </span>
        </div>
      </div>

      <div>
        <Stat
          label="Pool Balance"
          value={poolBalance !== undefined ? `${formatToken(poolBalance)} ELOA` : '—'}
          highlight="green"
        />
        <Stat
          label="Total Seeded"
          value={totalSeeded !== undefined ? `${formatToken(totalSeeded)} ELOA` : '—'}
        />
        <Stat
          label="Total Credited (fees)"
          value={totalCredited !== undefined ? `${formatToken(totalCredited)} ELOA` : '—'}
          highlight="violet"
        />
        <Stat
          label="Total Paid Out"
          value={totalPaid !== undefined ? `${formatToken(totalPaid)} ELOA` : '—'}
          highlight="amber"
        />
        <Stat
          label="Total Forfeited"
          value={totalForfeited !== undefined ? `${formatToken(totalForfeited)} ELOA` : '—'}
        />
      </div>

      {/* Utilisation bar */}
      <div>
        <div className="flex justify-between text-xs text-zinc-500 mb-1">
          <span>Vault utilisation</span>
          <span>{utilisation < 0.01 ? utilisation.toFixed(4) : utilisation.toFixed(2)}%</span>
        </div>
        <div className="h-1.5 w-full rounded-full bg-zinc-800 overflow-hidden">
          <div
            className="h-full rounded-full bg-linear-to-r from-emerald-500 to-emerald-400"
            style={{ width: `${Math.max(Math.min(utilisation, 100), utilisation > 0 ? 0.5 : 0)}%` }}
          />
        </div>
      </div>

      {/* Fee diversion */}
      {feeDiversionBps !== undefined && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-950/50 p-3 text-xs text-zinc-400 space-y-1">
          <div className="flex justify-between">
            <span>Fee diversion</span>
            <span className="text-zinc-300">{feeDiversionBps / 100}% of LP fees</span>
          </div>
          <div className="flex justify-between">
            <span>Fee growth global</span>
            <span className="text-zinc-300 font-mono">{feeGrowthGlobal?.toString() ?? '—'}</span>
          </div>
          <div className="flex justify-between">
            <span>Forfeit growth global</span>
            <span className="text-zinc-300 font-mono">{forfeitGrowthGlobal?.toString() ?? '—'}</span>
          </div>
        </div>
      )}

      {/* Yield vault */}
      <div className="flex items-center justify-between rounded-xl border border-zinc-800 bg-zinc-950/50 px-3 py-2 text-xs">
        <span className="text-zinc-400">Yield Strategy</span>
        {yieldVault && yieldVault !== '0x0000000000000000000000000000000000000000' ? (
          <span className="text-emerald-400 font-mono">{yieldVault.slice(0, 10)}…</span>
        ) : (
          <span className="text-zinc-600">None (raw balance)</span>
        )}
      </div>
    </div>
  )
}
