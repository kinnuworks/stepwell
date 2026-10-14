// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Waterfall} from "../../src/Waterfall.sol";

/// Proved for every input with Halmos (symbolic execution), not sampled:
///   halmos --contract WaterfallProofs
/// Amounts are bounded to 2^64 units (about 18 trillion USDC), far above any real balance.
contract WaterfallProofs is Test {
    function _st(uint256 s, uint256 d, uint256 c, uint256 dd, uint256 cd) internal pure returns (Waterfall.State memory) {
        vm.assume(s < 2 ** 64 && d < 2 ** 64 && c < 2 ** 64 && dd < 2 ** 64 && cd < 2 ** 64);
        return Waterfall.State(s, d, c, dd, cd);
    }

    /// A loss no bigger than the cover (after settling deposits take their own share) never
    /// touches covered deposits.
    function check_lossWithinCoverSparesDepositors(uint256 d, uint256 c, uint256 dd, uint256 cd, uint256 h, uint256 p, bool hs, bool hd, bool hc) public pure {
        Waterfall.State memory s = _st(0, d, c, dd, cd);
        vm.assume(p <= 10_000 && h < d + c && d + c - h <= c && (hs || hd || hc));
        (Waterfall.State memory n,) = Waterfall.split(s, h, Waterfall.Holders(hs, hd, hc), p);
        assert(n.deep == d);
        assert(n.cover == c - (d + c - h));
    }

    /// Whenever anyone holds shares, the buckets add up to exactly what the vault holds.
    function check_booksBalance(uint256 st, uint256 d, uint256 c, uint256 dd, uint256 cd, uint256 h, uint256 p, bool hs, bool hd, bool hc) public pure {
        Waterfall.State memory s = _st(st, d, c, dd, cd);
        vm.assume(p <= 10_000 && h < 2 ** 65 && (hs || hd || hc));
        (Waterfall.State memory n,) = Waterfall.split(s, h, Waterfall.Holders(hs, hd, hc), p);
        assert(n.settling + n.deep + n.cover == h);
    }

    /// Interest never makes any bucket poorer.
    function check_gainNeverHurts(uint256 st, uint256 d, uint256 c, uint256 dd, uint256 cd, uint256 h, uint256 p, bool hs, bool hd, bool hc) public pure {
        Waterfall.State memory s = _st(st, d, c, dd, cd);
        vm.assume(p <= 10_000 && h < 2 ** 65 && h >= st + d + c);
        (Waterfall.State memory n,) = Waterfall.split(s, h, Waterfall.Holders(hs, hd, hc), p);
        assert(n.settling >= st && n.deep >= d && n.cover >= c);
    }

    /// High-water mark: a loss inside the cover, followed by the same amount coming back,
    /// restores both layers exactly.
    function check_recoveryRestoresExactly(uint256 d, uint256 c, uint256 l, uint256 p) public pure {
        Waterfall.State memory s = _st(0, d, c, 0, 0);
        vm.assume(p <= 10_000 && l > 0 && l <= c);
        Waterfall.Holders memory who = Waterfall.Holders(false, true, true);
        (Waterfall.State memory a,) = Waterfall.split(s, d + c - l, who, p);
        (Waterfall.State memory b,) = Waterfall.split(a, d + c, who, p);
        assert(b.deep == d && b.cover == c && b.coverDeficit == 0);
    }
}
