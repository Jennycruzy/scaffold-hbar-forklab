// SPDX-License-Identifier: MIT
// Vendored from hedera-dev/scaffold-hbar, branch templates/payments-scheduler, commit
// 5bda7868322a2c7aab8cb681df01c756840bb464 (MIT, Copyright (c) 2023 BuidlGuidl, (c) 2026 hedera-dev).
// Imports are adjusted to this directory; the code is otherwise unchanged.

pragma solidity ^0.8.19;

/**
 * @title IExecutionStrategy
 * @notice Plugin interface for ScheduledVault execution strategies.
 *         Strategies are pure planners: they return a list of low-level calls
 *         that the vault executes as msg.sender, keeping full fund custody.
 */
interface IExecutionStrategy {
    struct Action {
        address target;
        uint256 value;
        bytes data;
    }

    /// @notice Compute the ordered list of calls the vault should execute.
    /// @param config ABI-encoded strategy-specific configuration
    /// @return actions Ordered array of calls for the vault to execute
    function plan(bytes calldata config) external view returns (Action[] memory actions);

    /// @notice Check whether `config` is well-formed for this strategy.
    /// @param config ABI-encoded strategy-specific configuration
    function validateConfig(bytes calldata config) external view returns (bool);
}
