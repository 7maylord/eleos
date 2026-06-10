'use client'

import {
  useAccount,
  useReadContract,
  useReadContracts,
  useWriteContract,
  useWaitForTransactionReceipt,
  useWatchContractEvent,
} from 'wagmi'
import type { Address, Log } from 'viem'

import {
  RECAPTURE_HOOK_ABI,
  RECAPTURE_VAULT_ABI,
  ERC20_ABI,
  POSITION_MANAGER_ABI,
  PERMIT2_ABI,
  SWAP_ROUTER_ABI,
} from './abis'
import { CONTRACTS, POOL_ID, POOL_KEY, POOL_CONFIG, MAX_UINT160, MAX_UINT48 } from './constants'
import {
  computePositionId,
  encodeAddHookData,
  encodeRemoveHookData,
  buildMintCalldata,
  buildDecreaseCalldata,
  defaultDeadline,
} from './utils'

// ─── Wallet ───────────────────────────────────────────────────────────────────

export function useWallet() {
  return useAccount()
}

// ─── Pool sqrtPrice ───────────────────────────────────────────────────────────

const SLOT0_ABI = [
  {
    name: 'getSlot0',
    type: 'function',
    stateMutability: 'view',
    inputs:  [{ name: 'id', type: 'bytes32' }],
    outputs: [
      { name: 'sqrtPriceX96', type: 'uint160' },
      { name: 'tick',         type: 'int24'   },
      { name: 'protocolFee',  type: 'uint24'  },
      { name: 'lpFee',        type: 'uint24'  },
    ],
  },
] as const

export function usePoolSqrtPrice() {
  const { data, isLoading } = useReadContract({
    address:      CONTRACTS.STATE_VIEW,
    abi:          SLOT0_ABI,
    functionName: 'getSlot0',
    args:         [POOL_ID],
  })
  return {
    sqrtPriceX96: data?.[0] as bigint | undefined,
    tick:         data?.[1] as number | undefined,
    isLoading,
  }
}

// ─── Position ─────────────────────────────────────────────────────────────────

/**
 * Read the full PositionInfo for the connected wallet's position.
 * Returns posId (for other hooks) plus all position fields.
 */
export function usePosition(
  tickLower = POOL_CONFIG.tickLower,
  tickUpper = POOL_CONFIG.tickUpper,
) {
  const { address } = useAccount()
  const posId = address
    ? computePositionId(POOL_ID, address, tickLower, tickUpper)
    : undefined

  const { data, isLoading, isError, refetch } = useReadContract({
    address:      CONTRACTS.HOOK,
    abi:          RECAPTURE_HOOK_ABI,
    functionName: 'positions',
    args:         posId ? [posId] : undefined,
    query:        { enabled: !!posId },
  })

  return {
    posId,
    owner:             data?.[0] as Address | undefined,
    entrySqrtPriceX96: data?.[1] as bigint  | undefined,
    entryTimestamp:    data?.[2] as number  | undefined,
    liquidityAdded:    data?.[3] as bigint  | undefined,
    lockDuration:      data?.[4] as number  | undefined,
    feeGrowthSnapshot: data?.[5] as bigint  | undefined,
    depositValue:      data?.[6] as bigint  | undefined,
    isLoading,
    isError,
    refetch,
  }
}

/**
 * Preview recapture for a position given the current pool sqrtPrice.
 * Call usePoolSqrtPrice() to get currentSqrtPrice.
 */
export function usePreviewRecapture(
  posId: `0x${string}` | undefined,
  currentSqrtPrice: bigint | undefined,
) {
  const { data, isLoading, isError } = useReadContract({
    address:      CONTRACTS.HOOK,
    abi:          RECAPTURE_HOOK_ABI,
    functionName: 'previewRecapture',
    args:         posId && currentSqrtPrice ? [posId, currentSqrtPrice] : undefined,
    query:        { enabled: !!posId && !!currentSqrtPrice },
  })

  return {
    ilPct:            data?.[0] as bigint | undefined,  // WAD-scaled IL %
    ratio:            data?.[1] as bigint | undefined,  // WAD-scaled recapture ratio
    loyaltyMult:      data?.[2] as bigint | undefined,  // WAD-scaled loyalty multiplier
    recapturedTokens: data?.[3] as bigint | undefined,  // token1 amount to receive
    forfeitedTokens:  data?.[4] as bigint | undefined,  // token1 amount forfeited
    isLoading,
    isError,
  }
}

// ─── Pool ─────────────────────────────────────────────────────────────────────

/** All per-pool accounting state from the hook. */
export function usePoolState() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'feeGrowthGlobal',        args: [POOL_ID] },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'forfeitGrowthGlobal',     args: [POOL_ID] },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'feeDiversionBps',         args: [POOL_ID] },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'poolRegistered',          args: [POOL_ID] },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'defaultFeeDiversionBps'              },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'loyaltyBasePeriod'                   },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'loyaltyBonusBps'                     },
      { address: CONTRACTS.HOOK, abi: RECAPTURE_HOOK_ABI, functionName: 'paused'                              },
    ],
  })

  return {
    feeGrowthGlobal:        data?.[0]?.result as bigint  | undefined,
    forfeitGrowthGlobal:    data?.[1]?.result as bigint  | undefined,
    feeDiversionBps:        data?.[2]?.result as number  | undefined,
    poolRegistered:         data?.[3]?.result as boolean | undefined,
    defaultFeeDiversionBps: data?.[4]?.result as number  | undefined,
    loyaltyBasePeriod:      data?.[5]?.result as bigint  | undefined,
    loyaltyBonusBps:        data?.[6]?.result as bigint  | undefined,
    paused:                 data?.[7]?.result as boolean | undefined,
    isLoading,
  }
}

// ─── Vault ────────────────────────────────────────────────────────────────────

/** Complete vault analytics for the pool. */
export function useVaultStats() {
  const { data, isLoading } = useReadContracts({
    contracts: [
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'poolBalance',   args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'totalSeeded',   args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'totalCredited', args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'totalPaid',     args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'totalForfeited',args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'yieldVault',    args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'poolToken',     args: [POOL_ID] },
      { address: CONTRACTS.VAULT, abi: RECAPTURE_VAULT_ABI, functionName: 'paused'                        },
    ],
  })

  return {
    poolBalance:    data?.[0]?.result as bigint  | undefined,
    totalSeeded:    data?.[1]?.result as bigint  | undefined,
    totalCredited:  data?.[2]?.result as bigint  | undefined,
    totalPaid:      data?.[3]?.result as bigint  | undefined,
    totalForfeited: data?.[4]?.result as bigint  | undefined,
    yieldVault:     data?.[5]?.result as Address | undefined,
    poolToken:      data?.[6]?.result as Address | undefined,
    vaultPaused:    data?.[7]?.result as boolean | undefined,
    isLoading,
  }
}

// ─── Token balances & allowances ──────────────────────────────────────────────

export function useTokenBalances() {
  const { address } = useAccount()

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      { address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'balanceOf', args: address ? [address] : undefined },
      { address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'balanceOf', args: address ? [address] : undefined },
      { address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'symbol'                                           },
      { address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'symbol'                                           },
      { address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'decimals'                                         },
      { address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'decimals'                                         },
    ],
    query: { enabled: !!address },
  })

  return {
    token0Balance:  data?.[0]?.result as bigint | undefined,
    token1Balance:  data?.[1]?.result as bigint | undefined,
    token0Symbol:   data?.[2]?.result as string | undefined,
    token1Symbol:   data?.[3]?.result as string | undefined,
    token0Decimals: data?.[4]?.result as number | undefined,
    token1Decimals: data?.[5]?.result as number | undefined,
    isLoading,
    refetch,
  }
}

/**
 * Read Permit2 allowances for both tokens to the PositionManager.
 * Permit2 requires: token.approve(PERMIT2, MAX) then permit2.approve(token, PM, amount, expiry)
 */
export function usePermit2Allowances() {
  const { address } = useAccount()

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.TOKEN0, CONTRACTS.POSITION_MANAGER] : undefined,
      },
      {
        address: CONTRACTS.PERMIT2, abi: PERMIT2_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.TOKEN1, CONTRACTS.POSITION_MANAGER] : undefined,
      },
    ],
    query: { enabled: !!address },
  })

  const now = BigInt(Math.floor(Date.now() / 1000))
  const t0  = data?.[0]?.result
  const t1  = data?.[1]?.result

  return {
    // Permit2 allowance is valid when amount > 0 AND expiration is in the future
    token0Approved: t0 ? (t0[0] > 0n && BigInt(t0[1]) > now) : false,
    token1Approved: t1 ? (t1[0] > 0n && BigInt(t1[1]) > now) : false,
    token0Amount:   t0?.[0] as bigint | undefined,
    token1Amount:   t1?.[0] as bigint | undefined,
    isLoading,
  }
}

// ─── Write: Token approvals ───────────────────────────────────────────────────

/** Step 1: token.approve(permit2, MAX_UINT256) */
export function useApproveTokenToPermit2(tokenAddress: Address) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const approve = () =>
    writeContract({
      address:      tokenAddress,
      abi:          ERC20_ABI,
      functionName: 'approve',
      args:         [CONTRACTS.PERMIT2, 2n ** 256n - 1n],
    })

  return { approve, hash, isPending, isConfirming, isSuccess, error, reset }
}

/** Step 2: permit2.approve(token, positionManager, MAX_UINT160, MAX_UINT48) */
export function usePermit2Approve(tokenAddress: Address) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const approve = () =>
    writeContract({
      address:      CONTRACTS.PERMIT2,
      abi:          PERMIT2_ABI,
      functionName: 'approve',
      args:         [tokenAddress, CONTRACTS.POSITION_MANAGER, MAX_UINT160, MAX_UINT48],
    })

  return { approve, hash, isPending, isConfirming, isSuccess, error, reset }
}

// ─── Write: Claim recapture ───────────────────────────────────────────────────

/**
 * Claim accrued IL recapture without removing liquidity.
 * Requires the lock period to have elapsed (or partial recapture is paid with loyalty multiplier).
 */
export function useClaimRecapture(
  tickLower = POOL_CONFIG.tickLower,
  tickUpper = POOL_CONFIG.tickUpper,
) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const claim = () =>
    writeContract({
      address:      CONTRACTS.HOOK,
      abi:          RECAPTURE_HOOK_ABI,
      functionName: 'claimRecapture',
      args:         [POOL_KEY, tickLower, tickUpper],
    })

  return { claim, hash, isPending, isConfirming, isSuccess, error, reset }
}

// ─── Write: Add liquidity ─────────────────────────────────────────────────────

/**
 * Mint a new LP position via the v4 PositionManager.
 *
 * Prerequisites (check usePermit2Allowances):
 *   1. token0.approve(PERMIT2, MAX)
 *   2. permit2.approve(TOKEN0, POSITION_MANAGER, MAX_UINT160, MAX_UINT48)
 *   3. Same for token1
 *
 * lockDuration defaults to POOL_CONFIG.lockDuration (30 days).
 */
export function useAddLiquidity() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const addLiquidity = (params: {
    tickLower?:    number
    tickUpper?:    number
    liquidity:     bigint
    amount0Max:    bigint
    amount1Max:    bigint
    lockDuration?: number
    deadline?:     bigint
  }) => {
    if (!address) throw new Error('Wallet not connected')

    const tickLower  = params.tickLower  ?? POOL_CONFIG.tickLower
    const tickUpper  = params.tickUpper  ?? POOL_CONFIG.tickUpper
    const lockDur    = params.lockDuration ?? POOL_CONFIG.lockDuration
    const hookData   = encodeAddHookData(address, lockDur)
    const unlockData = buildMintCalldata({
      tickLower,
      tickUpper,
      liquidity:  params.liquidity,
      amount0Max: params.amount0Max,
      amount1Max: params.amount1Max,
      recipient:  address,
      hookData,
    })

    writeContract({
      address:      CONTRACTS.POSITION_MANAGER,
      abi:          POSITION_MANAGER_ABI,
      functionName: 'modifyLiquidities',
      args:         [unlockData, params.deadline ?? defaultDeadline()],
    })
  }

  return { addLiquidity, hash, isPending, isConfirming, isSuccess, error, reset }
}

// ─── Write: Remove liquidity ──────────────────────────────────────────────────

/**
 * Decrease (or fully remove) a position via the v4 PositionManager.
 * Triggers beforeRemoveLiquidity on the hook, which pays out IL recapture.
 *
 * tokenId: the ERC-721 id from PositionManager.
 * liquidity: 0 → use type(uint128).max to remove everything.
 */
export function useRemoveLiquidity() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const removeLiquidity = (params: {
    tokenId:     bigint
    liquidity:   bigint
    amount0Min?: bigint
    amount1Min?: bigint
    deadline?:   bigint
  }) => {
    if (!address) throw new Error('Wallet not connected')

    const hookData   = encodeRemoveHookData(address)
    const unlockData = buildDecreaseCalldata({
      tokenId:    params.tokenId,
      liquidity:  params.liquidity,
      amount0Min: params.amount0Min ?? 0n,
      amount1Min: params.amount1Min ?? 0n,
      recipient:  address,
      hookData,
    })

    writeContract({
      address:      CONTRACTS.POSITION_MANAGER,
      abi:          POSITION_MANAGER_ABI,
      functionName: 'modifyLiquidities',
      args:         [unlockData, params.deadline ?? defaultDeadline()],
    })
  }

  return { removeLiquidity, hash, isPending, isConfirming, isSuccess, error, reset }
}

// ─── Write: Swap ─────────────────────────────────────────────────────────────

/** Check whether both tokens are approved to the SwapRouter (direct ERC-20 approval). */
export function useSwapRouterAllowances() {
  const { address } = useAccount()
  const { data, refetch } = useReadContracts({
    contracts: [
      {
        address: CONTRACTS.TOKEN0, abi: ERC20_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.SWAP_ROUTER] : undefined,
      },
      {
        address: CONTRACTS.TOKEN1, abi: ERC20_ABI, functionName: 'allowance',
        args: address ? [address, CONTRACTS.SWAP_ROUTER] : undefined,
      },
    ],
    query: { enabled: !!address },
  })
  return {
    token0Approved: ((data?.[0]?.result ?? 0n) as bigint) > 0n,
    token1Approved: ((data?.[1]?.result ?? 0n) as bigint) > 0n,
    refetch,
  }
}

/** Approve a token directly to the SwapRouter (not Permit2). */
export function useApproveTokenToSwapRouter(tokenAddress: Address) {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })
  const approve = () =>
    writeContract({
      address:      tokenAddress,
      abi:          ERC20_ABI,
      functionName: 'approve',
      args:         [CONTRACTS.SWAP_ROUTER, 2n ** 256n - 1n],
    })
  return { approve, hash, isPending, isConfirming, isSuccess, error, reset }
}

/**
 * Execute a single-pool exact-input swap via the v4 SwapRouter.
 * Requires: token.approve(SWAP_ROUTER, MAX) for the input token.
 */
export function useSwap() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const swap = (params: {
    amountIn:     bigint
    amountOutMin: bigint
    zeroForOne:   boolean
  }) => {
    if (!address) throw new Error('Wallet not connected')
    writeContract({
      address:      CONTRACTS.SWAP_ROUTER,
      abi:          SWAP_ROUTER_ABI,
      functionName: 'swapExactTokensForTokens',
      args: [
        params.amountIn,
        params.amountOutMin,
        params.zeroForOne,
        POOL_KEY,
        '0x',
        address,
        defaultDeadline(),
      ],
    })
  }

  return { swap, hash, isPending, isConfirming, isSuccess, error, reset }
}

// ─── Events ───────────────────────────────────────────────────────────────────

type RecaptureSettledArgs = {
  positionId:       `0x${string}`
  owner:            Address
  ilPct:            bigint
  recaptureRatio:   bigint
  loyaltyMult:      bigint
  recapturedTokens: bigint
  forfeitedTokens:  bigint
}

export function useOnRecaptureSettled(
  handler: (args: RecaptureSettledArgs, log: Log) => void,
) {
  useWatchContractEvent({
    address:   CONTRACTS.HOOK,
    abi:       RECAPTURE_HOOK_ABI,
    eventName: 'RecaptureSettled',
    onLogs:    (logs) => logs.forEach((log) => handler(log.args as RecaptureSettledArgs, log)),
  })
}

export function useOnSwapFeeDiverted(
  handler: (args: { poolId: `0x${string}`; amount: bigint; newFeeGrowth: bigint }, log: Log) => void,
) {
  useWatchContractEvent({
    address:   CONTRACTS.HOOK,
    abi:       RECAPTURE_HOOK_ABI,
    eventName: 'SwapFeeDiverted',
    onLogs:    (logs) => logs.forEach((log) => handler(log.args as never, log)),
  })
}

export function useOnRecaptureClaimed(
  handler: (args: { positionId: `0x${string}`; owner: Address; recapturedTokens: bigint }, log: Log) => void,
) {
  useWatchContractEvent({
    address:   CONTRACTS.HOOK,
    abi:       RECAPTURE_HOOK_ABI,
    eventName: 'RecaptureClaimed',
    onLogs:    (logs) => logs.forEach((log) => handler(log.args as never, log)),
  })
}

export function useOnPositionRegistered(
  handler: (args: {
    positionId:    `0x${string}`
    owner:         Address
    poolId:        `0x${string}`
    entrySqrtPrice:bigint
    lockDuration:  number
  }, log: Log) => void,
) {
  useWatchContractEvent({
    address:   CONTRACTS.HOOK,
    abi:       RECAPTURE_HOOK_ABI,
    eventName: 'PositionRegistered',
    onLogs:    (logs) => logs.forEach((log) => handler(log.args as never, log)),
  })
}
