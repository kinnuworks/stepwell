// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "./Stepwell.sol";

/// @title StepwellFactory
/// @notice Anyone can open a Stepwell on any ERC-4626 vault. The factory is also the registry
///         that answers, for any vault address, which Stepwells cover it and how well.
/// @dev Anyone can create a Stepwell with any parameters, including useless ones. So the
///      registry marks which ones use the standard terms, and `standardCoverageFor` returns only
///      those. Apps showing cover to users should read that one.
///      The Stepwell's own creation code is too large to embed here under the 24 KB contract
///      limit, so callers pass it in, and the factory refuses anything whose hash differs from
///      the code fixed at deployment. Nobody can register an impostor.
contract StepwellFactory {
    bytes32 public immutable stepwellCodeHash;

    error WrongCode();

    constructor(bytes32 stepwellCodeHash_) {
        stepwellCodeHash = stepwellCodeHash_;
    }

    address[] public all;
    mapping(address vault => address[]) private _byVault;
    mapping(address stepwell => bool) public isStandard;

    event Created(address indexed vault, address indexed stepwell, string name, bool standard);

    /// @notice The standard terms: 15% cover floor, premium sliding from 35% to 15% of interest
    ///         between 10% and 20% cover, three days' notice, one day to claim, one day warm-up.
    function standardParams() public pure returns (Stepwell.Params memory) {
        return Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 1 days, 1 days);
    }

    function create(
        IERC4626 vault,
        string calldata name,
        string calldata symbol,
        Stepwell.Params calldata p,
        bytes calldata creationCode
    ) external returns (Stepwell s) {
        if (keccak256(creationCode) != stepwellCodeHash) revert WrongCode();
        bytes memory init = abi.encodePacked(creationCode, abi.encode(vault, name, symbol, p));
        address a;
        assembly ("memory-safe") {
            a := create(0, add(init, 0x20), mload(init))
        }
        require(a != address(0), "deploy failed");
        s = Stepwell(a);
        bool standard = keccak256(abi.encode(p)) == keccak256(abi.encode(standardParams()));
        all.push(address(s));
        _byVault[address(vault)].push(address(s));
        isStandard[address(s)] = standard;
        emit Created(address(vault), address(s), name, standard);
    }

    function count() external view returns (uint256) {
        return all.length;
    }

    function stepwellsFor(address vault) external view returns (address[] memory) {
        return _byVault[vault];
    }

    /// @notice Coverage figures for every Stepwell on a vault, in one call.
    function coverageFor(address vault) public view returns (Stepwell.Coverage[] memory out) {
        address[] storage list = _byVault[vault];
        out = new Stepwell.Coverage[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            out[i] = Stepwell(list[i]).coverage();
        }
    }

    /// @notice Coverage figures for the standard-terms Stepwells on a vault only.
    function standardCoverageFor(address vault)
        external
        view
        returns (address[] memory stepwells, Stepwell.Coverage[] memory out)
    {
        address[] storage list = _byVault[vault];
        uint256 n;
        for (uint256 i = 0; i < list.length; i++) if (isStandard[list[i]]) n++;
        stepwells = new address[](n);
        out = new Stepwell.Coverage[](n);
        uint256 j;
        for (uint256 i = 0; i < list.length; i++) {
            if (!isStandard[list[i]]) continue;
            stepwells[j] = list[i];
            out[j] = Stepwell(list[i]).coverage();
            j++;
        }
    }
}
