'use client'

import { useAccount } from 'wagmi'
import { useTokenBalances, usePermit2Allowances } from '@/lib/eleos'
import { useApproveTokenToPermit2, usePermit2Approve } from '@/lib/eleos/hooks'
import { formatToken } from '@/lib/eleos/utils'
import { CONTRACTS } from '@/lib/eleos/constants'

function ApprovalStep({
  label,
  approved,
  onApprove,
  isPending,
}: {
  label: string
  approved: boolean
  onApprove: () => void
  isPending: boolean
}) {
  return (
    <div className="flex items-center justify-between">
      <div className="flex items-center gap-2">
        <span className={`h-2 w-2 rounded-full ${approved ? 'bg-emerald-400' : 'bg-zinc-600'}`} />
        <span className="text-xs text-zinc-400">{label}</span>
      </div>
      {!approved && (
        <button
          onClick={onApprove}
          disabled={isPending}
          className="rounded-lg bg-zinc-800 px-3 py-1 text-xs text-zinc-300 hover:bg-zinc-700 transition-colors disabled:opacity-50"
        >
          {isPending ? 'Approving…' : 'Approve'}
        </button>
      )}
    </div>
  )
}

export function TokenBalancesCard() {
  const { isConnected } = useAccount()
  const { token0Balance, token1Balance, token0Symbol, token1Symbol, isLoading } = useTokenBalances()
  const { token0Approved, token1Approved } = usePermit2Allowances()

  // Approval flow: token0 → Permit2
  const approveTok0ToPermit2 = useApproveTokenToPermit2(CONTRACTS.TOKEN0)
  const approveTok1ToPermit2 = useApproveTokenToPermit2(CONTRACTS.TOKEN1)
  const permit2Tok0 = usePermit2Approve(CONTRACTS.TOKEN0)
  const permit2Tok1 = usePermit2Approve(CONTRACTS.TOKEN1)

  if (!isConnected) {
    return null
  }

  return (
    <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-4">
      <h2 className="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Token Balances</h2>

      {isLoading ? (
        <div className="space-y-2">
          {[1, 2].map((i) => <div key={i} className="h-10 animate-pulse rounded bg-zinc-800" />)}
        </div>
      ) : (
        <div className="space-y-2">
          <div className="flex items-center justify-between rounded-xl bg-zinc-950/50 border border-zinc-800 px-4 py-3">
            <span className="text-sm font-medium text-zinc-300">{token0Symbol ?? 'ELOB'}</span>
            <span className="text-sm tabular-nums text-zinc-100">
              {token0Balance !== undefined ? formatToken(token0Balance) : '—'}
            </span>
          </div>
          <div className="flex items-center justify-between rounded-xl bg-zinc-950/50 border border-zinc-800 px-4 py-3">
            <span className="text-sm font-medium text-zinc-300">{token1Symbol ?? 'ELOA'}</span>
            <span className="text-sm tabular-nums text-zinc-100">
              {token1Balance !== undefined ? formatToken(token1Balance) : '—'}
            </span>
          </div>
        </div>
      )}

      {/* Permit2 approval status (required before adding liquidity) */}
      <div className="border-t border-zinc-800 pt-4 flex flex-col gap-2">
        <p className="text-xs text-zinc-500 mb-1">PositionManager approvals (required to add liquidity)</p>
        <ApprovalStep
          label="ELOB → Permit2"
          approved={approveTok0ToPermit2.isSuccess || token0Approved}
          onApprove={approveTok0ToPermit2.approve}
          isPending={approveTok0ToPermit2.isPending || approveTok0ToPermit2.isConfirming}
        />
        <ApprovalStep
          label="ELOA → Permit2"
          approved={approveTok1ToPermit2.isSuccess || token1Approved}
          onApprove={approveTok1ToPermit2.approve}
          isPending={approveTok1ToPermit2.isPending || approveTok1ToPermit2.isConfirming}
        />
        <ApprovalStep
          label="Permit2 → PositionManager (ELOB)"
          approved={permit2Tok0.isSuccess || token0Approved}
          onApprove={permit2Tok0.approve}
          isPending={permit2Tok0.isPending || permit2Tok0.isConfirming}
        />
        <ApprovalStep
          label="Permit2 → PositionManager (ELOA)"
          approved={permit2Tok1.isSuccess || token1Approved}
          onApprove={permit2Tok1.approve}
          isPending={permit2Tok1.isPending || permit2Tok1.isConfirming}
        />
      </div>
    </div>
  )
}
