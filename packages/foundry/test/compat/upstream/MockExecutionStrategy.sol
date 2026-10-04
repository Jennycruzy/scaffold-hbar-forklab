// SPDX-License-Identifier: MIT
// Vendored from hedera-dev/scaffold-hbar, branch templates/payments-scheduler, commit
// 5bda7868322a2c7aab8cb681df01c756840bb464 (MIT, Copyright (c) 2023 BuidlGuidl, (c) 2026 hedera-dev).
// Imports are adjusted to this directory; the code is otherwise unchanged.
pragma solidity ^0.8.19;

import { IExecutionStrategy } from "./IExecutionStrategy.sol";

/**
 * @dev Configurable mock for vault-level tests. By default plan() returns an empty
 *      action list (no-op execution). Tests can push actions, force reverts, or
 *      toggle validateConfig behaviour.
 */
contract MockExecutionStrategy is IExecutionStrategy {
    Action[] internal _actions;
    bool public shouldRevertOnPlan;
    string public planRevertMessage;
    bool public configValid = true;

    function setConfigValid(bool valid) external {
        configValid = valid;
    }

    function setShouldRevertOnPlan(bool revert_, string calldata message) external {
        shouldRevertOnPlan = revert_;
        planRevertMessage = message;
    }

    function pushAction(address target, uint256 value, bytes calldata data) external {
        _actions.push(Action({ target: target, value: value, data: data }));
    }

    function clearActions() external {
        delete _actions;
    }

    function plan(bytes calldata) external view override returns (Action[] memory) {
        if (shouldRevertOnPlan) {
            revert(planRevertMessage);
        }
        Action[] memory out = new Action[](_actions.length);
        for (uint256 i = 0; i < _actions.length; i++) {
            out[i] = _actions[i];
        }
        return out;
    }

    function validateConfig(bytes calldata) external view override returns (bool) {
        return configValid;
    }
}
