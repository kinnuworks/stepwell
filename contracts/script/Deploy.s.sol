// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {StepwellFactory} from "../src/StepwellFactory.sol";
import {RehearsalVault} from "../src/RehearsalVault.sol";

/// Deploys everything and seeds it from the deployer. The full plan uses about 13.6 USDC; with less
/// in the wallet, every seed shrinks in proportion, keeping 0.6 USDC back for gas.
///   PRIVATE_KEY=0x... OPERATOR=0x... arc-forge script script/Deploy.s.sol --rpc-url arc --broadcast
/// OPERATOR is the hot key the website's rehearsal button uses. It needs about 1 USDC for gas.
contract Deploy is Script {
    IERC20 constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC4626 constant STEAKHOUSE = IERC4626(0xbeef0016cb2Fd5C352ea7CA08a9f54739DFa7298);

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        address operator = vm.envAddress("OPERATOR");
        vm.startBroadcast(pk);

        bytes memory code = type(Stepwell).creationCode;
        StepwellFactory factory = new StepwellFactory(keccak256(code));
        // the operator is also the sink: money a rehearsal "loses" goes to it, and it puts money back with refill
        RehearsalVault rehearsal = new RehearsalVault(USDC, operator, operator);

        // the rehearsal Stepwell uses a short notice so the whole cycle can be shown in minutes
        Stepwell drill = factory.create(
            rehearsal, "Stepwell rehearsal", "swDRILL",
            Stepwell.Params(1500, 1000, 2000, 3500, 1500, 10 minutes, 1 days, 60), code
        );
        // On mainnet this is Steakhouse Prime USDC. Arc testnet has no Morpho vaults, so a testnet
        // run puts the standard-terms well on a second test vault instead.
        IERC4626 real = address(STEAKHOUSE).code.length > 0
            ? STEAKHOUSE
            : IERC4626(address(new RehearsalVault(USDC, operator, operator)));
        Stepwell steak = factory.create(
            real,
            address(real) == address(STEAKHOUSE) ? "Stepwell on Steakhouse Prime USDC" : "Stepwell on a test vault",
            "swSTEAK", factory.standardParams(), code
        );

        // seeds out of 13.25 USDC: drill 1.5 cover + 6 deposit, Steakhouse 0.75 + 4, operator gas 1
        uint256 spare = USDC.balanceOf(me) > 0.6e6 ? USDC.balanceOf(me) - 0.6e6 : 0;
        uint256 scale = spare >= 13.25e6 ? 1e6 : spare * 1e6 / 13.25e6;
        require(scale >= 0.1e6, "fund the deployer with at least 2 USDC");

        USDC.approve(address(drill), type(uint256).max);
        USDC.approve(address(steak), type(uint256).max);
        drill.depositCover(1.5e6 * scale / 1e6, me);
        uint256 want = 6e6 * scale / 1e6;
        drill.requestDeposit(drill.maxRequest() < want ? drill.maxRequest() : want, me, me);
        steak.depositCover(0.75e6 * scale / 1e6, me);
        want = 4e6 * scale / 1e6;
        steak.requestDeposit(steak.maxRequest() < want ? steak.maxRequest() : want, me, me);
        // Both requests warm up before they are covered (60 seconds on the rehearsal well, a day
        // on the real one). Anyone can then call settle(me); the site's relayer does it.

        // gas money for the rehearsal relayer
        USDC.transfer(operator, 1e6 * scale / 1e6);

        vm.stopBroadcast();
        console2.log("factory   ", address(factory));
        console2.log("rehearsal ", address(rehearsal));
        console2.log("drill     ", address(drill));
        console2.log("steakhouse", address(steak));
        console2.log("realvault ", address(real));
    }
}
