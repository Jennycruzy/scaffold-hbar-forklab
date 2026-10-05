// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IERC20RecurringBuy } from "../../contracts/RecurringBuy.sol";

/// @notice Calls `approve` on a token and reports the raw result, like the testnet probe contract.
contract ApproveCaller {
    function tryApprove(address token, address spender, uint256 amount)
        external
        returns (bool success, bytes memory ret)
    {
        (success, ret) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
    }
}

/// @notice `approve` association rules on the pinned mainnet fork, matching the 4 October 2026 testnet probe
///         (docs/TESTNET_PROOF.md, "Edge-case probe"): an unassociated caller's approve reverts with empty data
///         and leaves the allowance unchanged; an associated caller's approve succeeds.
contract TokenAssociationMainnetTest is Test {
    address private constant USDC = 0x000000000000000000000000000000000006f89a;
    /// @dev Mainnet account 0.0.5000, which holds no USDC relationship at the pinned block.
    address private constant UNASSOCIATED_ACCOUNT = 0x0000000000000000000000000000000000001388;
    /// @dev Mainnet account associated with USDC at the pinned block (also the RecurringBuy fork-test owner).
    address private constant ASSOCIATED_ACCOUNT = 0xC376f5159300C1b16d2d711cc43AFCaF7433B0EE;
    address private immutable spender = makeAddr("spender");

    function setUp() external {
        if (block.chainid != 295) vm.skip(true, "requires the pinned Hedera mainnet fork");
        Forklab.setUp();
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;
        Forklab.useTokens(tokens);
    }

    function test_unassociatedContractApproveRevertsLikeTestnet() external {
        ApproveCaller caller = new ApproveCaller();
        (bool success, bytes memory ret) = caller.tryApprove(USDC, spender, 1);
        assertFalse(success);
        assertEq(ret.length, 0);
        assertEq(IERC20RecurringBuy(USDC).allowance(address(caller), spender), 0);
    }

    function test_unassociatedMirrorAccountApproveReverts() external {
        vm.prank(UNASSOCIATED_ACCOUNT);
        (bool success, bytes memory ret) = USDC.call(abi.encodeWithSignature("approve(address,uint256)", spender, 1));
        assertFalse(success);
        assertEq(ret.length, 0);
    }

    function test_associatedAccountApproveSucceeds() external {
        vm.prank(ASSOCIATED_ACCOUNT);
        assertTrue(IERC20RecurringBuy(USDC).approve(spender, 7));
        assertEq(IERC20RecurringBuy(USDC).allowance(ASSOCIATED_ACCOUNT, spender), 7);
    }

    function test_locallyAssociatedContractApproveSucceeds() external {
        ApproveCaller caller = new ApproveCaller();
        assertTrue(Forklab.associateLocalAccount(USDC, address(caller)));
        (bool success, bytes memory ret) = caller.tryApprove(USDC, spender, 5);
        assertTrue(success);
        assertTrue(abi.decode(ret, (bool)));
        assertEq(IERC20RecurringBuy(USDC).allowance(address(caller), spender), 5);
    }
}
