// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { RecurringBuy } from "./RecurringBuy.sol";

/// @title RecurringBuyFactory
/// @notice Deploys a RecurringBuy and assigns ownership to the requesting wallet.
/// @dev The factory never holds the vault after createVault returns. The new
///      vault is constructed with the factory as the temporary owner, then
///      transfers ownership to msg.sender in the same transaction.
contract RecurringBuyFactory {
    error InvalidConfiguration();

    event VaultCreated(address indexed owner, address indexed vault, address supra, address router);

    function createVault(address supra, address router) external returns (address vault) {
        if (supra == address(0) || router == address(0)) revert InvalidConfiguration();

        RecurringBuy created = new RecurringBuy(supra, router);
        created.transferOwnership(msg.sender);
        vault = address(created);
        emit VaultCreated(msg.sender, vault, supra, router);
    }
}
