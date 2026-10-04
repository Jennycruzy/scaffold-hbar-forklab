// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IHederaScheduleService } from "../forklab/IHederaScheduleService.sol";

/// @title HssProbe
/// @notice Records what live Hedera returns for schedule-service and token edge cases, so the
///         emulator's answers can be checked against the network. Used by `yarn foundry:testnet:probe`.
/// @dev Each probe stores the raw response code instead of reverting, because the schedule service
///      reports failures through response codes, not reverts.
contract HssProbe {
    IHederaScheduleService private constant HSS = IHederaScheduleService(address(0x16b));

    /// @notice Number of times a schedule has called `ping`.
    uint256 public pings;
    /// @notice Response code and schedule address from the last schedule creation.
    int64 public lastCreateCode;
    address public lastSchedule;
    /// @notice Response code from the last `deleteOther` call.
    int64 public lastDeleteCode;
    /// @notice Low-level result of the last `approveToken` call.
    bool public lastApproveSuccess;
    bytes public lastApproveReturn;

    event Probed(string probe, int64 responseCode, address schedule);

    receive() external payable { }

    /// @notice Target for scheduled calls.
    function ping() external {
        pings++;
    }

    /// @notice Schedules `ping()` on this contract, paid by this contract.
    function scheduleSelf(uint256 expirySecond, uint256 gasLimit) external {
        (int64 code, address schedule) =
            HSS.scheduleCall(address(this), expirySecond, gasLimit, 0, abi.encodeCall(this.ping, ()));
        lastCreateCode = code;
        lastSchedule = schedule;
        emit Probed("scheduleSelf", code, schedule);
    }

    /// @notice Schedules `ping()` with an external payer whose signature is never given.
    function scheduleWithPayer(address payer, uint256 expirySecond, uint256 gasLimit) external {
        (int64 code, address schedule) =
            HSS.scheduleCallWithPayer(address(this), payer, expirySecond, gasLimit, 0, abi.encodeCall(this.ping, ()));
        lastCreateCode = code;
        lastSchedule = schedule;
        emit Probed("scheduleWithPayer", code, schedule);
    }

    /// @notice Tries to delete a schedule created by another contract.
    function deleteOther(address schedule) external {
        int64 code = HSS.deleteSchedule(schedule);
        lastDeleteCode = code;
        emit Probed("deleteOther", code, schedule);
    }

    /// @notice Calls `approve` on an HTS token from this contract, which is not associated with it.
    function approveToken(address token, address spender, uint256 amount) external {
        (bool success, bytes memory ret) =
            token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        lastApproveSuccess = success;
        lastApproveReturn = ret;
        emit Probed("approveToken", success ? int64(1) : int64(0), token);
    }
}
