'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { WalletButton } from './WalletButton'

export function Header() {
  const path = usePathname()

  return (
    <header className="sticky top-0 z-40 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur-sm">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-4">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2">
          <span className="text-xl font-bold bg-linear-to-r from-violet-400 to-fuchsia-400 bg-clip-text text-transparent">
            Eleos
          </span>
          <span className="rounded-full bg-zinc-800 px-2 py-0.5 text-xs text-zinc-400 font-mono">
            v4 hook
          </span>
        </Link>

        {/* Nav */}
        <nav className="hidden md:flex items-center gap-1">
          <Link
            href="/"
            className={`rounded-lg px-3 py-1.5 text-sm transition-colors ${
              path === '/'
                ? 'bg-zinc-800 text-zinc-100'
                : 'text-zinc-400 hover:text-zinc-100'
            }`}
          >
            Home
          </Link>
          <Link
            href="/dashboard"
            className={`rounded-lg px-3 py-1.5 text-sm transition-colors ${
              path === '/dashboard'
                ? 'bg-zinc-800 text-zinc-100'
                : 'text-zinc-400 hover:text-zinc-100'
            }`}
          >
            Dashboard
          </Link>
        </nav>

        <WalletButton />
      </div>
    </header>
  )
}
