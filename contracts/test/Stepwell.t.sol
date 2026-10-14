// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {StepwellFactory} from "../src/StepwellFactory.sol";
import {CoverToken} from "../src/CoverToken.sol";
import {MockUSDC, MockVault} from "./mocks/Mocks.sol";

contract StepwellTest is Test {
    MockUSDC usdc;
    MockVault vault;
    StepwellFactory factory;
    Stepwell well;
    CoverToken coverToken;

    address under = address(0xA11CE);
    address dep = address(0xB0B);
    address dep2 = address(0xCA7);

    uint256 constant D = 1e6;

    function params() internal pure returns (Stepwell.Params memory) {
        return Stepwell.Params({
            floorBps: 1500,
            coverLowBps: 1000,
            coverHighBps: 2000,
            premiumHighBps: 3500,
            premiumLowBps: 1500,
            noticeSeconds: 3 days,
            claimWindowSeconds: 7 days
        });
    }

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MockVault(usdc);
        factory = new StepwellFactory();
        well = factory.create(vault, "Stepwell test", "swT", params());
        coverToken = well.cover();
        for (uint256 i = 0; i < 3; i++) {
            address a = [under, dep, dep2][i];
            usdc.mint(a, 1_000_000 * D);
            vm.prank(a);
            usdc.approve(address(well), type(uint256).max);
        }
    }

    function _seed() internal {
        vm.prank(under);
        well.depositCover(150 * D, under);
        vm.prank(dep);
        well.deposit(850 * D, dep);
    }

    function test_noCoverMeansNoCoveredDeposits() public {
        vm.prank(dep);
        vm.expectRevert(abi.encodeWithSelector(Stepwell.NotEnoughCover.selector, 0));
        well.deposit(1 * D, dep);
    }

    function test_floorLimitsDeposits() public {
        vm.prank(under);
        well.depositCover(150 * D, under);
        assertEq(well.maxDeposit(dep), 850 * D);
        vm.prank(dep);
        vm.expectRevert(abi.encodeWithSelector(Stepwell.NotEnoughCover.selector, 850 * D));
        well.deposit(851 * D, dep);
    }

    function test_lossInsideCoverLeavesDepositorsWhole() public {
        _seed();
        vault.lose(80 * D);
        (uint256 deep, uint256 c) = well.settled();
        assertApproxEqAbs(deep, 850 * D, 2);
        assertApproxEqAbs(c, 70 * D, 2);
        well.sync();
        assertApproxEqAbs(well.lossAbsorbed(), 80 * D, 2);
        assertEq(well.lossPassedThrough(), 0);
        assertApproxEqAbs(well.previewRedeem(well.balanceOf(dep)), 850 * D, 2);
    }

    function test_lossBeyondCoverWipesLayerAndReachesDepositors() public {
        _seed();
        uint256 epoch = coverToken.epoch();
        vault.lose(220 * D);
        well.sync();
        assertEq(well.coverAssets(), 0);
        assertApproxEqAbs(well.deepAssets(), 780 * D, 2);
        assertEq(coverToken.epoch(), epoch + 1);
        assertEq(coverToken.balanceOf(under), 0);
        assertEq(coverToken.totalSupply(), 0);
        assertApproxEqAbs(well.lossPassedThrough(), 70 * D, 2);
        // a fresh layer starts clean
        vm.prank(dep2);
        well.depositCover(100 * D, dep2);
        assertApproxEqAbs(well.coverBalanceAssets(dep2), 100 * D, 2);
    }

    function test_gainSplitsWithPremium() public {
        _seed();
        vault.earn(60 * D);
        (uint256 deep, uint256 c) = well.settled();
        // cover at 15% sits halfway on the curve: 25% of depositors' interest passes up
        assertEq(well.premiumBpsAt(850 * D, 150 * D), 2500);
        assertApproxEqAbs(deep, 888_250_000, 3);
        assertApproxEqAbs(c, 171_750_000, 3);
    }

    function test_premiumCurve() public view {
        assertEq(well.premiumBpsAt(900, 100), 3500);
        assertEq(well.premiumBpsAt(800, 200), 1500);
        assertEq(well.premiumBpsAt(500, 500), 1500);
        assertEq(well.premiumBpsAt(950, 50), 3500);
    }

    function test_depositorExitsAnyTime() public {
        _seed();
        uint256 shares = well.balanceOf(dep);
        uint256 before = usdc.balanceOf(dep);
        vm.prank(dep);
        well.redeem(shares, dep, dep);
        assertApproxEqAbs(usdc.balanceOf(dep) - before, 850 * D, 2);
        assertEq(well.balanceOf(dep), 0);
    }

    function test_underwriterNeedsNotice() public {
        _seed();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        vm.expectRevert(Stepwell.NoNotice.selector);
        well.claimCover(under);
        vm.prank(under);
        well.giveNotice(shares);
        vm.prank(under);
        vm.expectRevert();
        well.claimCover(under);
        vm.warp(block.timestamp + 3 days);
        // a loss during the notice still lands on the underwriter
        vault.lose(50 * D);
        uint256 before = usdc.balanceOf(under);
        vm.prank(under);
        well.claimCover(under);
        assertApproxEqAbs(usdc.balanceOf(under) - before, 100 * D, 2);
    }

    function test_noticeExpires() public {
        _seed();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        well.giveNotice(shares);
        vm.warp(block.timestamp + 3 days + 7 days + 1);
        vm.prank(under);
        vm.expectRevert(Stepwell.NoticeExpired.selector);
        well.claimCover(under);
    }

    function test_noticeVoidedByWipe() public {
        _seed();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        well.giveNotice(shares);
        vault.lose(300 * D);
        vm.warp(block.timestamp + 3 days);
        vm.prank(under);
        vm.expectRevert(Stepwell.NoNotice.selector);
        well.claimCover(under);
    }

    function test_coverSharesCannotMove() public {
        _seed();
        vm.prank(under);
        vm.expectRevert(CoverToken.NotTransferable.selector);
        coverToken.transfer(dep, 1);
        vm.expectRevert(CoverToken.OnlyStepwell.selector);
        coverToken.mint(dep, 1);
    }

    function test_exitInKind() public {
        _seed();
        uint256 shares = well.balanceOf(dep);
        vm.prank(dep);
        uint256 got = well.redeemInKind(shares, dep, dep);
        assertApproxEqAbs(vault.previewRedeem(got), 850 * D, 3);
        assertApproxEqAbs(well.coverAssets(), 150 * D, 3);
    }

    function test_registryReportsCoverage() public {
        _seed();
        vault.lose(30 * D);
        Stepwell.Coverage[] memory c = factory.coverageFor(address(vault));
        assertEq(c.length, 1);
        assertApproxEqAbs(c[0].coverAssets, 120 * D, 2);
        assertApproxEqAbs(c[0].coveredAssets, 850 * D, 2);
        assertEq(c[0].floorBps, 1500);
    }

    function test_historyKeptOnChain() public {
        _seed();
        vault.lose(10 * D);
        well.sync();
        Stepwell.Revision[] memory r = well.revisions(10);
        assertEq(r.length, 3);
        assertEq(r[0].kind, well.KIND_LOSS());
        assertEq(r[2].kind, well.KIND_COVER_DEPOSIT());
        for (uint256 i = 0; i < 70; i++) well.sync() ;
        vault.earn(1);
        for (uint256 i = 0; i < 70; i++) { vault.earn(1); well.sync(); }
        assertEq(well.revisions(100).length, 64);
    }

    function test_inflationAttackDoesNotPay() public {
        vm.prank(under);
        well.depositCover(1, under);
        // attacker donates to the vault to inflate the price
        vault.earn(1_000 * D);
        vm.prank(dep2);
        well.depositCover(500 * D, dep2);
        assertGt(well.coverBalanceAssets(dep2), 499 * D);
    }

    function testFuzz_depositExitNeverProfits(uint96 coverAmt, uint96 amt) public {
        coverAmt = uint96(bound(coverAmt, 10 * D, 100_000 * D));
        vm.prank(under);
        well.depositCover(coverAmt, under);
        amt = uint96(bound(amt, 1 * D, well.maxDeposit(dep)));
        uint256 before = usdc.balanceOf(dep);
        vm.startPrank(dep);
        uint256 shares = well.deposit(amt, dep);
        well.redeem(shares, dep, dep);
        vm.stopPrank();
        assertLe(usdc.balanceOf(dep), before);
        assertApproxEqAbs(usdc.balanceOf(dep), before, 3);
    }

    function testFuzz_lossWithinCoverSparesDepositors(uint96 lossAmt) public {
        _seed();
        lossAmt = uint96(bound(lossAmt, 1, 150 * D));
        uint256 priceBefore = well.convertToAssets(1e12);
        vault.lose(lossAmt);
        well.sync();
        assertGe(well.convertToAssets(1e12), priceBefore);
    }
}
