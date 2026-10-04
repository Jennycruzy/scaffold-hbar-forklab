// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, Vm } from "forge-std/Test.sol";
import { ISupraSValueFeed } from "../../contracts/ISupraSValueFeed.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IERC20RecurringBuy, ISaucerSwapRouterRecurringBuy, RecurringBuy } from "../../contracts/RecurringBuy.sol";
import { RecurringBuyFactory } from "../../contracts/RecurringBuyFactory.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";

interface IBonzoPausable {
    function paused() external view returns (bool);
}

/// @notice Real mainnet-fork proofs for Supra-backed recurring SaucerSwap buys.
contract RecurringBuyMainnetTest is Test {
    uint256 private constant TINYBARS_PER_HBAR = 100_000_000;
    uint256 private constant HBAR_USD_PAIR_INDEX = 432;
    int64 private constant INSUFFICIENT_PAYER_BALANCE = 10;
    uint256 private constant FULL_LIMIT_FEE = 2_500_000 * 83;

    address private constant SUPRA = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;
    address private constant ROUTER = 0x00000000000000000000000000000000002E7A5D;
    address private constant WHBAR = 0x0000000000000000000000000000000000163B5a;
    address private constant USDC = 0x000000000000000000000000000000000006f89a;
    address private constant BONZO_POOL = 0x236897c518996163E7b313aD21D1C9fCC7BA1afc;
    address private constant A_USDC = 0xB7687538c7f4CAD022d5e97CC778d0b46457c5DB;
    address private constant OWNER = 0xC376f5159300C1b16d2d711cc43AFCaF7433B0EE;
    /// @dev Mainnet account 0.0.5000 (ED25519). Mirror Node, 4 October 2026:
    ///      `/accounts/0.0.5000/tokens?token.id=0.0.456858` returns no tokens and
    ///      `max_automatic_token_associations` is 0, so it holds no USDC relationship.
    address private constant UNASSOCIATED_ACCOUNT = 0x0000000000000000000000000000000000001388;
    /// @dev Mainnet account 0.0.10162362. Mirror Node, 4 October 2026: its USDC relationship has
    ///      `created_timestamp` 1790829609.024372590, after the pinned block's 1790821038.006379925.
    address private constant ASSOCIATED_AFTER_PIN = 0x00000000000000000000000000000000009B10BA;

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
        vm.deal(address(vault), 20 * TINYBARS_PER_HBAR);
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
        vm.deal(address(vault), 5 * TINYBARS_PER_HBAR);
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
        vm.deal(address(vault), 5 * TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        vault.start();
        uint256 ownerBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);

        vm.expectEmit(false, false, false, false, address(vault));
        emit SkippedStalePrice(0, 0);
        assertEq(Forklab.warp(2), 1);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerBefore);
        assertTrue(vault.running());
    }

    /// @notice A vault without HBAR for gas records the payer-balance failure.
    function test_outOfHbarRecordsPayerFailure() external {
        RecurringBuy vault = _newVault(60, 500, 3_600);
        vm.prank(OWNER);
        (, address scheduleAddress) = vault.start();
        assertEq(Forklab.warp(60), 1);
        assertEq(Forklab.schedule(scheduleAddress).status, INSUFFICIENT_PAYER_BALANCE);
        assertFalse(Forklab.schedule(scheduleAddress).success);
    }

    /// @notice A funded vault buys twice, pays Hedera gas each run, then cannot reserve gas for the next run.
    function test_vaultRunsTwoBuysThenRunsOutOfHbar() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        // Each run must reserve gas at the full 2,500,000 limit (2.075 HBAR at 83 tinybars),
        // then pays the gas it used plus the one-HBAR purchase.
        vm.deal(address(vault), 6 * TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        vault.start();

        uint256 ownerBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        uint256 vaultBefore = address(vault).balance;
        assertEq(Forklab.warp(60), 1);
        uint256 afterFirst = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        assertGt(afterFirst, ownerBefore);
        uint256 firstRunCost = vaultBefore - address(vault).balance;
        assertGt(firstRunCost, TINYBARS_PER_HBAR);
        assertEq((firstRunCost - TINYBARS_PER_HBAR) % 83, 0);

        assertEq(Forklab.warp(60), 1);
        assertGt(IERC20RecurringBuy(USDC).balanceOf(OWNER), afterFirst);
        assertLt(address(vault).balance, FULL_LIMIT_FEE);

        address failingSchedule = vault.nextSchedule();
        uint256 beforeFailure = address(vault).balance;
        vm.expectEmit(true, false, false, false, address(0x16b));
        emit ScheduleExecuted(failingSchedule, false, bytes(""));
        assertEq(Forklab.warp(60), 1);
        assertEq(Forklab.schedule(failingSchedule).status, INSUFFICIENT_PAYER_BALANCE);
        assertFalse(Forklab.schedule(failingSchedule).success);
        // As on testnet (schedule 0.0.10862057), the failed attempt still costs 1,735,120 tinybars.
        assertEq(address(vault).balance, beforeFailure - 1_735_120);
    }

    /// @notice The 1,500,000 gas limit that failed on testnet cannot fund both the
    ///         re-schedule (1,409,649 gas on testnet) and the purchase.
    function test_testnetFailureGasLimitCannotFundRescheduleAndPurchase() external {
        RecurringBuy vault = _newVault(60, 500, 7_200);
        vm.prank(OWNER);
        vault.setExecutionGas(1_500_000);
        vm.deal(address(vault), 10 * TINYBARS_PER_HBAR);
        vm.prank(OWNER);
        (, address firstSchedule) = vault.start();

        uint256 ownerBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        vm.recordLogs();
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(firstSchedule).success);
        assertTrue(_emitted(address(vault), keccak256("PurchaseFailed(bytes)")));
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerBefore);
        assertTrue(vault.running());
        assertNotEq(vault.nextSchedule(), firstSchedule);
    }

    /// @notice Bonzo's mainnet LendingPool is paused at the pinned block. The sweep fails with
    ///         Aave v2 error "64" (LP_IS_PAUSED), no aUSDC is minted, and the next run is
    ///         still scheduled.
    function test_bonzoPausedPoolFailsPurchaseButKeepsSchedule() external {
        assertTrue(IBonzoPausable(BONZO_POOL).paused());
        RecurringBuy vault = _newVault(60, 500, 7_200);
        vm.prank(OWNER);
        vault.configureBonzo(BONZO_POOL, true);
        vm.deal(address(vault), 10 * TINYBARS_PER_HBAR);

        uint256 aTokenBefore = IERC20RecurringBuy(A_USDC).balanceOf(OWNER);
        uint256 ownerTokenBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        vm.prank(OWNER);
        (, address firstSchedule) = vault.start();

        vm.expectEmit(false, false, false, true, address(vault));
        emit PurchaseFailed(abi.encodeWithSignature("Error(string)", "64"));
        assertEq(Forklab.warp(60), 1);
        assertTrue(Forklab.schedule(firstSchedule).success);
        assertEq(IERC20RecurringBuy(A_USDC).balanceOf(OWNER), aTokenBefore);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerTokenBefore);
        assertTrue(vault.running());
        assertNotEq(vault.nextSchedule(), firstSchedule);
        assertEq(vault.nextRunAt(), block.timestamp + 60);
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
        vm.expectRevert(RecurringBuy.OnlyVault.selector);
        vault.purchase();
    }

    /// @notice The factory deploys a vault against the real router and hands it to the caller.
    function test_factoryAssignsVaultToRequestingWallet() external {
        RecurringBuyFactory factory = new RecurringBuyFactory();
        vm.prank(OWNER);
        RecurringBuy vault = RecurringBuy(payable(factory.createVault(SUPRA, ROUTER)));
        assertEq(vault.owner(), OWNER);
        assertEq(address(vault.router()), ROUTER);
        assertEq(vault.whbar(), WHBAR);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(RecurringBuy.NotOwner.selector);
        vault.transferOwnership(stranger);
    }

    /// @notice A real account with no USDC association cannot start a vault.
    /// @dev HRC-719 `isAssociated()` reads the account's real token relationships from
    ///      the Mirror Node, so the fork proves this owner is unassociated while the
    ///      funded OWNER is associated. start() then rejects the missing approval proof.
    ///      Whether Hedera rejects `approve` from an unassociated account is a live
    ///      testnet check; the emulated HTS `approve` does not model it.
    function test_unassociatedOwnerCannotStart() external {
        vm.prank(UNASSOCIATED_ACCOUNT);
        assertFalse(IHRC719(USDC).isAssociated());
        vm.prank(OWNER);
        assertTrue(IHRC719(USDC).isAssociated());

        vm.prank(UNASSOCIATED_ACCOUNT);
        RecurringBuy vault = new RecurringBuy(SUPRA, ROUTER);
        vm.prank(UNASSOCIATED_ACCOUNT);
        vault.configure(USDC, TINYBARS_PER_HBAR, 60, 500, 7_200);
        assertTrue(Forklab.associateLocalAccount(USDC, address(vault)));

        vm.prank(UNASSOCIATED_ACCOUNT);
        vm.expectRevert(RecurringBuy.OwnerTokenAssociationRequired.selector);
        vault.start();
    }

    /// @notice An association created after the pinned block is not visible at the pin.
    function test_associationCreatedAfterThePinIsNotVisible() external {
        vm.prank(ASSOCIATED_AFTER_PIN);
        assertFalse(IHRC719(USDC).isAssociated());
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
        vm.prank(OWNER);
        IERC20RecurringBuy(USDC).approve(address(vault), 1);
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
    event PurchaseFailed(bytes reason);

    function _emitted(address emitter, bytes32 topic) private view returns (bool) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == emitter && logs[i].topics.length != 0 && logs[i].topics[0] == topic) return true;
        }
        return false;
    }
}
