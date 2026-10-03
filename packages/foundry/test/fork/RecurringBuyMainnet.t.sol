// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ISupraSValueFeed } from "../../contracts/ISupraSValueFeed.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IERC20RecurringBuy, ISaucerSwapRouterRecurringBuy, RecurringBuy } from "../../contracts/RecurringBuy.sol";

/// @notice Real mainnet-fork proofs for Supra-backed recurring SaucerSwap buys.
contract RecurringBuyMainnetTest is Test {
    uint256 private constant TINYBARS_PER_HBAR = 100_000_000;
    uint256 private constant HBAR_USD_PAIR_INDEX = 432;
    int64 private constant INSUFFICIENT_PAYER_BALANCE = 10;

    address private constant SUPRA = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;
    address private constant ROUTER = 0x00000000000000000000000000000000002E7A5D;
    address private constant WHBAR = 0x0000000000000000000000000000000000163B5a;
    address private constant USDC = 0x000000000000000000000000000000000006f89a;
    address private constant BONZO_POOL = 0x236897c518996163E7b313aD21D1C9fCC7BA1afc;
    address private constant A_USDC = 0xB7687538c7f4CAD022d5e97CC778d0b46457c5DB;
    address private constant OWNER = 0xC376f5159300C1b16d2d711cc43AFCaF7433B0EE;

    ISaucerSwapRouterRecurringBuy private constant ROUTER_CONTRACT = ISaucerSwapRouterRecurringBuy(ROUTER);
    ISupraSValueFeed private constant SUPRA_CONTRACT = ISupraSValueFeed(SUPRA);

    function setUp() public {
        if (block.chainid != 295) vm.skip(true, "requires the pinned Hedera mainnet fork");
        Forklab.setUp();
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WHBAR;
        Forklab.useTokens(tokens);
    }

    /// @notice Confirms the real HBAR/USD observation is live at the pinned block.
    function test_supraHbarUsdFeedIsLiveAtPinnedBlock() external view {
        ISupraSValueFeed.PriceFeed memory observation = SUPRA_CONTRACT.getSvalue(HBAR_USD_PAIR_INDEX);
        uint256 publishTime = observation.time / 1_000;
        assertEq(observation.decimals, 18);
        assertGt(observation.price, 0);
        assertLe(publishTime, block.timestamp);
        assertLe(block.timestamp - publishTime, 3_600);
    }

    /// @notice Executes three real scheduled purchases and confirms owner proceeds.
    function test_threeScheduledBuysUseRealSupraAndSaucerSwap() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        vm.deal(address(vault), 10 * TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        (, address firstSchedule) = vault.start();

        uint256 firstBalance = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        uint256 firstQuote = _quoteOneHbar();
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(firstSchedule).success);
        uint256 secondBalance = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        assertEq(secondBalance - firstBalance, firstQuote);

        address secondSchedule = vault.nextSchedule();
        uint256 secondQuote = _quoteOneHbar();
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(secondSchedule).success);
        uint256 thirdBalance = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        assertEq(thirdBalance - secondBalance, secondQuote);

        address thirdSchedule = vault.nextSchedule();
        uint256 thirdQuote = _quoteOneHbar();
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(thirdSchedule).success);
        uint256 fourthBalance = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        assertEq(fourthBalance - thirdBalance, thirdQuote);
        assertTrue(vault.running());
        assertNotEq(vault.nextSchedule(), address(0));
    }

    /// @notice A real large swap moves the pool quote outside the Supra tolerance.
    function test_largeRealSwapCausesDeviationSkip() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        vm.deal(address(vault), TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        vault.start();

        address trader = makeAddr("price-moving-trader");
        uint256 input = 100_000 * TINYBARS_PER_HBAR;
        vm.deal(trader, input);
        address[] memory path = new address[](2);
        path[0] = WHBAR;
        path[1] = USDC;
        uint256[] memory quote = ROUTER_CONTRACT.getAmountsOut(input, path);
        vm.prank(trader);
        ROUTER_CONTRACT.swapExactETHForTokens{ value: input }(quote[1], path, trader, block.timestamp + 600);

        uint256 ownerBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        vm.expectEmit(false, false, false, false, address(vault));
        emit SkippedDeviation(0, 0, 0);
        assertEq(Forklab.warp(60), 1);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerBefore);
        assertTrue(vault.running());
    }

    /// @notice A Supra price older than the configured bound skips without swapping.
    function test_staleSupraPriceSkips() external {
        RecurringBuy vault = _newVault(2, 500, 1);
        vm.deal(address(vault), TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        vault.start();
        uint256 ownerBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);

        vm.expectEmit(false, false, false, false, address(vault));
        emit SkippedStalePrice(0, 0);
        assertEq(Forklab.warp(2), 1);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerBefore);
        assertTrue(vault.running());
    }

    /// @notice A vault without HBAR records the real emulator payer-balance failure.
    function test_outOfHbarRecordsPayerFailure() external {
        RecurringBuy vault = _newVault(60, 500, 3_600);
        Forklab.setScheduleFeeTinybars(1);
        vm.prank(OWNER);
        (, address scheduleAddress) = vault.start();
        assertEq(Forklab.warp(60), 1);
        assertEq(Forklab.schedule(scheduleAddress).status, int64(10));
        assertFalse(Forklab.schedule(scheduleAddress).success);
    }

    /// @notice A funded vault can buy twice and then records payer exhaustion.
    function test_vaultRunsTwoBuysThenRunsOutOfHbar() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        Forklab.setScheduleFeeTinybars(2);
        vm.deal(address(vault), 2 * TINYBARS_PER_HBAR + 5);
        vm.prank(OWNER);
        vault.start();

        assertEq(Forklab.warp(60), 1);
        assertEq(address(vault).balance, TINYBARS_PER_HBAR + 3);
        assertEq(Forklab.warp(60), 1);
        assertEq(address(vault).balance, 1);
        address failingSchedule = vault.nextSchedule();
        vm.expectEmit(true, false, false, false, address(0x16b));
        emit ScheduleExecuted(failingSchedule, false, bytes(""));
        assertEq(Forklab.warp(60), 1);
        assertEq(Forklab.schedule(failingSchedule).status, INSUFFICIENT_PAYER_BALANCE);
        assertFalse(Forklab.schedule(failingSchedule).success);
    }

    /// @notice Records the real Bonzo response when its pinned USDC reserve is frozen.
    /// @dev The official pool is reached and the swap/approval succeed, but Bonzo returns
    ///      Error(string) "64" before minting aUSDC. This must become a success proof only
    ///      after the external reserve is reopened and the test is updated with that receipt.
    function test_bonzoSweepReportsPinnedFrozenReserve() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        vm.prank(OWNER);
        vault.configureBonzo(BONZO_POOL, true);
        vm.deal(address(vault), TINYBARS_PER_HBAR);

        uint256 aTokenBefore = IERC20RecurringBuy(A_USDC).balanceOf(OWNER);
        uint256 ownerTokenBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        uint256 quote = _quoteOneHbar();
        vm.prank(OWNER);
        (, address scheduleAddress) = vault.start();

        assertEq(Forklab.warp(60), 1);
        Forklab.ScheduleInfo memory scheduleInfo = Forklab.schedule(scheduleAddress);
        assertFalse(scheduleInfo.success);
        assertEq(bytes4(scheduleInfo.returnData), bytes4(0x08c379a0));
        assertGt(scheduleInfo.returnData.length, 4);
        assertEq(IERC20RecurringBuy(A_USDC).balanceOf(OWNER), aTokenBefore);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerTokenBefore);
        assertTrue(vault.sweepToBonzo());
        assertEq(quote, 103_761);
    }

    /// @notice Stopping a vault deletes its pending schedule.
    function test_stopDeletesPendingSchedule() external {
        RecurringBuy vault = _newVault(60, 500, 3_600);
        vm.deal(address(vault), TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        (, address scheduleAddress) = vault.start();
        vm.prank(OWNER);
        assertEq(vault.stop(), int64(22));
        assertEq(Forklab.schedule(scheduleAddress).status, int64(22));
        assertEq(vault.nextSchedule(), address(0));
        assertFalse(vault.running());
    }

    /// @notice Direct execution by a test caller is rejected; the HSS payer frame is required.
    function test_executeRequiresVaultCaller() external {
        RecurringBuy vault = _newVault(60, 500, 3_600);
        vm.expectRevert(RecurringBuy.OnlyVault.selector);
        vault.execute();
    }

    function _newVault(uint256 intervalSeconds, uint256 deviationBps, uint256 priceAgeSeconds)
        private
        returns (RecurringBuy vault)
    {
        vm.prank(OWNER);
        vault = new RecurringBuy(SUPRA, ROUTER);
        vm.prank(OWNER);
        vault.configure(USDC, TINYBARS_PER_HBAR, intervalSeconds, deviationBps, priceAgeSeconds);
        assertTrue(Forklab.associateLocalAccount(USDC, address(vault)));
    }

    function _quoteOneHbar() private view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = WHBAR;
        path[1] = USDC;
        uint256[] memory quote = ROUTER_CONTRACT.getAmountsOut(TINYBARS_PER_HBAR, path);
        return quote[1];
    }

    event SkippedDeviation(uint256 oracleAmountOut, uint256 poolAmountOut, uint256 deviationBps);
    event SkippedStalePrice(uint256 publishTime, uint256 currentTime);
    event ScheduleExecuted(address indexed schedule, bool success, bytes returnData);
}
