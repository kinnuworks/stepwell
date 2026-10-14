// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {StepwellFactory} from "../src/StepwellFactory.sol";

/// Runs against Arc mainnet state: a real Morpho vault and Arc's native USDC.
/// FORK=1 arc-forge test --match-contract Fork
contract ForkTest is Test {
    IERC20 constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC4626 constant STEAKHOUSE = IERC4626(0xbeef0016cb2Fd5C352ea7CA08a9f54739DFa7298);

    function setUp() public {
        if (vm.envOr("FORK", uint256(0)) == 0) return;
        vm.createSelectFork("arc");
    }

    function test_fork_realMorphoVault() public {
        if (vm.envOr("FORK", uint256(0)) == 0) return;
        assertEq(STEAKHOUSE.asset(), address(USDC));
        StepwellFactory f = new StepwellFactory();
        Stepwell w = f.create(STEAKHOUSE, "Stepwell Steakhouse", "swSTEAK",
            Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 7 days));
        address u = makeAddr("underwriter");
        address d = makeAddr("depositor");
        vm.deal(u, 10 ether); // native USDC has 18 decimals: 10e18 is 10 USDC
        vm.deal(d, 10 ether);
        assertEq(USDC.balanceOf(u), 10e6);
        vm.startPrank(u);
        USDC.approve(address(w), type(uint256).max);
        w.depositCover(1.5e6, u);
        vm.stopPrank();
        vm.startPrank(d);
        USDC.approve(address(w), type(uint256).max);
        uint256 amt = w.maxDeposit(d); // the vault rounds a few units off the cover, so the floor allows a hair under 8.5
        uint256 shares = w.deposit(amt, d);
        vm.warp(block.timestamp + 30 days);
        w.sync();
        uint256 got = w.redeem(shares, d, d);
        vm.stopPrank();
        emit log_named_uint("covered deposit back after 30 days (6 dp)", got);
        assertGe(got + 2, amt);
        Stepwell.Coverage memory c = w.coverage();
        emit log_named_uint("cover layer after 30 days (6 dp)", c.coverAssets);
        assertGe(c.coverAssets + 2, 1.5e6);
    }
}
