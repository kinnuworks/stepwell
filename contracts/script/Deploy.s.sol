// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {StepwellFactory} from "../src/StepwellFactory.sol";
import {RehearsalVault} from "../src/RehearsalVault.sol";

/// Deploys everything and seeds it with about 13 USDC from the deployer.
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

        StepwellFactory factory = new StepwellFactory();
        // the operator is also the sink: money a rehearsal "loses" goes to it, and it puts money back with refill
        RehearsalVault rehearsal = new RehearsalVault(USDC, operator, operator);

        // the rehearsal Stepwell uses a short notice so the whole cycle can be shown in minutes
        Stepwell drill = factory.create(
            rehearsal, "Stepwell rehearsal", "swDRILL",
            Stepwell.Params(1500, 1000, 2000, 3500, 1500, 10 minutes, 7 days)
        );
        Stepwell steak = factory.create(
            STEAKHOUSE, "Stepwell on Steakhouse Prime USDC", "swSTEAK",
            Stepwell.Params(1500, 1000, 2000, 3500, 1500, 3 days, 7 days)
        );

        USDC.approve(address(drill), type(uint256).max);
        USDC.approve(address(steak), type(uint256).max);
        drill.depositCover(1.5e6, me);
        drill.deposit(drill.maxDeposit(me) < 6e6 ? drill.maxDeposit(me) : 6e6, me);
        steak.depositCover(0.75e6, me);
        steak.deposit(steak.maxDeposit(me) < 4e6 ? steak.maxDeposit(me) : 4e6, me);

        // gas money for the rehearsal relayer
        USDC.transfer(operator, 1e6);

        vm.stopBroadcast();
        console2.log("factory   ", address(factory));
        console2.log("rehearsal ", address(rehearsal));
        console2.log("drill     ", address(drill));
        console2.log("steakhouse", address(steak));
    }
}
