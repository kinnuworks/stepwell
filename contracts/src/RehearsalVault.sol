// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RehearsalVault
/// @notice A plain ERC-4626 vault holding a few of the Stepwell team's own dollars, with one
///         extra power: the rehearsal operator can mark it down, so anyone visiting the site can
///         watch a real loss hit a real Stepwell on mainnet. Lost money goes to `sink`, which
///         belongs to the team, and is put back with `refill`. It holds nobody else's money.
contract RehearsalVault is ERC4626 {
    using SafeERC20 for IERC20;

    address public immutable operator;
    address public immutable sink;
    uint256 public constant MAX_LOSS_BPS = 1_500;
    uint256 public lastLossAt;

    event Loss(uint256 bps, uint256 assets);
    event Refill(uint256 assets);

    error OnlyOperator();
    error TooMuch();

    constructor(IERC20 usdc, address operator_, address sink_)
        ERC20("Stepwell rehearsal vault", "swREH")
        ERC4626(usdc)
    {
        operator = operator_;
        sink = sink_;
    }

    /// @notice Lose `bps` of the vault's assets, at most 15% per call.
    function lose(uint256 bps) external returns (uint256 assets) {
        if (msg.sender != operator) revert OnlyOperator();
        if (bps == 0 || bps > MAX_LOSS_BPS) revert TooMuch();
        assets = totalAssets() * bps / 10_000;
        lastLossAt = block.timestamp;
        IERC20(asset()).safeTransfer(sink, assets);
        emit Loss(bps, assets);
    }

    /// @notice Put money back, booked as a gain for whoever holds the vault.
    function refill(uint256 assets) external {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        emit Refill(assets);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
