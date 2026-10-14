// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Stepwell} from "../src/Stepwell.sol";
import {StepwellFactory} from "../src/StepwellFactory.sol";

interface IMorphoVaultV2 {
    function adapters(uint256) external view returns (address);
}

interface IAdapter {
    function realAssets() external view returns (uint256);
}

interface IMulticall3From {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (bytes[] memory);
}

interface IMemo {
    function memo(address target, bytes calldata data, bytes32 memoId, bytes calldata memoData) external;
}

/// Runs against Arc mainnet state: the real Steakhouse Prime USDC vault (Morpho Vault V2),
/// Arc's native USDC, and Arc's Multicall3From and Memo predeploys.
///   FORK=1 arc-forge test --match-contract Fork --isolate -vv
/// --isolate runs each call as its own transaction. Morpho Vault V2 books interest and losses
/// once per transaction, so without it a loss and its booking would share one transaction.
contract ForkTest is Test {
    IERC20 constant USDC = IERC20(0x3600000000000000000000000000000000000000);
    IERC4626 constant STEAKHOUSE = IERC4626(0xbeef0016cb2Fd5C352ea7CA08a9f54739DFa7298);
    address constant MULTICALL3_FROM = 0x522fAf9A91c41c443c66765030741e4AaCe147D0;
    address constant MEMO = 0x5294E9927c3306DcBaDb03fe70b92e01cCede505;

    StepwellFactory f;
    Stepwell w;
    address u = makeAddr("underwriter");
    address d = makeAddr("depositor");

    function setUp() public {
        if (vm.envOr("FORK", uint256(0)) == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("arc");
        f = new StepwellFactory(keccak256(type(Stepwell).creationCode));
        w = f.create(STEAKHOUSE, "Stepwell Steakhouse", "swSTEAK", f.standardParams(), type(Stepwell).creationCode);
        vm.deal(u, 1000 ether); // native USDC has 18 decimals: 1000e18 is 1,000 USDC
        vm.deal(d, 1000 ether);
        vm.prank(u);
        USDC.approve(address(w), type(uint256).max);
        vm.prank(d);
        USDC.approve(address(w), type(uint256).max);
    }

    function _seed(uint256 coverAmt) internal returns (uint256 shares) {
        vm.prank(u);
        w.depositCover(coverAmt, u);
        uint256 amt = w.maxRequest();
        vm.prank(d);
        w.requestDeposit(amt, d, d);
        vm.warp(block.timestamp + 1 days);
        shares = w.settle(d);
    }

    function test_fork_requestSettleRedeem() public {
        uint256 shares = _seed(1.5e6);
        vm.warp(block.timestamp + 30 days);
        vm.prank(d);
        uint256 got = w.redeem(shares, d, d);
        emit log_named_uint("covered deposit back after 30 days (6 dp)", got);
        assertGe(got + 2, 8.49e6);
    }

    /// Bad debt in a Morpho market shows up as the vault's adapter reporting fewer real assets;
    /// Vault V2 books that as a lower share price. The real adapter is made to report a 2%
    /// markdown, and Stepwell must book it as a loss taken entirely by cover.
    function test_fork_morphoBadDebtIsBookedAsLoss() public {
        _seed(30e6);
        (uint256 deepBefore, uint256 coverBefore) = w.settled();
        uint256 priceBefore = STEAKHOUSE.convertToAssets(1e18);
        address adapter = IMorphoVaultV2(address(STEAKHOUSE)).adapters(0);
        uint256 real = IAdapter(adapter).realAssets();
        vm.mockCall(adapter, abi.encodeWithSelector(IAdapter.realAssets.selector), abi.encode(real * 98 / 100));
        vm.warp(block.timestamp + 1);
        assertLt(STEAKHOUSE.convertToAssets(1e18), priceBefore, "vault share price fell");
        w.sync();
        (uint256 deepAfter, uint256 coverAfter) = w.settled();
        emit log_named_uint("cover before (6 dp)", coverBefore);
        emit log_named_uint("cover after  (6 dp)", coverAfter);
        emit log_named_uint("loss absorbed (6 dp)", w.lossAbsorbed());
        assertGt(w.lossAbsorbed(), 0, "loss booked");
        assertLt(coverAfter, coverBefore, "cover took the loss");
        assertApproxEqAbs(deepAfter, deepBefore, 2, "depositors untouched");
        assertEq(w.lossPassedThrough(), 0);
    }

    /// The path the website and the SDK use: one transaction from an ordinary wallet, batched by
    /// Multicall3From, with the deposit routed through Arc's Memo contract. The wallet itself
    /// must end up as the depositor.
    function test_fork_oneSignatureDepositThroughMemo() public {
        vm.prank(u);
        w.depositCover(10e6, u);
        uint256 amt = 5e6;
        IMulticall3From.Call3[] memory calls = new IMulticall3From.Call3[](2);
        calls[0] = IMulticall3From.Call3(address(USDC), false, abi.encodeCall(IERC20.approve, (address(w), amt)));
        bytes memory inner = abi.encodeCall(Stepwell.requestDeposit, (amt, d, d));
        calls[1] = IMulticall3From.Call3(
            MEMO, false, abi.encodeCall(IMemo.memo, (address(w), inner, keccak256("stepwell.site"), bytes("stepwell.site")))
        );
        vm.prank(d, d); // msg.sender and tx.origin are the wallet, as in a real transaction
        IMulticall3From(MULTICALL3_FROM).aggregate3(calls);
        (uint256 shares,) = w.requests(d);
        assertGt(shares, 0, "the wallet itself holds the request");
    }
}
