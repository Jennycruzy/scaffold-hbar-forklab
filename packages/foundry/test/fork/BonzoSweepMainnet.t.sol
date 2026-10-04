// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IERC20RecurringBuy, ISaucerSwapRouterRecurringBuy, RecurringBuy } from "../../contracts/RecurringBuy.sol";

interface IBonzoLendingPoolState {
    function paused() external view returns (bool);
}

/// @notice A successful RecurringBuy -> Bonzo Lend sweep on real mainnet state.
/// @dev Bonzo's mainnet LendingPool was paused at block 97,506,158 and is still paused
///      at Forklab's main pin (100,579,000). This suite runs on a separate pin,
///      block 97,505,850, before that pause: the USDC reserve is active and
///      unfrozen, Supra pair 432 is 3,263 seconds old, and the Mirror Node balance
///      snapshot for the USDC/WHBAR pair postdates its last swap, so the pair's
///      reserves and emulated HTS balances agree. See docs/VERIFIED.md.
contract BonzoSweepMainnetTest is Test {
    uint256 private constant BONZO_FORK_BLOCK = 97_505_850;
    uint256 private constant TINYBARS_PER_HBAR = 100_000_000;

    address private constant SUPRA = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;
    address private constant ROUTER = 0x00000000000000000000000000000000002E7A5D;
    address private constant WHBAR = 0x0000000000000000000000000000000000163B5a;
    address private constant USDC = 0x000000000000000000000000000000000006f89a;
    address private constant BONZO_POOL = 0x236897c518996163E7b313aD21D1C9fCC7BA1afc;
    address private constant A_USDC = 0xB7687538c7f4CAD022d5e97CC778d0b46457c5DB;
    /// @dev Account 0.0.1764: an ED25519 account holding USDC at the fork timestamp.
    address private constant OWNER = 0x00000000000000000000000000000000000006e4;

    function setUp() public {
        if (block.chainid != 295 || block.number != BONZO_FORK_BLOCK) {
            vm.skip(true, "run with --fork-block-number 97505850 (yarn foundry:test:fork does this)");
        }
        Forklab.setUp();
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WHBAR;
        Forklab.useTokens(tokens);
    }

    /// @notice A scheduled purchase deposits the exact SaucerSwap fill into Bonzo for the owner.
    function test_scheduledBuySweepsRealFillIntoBonzo() external {
        assertFalse(IBonzoLendingPoolState(BONZO_POOL).paused());

        vm.prank(OWNER);
        RecurringBuy vault = new RecurringBuy(SUPRA, ROUTER);
        vm.startPrank(OWNER);
        vault.configure(USDC, TINYBARS_PER_HBAR, 60, 500, 7_200);
        vault.configureBonzo(BONZO_POOL, true);
        // Emulated HTS token calls run as EVM code and cost far more gas than Hedera's
        // system-contract pricing (testnet: 15,284 gas per HTS transfer; emulated approve
        // here: ~298,000). The higher limit keeps that emulator overhead from starving
        // the Bonzo deposit; it is not a measured production setting.
        vault.setExecutionGas(6_000_000);
        vm.stopPrank();
        assertTrue(Forklab.associateLocalAccount(USDC, address(vault)));
        vm.prank(OWNER);
        IERC20RecurringBuy(USDC).approve(address(vault), 1);
        vm.deal(address(vault), 10 * TINYBARS_PER_HBAR);

        vm.prank(OWNER);
        (, address firstSchedule) = vault.start();

        uint256 aTokenBefore = IERC20RecurringBuy(A_USDC).balanceOf(OWNER);
        uint256 ownerUsdcBefore = IERC20RecurringBuy(USDC).balanceOf(OWNER);
        address[] memory path = new address[](2);
        path[0] = WHBAR;
        path[1] = USDC;
        uint256 quote = ISaucerSwapRouterRecurringBuy(ROUTER).getAmountsOut(TINYBARS_PER_HBAR, path)[1];

        vm.expectEmit(true, true, false, true, address(vault));
        emit SweptToBonzo(USDC, OWNER, quote);
        assertEq(Forklab.warp(60), 1);

        assertTrue(Forklab.schedule(firstSchedule).success);
        // Aave-style aTokens can round the minted balance by one unit at a non-unit index.
        assertApproxEqAbs(IERC20RecurringBuy(A_USDC).balanceOf(OWNER) - aTokenBefore, quote, 1);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(OWNER), ownerUsdcBefore);
        assertEq(IERC20RecurringBuy(USDC).balanceOf(address(vault)), 0);
        assertTrue(vault.running());
    }

    event SweptToBonzo(address indexed asset, address indexed onBehalfOf, uint256 amount);
}
