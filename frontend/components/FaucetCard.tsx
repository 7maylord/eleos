'use client'

import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { CONTRACTS } from '@/lib/eleos/constants'
import { useTokenBalances } from '@/lib/eleos'
import { formatToken } from '@/lib/eleos/utils'

const MOCK_ERC20_MINT_ABI = [
  {
    name: 'mint',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'to',     type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [],
  },
] as const

const MINT_AMOUNT = 10_000n * 10n ** 18n  // 10,000 tokens

function MintButton({
  label,
  tokenAddress,
  onSuccess,
}: {
  label: string
  tokenAddress: `0x${string}`
  onSuccess?: () => void
}) {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const mint = () => {
    if (!address) return
    writeContract({
      address: tokenAddress,
      abi:     MOCK_ERC20_MINT_ABI,
      functionName: 'mint',
      args:    [address, MINT_AMOUNT],
    })
  }

  return (
    <button
      onClick={mint}
      disabled={isPending || isConfirming}
      className="flex-1 rounded-xl border border-zinc-700 bg-zinc-800 px-4 py-2.5 text-sm font-medium text-zinc-200
        hover:bg-zinc-700 hover:border-zinc-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
    >
      {isPending
        ? 'Confirm…'
        : isConfirming
        ? 'Minting…'
        : isSuccess
        ? `✓ Got 10k ${label}`
        : `Mint 10k ${label}`}
    </button>
  )
}

export function FaucetCard() {
  const { isConnected } = useAccount()
  const { token0Balance, token1Balance, refetch } = useTokenBalances()

  if (!isConnected) return null

  return (
    <div className="rounded-2xl border border-amber-800/40 bg-amber-950/10 p-5 flex flex-col gap-3">
      <div className="flex items-center gap-2">
        <span className="text-lg">🚰</span>
        <div>
          <h2 className="text-sm font-semibold text-amber-400">Testnet Faucet</h2>
          <p className="text-xs text-zinc-500">MockERC20 — anyone can mint</p>
        </div>
      </div>

      {/* Current balances */}
      <div className="grid grid-cols-2 gap-2 text-xs">
        <div className="rounded-lg bg-zinc-900 border border-zinc-800 px-3 py-2">
          <p className="text-zinc-500 mb-0.5">ELOB (token0)</p>
          <p className="text-zinc-200 font-mono tabular-nums">
            {token0Balance !== undefined ? formatToken(token0Balance, 2) : '…'}
          </p>
        </div>
        <div className="rounded-lg bg-zinc-900 border border-zinc-800 px-3 py-2">
          <p className="text-zinc-500 mb-0.5">ELOA (token1)</p>
          <p className="text-zinc-200 font-mono tabular-nums">
            {token1Balance !== undefined ? formatToken(token1Balance, 2) : '…'}
          </p>
        </div>
      </div>

      <div className="flex gap-2">
        <MintButton label="ELOB" tokenAddress={CONTRACTS.TOKEN0} onSuccess={refetch} />
        <MintButton label="ELOA" tokenAddress={CONTRACTS.TOKEN1} onSuccess={refetch} />
      </div>

      <p className="text-xs text-zinc-600">
        Unichain Sepolia ETH faucet:{' '}
        <a
          href="https://faucet.quicknode.com/unichain/sepolia"
          target="_blank"
          rel="noopener noreferrer"
          className="text-zinc-400 hover:text-zinc-300 underline"
        >
          QuickNode
        </a>
        {' · '}
        <a
          href="https://superbridge.app"
          target="_blank"
          rel="noopener noreferrer"
          className="text-zinc-400 hover:text-zinc-300 underline"
        >
          bridge from Sepolia
        </a>
      </p>
    </div>
  )
}
