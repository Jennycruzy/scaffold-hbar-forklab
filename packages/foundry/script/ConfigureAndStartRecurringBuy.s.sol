// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { RecurringBuy } from "../contracts/RecurringBuy.sol";

/// @notice Configures, funds, and starts an existing testnet vault after direct owner association.
contract ConfigureAndStartRecurringBuy is Script {
    int64 private constant SUCCESS_RESPONSE = 22;
    address private constant DEFAULT_TOKEN_OUT = 0x000000000000000000000000000000000042E926;

    error ScheduleCreationFailed(int64 responseCode);

    function run() external {
        RecurringBuy vault = RecurringBuy(payable(vm.envAddress("RECURRING_BUY_VAULT")));
        address tokenOut = vm.envOr("RECURRING_BUY_TOKEN_OUT", DEFAULT_TOKEN_OUT);
        uint256 amountTinybars = vm.envOr("RECURRING_BUY_AMOUNT_TINYBARS", uint256(100_000_000));
        uint256 intervalSeconds = vm.envOr("RECURRING_BUY_INTERVAL_SECONDS", uint256(60));
        uint256 deviationBps = vm.envOr("RECURRING_BUY_DEVIATION_BPS", uint256(10_000));
        uint256 maxPriceAge = vm.envOr("RECURRING_BUY_MAX_PRICE_AGE", uint256(7_200));
        uint256 executionGas = vm.envOr("RECURRING_BUY_EXECUTION_GAS", uint256(2_500_000));
        // Each run must reserve gas at the full limit (2,500,000 x 83 tinybars = 2.075 HBAR at
        // the 4 October 2026 testnet price), pays the gas it uses (about 1.7M, ~1.4 HBAR, from
        // the measured schedule and purchase costs), and spends amountTinybars. Fifteen HBAR
        // covers several one-HBAR runs.
        uint256 fundWeibars = vm.envOr("RECURRING_BUY_FUND_WEIBARS", uint256(15 ether));

        vm.startBroadcast();
        vault.configure(tokenOut, amountTinybars, intervalSeconds, deviationBps, maxPriceAge);
        if (vault.executionGas() != executionGas) vault.setExecutionGas(executionGas);
        vault.configureBonzo(address(0), false);
        vault.deposit{ value: fundWeibars }();
        (int64 responseCode,) = vault.start();
        if (responseCode != SUCCESS_RESPONSE) revert ScheduleCreationFailed(responseCode);
        vm.stopBroadcast();
    }
}
