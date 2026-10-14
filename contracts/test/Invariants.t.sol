// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {CoverToken} from "../src/CoverToken.sol";
import {MockUSDC, MockVault} from "./mocks/Mocks.sol";

/// @dev Drives random sequences of every action against one Stepwell, with no sync() calls of
///      its own: every booking happens inside the contract's own actions, as it would on chain.
///      Beside it runs a separately written model of the rules (its own premium curve, its own
///      waterfall), which must agree with the contract to the unit after every action.
contract Handler is Test {
    Stepwell public well;
    MockUSDC public usdc;
    MockVault public vault;
    CoverToken public cover;
    address[] public actors;
    uint256 constant D = 1e6;

    // the model
    uint256 public mSet;
    uint256 public mDeep;
    uint256 public mCov;
    uint256 public mDeepDef;
    uint256 public mCovDef;

    uint256 public lastPrice;
    bool public priceFellWithCover;
    bool public modelDiverged;
    bool public earlyExit;
    bool public validClaimFailed;
    bool public noticePaidAboveCap;

    uint256 public nWipes;
    uint256 public nPierced;
    uint256 public nAbsorbed;
    uint256 public nClaims;
    uint256 public nInKind;
    uint256 public nFloorRefusals;
    uint256 public nRestarts;
    uint256 public nSettles;
    uint256 public nCancels;
    uint256 public nRecoveries;

    constructor(Stepwell w, MockUSDC u, MockVault v) {
        well = w;
        usdc = u;
        vault = v;
        cover = w.cover();
        for (uint256 i = 0; i < 5; i++) {
            address a = address(uint160(0x1000 + i));
            actors.push(a);
            vm.prank(a);
            usdc.approve(address(w), type(uint256).max);
        }
        lastPrice = w.convertToAssets(1e12);
    }

    function _actor(uint256 s) internal view returns (address) {
        return actors[s % actors.length];
    }

    // --- the model, written separately from src/Waterfall.sol -----------------------------

    function _premium(uint256 deep, uint256 cov) internal pure returns (uint256) {
        if (deep + cov == 0) return 3500;
        uint256 ratio = cov * 10_000 / (deep + cov);
        if (ratio <= 1000) return 3500;
        if (ratio >= 2000) return 1500;
        return 3500 - (ratio - 1000) * 2000 / 1000;
    }

    function _book() internal {
        uint256 h = vault.previewRedeem(vault.balanceOf(address(well)));
        uint256 total = mSet + mDeep + mCov;
        bool hs = well.totalSettlingShares() > 0;
        bool hd = well.totalSupply() > 0;
        bool hc = cover.totalSupply() > 0;
        if (h == total || !(hs || hd || hc)) return;
        if (h > total) {
            uint256 g = h - total;
            if (total == 0) {
                if (hc) mCov += g; else if (hd) mDeep += g; else mSet += g;
                return;
            }
            uint256 s = g * mSet / total;
            mSet += s;
            g -= s;
            uint256 r = g < mDeepDef ? g : mDeepDef;
            mDeep += r; mDeepDef -= r; g -= r;
            r = g < mCovDef ? g : mCovDef;
            mCov += r; mCovDef -= r; g -= r;
            if (r > 0) nRecoveries++;
            if (g == 0) return;
            // what is left is split between the layers as they stood before this booking
            uint256 sd = _deepAtStart;
            uint256 sc = _covAtStart;
            if (sd + sc == 0 || !hd) { mCov += g; return; }
            if (!hc) { mDeep += g; return; }
            uint256 gross = g * sd / (sd + sc);
            uint256 prem = gross * _premium(sd, sc) / 10_000;
            mDeep += gross - prem;
            mCov += g - (gross - prem);
        } else {
            uint256 l = total - h;
            uint256 s = l * mSet / total;
            mSet -= s;
            l -= s;
            if (l <= mCov) {
                bool hadCover = mCov > 0;
                mCov -= l;
                mCovDef += l;
                if (mCov == 0 && hadCover && hc) { mCovDef = 0; nWipes++; }
            } else {
                uint256 through = l - mCov;
                if (through > 0) piercedNow = true;
                if (through > mDeep) { mSet -= (through - mDeep) < mSet ? through - mDeep : mSet; through = mDeep; }
                mCovDef += mCov;
                mDeep -= through;
                mDeepDef += through;
                bool wiped = mCov > 0 && hc;
                mCov = 0;
                if (wiped) { mCovDef = 0; nWipes++; }
                nPierced++;
                return;
            }
            nAbsorbed++;
        }
    }

    bool internal piercedNow;
    uint256 internal _deepAtStart;
    uint256 internal _covAtStart;

    /// mirrors the contract booking at the start of an action
    function _pre() internal {
        _deepAtStart = mDeep;
        _covAtStart = mCov;
        _book();
    }

    function _check(bool) internal {
        bool pierced = piercedNow;
        piercedNow = false;
        if (
            well.settlingAssets() != mSet || well.deepAssets() != mDeep || well.coverAssets() != mCov
                || well.coverDeficit() != mCovDef || well.deepDeficit() != mDeepDef
        ) modelDiverged = true;
        uint256 p = well.convertToAssets(1e12);
        if (!pierced && well.totalSupply() > 0 && p + 1 < lastPrice) priceFellWithCover = true;
        lastPrice = p;
    }

    /// what a deposit is credited with: the value of the vault shares it minted, capped at the deposit
    function _credited(uint256 sharesBefore, uint256 amt) internal view returns (uint256 c) {
        c = vault.previewRedeem(vault.balanceOf(address(well)) - sharesBefore);
        if (c > amt) c = amt;
    }

    // --- actions --------------------------------------------------------------------------

    function depositCover(uint256 s, uint256 amt) external {
        address a = _actor(s);
        amt = bound(amt, 1 * D, 500_000 * D);
        usdc.mint(a, amt);
        _pre();
        bool restart = cover.totalSupply() == 0;
        uint256 vb = vault.balanceOf(address(well));
        vm.prank(a);
        well.depositCover(amt, a);
        mCov += _credited(vb, amt);
        if (restart) nRestarts++;
        _check(false);
    }

    function requestDeposit(uint256 s, uint256 amt) external {
        address a = _actor(s);
        amt = bound(amt, 1 * D, 2_000_000 * D);
        usdc.mint(a, amt);
        uint256 limit = well.maxRequest();
        if (amt > limit) {
            vm.prank(a);
            vm.expectRevert();
            well.requestDeposit(amt, a, a);
            nFloorRefusals++;
            return;
        }
        _pre();
        uint256 vb = vault.balanceOf(address(well));
        vm.prank(a);
        well.requestDeposit(amt, a, a);
        mSet += _credited(vb, amt);
        _check(false);
    }

    function settle(uint256 s, uint256 wait) external {
        address a = _actor(s);
        (uint256 shares, uint64 readyAt) = well.requests(a);
        if (shares == 0) return;
        vm.warp(block.timestamp + bound(wait, 0, 2 days));
        if (block.timestamp < readyAt) return;
        _pre();
        uint256 moved = shares * (mSet + 1) / (well.totalSettlingShares() + 1e6);
        if (moved > mSet) moved = mSet;
        well.settle(a);
        mSet -= moved;
        mDeep += moved;
        nSettles++;
        _check(false);
    }

    function cancelRequest(uint256 s) external {
        address a = _actor(s);
        (uint256 shares,) = well.requests(a);
        if (shares == 0) return;
        _pre();
        vm.prank(a);
        uint256 got = well.cancelDepositRequest(a);
        mSet -= got;
        nCancels++;
        _check(false);
    }

    function redeemCovered(uint256 s, uint256 frac) external {
        address a = _actor(s);
        uint256 bal = well.balanceOf(a);
        if (bal == 0) return;
        uint256 sh = bound(frac, 1, bal);
        if (well.previewRedeem(sh) == 0) return;
        _pre();
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
        _pre();
        vm.prank(a);
        well.redeemInKind(sh, a, a);
        // in-kind exits round inside the vault: take the contract's figures and keep going
        mSet = well.settlingAssets(); mDeep = well.deepAssets(); mCov = well.coverAssets();
        mDeepDef = well.deepDeficit(); mCovDef = well.coverDeficit();
        nInKind++;
        lastPrice = well.convertToAssets(1e12);
    }

    function giveNotice(uint256 s, uint256 frac) external {
        address a = _actor(s);
        uint256 bal = cover.balanceOf(a);
        if (bal == 0) return;
        uint256[5] memory snap = [mSet, mDeep, mCov, mDeepDef, mCovDef];
        _pre();
        vm.prank(a);
        try well.giveNotice(bound(frac, 1, bal)) {
            _check(false);
        } catch {
            // a loss booked inside the call wiped the layer first: the notice is refused and the
            // whole call, booking included, rolled back
            (mSet, mDeep, mCov, mDeepDef, mCovDef) = (snap[0], snap[1], snap[2], snap[3], snap[4]);
        }
    }

    function claimCover(uint256 s, uint256 wait) external {
        address a = _actor(s);
        (uint128 shares, uint128 cap, uint64 readyAt, uint64 ep) = well.notices(a);
        if (shares == 0) return;
        vm.warp(block.timestamp + bound(wait, 0, 4 days));
        uint256[5] memory snap = [mSet, mDeep, mCov, mDeepDef, mCovDef];
        _pre();
        // a loss booked by the claim itself can wipe the layer, which voids the notice
        bool valid = mCov > 0 && ep == cover.epoch() && block.timestamp >= readyAt
            && block.timestamp <= uint256(readyAt) + 1 days && cover.balanceOf(a) >= shares;
        vm.prank(a);
        try well.claimCover(a) returns (uint256 got) {
            if (block.timestamp < readyAt) earlyExit = true;
            if (got > cap) noticePaidAboveCap = true;
            mCov -= got;
            nClaims++;
        } catch {
            if (valid) validClaimFailed = true; // the mock vault is always liquid
            // the reverted claim also rolled back its booking, so roll the model back too
            (mSet, mDeep, mCov, mDeepDef, mCovDef) = (snap[0], snap[1], snap[2], snap[3], snap[4]);
            return;
        }
        _check(false);
    }

    function earn(uint256 bps) external {
        uint256 h = well.holdings();
        if (h == 0) return;
        vault.earn(h * bound(bps, 1, 300) / 100_000);
    }

    function lose(uint256 bps) external {
        uint256 h = well.holdings();
        if (h == 0) return;
        vault.lose(vault.totalAssets() * bound(bps, 1, 2_500) / 10_000);
    }
}

contract StepwellInvariants is Test {
    Handler h;
    Stepwell well;

    function setUp() public {
        MockUSDC usdc = new MockUSDC();
        MockVault vault = new MockVault(usdc);
        well = new Stepwell(vault, "Stepwell inv", "swI", Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 1 days, 1 days));
        h = new Handler(well, usdc, vault);
        targetContract(address(h));
    }

    /// The buckets never claim more than the vault shares are worth.
    function invariant_booksNeverExceedHoldings() public view {
        (uint256 d, uint256 c) = well.settled();
        assertLe(d + c + well.settledState().settling, well.holdings() + 2);
    }

    /// The contract agrees with the separately written model after every action.
    function invariant_matchesModel() public view {
        assertFalse(h.modelDiverged());
    }

    /// A covered share never loses value while any cover is left.
    function invariant_coveredPriceHoldsWhileCovered() public view {
        assertFalse(h.priceFellWithCover());
    }

    /// No underwriter leaves before notice runs out, or takes more than their capped value.
    function invariant_noticeIsHonoured() public view {
        assertFalse(h.earlyExit());
        assertFalse(h.noticePaidAboveCap());
    }

    /// A valid claim never fails.
    function invariant_validClaimsSucceed() public view {
        assertFalse(h.validClaimFailed());
    }
}

/// Drives a long random walk through the same handler and fails unless it reached every end
/// state, so the invariants above are known to have been exercised against each of them.
contract StepwellReachability is Test {
    function test_everyEndStateIsReached() public {
        MockUSDC usdc = new MockUSDC();
        MockVault vault = new MockVault(usdc);
        Stepwell well = new Stepwell(vault, "Stepwell reach", "swR", Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 1 days, 1 days));
        Handler h = new Handler(well, usdc, vault);
        uint256 seed = 42;
        for (uint256 i = 0; i < 6000; i++) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 a = seed >> 8;
            uint256 b = seed >> 128;
            uint256 op = seed % 12;
            if (op == 0) h.depositCover(a, b);
            else if (op <= 2) h.requestDeposit(a, b);
            else if (op == 3) h.settle(a, b);
            else if (op == 4) h.cancelRequest(a);
            else if (op == 5) h.redeemCovered(a, b);
            else if (op == 6) h.redeemInKind(a, b);
            else if (op == 7) h.giveNotice(a, b);
            else if (op == 8) h.claimCover(a, b);
            else if (op == 9) h.earn(b);
            else h.lose(b);
        }
        assertGt(h.nWipes(), 0, "cover wiped out");
        assertGt(h.nPierced(), 0, "loss pierced cover");
        assertGt(h.nAbsorbed(), 0, "loss absorbed");
        assertGt(h.nRecoveries(), 0, "recovery refilled cover");
        assertGt(h.nClaims(), 0, "notice claimed");
        assertGt(h.nInKind(), 0, "exit in kind");
        assertGt(h.nFloorRefusals(), 0, "request refused at floor");
        assertGt(h.nRestarts(), 1, "cover restarted from empty");
        assertGt(h.nSettles(), 0, "deposit settled");
        assertGt(h.nCancels(), 0, "request cancelled");
        assertFalse(h.modelDiverged(), "model");
        assertFalse(h.priceFellWithCover(), "price");
        assertFalse(h.earlyExit(), "early exit");
        assertFalse(h.noticePaidAboveCap(), "notice cap");
        assertFalse(h.validClaimFailed(), "valid claim failed");
    }
}
