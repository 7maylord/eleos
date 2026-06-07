'use client'

import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from 'wagmi'
import { useState } from 'react'
import { unichainSepolia } from '@/lib/eleos/chain'

const CHAIN_ID = unichainSepolia.id

function truncate(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

export function WalletButton() {
  const { address, isConnected } = useAccount()
  const { connectors, connect, isPending: isConnecting } = useConnect()
  const { disconnect } = useDisconnect()
  const chainId = useChainId()
  const { switchChain, isPending: isSwitching } = useSwitchChain()
  const [showMenu, setShowMenu] = useState(false)

  const onCorrectChain = chainId === CHAIN_ID

  if (isConnected && address) {
    // Wrong network — prominent switch button, no dropdown needed
    if (!onCorrectChain) {
      return (
        <button
          onClick={() => switchChain({ chainId: CHAIN_ID })}
          disabled={isSwitching}
          className="flex items-center gap-2 rounded-full bg-amber-900/60 border border-amber-700 px-4 py-2 text-sm font-medium text-amber-300 hover:bg-amber-800/60 transition-colors disabled:opacity-50"
        >
          <span className="h-2 w-2 rounded-full bg-amber-400" />
          {isSwitching ? 'Switching…' : 'Switch to Unichain'}
        </button>
      )
    }

    return (
      <div className="relative">
        <button
          onClick={() => setShowMenu((v) => !v)}
          className="flex items-center gap-2 rounded-full bg-zinc-800 border border-zinc-700 px-4 py-2 text-sm font-medium text-zinc-100 hover:bg-zinc-700 transition-colors"
        >
          <span className="h-2 w-2 rounded-full bg-emerald-400" />
          {truncate(address)}
        </button>
        {showMenu && (
          <div className="absolute right-0 mt-2 w-48 rounded-xl border border-zinc-800 bg-zinc-900 shadow-xl z-50">
            <div className="px-4 py-2 text-xs text-zinc-500 border-b border-zinc-800">
              Unichain Sepolia
            </div>
            <button
              onClick={() => { disconnect(); setShowMenu(false) }}
              className="w-full rounded-b-xl px-4 py-3 text-left text-sm text-zinc-300 hover:bg-zinc-800 hover:text-zinc-100 transition-colors"
            >
              Disconnect
            </button>
          </div>
        )}
      </div>
    )
  }

  // Show connector list
  if (showMenu) {
    return (
      <div className="relative">
        <button
          onClick={() => setShowMenu(false)}
          className="rounded-full bg-violet-600 px-4 py-2 text-sm font-medium text-white hover:bg-violet-500 transition-colors"
        >
          Connect Wallet
        </button>
        <div className="absolute right-0 mt-2 w-52 rounded-xl border border-zinc-800 bg-zinc-900 shadow-xl z-50">
          {connectors.map((connector) => (
            <button
              key={connector.uid}
              disabled={isConnecting}
              onClick={() => { connect({ connector, chainId: CHAIN_ID }); setShowMenu(false) }}
              className="w-full rounded-xl px-4 py-3 text-left text-sm text-zinc-300 hover:bg-zinc-800 hover:text-zinc-100 transition-colors disabled:opacity-50"
            >
              {connector.name}
            </button>
          ))}
        </div>
      </div>
    )
  }

  return (
    <button
      onClick={() => setShowMenu(true)}
      className="rounded-full bg-violet-600 px-4 py-2 text-sm font-medium text-white hover:bg-violet-500 transition-colors"
    >
      Connect Wallet
    </button>
  )
}
