// SPDX-License-Identifier: MIT
// Vendored from hedera-dev/scaffold-hbar, branch templates/payments-scheduler, commit
// 5bda7868322a2c7aab8cb681df01c756840bb464 (MIT, Copyright (c) 2023 BuidlGuidl, (c) 2026 hedera-dev).
// Imports are adjusted to this directory; the code is otherwise unchanged.

pragma solidity ^0.8.19;

/**
 * @title IHederaScheduleService
 * @notice Minimal interface for Hedera Schedule Service (HSS) system contract at 0x16b
 */
interface IHederaScheduleService {
    /**
     * @notice Schedule a contract call for future execution
     * @param to Target contract address
     * @param expirySecond Earliest execution time (consensus time) and expiration
     * @param gasLimit Gas limit for the scheduled call
     * @param value HBAR to send with the call (0 for DCA - vault has balance)
     * @param callData ABI-encoded function call
     * @return responseCode 22 = SUCCESS
     * @return scheduleAddress Address of the created schedule (address(0) on failure)
     */
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes memory callData)
        external
        returns (int64 responseCode, address scheduleAddress);

    /**
     * @notice Check if a second has capacity for scheduling
     * @param expirySecond The second to check
     * @param gasLimit Gas limit for the planned call
     */
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool hasCapacity);

    /**
     * @notice Delete a scheduled transaction
     */
    function deleteSchedule(address scheduleAddress) external returns (int64 responseCode);
}
