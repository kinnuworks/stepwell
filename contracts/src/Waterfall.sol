// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Waterfall
/// @notice The whole interest-and-loss rule as one pure function, so it can be proved on its own.
/// @dev Three buckets share one vault position:
///      - settling: deposits still in their warm-up. They earn and lose pro rata, like a plain
///        vault deposit, and are not covered yet. This stops anyone buying cover just before a
///        loss they can already see.
///      - deep: covered deposits.
///      - cover: the first-loss layer.
///      Losses: settling takes its pro-rata share; the rest comes out of cover until it is gone,
///      then out of deep. Gains: settling takes its pro-rata share; the rest first repays any
///      loss deep has taken, then repays cover's past losses (a high-water mark), and only then
///      is split, with depositors passing `premiumBps` of their interest to cover.
library Waterfall {
    using Math for uint256;

    uint256 internal constant BPS = 10_000;

    struct State {
        uint256 settling;
        uint256 deep;
        uint256 cover;
        uint256 deepDeficit; // losses deep has taken and not yet been repaid
        uint256 coverDeficit; // losses the current cover layer has taken and not yet been repaid
    }

    struct Holders {
        bool settling;
        bool deep;
        bool cover;
    }

    struct Result {
        uint256 gain;
        uint256 loss;
        uint256 premium; // interest passed from depositors to cover
        uint256 absorbed; // part of the loss taken by cover
        uint256 passedThrough; // part of the loss that reached covered deposits
    }

    function split(State memory s, uint256 h, Holders memory who, uint256 premiumBps)
        internal
        pure
        returns (State memory n, Result memory r)
    {
        // a fresh copy: `n = s` would alias the same memory and change `s` as `n` changes
        n = State(s.settling, s.deep, s.cover, s.deepDeficit, s.coverDeficit);
        uint256 booked = s.settling + s.deep + s.cover;
        if (h == booked) return (n, r);
        if (!who.settling && !who.deep && !who.cover) return (n, r); // nobody to credit or debit

        if (h > booked) {
            r.gain = h - booked;
            uint256 g = r.gain;
            if (booked == 0) {
                // nothing booked yet: the first holder class present takes it
                if (who.cover) n.cover += g;
                else if (who.deep) n.deep += g;
                else n.settling += g;
                return (n, r);
            }
            uint256 toSettling = g.mulDiv(s.settling, booked);
            n.settling += toSettling;
            g -= toSettling;
            // repay deep's past losses first, then cover's
            uint256 repay = g < n.deepDeficit ? g : n.deepDeficit;
            n.deep += repay;
            n.deepDeficit -= repay;
            g -= repay;
            repay = g < n.coverDeficit ? g : n.coverDeficit;
            n.cover += repay;
            n.coverDeficit -= repay;
            g -= repay;
            if (g == 0) return (n, r);
            uint256 layered = s.deep + s.cover;
            if (layered == 0 || !who.deep) {
                n.cover += g;
            } else if (!who.cover) {
                n.deep += g;
            } else {
                uint256 deepGross = g.mulDiv(s.deep, layered);
                r.premium = deepGross.mulDiv(premiumBps, BPS);
                n.deep += deepGross - r.premium;
                n.cover += g - (deepGross - r.premium);
            }
        } else {
            r.loss = booked - h;
            uint256 l = r.loss;
            uint256 fromSettling = l.mulDiv(s.settling, booked);
            n.settling -= fromSettling;
            l -= fromSettling;
            if (l <= n.cover) {
                n.cover -= l;
                n.coverDeficit += l;
                r.absorbed = l;
            } else {
                r.absorbed = n.cover;
                r.passedThrough = l - n.cover;
                if (r.passedThrough > n.deep) {
                    // rounding left a unit or two more than the layers hold: settling takes it
                    uint256 extra = r.passedThrough - n.deep;
                    r.passedThrough = n.deep;
                    n.settling -= extra < n.settling ? extra : n.settling;
                }
                n.coverDeficit += n.cover;
                n.deep -= r.passedThrough;
                n.deepDeficit += r.passedThrough;
                n.cover = 0;
            }
        }
    }
}
