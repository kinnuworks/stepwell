// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Waterfall
/// @notice The whole loss-and-interest rule, as one pure function so it can be proven on its own.
library Waterfall {
    using Math for uint256;

    uint256 internal constant BPS = 10_000;

    /// @param deep what depositors were owed at the last booking
    /// @param cover what the cover layer was worth at the last booking
    /// @param h what the vault shares are worth now
    /// @param premiumBps share of depositors' interest passed to cover
    function split(uint256 deep, uint256 cover, uint256 h, bool coverHolders, bool deepHolders, uint256 premiumBps)
        internal
        pure
        returns (uint256 newDeep, uint256 newCover, uint256 gain, uint256 loss, uint256 premium)
    {
        uint256 booked = deep + cover;
        newDeep = deep;
        newCover = cover;
        if (h > booked) {
            gain = h - booked;
            if (!deepHolders && !coverHolders) return (deep, cover, 0, 0, 0);
            if (!deepHolders || booked == 0) {
                newCover += gain;
            } else if (!coverHolders) {
                newDeep += gain;
            } else {
                uint256 deepGross = gain.mulDiv(deep, booked);
                premium = deepGross.mulDiv(premiumBps, BPS);
                newDeep += deepGross - premium;
                newCover += gain - (deepGross - premium);
            }
        } else if (h < booked) {
            loss = booked - h;
            if (loss <= cover) {
                newCover -= loss;
            } else {
                newDeep -= loss - cover;
                newCover = 0;
            }
        }
    }
}
