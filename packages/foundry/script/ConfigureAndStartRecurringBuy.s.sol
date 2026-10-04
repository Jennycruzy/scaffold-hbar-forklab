// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";
import { RecurringBuy } from "../contracts/RecurringBuy.sol";

/// @notice Associates the owner, configures, funds, and starts an existing testnet vault.
contract ConfigureAndStartRecurringBuy is Script {
    uint256 private constant SUCCESS = 22;
    int64 private constant SUCCESS_RESPONSE = 22;
    uint256 private constant TOKEN_ALREADY_ASSOCIATED = 194;
    address private constant DEFAULT_VAULT = 0x3DD43acB0c5b3AAc6540b3cbed0Ae5C021317350;
    address private constant DEFAULT_TOKEN_OUT = 0x000000000000000000000000000000000042E926;

    error AssociationFailed(uint256 responseCode);
    error ScheduleCreationFailed(int64 responseCode);

    function run() external {
        RecurringBuy vault = RecurringBuy(payable(vm.envOr("RECURRING_BUY_VAULT", DEFAULT_VAULT)));
        address tokenOut = vm.envOr("RECURRING_BUY_TOKEN_OUT", DEFAULT_TOKEN_OUT);
        uint256 amountTinybars = vm.envOr("RECURRING_BUY_AMOUNT_TINYBARS", uint256(100_000_000));
        uint256 intervalSeconds = vm.envOr("RECURRING_BUY_INTERVAL_SECONDS", uint256(60));
        uint256 deviationBps = vm.envOr("RECURRING_BUY_DEVIATION_BPS", uint256(10_000));
        uint256 maxPriceAge = vm.envOr("RECURRING_BUY_MAX_PRICE_AGE", uint256(7_200));
        // Five HBAR leaves room for at least two one-HBAR purchases plus HSS fees.
        uint256 fundWeibars = vm.envOr("RECURRING_BUY_FUND_WEIBARS", uint256(50 ether));

        vm.startBroadcast();
        uint256 associationCode = IHRC719(tokenOut).associate();
        if (associationCode != SUCCESS && associationCode != TOKEN_ALREADY_ASSOCIATED) {
            revert AssociationFailed(associationCode);
        }

        vault.configure(tokenOut, amountTinybars, intervalSeconds, deviationBps, maxPriceAge);
        vault.configureBonzo(address(0), false);
        vault.deposit{ value: fundWeibars }();
        (int64 responseCode,) = vault.start();
        if (responseCode != SUCCESS_RESPONSE) revert ScheduleCreationFailed(responseCode);
        vm.stopBroadcast();
    }
}
