// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { ForklabMirrorNode } from "../../contracts/forklab/ForklabMirrorNode.sol";

interface ISaucerSwapRouter {
    function factory() external view returns (address);

    function WHBAR() external view returns (address);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IERC20View {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

/// @notice Real mainnet-fork proofs for HTS proxy repair and SaucerSwap V1.
contract SaucerSwapMainnetTest is Test {
    uint256 private constant TINYBARS_PER_HBAR = 100_000_000;
    uint256 private constant HBAR_INPUT = 100 * TINYBARS_PER_HBAR;
    uint256 private constant USDC_INPUT = 50_000_000;

    address private constant ROUTER = 0x00000000000000000000000000000000002E7A5D;
    address private constant WHBAR = 0x0000000000000000000000000000000000163B5a;
    address private constant USDC = 0x000000000000000000000000000000000006f89a;
    address private constant SAUCE = 0x00000000000000000000000000000000000b2aD5;
    address private constant WHBAR_HELPER = 0x0000000000000000000000000000000000163B59;
    address private constant SAUCE_SUPPLY_CONTRACT = 0x000000000000000000000000000000000010717B;
    address private constant USDC_WHBAR_PAIR = 0xdB34c1Ef944883f0e5A2fC18B6C1978B088bD31d;

    ISaucerSwapRouter private constant ROUTER_CONTRACT = ISaucerSwapRouter(ROUTER);

    function setUp() public {
        if (block.chainid != 295) vm.skip(true, "requires the pinned Hedera mainnet fork");
        Forklab.setUp();
        address[] memory tokens = new address[](3);
        tokens[0] = USDC;
        tokens[1] = WHBAR;
        tokens[2] = SAUCE;
        Forklab.useTokens(tokens);
    }

    /// @notice Confirms an HTS token read agrees with the timestamped Mirror Node response.
    function test_usdcRouterBalanceMatchesMirrorNode() external {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 routerAccount = uint32(uint160(ROUTER));
        uint256 evmBalance = IERC20View(USDC).balanceOf(ROUTER);
        ForklabMirrorNode mirrorNode = new ForklabMirrorNode();
        string memory json = mirrorNode.fetchBalance(USDC, routerAccount);
        uint256 mirrorBalance =
            vm.keyExistsJson(json, ".balances[0].balance") ? vm.parseJsonUint(json, ".balances[0].balance") : 0;
        assertEq(evmBalance, mirrorBalance);
    }

    /// @notice Fails loudly if the pinned hedera-forking token-key layout moves.
    function test_protobufSupplyKeyRepairMatchesPinnedStorageLayout() external view {
        uint256 supplyContractSlot = uint256(keccak256(abi.encodePacked(uint256(7)))) + 4 * 5 + 1;
        assertEq(address(uint160(uint256(vm.load(WHBAR, bytes32(supplyContractSlot))))), WHBAR_HELPER);
        assertEq(address(uint160(uint256(vm.load(SAUCE, bytes32(supplyContractSlot))))), SAUCE_SUPPLY_CONTRACT);
    }

    /// @notice Confirms the real WHBAR helper path can swap HBAR for USDC.
    function test_hbarToUsdcMatchesRouterQuote() external {
        address trader = makeAddr("hbar-trader");
        vm.deal(trader, 1_000 * TINYBARS_PER_HBAR);
        address[] memory path = new address[](2);
        path[0] = WHBAR;
        path[1] = USDC;
        uint256[] memory quote = ROUTER_CONTRACT.getAmountsOut(HBAR_INPUT, path);
        vm.prank(trader);
        ROUTER_CONTRACT.swapExactETHForTokens{ value: HBAR_INPUT }(quote[1], path, trader, block.timestamp + 60);

        assertEq(IERC20View(USDC).balanceOf(trader), quote[1]);
    }

    /// @notice Confirms the real USDC-WHBAR-SAUCE route matches its quote.
    function test_usdcToWhbarToSauceMatchesRouterQuote() external {
        address trader = makeAddr("token-trader");
        // Hedera rejects approve from an unassociated account, and Forklab's token proxy does too.
        Forklab.associateLocalAccount(USDC, trader);
        deal(USDC, trader, USDC_INPUT);
        address[] memory path = new address[](3);
        path[0] = USDC;
        path[1] = WHBAR;
        path[2] = SAUCE;
        uint256[] memory quote = ROUTER_CONTRACT.getAmountsOut(USDC_INPUT, path);

        vm.startPrank(trader);
        IERC20View(USDC).approve(ROUTER, USDC_INPUT);
        ROUTER_CONTRACT.swapExactTokensForTokens(USDC_INPUT, quote[2], path, trader, block.timestamp + 60);
        vm.stopPrank();

        assertEq(IERC20View(SAUCE).balanceOf(trader), quote[2]);
    }

    /// @notice Confirms later local block numbers do not move Mirror reads off the fork snapshot.
    function test_pairReserveMatchesEmulatedUsdcBalance() external {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(USDC_WHBAR_PAIR).getReserves();
        vm.roll(block.number + 100);
        address token0 = IUniswapV2Pair(USDC_WHBAR_PAIR).token0();
        address token1 = IUniswapV2Pair(USDC_WHBAR_PAIR).token1();
        assertEq(token0, USDC);
        assertEq(token1, WHBAR);
        assertEq(IERC20View(token0).balanceOf(USDC_WHBAR_PAIR), reserve0);
        assertEq(IERC20View(token1).balanceOf(USDC_WHBAR_PAIR), reserve1);
    }
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}
