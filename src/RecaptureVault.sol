// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @dev Minimal ERC-4626 interface used for pluggable yield strategies (Aave, Morpho, etc.).
interface IYieldVault {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);
    function convertToAssets(uint256 shares) external view returns (uint256 assets);
    function balanceOf(address account) external view returns (uint256);
}

/// @title RecaptureVault
/// @notice Holds tokens used for IL recapture payouts.
///
/// Phase 1: Admin-seeded capital per pool; no external yield.
///          Vault balance decreases as LPs exit with recapture payouts.
///          Patient LPs benefit implicitly — early exiters leave more in the vault.
///
/// Phase 2: Real fee diversion via hook's afterSwapReturnDelta (tokens pushed directly).
///          External yield strategies (ERC-4626 compatible) pluggable per pool.
///          Per-position forfeit redistribution via forfeitGrowthGlobal in hook.
///          LP can claim recapture without removing liquidity (claimRecapture on hook).
contract RecaptureVault is Ownable, Pausable, ReentrancyGuard {
    address public hook;

    /// @notice Per-pool: which ERC-20 token the vault holds for this pool (currency1).
    mapping(PoolId => address) public poolToken;

    /// @notice Per-pool raw balance (tokens held directly in this contract, not in yield vault).
    mapping(PoolId => uint256) internal _poolBalance;

    /// @notice Optional ERC-4626 yield vault per pool (address(0) = no yield strategy).
    mapping(PoolId => address) public yieldVault;

    /// @notice Shares held in the yield vault per pool.
    mapping(PoolId => uint256) public yieldShares;

    // ─── Analytics (Feature 4 / 7) ─────────────────────────────────────────────

    mapping(PoolId => uint256) public totalSeeded;
    mapping(PoolId => uint256) public totalCredited;
    mapping(PoolId => uint256) public totalPaid;
    mapping(PoolId => uint256) public totalForfeited;

    // ─── Events ────────────────────────────────────────────────────────────────

    event HookSet(address hook);
    event PoolRegistered(PoolId indexed poolId, address token);
    event PoolSeeded(PoolId indexed poolId, uint256 amount);
    event PoolCredited(PoolId indexed poolId, uint256 amount);
    event RecapturePaid(PoolId indexed poolId, bytes32 indexed positionId, address recipient, uint256 amount);
    event ForfeitRetained(PoolId indexed poolId, bytes32 indexed positionId, uint256 amount);
    event YieldVaultSet(PoolId indexed poolId, address yieldVault);
    event YieldDeposited(PoolId indexed poolId, uint256 assets, uint256 shares);
    event YieldWithdrawn(PoolId indexed poolId, uint256 shares, uint256 assets);

    // ─── Errors ────────────────────────────────────────────────────────────────

    error OnlyHook();
    error PoolAlreadyRegistered();
    error PoolNotRegistered();
    error ZeroAmount();
    error YieldVaultHasShares();

    modifier onlyHook() {
        if (msg.sender != hook) revert OnlyHook();
        _;
    }

    constructor(address owner_) Ownable(owner_) {}

    // ─── Admin Setup ───────────────────────────────────────────────────────────

    /// @notice Point vault to the deployed hook (callable exactly once after deployment).
    function setHook(address _hook) external onlyOwner {
        require(hook == address(0), "hook already set"); // L-2: immutable after first set
        hook = _hook;
        emit HookSet(_hook);
    }

    /// @notice Register which token a pool's vault uses (called by hook on first addLiquidity).
    function registerPool(PoolId poolId, address token) external onlyHook {
        if (poolToken[poolId] != address(0)) revert PoolAlreadyRegistered();
        poolToken[poolId] = token;
        emit PoolRegistered(poolId, token);
    }

    /// @notice Admin seeds the vault with initial capital for a pool.
    ///         Must be called after registerPool so the token is known.
    function seedPool(PoolId poolId, uint256 amount) external onlyOwner whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        address token = poolToken[poolId];
        if (token == address(0)) revert PoolNotRegistered();
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        _poolBalance[poolId] += amount;
        totalSeeded[poolId] += amount;
        _depositToYield(poolId, amount);
        emit PoolSeeded(poolId, amount);
    }

    /// @notice Set an ERC-4626 yield vault for a pool.
    ///         Any existing raw balance is deposited into the new vault immediately.
    ///         To remove a yield strategy, call with address(0) — existing shares are redeemed first.
    function setYieldVault(PoolId poolId, address _yieldVault) external onlyOwner {
        address token = poolToken[poolId];
        require(token != address(0), "pool not registered");
        require(yieldShares[poolId] == 0, "redeem yield before changing vault");

        // Auto-deposit any raw balance into the new vault
        if (_yieldVault != address(0) && _poolBalance[poolId] > 0) {
            uint256 bal = _poolBalance[poolId];
            _poolBalance[poolId] = 0;
            IERC20(token).approve(_yieldVault, bal);
            uint256 shares = IYieldVault(_yieldVault).deposit(bal, address(this));
            yieldShares[poolId] = shares;
            emit YieldDeposited(poolId, bal, shares);
        }

        yieldVault[poolId] = _yieldVault;
        emit YieldVaultSet(poolId, _yieldVault);
    }

    // ─── Hook Interface ────────────────────────────────────────────────────────

    /// @notice Credit the pool's vault with diverted swap fees.
    ///         Phase 2: tokens are already in this contract (pushed via poolManager.take).
    ///         No transferFrom — caller (hook) is responsible for having sent tokens first.
    function credit(PoolId poolId, uint256 amount) external onlyHook whenNotPaused {
        if (amount == 0) return;
        address token = poolToken[poolId];
        if (token == address(0)) revert PoolNotRegistered();
        _poolBalance[poolId] += amount;
        totalCredited[poolId] += amount;
        _depositToYield(poolId, amount);
        emit PoolCredited(poolId, amount);
    }

    /// @notice Pay out a recapture amount to an LP on position removal or direct claim.
    ///         Amount is capped to available pool balance — vault never over-pays.
    /// @return paid Actual amount transferred.
    function payRecapture(PoolId poolId, bytes32 positionId, address recipient, uint256 requested)
        external
        onlyHook
        nonReentrant
        whenNotPaused
        returns (uint256 paid)
    {
        if (requested == 0) return 0;
        address token = poolToken[poolId];
        if (token == address(0)) revert PoolNotRegistered();

        uint256 available = poolBalance(poolId);
        paid = requested > available ? available : requested;
        if (paid == 0) return 0;

        _ensureBalance(poolId, paid);
        paid = paid > _poolBalance[poolId] ? _poolBalance[poolId] : paid;
        if (paid == 0) return 0;

        _poolBalance[poolId] -= paid;
        totalPaid[poolId] += paid;
        IERC20(token).transfer(recipient, paid);
        emit RecapturePaid(poolId, positionId, recipient, paid);
    }

    /// @notice Record an early-exit forfeit and update the global forfeit total.
    ///         Forfeited tokens remain in the pool balance for redistribution to loyal LPs.
    function recordForfeit(PoolId poolId, bytes32 positionId, uint256 amount)
        external
        onlyHook
        whenNotPaused
    {
        totalForfeited[poolId] += amount;
        emit ForfeitRetained(poolId, positionId, amount);
    }

    // ─── ERC-4626–style View Interface (Feature 7) ─────────────────────────────

    /// @notice The token managed by this vault for the given pool.
    function asset(PoolId poolId) external view returns (address) {
        return poolToken[poolId];
    }

    /// @notice Total assets available for recapture payouts (direct + yield vault).
    function totalAssets(PoolId poolId) external view returns (uint256) {
        return poolBalance(poolId);
    }

    /// @notice Current available pool balance, including accrued yield.
    function poolBalance(PoolId poolId) public view returns (uint256) {
        address yv = yieldVault[poolId];
        if (yv != address(0) && yieldShares[poolId] > 0) {
            return _poolBalance[poolId]
                + IYieldVault(yv).convertToAssets(yieldShares[poolId]);
        }
        return _poolBalance[poolId];
    }

    // ─── Emergency ─────────────────────────────────────────────────────────────

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Rescue all tokens of a given address. Only callable while paused.
    function emergencyRescue(address token, address recipient) external onlyOwner whenPaused {
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) IERC20(token).transfer(recipient, bal);
    }

    // ─── Internal Helpers ──────────────────────────────────────────────────────

    /// @dev If a yield vault is set, deposit the just-added `amount` from raw balance into it.
    function _depositToYield(PoolId poolId, uint256 amount) internal {
        address yv = yieldVault[poolId];
        if (yv == address(0)) return;
        address token = poolToken[poolId];
        _poolBalance[poolId] -= amount;
        IERC20(token).approve(yv, amount);
        uint256 shares = IYieldVault(yv).deposit(amount, address(this));
        yieldShares[poolId] += shares;
        emit YieldDeposited(poolId, amount, shares);
    }

    /// @dev Ensure at least `needed` tokens are in `_poolBalance`, redeeming from yield vault if necessary.
    function _ensureBalance(PoolId poolId, uint256 needed) internal {
        if (_poolBalance[poolId] >= needed) return;
        address yv = yieldVault[poolId];
        if (yv == address(0) || yieldShares[poolId] == 0) return;

        uint256 shortfall = needed - _poolBalance[poolId];
        uint256 sharesToRedeem = IYieldVault(yv).previewWithdraw(shortfall);
        if (sharesToRedeem > yieldShares[poolId]) sharesToRedeem = yieldShares[poolId];
        if (sharesToRedeem == 0) return;

        uint256 redeemed = IYieldVault(yv).redeem(sharesToRedeem, address(this), address(this));
        yieldShares[poolId] -= sharesToRedeem;
        _poolBalance[poolId] += redeemed;
        emit YieldWithdrawn(poolId, sharesToRedeem, redeemed);
    }
}
