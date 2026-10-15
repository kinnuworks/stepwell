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
    address attacker = address(0xBAD);

    uint256 constant D = 1e6;

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MockVault(usdc);
        factory = new StepwellFactory(keccak256(type(Stepwell).creationCode));
        well = factory.create(vault, "Stepwell test", "swT", factory.standardParams(), type(Stepwell).creationCode);
        coverToken = well.cover();
        address[4] memory who = [under, dep, dep2, attacker];
        for (uint256 i = 0; i < who.length; i++) {
            usdc.mint(who[i], 1_000_000 * D);
            vm.prank(who[i]);
            usdc.approve(address(well), type(uint256).max);
        }
    }

    function _request(address a, uint256 amt) internal {
        vm.prank(a);
        well.requestDeposit(amt, a, a);
    }

    /// 150 of cover and 850 of settled covered deposits.
    function _seed() internal {
        vm.prank(under);
        well.depositCover(150 * D, under);
        _request(dep, 850 * D);
        vm.warp(block.timestamp + 1 days);
        well.settle(dep);
    }

    // --- deposits --------------------------------------------------------------------------

    function test_noCoverMeansNoRequests() public {
        vm.prank(dep);
        vm.expectRevert(abi.encodeWithSelector(Stepwell.NotEnoughCover.selector, 0));
        well.requestDeposit(1 * D, dep, dep);
    }

    function test_floorLimitsRequests() public {
        vm.prank(under);
        well.depositCover(150 * D, under);
        assertEq(well.maxRequest(), 850 * D);
        vm.prank(dep);
        vm.expectRevert(abi.encodeWithSelector(Stepwell.NotEnoughCover.selector, 850 * D));
        well.requestDeposit(851 * D, dep, dep);
    }

    function test_synchronousDepositsAreOff() public {
        assertEq(well.maxDeposit(dep), 0);
        assertEq(well.maxMint(dep), 0);
        vm.expectRevert(Stepwell.UseRequestDeposit.selector);
        well.deposit(1, dep);
        vm.expectRevert(Stepwell.UseRequestDeposit.selector);
        well.mint(1, dep);
    }

    function test_settleOnlyAfterWarmup() public {
        vm.prank(under);
        well.depositCover(150 * D, under);
        _request(dep, 100 * D);
        assertApproxEqAbs(well.pendingDepositRequest(0, dep), 100 * D, 1);
        assertEq(well.claimableDepositRequest(0, dep), 0);
        vm.expectRevert();
        well.settle(dep);
        vm.warp(block.timestamp + 1 days);
        assertApproxEqAbs(well.claimableDepositRequest(0, dep), 100 * D, 1);
        vm.prank(dep2); // anyone may settle for anyone
        well.settle(dep);
        assertApproxEqAbs(well.convertToAssets(well.balanceOf(dep)), 100 * D, 2);
    }

    function test_cancelRequest() public {
        vm.prank(under);
        well.depositCover(150 * D, under);
        _request(dep, 100 * D);
        uint256 before = usdc.balanceOf(dep);
        vm.prank(dep);
        well.cancelDepositRequest(dep);
        assertApproxEqAbs(usdc.balanceOf(dep) - before, 100 * D, 1);
        assertEq(well.totalSettlingShares(), 0);
    }

    function test_decimalsMatchVirtualShares() public {
        _seed();
        assertEq(well.decimals(), 12);
        assertEq(coverToken.decimals(), 12);
        // one dollar of deposit is about one share in a wallet
        assertApproxEqRel(well.balanceOf(dep), 850e12, 1e15);
    }

    // --- the waterfall ---------------------------------------------------------------------

    function test_lossInsideCoverLeavesDepositorsWhole() public {
        _seed();
        vault.lose(80 * D);
        (uint256 deep, uint256 c) = well.settled();
        assertApproxEqAbs(deep, 850 * D, 2);
        assertApproxEqAbs(c, 70 * D, 2);
        well.sync();
        assertApproxEqAbs(well.lossAbsorbed(), 80 * D, 2);
        assertEq(well.lossPassedThrough(), 0);
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
        assertEq(well.coverDeficit(), 0, "a fresh layer is owed nothing");
        assertApproxEqAbs(well.deepDeficit(), 70 * D, 2);
        vm.prank(dep2);
        well.depositCover(100 * D, dep2);
        assertApproxEqAbs(well.coverBalanceAssets(dep2), 100 * D, 2);
    }

    function test_gainSplitsWithPremium() public {
        _seed();
        vault.earn(60 * D);
        (uint256 deep, uint256 c) = well.settled();
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

    // --- exits -----------------------------------------------------------------------------

    function test_depositorExitsAnyTime() public {
        _seed();
        uint256 before = usdc.balanceOf(dep);
        vm.startPrank(dep);
        well.redeem(well.balanceOf(dep), dep, dep);
        vm.stopPrank();
        assertApproxEqAbs(usdc.balanceOf(dep) - before, 850 * D, 2);
    }

    function test_maxWithdrawRespectsVaultLiquidity() public {
        _seed();
        vault.setLiquidityCap(100 * D);
        assertEq(well.maxWithdraw(dep), 100 * D);
        assertLt(well.maxRedeem(dep), well.balanceOf(dep));
        uint256 tooMuch = well.balanceOf(dep);
        vm.prank(dep);
        vm.expectRevert(abi.encodeWithSelector(Stepwell.ExceedsLiquidity.selector, 100 * D));
        well.redeem(tooMuch, dep, dep);
        // the in-kind exit still works
        vm.prank(dep);
        well.redeemInKind(tooMuch, dep, dep);
        assertApproxEqAbs(vault.previewRedeem(vault.balanceOf(dep)), 850 * D, 3);
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
        vault.lose(50 * D); // a loss during the notice still lands on the underwriter
        uint256 before = usdc.balanceOf(under);
        vm.prank(under);
        well.claimCover(under);
        assertApproxEqAbs(usdc.balanceOf(under) - before, 100 * D, 2);
    }

    function test_noticeExpires() public {
        _seed();
        vm.startPrank(under);
        well.giveNotice(coverToken.balanceOf(under));
        vm.warp(block.timestamp + 3 days + 1 days + 1);
        vm.expectRevert(Stepwell.NoticeExpired.selector);
        well.claimCover(under);
        vm.stopPrank();
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
        well.sync(); // the failed claim rolled back its own booking; book the loss for real
        assertEq(well.noticedShares(), 0);
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

    function test_claimCoverInKind() public {
        _seed();
        vm.startPrank(under);
        well.giveNotice(coverToken.balanceOf(under));
        vm.warp(block.timestamp + 3 days);
        uint256 got = well.claimCoverInKind(under);
        vm.stopPrank();
        assertApproxEqAbs(vault.previewRedeem(got), 150 * D, 3);
    }

    // --- regressions for attacks found in review ------------------------------------------

    /// A deposit made just before a loss is not covered: it takes its own pro-rata share.
    function test_jitDepositGetsNoCover() public {
        _seed();
        vm.prank(under);
        well.depositCover(50 * D, under); // room for the attacker
        uint256 room = well.maxRequest();
        _request(attacker, room);
        uint256 coverBefore = well.coverAssets();
        vault.lose(vault.totalAssets() / 10); // the vault loses 10%
        vm.warp(block.timestamp + 1 days);
        well.settle(attacker);
        uint256 attackerValue = well.convertToAssets(well.balanceOf(attacker));
        assertLt(attackerValue, room * 91 / 100, "attacker took its own 10%");
        (, uint256 c) = well.settled();
        assertGt(c, coverBefore * 10 / 100, "cover only paid for the covered deposits");
    }

    /// Shares under notice stop earning, so a matured notice is not a free option.
    function test_noticedSharesStopEarning() public {
        _seed();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        well.giveNotice(shares);
        uint256 cap = well.coverValueOf(shares);
        vault.earn(100 * D);
        vm.warp(block.timestamp + 3 days);
        uint256 before = usdc.balanceOf(under);
        vm.prank(under);
        well.claimCover(under);
        assertLe(usdc.balanceOf(under) - before, cap);
        assertGt(well.coverAssets(), 0, "what the leaver did not take stays with cover");
    }

    /// Nobody can add to someone else's request, so nobody can restart their warm-up.
    function test_cannotResetAnotherDepositorsWarmup() public {
        vm.prank(under);
        well.depositCover(150 * D, under);
        _request(dep, 100 * D);
        vm.warp(block.timestamp + 20 hours);
        vm.prank(attacker);
        vm.expectRevert(Stepwell.NotController.selector);
        well.requestDeposit(1, dep, attacker);
        vm.warp(block.timestamp + 4 hours);
        well.settle(dep);
        assertGt(well.balanceOf(dep), 0, "settled on time");
    }

    /// Two underwriters with 75 each and 850 of covered deposits.
    function _seedTwo() internal {
        vm.prank(under);
        well.depositCover(75 * D, under);
        vm.prank(dep2);
        well.depositCover(75 * D, dep2);
        _request(dep, 850 * D);
        vm.warp(block.timestamp + 1 days);
        well.settle(dep);
    }

    /// Cancelling a notice gives up what the noticed shares earned meanwhile, to the other underwriters.
    function test_cancelledNoticeForfeitsItsGain() public {
        _seedTwo();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        well.giveNotice(shares);
        uint256 cap = well.coverValueOf(shares);
        vault.earn(100 * D);
        vm.prank(under);
        well.cancelNotice();
        uint256 mine = well.coverValueOf(coverToken.balanceOf(under));
        uint256 theirs = well.coverValueOf(coverToken.balanceOf(dep2));
        assertApproxEqAbs(mine, cap, 2, "no interest kept from the notice period");
        assertGt(theirs, mine, "the forfeited interest went to the other underwriter");
    }

    /// Renewing a notice also gives up the gain, so standing notice is not a free option.
    function test_renewedNoticeForfeitsItsGain() public {
        _seedTwo();
        uint256 shares = coverToken.balanceOf(under);
        vm.prank(under);
        well.giveNotice(shares);
        uint256 cap = well.coverValueOf(shares);
        vault.earn(100 * D);
        vm.prank(under);
        well.giveNotice(shares); // renew on everything; capped at what is left after the forfeit
        assertApproxEqAbs(well.coverValueOf(coverToken.balanceOf(under)), cap, 2, "renewal does not reset the cap upward");
    }

    /// After a loss, recovering money refills the cover first (a high-water mark).
    function test_recoveryRefillsCoverFirst() public {
        _seed();
        vault.lose(80 * D);
        well.sync();
        assertApproxEqAbs(well.coverDeficit(), 80 * D, 2);
        vault.earn(80 * D);
        well.sync();
        assertApproxEqAbs(well.deepAssets(), 850 * D, 3);
        assertApproxEqAbs(well.coverAssets(), 150 * D, 3);
        assertLe(well.coverDeficit(), 3);
    }

    function test_inflationAttackDoesNotPay() public {
        vm.prank(attacker);
        well.depositCover(1, attacker);
        uint256 spent = 1_000 * D + 1;
        vault.earn(1_000 * D); // attacker's donation, simulated
        vm.prank(dep2);
        well.depositCover(500 * D, dep2);
        assertGt(well.coverBalanceAssets(dep2), 499 * D, "victim kept their money");
        assertLt(well.coverBalanceAssets(attacker), spent, "attacker lost on the trick");
    }

    // --- registry and history --------------------------------------------------------------

    function test_registryOnlyVouchesForStandardTerms() public {
        _seed();
        Stepwell junk = factory.create(vault, "junk", "J", Stepwell.Params(0, 1000, 2000, 0, 0, 0, 1, 0), type(Stepwell).creationCode);
        assertFalse(factory.isStandard(address(junk)));
        assertTrue(factory.isStandard(address(well)));
        (address[] memory s, Stepwell.Coverage[] memory c) = factory.standardCoverageFor(address(vault));
        assertEq(s.length, 1);
        assertEq(s[0], address(well));
        assertApproxEqAbs(c[0].coverAssets, 150 * D, 2);
        assertEq(factory.coverageFor(address(vault)).length, 2);
    }

    function test_coverageReportsNoticeAndWarmup() public {
        _seed();
        uint256 half = coverToken.balanceOf(under) / 2;
        vm.prank(under);
        well.giveNotice(half);
        vm.prank(dep2);
        well.depositCover(10 * D, dep2); // room for one more request
        _request(dep2, 10 * D);
        Stepwell.Coverage memory c = well.coverage();
        assertApproxEqAbs(c.coverUnderNotice, 75 * D, 3);
        assertApproxEqAbs(c.settlingAssets, 10 * D, 2);
        assertEq(c.warmupSeconds, 1 days);
    }

    function test_historyKeptOnChain() public {
        _seed();
        vault.lose(10 * D);
        well.sync();
        Stepwell.Revision[] memory r = well.revisions(10);
        assertEq(r[0].kind, well.KIND_LOSS());
        assertEq(r[1].kind, well.KIND_SETTLED());
        for (uint256 i = 0; i < 70; i++) {
            vault.earn(1);
            well.sync();
        }
        assertEq(well.revisions(100).length, 64);
    }

    // --- fuzz ------------------------------------------------------------------------------

    function testFuzz_requestSettleExitNeverProfits(uint96 coverAmt, uint96 amt) public {
        coverAmt = uint96(bound(coverAmt, 10 * D, 100_000 * D));
        vm.prank(under);
        well.depositCover(coverAmt, under);
        amt = uint96(bound(amt, 1 * D, well.maxRequest()));
        uint256 before = usdc.balanceOf(dep);
        _request(dep, amt);
        vm.warp(block.timestamp + 1 days);
        well.settle(dep);
        vm.startPrank(dep);
        well.redeem(well.balanceOf(dep), dep, dep);
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
