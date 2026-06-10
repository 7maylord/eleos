'use client'

import { useAccount } from 'wagmi'
import { Header } from '@/components/Header'
import { PositionCard } from '@/components/PositionCard'
import { AddLiquidityCard } from '@/components/AddLiquidityCard'
import { SwapCard } from '@/components/SwapCard'
import { VaultCard } from '@/components/VaultCard'
import { TokenBalancesCard } from '@/components/TokenBalancesCard'
import { FaucetCard } from '@/components/FaucetCard'
import { WalletButton } from '@/components/WalletButton'
import { POOL_CONFIG, CONTRACTS, POOL_ID } from '@/lib/eleos/constants'

function ConnectPrompt() {
  return (
    <div className="flex flex-col items-center justify-center gap-6 py-24 text-center">
      <div className="h-20 w-20 rounded-full bg-violet-950/50 border border-violet-800/40 flex items-center justify-center text-4xl">
        🔗
      </div>
      <div>
        <h2 className="text-xl font-bold text-zinc-100 mb-2">Connect your wallet</h2>
        <p className="text-zinc-400 text-sm max-w-xs">
          Connect to Unichain Sepolia to view your LP position and claim IL recapture.
        </p>
      </div>
      <WalletButton />
    </div>
  )
}

function InfoPill({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center gap-1.5 rounded-full bg-zinc-900 border border-zinc-800 px-3 py-1 text-xs">
      <span className="text-zinc-500">{label}</span>
      <span className="text-zinc-300 font-mono">{value}</span>
    </div>
  )
}

export default function Dashboard() {
  const { isConnected } = useAccount()

  return (
    <div className="flex flex-col min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      <main className="mx-auto w-full max-w-6xl px-4 py-8 flex flex-col gap-6 flex-1">

        {/* Page header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold text-zinc-100">Dashboard</h1>
            <p className="text-sm text-zinc-500 mt-0.5">
              Manage your LP position and claim IL recapture.
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <InfoPill label="Pool" value={`${POOL_ID.slice(0, 8)}…`} />
            <InfoPill label="Fee" value={`${POOL_CONFIG.fee / 10000}%`} />
            <InfoPill label="Ticks" value={`${POOL_CONFIG.tickLower} / ${POOL_CONFIG.tickUpper}`} />
            <InfoPill label="Chain" value="Unichain Sepolia" />
          </div>
        </div>

        {!isConnected ? (
          <ConnectPrompt />
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Left column: position + swap + add liquidity */}
            <div className="flex flex-col gap-4">
              <PositionCard />
              <SwapCard />
              <AddLiquidityCard />
            </div>

            {/* Right column: vault + balances + faucet */}
            <div className="flex flex-col gap-4">
              <VaultCard />
              <TokenBalancesCard />
              <FaucetCard />
            </div>
          </div>
        )}

        {/* Contract quick-links */}
        <div className="rounded-2xl border border-zinc-800 bg-zinc-900/50 p-4">
          <p className="text-xs text-zinc-500 mb-3 uppercase tracking-wider">Contract addresses · Unichain Sepolia</p>
          <div className="flex flex-wrap gap-2">
            {(
              [
                ['Hook',     CONTRACTS.HOOK   ],
                ['Vault',    CONTRACTS.VAULT  ],
                ['ELOB',     CONTRACTS.TOKEN0 ],
                ['ELOA',     CONTRACTS.TOKEN1 ],
              ] as const
            ).map(([label, addr]) => (
              <a
                key={label}
                href={`https://sepolia.uniscan.xyz/address/${addr}`}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-lg border border-zinc-800 bg-zinc-950 px-3 py-1.5 text-xs text-zinc-400 hover:text-violet-400 hover:border-violet-800/50 transition-colors font-mono"
              >
                {label}: {addr.slice(0, 8)}…{addr.slice(-4)} ↗
              </a>
            ))}
          </div>
        </div>
      </main>

      <footer className="border-t border-zinc-800 py-6 text-center text-xs text-zinc-700">
        Eleos — Uniswap v4 IL Recapture Hook
      </footer>
    </div>
  )
}
