// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev A vault whose value the test can move up or down, standing in for a Morpho vault.
contract MockVault is ERC4626 {
    constructor(IERC20 a) ERC20("Mock vault", "mv") ERC4626(a) {}

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    uint256 public liquidityCap = type(uint256).max;

    function setLiquidityCap(uint256 c) external {
        liquidityCap = c;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 m = super.maxWithdraw(owner);
        return m < liquidityCap ? m : liquidityCap;
    }

    function lose(uint256 assets) external {
        IERC20(asset()).transfer(address(0xdead), assets);
    }

    function earn(uint256 assets) external {
        MockUSDC(asset()).mint(address(this), assets);
    }
}
