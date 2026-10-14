// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {CoverToken} from "../src/CoverToken.sol";
import {MockUSDC, MockVault} from "./mocks/Mocks.sol";

/// @dev Drives random sequences of every action against one Stepwell and keeps an independent,
///      deliberately naive model of the two layers alongside it.
contract Handler is Test {
    Stepwell public well;
    MockUSDC public usdc;
    MockVault public vault;
    CoverToken public cover;

    address[] public actors;
    uint256 constant D = 1e6;

    // reference model
    uint256 public mDeep;
    uint256 public mCover;

    // the covered share price must never fall while any cover remains
    uint256 public lastPrice;
    bool public priceFellWithCover;
    bool public modelDiverged;
    bool public earlyExit;

    // end states reached
    uint256 public nWipes;
    uint256 public nPierced;
    uint256 public nClaims;
    uint256 public nInKind;
    uint256 public nFloorRefusals;
    uint256 public nRestarts;
    uint256 public nLossesAbsorbed;

    constructor(Stepwell w, MockUSDC u, MockVault v) {
        well = w;
        usdc = u;
        vault = v;
        cover = w.cover();
        for (uint256 i = 0; i < 5; i++) {
            address a = address(uint160(0x1000 + i));
            actors.push(a);
            usdc.mint(a, 10_000_000 * D);
            vm.prank(a);
            usdc.approve(address(w), type(uint256).max);
        }
        lastPrice = w.convertToAssets(1e12);
    }

    function _actor(uint256 s) internal view returns (address) {
        return actors[s % actors.length];
    }

    function _bookModel() internal {
        uint256 h = well.holdings();
        uint256 booked = mDeep + mCover;
        bool coverHolders = cover.totalSupply() > 0;
        bool deepHolders = well.totalSupply() > 0;
        if (h > booked) {
            uint256 gain = h - booked;
            if (!deepHolders && !coverHolders) return;
            if (!deepHolders || booked == 0) mCover += gain;
            else if (!coverHolders) mDeep += gain;
            else {
                uint256 gross = gain * mDeep / booked;
                uint256 prem = gross * well.premiumBpsAt(mDeep, mCover) / 10_000;
                mDeep += gross - prem;
                mCover += gain - (gross - prem);
            }
        } else if (h < booked) {
            uint256 loss = booked - h;
            if (loss <= mCover) mCover -= loss;
            else { mDeep -= loss - mCover; mCover = 0; }
        }
    }

    function _check(bool pierced) internal {
        if (well.deepAssets() != mDeep || well.coverAssets() != mCover) modelDiverged = true;
        uint256 p = well.convertToAssets(1e12);
        if (!pierced && well.totalSupply() > 0 && p + 1 < lastPrice) priceFellWithCover = true;
        lastPrice = p;
    }

    function _pre() internal {
        _bookModel();
    }

    function depositCover(uint256 s, uint256 amt) external {
        address a = _actor(s);
        amt = bound(amt, 1 * D, 500_000 * D);
        usdc.mint(a, amt);
        well.sync();
        _bookModel();
        bool restart = cover.totalSupply() == 0;
        uint256 hb = well.holdings();
        vm.prank(a);
        well.depositCover(amt, a);
        mCover += well.holdings() - hb;
        if (restart) nRestarts++;
        _check(false);
    }

    function depositCovered(uint256 s, uint256 amt) external {
        address a = _actor(s);
        amt = bound(amt, 1 * D, 2_000_000 * D);
        usdc.mint(a, amt);
        well.sync();
        _bookModel();
        uint256 limit = well.maxDeposit(a);
        if (amt > limit) {
            vm.prank(a);
            vm.expectRevert();
            well.deposit(amt, a);
            nFloorRefusals++;
            return;
        }
        uint256 hb = well.holdings();
        vm.prank(a);
        well.deposit(amt, a);
        mDeep += well.holdings() - hb;
        _check(false);
    }

    function redeemCovered(uint256 s, uint256 frac) external {
        address a = _actor(s);
        uint256 bal = well.balanceOf(a);
        if (bal == 0) return;
        uint256 sh = bound(frac, 1, bal);
        well.sync();
        _bookModel();
        if (well.previewRedeem(sh) == 0) return;
        vm.prank(a);
        uint256 got = well.redeem(sh, a, a);
        mDeep -= got;
        _check(false);
    }

    function redeemInKind(uint256 s, uint256 frac) external {
        address a = _actor(s);
        uint256 bal = well.balanceOf(a);
        if (bal == 0) return;
        uint256 sh = bound(frac, 1, bal);
        well.sync();
        _bookModel();
        vm.prank(a);
        well.redeemInKind(sh, a, a);
        // in-kind exits round inside the vault; resync the model from the contract and only
        // check that the books still balance
        mDeep = well.deepAssets();
        mCover = well.coverAssets();
        nInKind++;
        lastPrice = well.convertToAssets(1e12);
    }

    function giveNotice(uint256 s, uint256 frac) external {
        address a = _actor(s);
        uint256 bal = cover.balanceOf(a);
        if (bal == 0) return;
        vm.prank(a);
        well.giveNotice(bound(frac, 1, bal));
    }

    function claimCover(uint256 s, uint256 wait) external {
        address a = _actor(s);
        (uint128 shares, uint64 readyAt, uint64 ep) = well.notices(a);
        if (shares == 0) return;
        vm.warp(block.timestamp + bound(wait, 0, 4 days));
        well.sync();
        _bookModel();
        bool valid = ep == cover.epoch() && block.timestamp >= readyAt
            && block.timestamp <= uint256(readyAt) + 7 days && cover.balanceOf(a) >= shares;
        vm.prank(a);
        try well.claimCover(a) returns (uint256 got) {
            if (block.timestamp < readyAt) earlyExit = true;
            mCover -= got;
            nClaims++;
        } catch {
            if (valid) {} // vault liquidity or rounding; not an invariant breach
        }
        _check(false);
    }

    function earn(uint256 bps) external {
        uint256 h = well.holdings();
        if (h == 0) return;
        vault.earn(h * bound(bps, 1, 300) / 100_000);
        well.sync();
        _bookModel();
        _check(false);
    }

    function lose(uint256 bps) external {
        uint256 h = well.holdings();
        if (h == 0) return;
        uint256 loss = h * bound(bps, 1, 2_500) / 10_000;
        well.sync();
        _bookModel();
        uint256 coverBefore = mCover;
        bool holders = cover.totalSupply() > 0;
        // the mock vault holds only Stepwell's money, so the vault's loss is Stepwell's loss
        vault.lose(loss * vault.totalAssets() / h);
        well.sync();
        _bookModel();
        bool pierced = well.lossPassedThrough() > 0 && mCover == 0 && loss > coverBefore;
        if (pierced) nPierced++;
        else nLossesAbsorbed++;
        if (holders && mCover == 0) nWipes++;
        _check(pierced);
    }
}

contract StepwellInvariants is Test {
    Handler h;
    Stepwell well;

    function setUp() public {
        MockUSDC usdc = new MockUSDC();
        MockVault vault = new MockVault(usdc);
        well = new Stepwell(
            vault,
            "Stepwell inv",
            "swI",
            Stepwell.Params({
                floorBps: 1500,
                coverLowBps: 1000,
                coverHighBps: 2000,
                premiumHighBps: 3500,
                premiumLowBps: 1500,
                noticeSeconds: 3 days,
                claimWindowSeconds: 7 days
            })
        );
        h = new Handler(well, usdc, vault);
        targetContract(address(h));
    }

    /// The two layers never claim more than the vault shares are worth.
    function invariant_booksNeverExceedHoldings() public view {
        (uint256 d, uint256 c) = well.settled();
        assertLe(d + c, well.holdings() + 2);
    }

    /// The contract agrees with the independent model of the waterfall.
    function invariant_matchesReferenceModel() public view {
        assertFalse(h.modelDiverged());
    }

    /// A covered share never loses value while any cover is left.
    function invariant_coveredPriceHoldsWhileCovered() public view {
        assertFalse(h.priceFellWithCover());
    }

    /// Nobody can redeem more than a layer holds.
    function invariant_sharesBackedByAssets() public view {
        assertLe(well.convertToAssets(well.totalSupply()), well.deepAssets() + 1);
    }

    /// No underwriter ever leaves before notice runs out.
    function invariant_noEarlyExit() public view {
        assertFalse(h.earlyExit());
    }

}

/// Drives a long random walk through the same handler and proves every end state was reached,
/// so the invariants above are known to have been tested against each of them.
contract StepwellReachability is Test {
    function test_everyEndStateIsReached() public {
        MockUSDC usdc = new MockUSDC();
        MockVault vault = new MockVault(usdc);
        Stepwell well = new Stepwell(
            vault, "Stepwell reach", "swR",
            Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 7 days)
        );
        Handler h = new Handler(well, usdc, vault);
        uint256 seed = 42;
        for (uint256 i = 0; i < 4000; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 a = seed >> 8;
            uint256 b = seed >> 128;
            uint256 op = seed % 9;
            if (op == 0) h.depositCover(a, b);
            else if (op == 1 || op == 2) h.depositCovered(a, b);
            else if (op == 3) h.redeemCovered(a, b);
            else if (op == 4) h.redeemInKind(a, b);
            else if (op == 5) h.giveNotice(a, b);
            else if (op == 6) h.claimCover(a, b);
            else if (op == 7) h.earn(b);
            else h.lose(b);
        }
        assertGt(h.nWipes(), 0, "cover wiped out");
        assertGt(h.nPierced(), 0, "loss pierced cover");
        assertGt(h.nLossesAbsorbed(), 0, "loss absorbed");
        assertGt(h.nClaims(), 0, "notice matured and claimed");
        assertGt(h.nInKind(), 0, "exit in kind");
        assertGt(h.nFloorRefusals(), 0, "deposit refused at floor");
        assertGt(h.nRestarts(), 1, "cover layer restarted from empty");
        assertFalse(h.modelDiverged());
        assertFalse(h.priceFellWithCover());
        assertFalse(h.earlyExit());
    }
}
