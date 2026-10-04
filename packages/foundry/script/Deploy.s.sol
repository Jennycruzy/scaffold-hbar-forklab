//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";
import { RecurringBuy } from "../contracts/RecurringBuy.sol";
import { RecurringBuyFactory } from "../contracts/RecurringBuyFactory.sol";

/**
 * @notice Deploys RecurringBuy and RecurringBuyFactory with verified network integrations
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without `--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    address private constant MAINNET_SUPRA = 0xD02cc7a670047b6b012556A88e275c685d25e0c9;
    address private constant MAINNET_ROUTER = 0x00000000000000000000000000000000002E7A5D;
    address private constant TESTNET_SUPRA = 0x6Cd59830AAD978446e6cc7f6cc173aF7656Fb917;
    address private constant TESTNET_ROUTER = 0x0000000000000000000000000000000000004b40;

    function run() external ScaffoldEthDeployerRunner {
        address defaultSupra;
        address defaultRouter;
        if (block.chainid == 295) (defaultSupra, defaultRouter) = (MAINNET_SUPRA, MAINNET_ROUTER);
        if (block.chainid == 296) (defaultSupra, defaultRouter) = (TESTNET_SUPRA, TESTNET_ROUTER);
        address supra = vm.envOr("RECURRING_BUY_SUPRA", defaultSupra);
        address router = vm.envOr("RECURRING_BUY_ROUTER", defaultRouter);
        if (supra == address(0) || router == address(0)) revert InvalidChain();

        RecurringBuy recurringBuy = new RecurringBuy(supra, router);
        deployments.push(Deployment({ name: "RecurringBuy", addr: address(recurringBuy) }));

        // The /vault page creates per-wallet vaults through this factory.
        RecurringBuyFactory factory = new RecurringBuyFactory();
        deployments.push(Deployment({ name: "RecurringBuyFactory", addr: address(factory) }));
    }
}
