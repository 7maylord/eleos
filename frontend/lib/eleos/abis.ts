// Full ABIs for all Eleos contracts plus necessary periphery contracts.

export const RECAPTURE_HOOK_ABI = [
  // ─── State readers ───────────────────────────────────────────────────────────
  {
    name: 'vault', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'positions', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'posId', type: 'bytes32' }],
    outputs: [
      { name: 'owner',              type: 'address' },
      { name: 'entrySqrtPriceX96',  type: 'uint160' },
      { name: 'entryTimestamp',     type: 'uint40'  },
      { name: 'liquidityAdded',     type: 'uint128' },
      { name: 'lockDuration',       type: 'uint40'  },
      { name: 'feeGrowthSnapshot',  type: 'uint256' },
      { name: 'depositValue',       type: 'uint256' },
    ],
  },
  {
    name: 'positionPool', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'posId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  {
    name: 'feeGrowthGlobal', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'forfeitGrowthGlobal', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'forfeitGrowthSnapshot', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'posId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'feeDiversionBps', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint24' }],
  },
  {
    name: 'poolRegistered', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'defaultFeeDiversionBps', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint24' }],
  },
  {
    name: 'loyaltyBasePeriod', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'loyaltyBonusBps', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'paused', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'owner', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'address' }],
  },
  // ─── previewRecapture ────────────────────────────────────────────────────────
  {
    name: 'previewRecapture', type: 'function', stateMutability: 'view',
    inputs: [
      { name: 'posId', type: 'bytes32' },
      { name: 'currentSqrtPrice', type: 'uint160' },
    ],
    outputs: [
      { name: 'ilPct',            type: 'uint256' },
      { name: 'ratio',            type: 'uint256' },
      { name: 'loyaltyMult',      type: 'uint256' },
      { name: 'recapturedTokens', type: 'uint256' },
      { name: 'forfeitedTokens',  type: 'uint256' },
    ],
  },
  // ─── positionId ──────────────────────────────────────────────────────────────
  {
    name: 'positionId', type: 'function', stateMutability: 'pure',
    inputs: [
      { name: 'poolId',    type: 'bytes32' },
      { name: 'owner',     type: 'address' },
      { name: 'tickLower', type: 'int24'   },
      { name: 'tickUpper', type: 'int24'   },
    ],
    outputs: [{ name: '', type: 'bytes32' }],
  },
  // ─── claimRecapture ──────────────────────────────────────────────────────────
  {
    name: 'claimRecapture', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      {
        name: 'key', type: 'tuple',
        components: [
          { name: 'currency0',   type: 'address' },
          { name: 'currency1',   type: 'address' },
          { name: 'fee',         type: 'uint24'  },
          { name: 'tickSpacing', type: 'int24'   },
          { name: 'hooks',       type: 'address' },
        ],
      },
      { name: 'tickLower', type: 'int24' },
      { name: 'tickUpper', type: 'int24' },
    ],
    outputs: [],
  },
  // ─── Admin ───────────────────────────────────────────────────────────────────
  {
    name: 'setDefaultFeeDiversionBps', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'bps', type: 'uint24' }], outputs: [],
  },
  {
    name: 'setPoolFeeDiversionBps', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'poolId', type: 'bytes32' }, { name: 'bps', type: 'uint24' }], outputs: [],
  },
  {
    name: 'setLoyaltyParams', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'basePeriod', type: 'uint256' }, { name: 'bonusBps', type: 'uint256' }], outputs: [],
  },
  { name: 'pause',   type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { name: 'unpause', type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  // ─── Events ──────────────────────────────────────────────────────────────────
  {
    name: 'PositionRegistered', type: 'event',
    inputs: [
      { name: 'positionId',    type: 'bytes32', indexed: true  },
      { name: 'owner',         type: 'address', indexed: true  },
      { name: 'poolId',        type: 'bytes32', indexed: true  },
      { name: 'entrySqrtPrice',type: 'uint160', indexed: false },
      { name: 'lockDuration',  type: 'uint40',  indexed: false },
    ],
  },
  {
    name: 'PositionUpdated', type: 'event',
    inputs: [
      { name: 'positionId',       type: 'bytes32', indexed: true  },
      { name: 'newEntrySqrtPrice',type: 'uint160', indexed: false },
      { name: 'newLiquidity',     type: 'uint128', indexed: false },
    ],
  },
  {
    name: 'SwapFeeDiverted', type: 'event',
    inputs: [
      { name: 'poolId',      type: 'bytes32', indexed: true  },
      { name: 'amount',      type: 'uint256', indexed: false },
      { name: 'newFeeGrowth',type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'RecaptureSettled', type: 'event',
    inputs: [
      { name: 'positionId',       type: 'bytes32', indexed: true  },
      { name: 'owner',            type: 'address', indexed: true  },
      { name: 'ilPct',            type: 'uint256', indexed: false },
      { name: 'recaptureRatio',   type: 'uint256', indexed: false },
      { name: 'loyaltyMult',      type: 'uint256', indexed: false },
      { name: 'recapturedTokens', type: 'uint256', indexed: false },
      { name: 'forfeitedTokens',  type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'ForfeitRedistributed', type: 'event',
    inputs: [
      { name: 'poolId',          type: 'bytes32', indexed: true  },
      { name: 'amount',          type: 'uint256', indexed: false },
      { name: 'newForfeitGrowth',type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'RecaptureClaimed', type: 'event',
    inputs: [
      { name: 'positionId',      type: 'bytes32', indexed: true  },
      { name: 'owner',           type: 'address', indexed: true  },
      { name: 'recapturedTokens',type: 'uint256', indexed: false },
    ],
  },
] as const

export const RECAPTURE_VAULT_ABI = [
  // ─── State readers ───────────────────────────────────────────────────────────
  {
    name: 'hook', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'poolToken', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'yieldVault', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'yieldShares', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalSeeded', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalCredited', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalPaid', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalForfeited', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'poolBalance', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalAssets', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'asset', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'poolId', type: 'bytes32' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'paused', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'owner', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'address' }],
  },
  // ─── Admin ───────────────────────────────────────────────────────────────────
  {
    name: 'seedPool', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'poolId', type: 'bytes32' }, { name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'setYieldVault', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'poolId', type: 'bytes32' }, { name: '_yieldVault', type: 'address' }],
    outputs: [],
  },
  { name: 'pause',   type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { name: 'unpause', type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  {
    name: 'emergencyRescue', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'token', type: 'address' }, { name: 'recipient', type: 'address' }],
    outputs: [],
  },
  // ─── Events ──────────────────────────────────────────────────────────────────
  {
    name: 'PoolSeeded', type: 'event',
    inputs: [
      { name: 'poolId', type: 'bytes32', indexed: true  },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'PoolCredited', type: 'event',
    inputs: [
      { name: 'poolId', type: 'bytes32', indexed: true  },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'RecapturePaid', type: 'event',
    inputs: [
      { name: 'poolId',     type: 'bytes32', indexed: true  },
      { name: 'positionId', type: 'bytes32', indexed: true  },
      { name: 'recipient',  type: 'address', indexed: false },
      { name: 'amount',     type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'ForfeitRetained', type: 'event',
    inputs: [
      { name: 'poolId',     type: 'bytes32', indexed: true  },
      { name: 'positionId', type: 'bytes32', indexed: true  },
      { name: 'amount',     type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'YieldVaultSet', type: 'event',
    inputs: [
      { name: 'poolId',     type: 'bytes32', indexed: true  },
      { name: 'yieldVault', type: 'address', indexed: false },
    ],
  },
  {
    name: 'YieldDeposited', type: 'event',
    inputs: [
      { name: 'poolId',  type: 'bytes32', indexed: true  },
      { name: 'assets',  type: 'uint256', indexed: false },
      { name: 'shares',  type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'YieldWithdrawn', type: 'event',
    inputs: [
      { name: 'poolId',  type: 'bytes32', indexed: true  },
      { name: 'shares',  type: 'uint256', indexed: false },
      { name: 'assets',  type: 'uint256', indexed: false },
    ],
  },
] as const

export const ERC20_ABI = [
  {
    name: 'balanceOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'allowance', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'approve', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'spender', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'transfer', type: 'function', stateMutability: 'nonpayable',
    inputs: [{ name: 'to', type: 'address' }, { name: 'amount', type: 'uint256' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'symbol',   type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'string' }],
  },
  {
    name: 'name',     type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'string' }],
  },
  {
    name: 'decimals', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint8' }],
  },
  {
    name: 'totalSupply', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'Transfer', type: 'event',
    inputs: [
      { name: 'from',  type: 'address', indexed: true  },
      { name: 'to',    type: 'address', indexed: true  },
      { name: 'value', type: 'uint256', indexed: false },
    ],
  },
  {
    name: 'Approval', type: 'event',
    inputs: [
      { name: 'owner',   type: 'address', indexed: true  },
      { name: 'spender', type: 'address', indexed: true  },
      { name: 'value',   type: 'uint256', indexed: false },
    ],
  },
] as const

// Uniswap v4 PositionManager (periphery)
export const POSITION_MANAGER_ABI = [
  {
    name: 'modifyLiquidities', type: 'function', stateMutability: 'payable',
    inputs: [
      { name: 'unlockData', type: 'bytes'   },
      { name: 'deadline',   type: 'uint256' },
    ],
    outputs: [],
  },
  {
    name: 'multicall', type: 'function', stateMutability: 'payable',
    inputs: [{ name: 'data', type: 'bytes[]' }],
    outputs: [{ name: 'results', type: 'bytes[]' }],
  },
  {
    name: 'initializePool', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      {
        name: 'key', type: 'tuple',
        components: [
          { name: 'currency0',   type: 'address' },
          { name: 'currency1',   type: 'address' },
          { name: 'fee',         type: 'uint24'  },
          { name: 'tickSpacing', type: 'int24'   },
          { name: 'hooks',       type: 'address' },
        ],
      },
      { name: 'sqrtPriceX96', type: 'uint160' },
      { name: 'hookData',     type: 'bytes'   },
    ],
    outputs: [{ name: 'tick', type: 'int24' }],
  },
  {
    name: 'nextTokenId', type: 'function', stateMutability: 'view',
    inputs: [], outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'ownerOf', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: '', type: 'address' }],
  },
  {
    name: 'getPositionLiquidity', type: 'function', stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ name: 'liquidity', type: 'uint128' }],
  },
] as const

// Uniswap v4 SwapRouter (hookmate IUniswapV4Router04) — single-pool exact-input
export const SWAP_ROUTER_ABI = [
  {
    name: 'swapExactTokensForTokens',
    type: 'function',
    stateMutability: 'payable',
    inputs: [
      { name: 'amountIn',    type: 'uint256' },
      { name: 'amountOutMin',type: 'uint256' },
      { name: 'zeroForOne',  type: 'bool'    },
      {
        name: 'poolKey', type: 'tuple',
        components: [
          { name: 'currency0',   type: 'address' },
          { name: 'currency1',   type: 'address' },
          { name: 'fee',         type: 'uint24'  },
          { name: 'tickSpacing', type: 'int24'   },
          { name: 'hooks',       type: 'address' },
        ],
      },
      { name: 'hookData', type: 'bytes'   },
      { name: 'receiver', type: 'address' },
      { name: 'deadline',  type: 'uint256' },
    ],
    outputs: [{ name: 'delta', type: 'int256' }],
  },
] as const

// Permit2 — token allowance for PositionManager
export const PERMIT2_ABI = [
  {
    name: 'approve', type: 'function', stateMutability: 'nonpayable',
    inputs: [
      { name: 'token',      type: 'address' },
      { name: 'spender',    type: 'address' },
      { name: 'amount',     type: 'uint160' },
      { name: 'expiration', type: 'uint48'  },
    ],
    outputs: [],
  },
  {
    name: 'allowance', type: 'function', stateMutability: 'view',
    inputs: [
      { name: 'user',    type: 'address' },
      { name: 'token',   type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [
      { name: 'amount',     type: 'uint160' },
      { name: 'expiration', type: 'uint48'  },
      { name: 'nonce',      type: 'uint48'  },
    ],
  },
] as const
