// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "./Stepwell.sol";

/// @title StepwellFactory
/// @notice Anyone can open a Stepwell on any ERC-4626 vault. The factory is also the registry
///         that answers, for any vault address, which Stepwells cover it and how well.
contract StepwellFactory {
    address[] public all;
    mapping(address vault => address[]) private _byVault;

    event Created(address indexed vault, address indexed stepwell, string name);

    function create(IERC4626 vault, string calldata name, string calldata symbol, Stepwell.Params calldata p)
        external
        returns (Stepwell s)
    {
        s = new Stepwell(vault, name, symbol, p);
        all.push(address(s));
        _byVault[address(vault)].push(address(s));
        emit Created(address(vault), address(s), name);
    }

    function count() external view returns (uint256) {
        return all.length;
    }

    function stepwellsFor(address vault) external view returns (address[] memory) {
        return _byVault[vault];
    }

    /// @notice Coverage figures for every Stepwell on a vault, in one call.
    function coverageFor(address vault) external view returns (Stepwell.Coverage[] memory out) {
        address[] storage list = _byVault[vault];
        out = new Stepwell.Coverage[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            out[i] = Stepwell(list[i]).coverage();
        }
    }
}
