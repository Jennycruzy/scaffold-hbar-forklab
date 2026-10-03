// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { RecurringBuyFactory } from "../contracts/RecurringBuyFactory.sol";
import { ScaffoldETHDeploy } from "./DeployHelpers.s.sol";

/// @notice Deploys the factory used by the testnet /vault page.
contract DeployRecurringBuyFactory is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        RecurringBuyFactory factory = new RecurringBuyFactory();
        deployments.push(Deployment({ name: "RecurringBuyFactory", addr: address(factory) }));
    }
}
