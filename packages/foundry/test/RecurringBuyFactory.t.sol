// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { RecurringBuyFactory } from "../contracts/RecurringBuyFactory.sol";
import { RecurringBuy } from "../contracts/RecurringBuy.sol";

contract RecurringBuyFactoryTest is Test {
    address private constant SUPRA = address(0x1234);
    address private token;
    MockRouter private router;
    RecurringBuyFactory private factory;

    function setUp() public {
        token = makeAddr("wrapped-hbar-token");
        MockWhbar whbar = new MockWhbar(token);
        router = new MockRouter(address(whbar));
        factory = new RecurringBuyFactory();
    }

    function test_factoryAssignsVaultToRequestingWallet() external {
        address owner = makeAddr("vault-owner");
        vm.prank(owner);
        address payable vaultAddress = payable(factory.createVault(SUPRA, address(router)));

        RecurringBuy vault = RecurringBuy(vaultAddress);
        assertEq(vault.owner(), owner);
        assertEq(address(vault.supra()), SUPRA);
        assertEq(address(vault.router()), address(router));
        assertEq(vault.whbar(), token);
    }

    function test_onlyCurrentOwnerCanTransferOwnership() external {
        address owner = makeAddr("vault-owner");
        address nextOwner = makeAddr("next-owner");
        vm.prank(owner);
        RecurringBuy vault = RecurringBuy(payable(factory.createVault(SUPRA, address(router))));

        vm.prank(nextOwner);
        vm.expectRevert(RecurringBuy.NotOwner.selector);
        vault.transferOwnership(nextOwner);

        vm.prank(owner);
        vault.transferOwnership(nextOwner);
        assertEq(vault.owner(), nextOwner);
    }
}

contract MockRouter {
    address public immutable WHBAR;

    constructor(address whbar) {
        WHBAR = whbar;
    }
}

contract MockWhbar {
    address public immutable TOKEN;

    constructor(address tokenAddress) {
        TOKEN = tokenAddress;
    }

    function token() external view returns (address) {
        return TOKEN;
    }
}
