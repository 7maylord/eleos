import Link from 'next/link'
import { Header } from '@/components/Header'
import { VaultStatsBar } from '@/components/VaultStatsBar'
import { CONTRACTS, POOL_ID } from '@/lib/eleos/constants'

const FEATURES = [
  {
    icon: '📸',
    title: 'Position Snapshotting',
    desc: 'Entry sqrtPrice and timestamp recorded on every addLiquidity. IL is computed from this baseline at exit.',
  },
  {
    icon: '🔀',
    title: 'Fee Diversion',
    desc: '20% of LP fees are physically moved into the RecaptureVault on every swap via afterSwapReturnDelta.',
  },
  {
    icon: '⏱️',
    title: 'Linear Recapture Curve',
    desc: 'The longer you hold, the more IL you recover. Full recapture at lock expiry — no cliffs, no surprises.',
  },
  {
    icon: '💎',
    title: 'Loyalty Multiplier',
    desc: 'Up to 2× bonus for patient LPs. The loyalty multiplier compounds on top of the recapture ratio.',
  },
  {
    icon: '♻️',
    title: 'Forfeit Redistribution',
    desc: 'Early exiters forfeit their unrealised recapture. It accumulates in forfeitGrowthGlobal and flows back to loyal LPs.',
  },
  {
    icon: '🌱',
    title: 'ERC-4626 Yield Strategy',
    desc: 'Idle vault capital earns yield via any ERC-4626 vault (Aave, Morpho). Yield makes the vault self-sustaining.',
  },
]

const DEPLOYED = [
  { label: 'RecaptureHook',     addr: CONTRACTS.HOOK             },
  { label: 'RecaptureVault',    addr: CONTRACTS.VAULT            },
  { label: 'TOKEN0 (ELOB)',     addr: CONTRACTS.TOKEN0           },
  { label: 'TOKEN1 (ELOA)',     addr: CONTRACTS.TOKEN1           },
  { label: 'PoolManager',       addr: CONTRACTS.POOL_MANAGER     },
  { label: 'PositionManager',   addr: CONTRACTS.POSITION_MANAGER },
]

export default function LandingPage() {
  return (
    <div className="flex flex-col min-h-screen bg-zinc-950 text-zinc-100">
      <Header />

      {/* Hero */}
      <section className="relative flex flex-col items-center justify-center gap-6 px-4 py-28 text-center overflow-hidden">
        {/* Glow */}
        <div className="pointer-events-none absolute inset-0 -z-10 flex items-center justify-center">
          <div className="h-96 w-96 rounded-full bg-violet-600/10 blur-3xl" />
        </div>

        <div className="flex items-center gap-2 rounded-full border border-zinc-800 bg-zinc-900 px-3 py-1 text-xs text-zinc-400">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
          Live on Unichain Sepolia · Chain 1301
        </div>

        <h1 className="max-w-3xl text-5xl font-bold leading-tight tracking-tight md:text-6xl">
          <span className="bg-linear-to-r from-violet-400 via-fuchsia-400 to-pink-400 bg-clip-text text-transparent">
            IL is not lost.
          </span>
          <br />
          It is only deferred.
        </h1>

        <p className="max-w-xl text-lg text-zinc-400 leading-relaxed">
          Eleos is a Uniswap v4 hook that recaptures Impermanent Loss for patient liquidity providers
          through time-based curves, loyalty bonuses, and on-chain fee diversion.
        </p>

        <div className="flex flex-wrap gap-3 justify-center">
          <Link
            href="/dashboard"
            className="rounded-full bg-linear-to-r from-violet-600 to-fuchsia-600 px-6 py-3 text-sm font-semibold text-white hover:from-violet-500 hover:to-fuchsia-500 transition-all shadow-lg shadow-violet-900/30"
          >
            Launch App →
          </Link>
          <a
            href={`https://sepolia.uniscan.xyz/address/${CONTRACTS.HOOK}`}
            target="_blank"
            rel="noopener noreferrer"
            className="rounded-full border border-zinc-700 bg-zinc-900 px-6 py-3 text-sm font-semibold text-zinc-300 hover:bg-zinc-800 transition-colors"
          >
            View Contracts ↗
          </a>
        </div>
      </section>

      {/* Live Stats */}
      <section className="mx-auto w-full max-w-3xl px-4 pb-16">
        <VaultStatsBar />
      </section>

      {/* Features */}
      <section className="mx-auto w-full max-w-5xl px-4 pb-20">
        <h2 className="text-center text-2xl font-bold text-zinc-100 mb-10">How it works</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {FEATURES.map((f) => (
            <div
              key={f.title}
              className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 flex flex-col gap-3 hover:border-zinc-700 transition-colors"
            >
              <div className="text-3xl">{f.icon}</div>
              <h3 className="font-semibold text-zinc-100">{f.title}</h3>
              <p className="text-sm text-zinc-400 leading-relaxed">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* How recapture is calculated */}
      <section className="mx-auto w-full max-w-3xl px-4 pb-20">
        <h2 className="text-2xl font-bold text-zinc-100 mb-6">The Maths</h2>
        <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6 font-mono text-sm space-y-3 text-zinc-300">
          <p><span className="text-violet-400">IL</span> = (r−1)² / (r²+1)  &nbsp;<span className="text-zinc-500">where r = currentSqrt / entrySqrt</span></p>
          <p><span className="text-violet-400">ratio</span> = min(timeHeld / lockDuration, 1)  &nbsp;<span className="text-zinc-500">linear recapture curve</span></p>
          <p><span className="text-violet-400">loyalty</span> = 1 + min(timeHeld / 30d, 1)  &nbsp;<span className="text-zinc-500">up to 2× multiplier</span></p>
          <p><span className="text-fuchsia-400">recaptured</span> = IL × depositValue × ratio × loyalty</p>
          <p><span className="text-amber-400">forfeit</span> = IL × depositValue − recaptured  &nbsp;<span className="text-zinc-500">(redistributed to loyal LPs)</span></p>
        </div>
      </section>

      {/* Deployed contracts */}
      <section className="mx-auto w-full max-w-3xl px-4 pb-20">
        <h2 className="text-2xl font-bold text-zinc-100 mb-6">Deployed Contracts</h2>
        <div className="rounded-2xl border border-zinc-800 bg-zinc-900 divide-y divide-zinc-800">
          {DEPLOYED.map(({ label, addr }) => (
            <div key={label} className="flex items-center justify-between px-5 py-3">
              <span className="text-sm text-zinc-400">{label}</span>
              <a
                href={`https://sepolia.uniscan.xyz/address/${addr}`}
                target="_blank"
                rel="noopener noreferrer"
                className="font-mono text-xs text-violet-400 hover:text-violet-300 transition-colors"
              >
                {addr.slice(0, 10)}…{addr.slice(-6)} ↗
              </a>
            </div>
          ))}
          <div className="flex items-center justify-between px-5 py-3">
            <span className="text-sm text-zinc-400">Pool ID</span>
            <span className="font-mono text-xs text-zinc-500">
              {POOL_ID.slice(0, 10)}…{POOL_ID.slice(-6)}
            </span>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-zinc-800 py-8 text-center text-xs text-zinc-600">
        <p>Eleos — Uniswap v4 IL Recapture Hook · Unichain Sepolia · MIT License</p>
      </footer>
    </div>
  )
}
