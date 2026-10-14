// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Waterfall} from "../../src/Waterfall.sol";

/// Proved for every input with Halmos (symbolic execution), not sampled:
///   halmos --contract WaterfallProofs
/// Amounts are bounded to 2^96 (79 billion billion USDC units), far above any real balance.
contract WaterfallProofs is Test {
    function _bound(uint256 deep, uint256 cover, uint256 h, uint256 premiumBps) internal pure {
        vm.assume(deep < 2 ** 96 && cover < 2 ** 96 && h < 2 ** 97 && premiumBps <= 10_000);
    }

    /// A loss no bigger than the cover never touches depositors, and cover pays exactly the loss.
    function check_lossWithinCoverSparesDepositors(uint256 deep, uint256 cover, uint256 h, uint256 premiumBps, bool ch, bool dh) public pure {
        _bound(deep, cover, h, premiumBps);
        vm.assume(h < deep + cover && deep + cover - h <= cover);
        (uint256 d, uint256 c,,,) = Waterfall.split(deep, cover, h, ch, dh, premiumBps);
        assert(d == deep);
        assert(c == cover - (deep + cover - h));
    }

    /// A loss bigger than the cover takes all of the cover first.
    function check_bigLossEmptiesCoverFirst(uint256 deep, uint256 cover, uint256 h, uint256 premiumBps, bool ch, bool dh) public pure {
        _bound(deep, cover, h, premiumBps);
        vm.assume(h < deep + cover && deep + cover - h > cover);
        (uint256 d, uint256 c,,,) = Waterfall.split(deep, cover, h, ch, dh, premiumBps);
        assert(c == 0);
        assert(d == h);
    }

    /// Whenever anyone holds shares, the two layers add up to exactly what the vault holds.
    function check_booksBalance(uint256 deep, uint256 cover, uint256 h, uint256 premiumBps, bool ch, bool dh) public pure {
        _bound(deep, cover, h, premiumBps);
        vm.assume(ch || dh);
        (uint256 d, uint256 c,,,) = Waterfall.split(deep, cover, h, ch, dh, premiumBps);
        assert(d + c == h);
    }

    /// Interest never makes either layer poorer.
    function check_gainNeverHurts(uint256 deep, uint256 cover, uint256 h, uint256 premiumBps, bool ch, bool dh) public pure {
        _bound(deep, cover, h, premiumBps);
        vm.assume(h >= deep + cover);
        (uint256 d, uint256 c,,,) = Waterfall.split(deep, cover, h, ch, dh, premiumBps);
        assert(d >= deep);
        assert(c >= cover);
    }
}
