// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

/// @notice HIP-1215 interface implemented by the local Hedera Schedule Service emulator.
interface IHederaScheduleService {
    /// @notice Creates a schedule whose payer is the calling contract.
    /// @param to The contract or account that receives the scheduled call.
    /// @param expirySecond The consensus second at which the call becomes eligible.
    /// @param gasLimit The gas forwarded to the scheduled call.
    /// @param value The tinybars forwarded to the target.
    /// @param callData The calldata sent to the target.
    /// @return responseCode A Hedera response code.
    /// @return scheduleAddress The long-zero address assigned to the schedule.
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata callData)
        external
        returns (int64 responseCode, address scheduleAddress);

    /// @notice Creates a schedule that waits for the nominated payer's signature.
    /// @param to The contract or account that receives the scheduled call.
    /// @param payer The account whose signature authorizes execution.
    /// @param expirySecond The consensus second at which the call becomes eligible.
    /// @param gasLimit The gas forwarded to the scheduled call.
    /// @param value The tinybars forwarded to the target.
    /// @param callData The calldata sent to the target.
    /// @return responseCode A Hedera response code.
    /// @return scheduleAddress The long-zero address assigned to the schedule.
    function scheduleCallWithPayer(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes calldata callData
    ) external returns (int64 responseCode, address scheduleAddress);

    /// @notice Creates a schedule that executes when the payer signs before expiry.
    /// @param to The contract or account that receives the scheduled call.
    /// @param payer The account whose signature authorizes execution.
    /// @param expirySecond The final second at which the signature is accepted.
    /// @param gasLimit The gas forwarded to the scheduled call.
    /// @param value The tinybars forwarded to the target.
    /// @param callData The calldata sent to the target.
    /// @return responseCode A Hedera response code.
    /// @return scheduleAddress The long-zero address assigned to the schedule.
    function executeCallOnPayerSignature(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes calldata callData
    ) external returns (int64 responseCode, address scheduleAddress);

    /// @notice Deletes a schedule when called by its creator.
    /// @param scheduleAddress The schedule to delete.
    /// @return responseCode A Hedera response code.
    function deleteSchedule(address scheduleAddress) external returns (int64 responseCode);

    /// @notice Deletes the schedule represented by the current schedule address.
    /// @return responseCode A Hedera response code.
    function deleteSchedule() external returns (int64 responseCode);

    /// @notice Reports whether a schedule with these parameters fits the configured limits.
    /// @param expirySecond The requested consensus second.
    /// @param gasLimit The requested gas limit.
    /// @return available True when the next schedule can be created.
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool available);
}
