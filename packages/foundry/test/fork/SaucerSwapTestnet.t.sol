// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IERC20RecurringBuy, ISaucerSwapRouterRecurringBuy, RecurringBuy } from "../../contracts/RecurringBuy.sol";

/// @notice Testnet-fork coverage for the real SaucerSwap V1 router and a scheduled vault run.
contract SaucerSwapTestnetTest is Test {
    uint256 private constant ONE_HBAR = 100_000_000;
    address private constant SUPRA = 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917;
    address private constant ROUTER = 0x0000000000000000000000000000000000004b40;
    address private constant WHBAR = 0x0000000000000000000000000000000000003aD2;
    address private constant SAUCE = 0x0000000000000000000000000000000000120f46;
    address private constant PAIR = 0xfE7CC3cEb7b1128bfC3889184E2d5561BF74bfb3;

    ISaucerSwapRouterRecurringBuy private constant ROUTER_CONTRACT = ISaucerSwapRouterRecurringBuy(ROUTER);
    address private owner;

    function setUp() public {
        if (block.chainid != 296) vm.skip(true, "requires the pinned Hedera testnet fork");
        Forklab.setUp();
        address[] memory tokens = new address[](2);
        tokens[0] = WHBAR;
        tokens[1] = SAUCE;
        Forklab.useTokens(tokens);
        owner = makeAddr("testnet-vault-owner");
        assertTrue(Forklab.associateLocalAccount(SAUCE, owner));
    }

    /// @notice A real liquid testnet pair fills for exactly the router quote.
    function test_testnetHbarToSauceMatchesRouterQuote() external {
        (uint112 reserve0, uint112 reserve1,) = ITestnetPair(PAIR).getReserves();
        assertGt(reserve0, 0);
        assertGt(reserve1, 0);

        address trader = makeAddr("testnet-swap-trader");
        assertTrue(Forklab.associateLocalAccount(SAUCE, trader));
        vm.deal(trader, ONE_HBAR);
        address[] memory path = _path();
        uint256[] memory quote = ROUTER_CONTRACT.getAmountsOut(ONE_HBAR, path);

        vm.prank(trader);
        ROUTER_CONTRACT.swapExactETHForTokens{ value: ONE_HBAR }(quote[1], path, trader, block.timestamp + 300);
        assertEq(IERC20RecurringBuy(SAUCE).balanceOf(trader), quote[1]);
    }

    /// @notice The recurring vault executes on testnet state and reschedules after a real-price deviation skip.
    function test_testnetRecurringBuyRunsAndReschedules() external {
        vm.prank(owner);
        RecurringBuy vault = new RecurringBuy(SUPRA, ROUTER);
        vm.prank(owner);
        vault.configure(SAUCE, ONE_HBAR, 60, 10_000, 7_200);
        assertTrue(Forklab.associateLocalAccount(SAUCE, address(vault)));
        // start() requires the owner's one-unit approval proof.
        vm.prank(owner);
        IERC20RecurringBuy(SAUCE).approve(address(vault), 1);
        vm.deal(address(vault), 5 * ONE_HBAR);

        vm.prank(owner);
        (, address firstSchedule) = vault.start();
        vm.expectEmit(false, false, false, false, address(vault));
        emit SkippedDeviation(0, 0, 0);
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(firstSchedule).success);
        assertTrue(vault.running());
        assertNotEq(vault.nextSchedule(), address(0));
    }

    function _path() private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = WHBAR;
        path[1] = SAUCE;
    }

    event SkippedDeviation(uint256 oracleAmountOut, uint256 poolAmountOut, uint256 deviationBps);
}

interface ITestnetPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
