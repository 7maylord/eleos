// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice 1:1 ERC-4626 mock for testing yield strategy integration.
///         1 share = 1 asset at all times (no yield accrual needed for unit tests).
contract MockYieldVault {
    IERC20 public immutable underlying;
    mapping(address => uint256) public balanceOf;

    constructor(address _underlying) {
        underlying = IERC20(_underlying);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        underlying.transferFrom(msg.sender, address(this), assets);
        shares = assets;
        balanceOf[receiver] += shares;
    }

    function redeem(uint256 shares, address receiver, address owner_) external returns (uint256 assets) {
        require(balanceOf[owner_] >= shares, "insufficient shares");
        balanceOf[owner_] -= shares;
        assets = shares;
        underlying.transfer(receiver, assets);
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256 shares) {
        return assets;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256 assets) {
        return shares;
    }
}
