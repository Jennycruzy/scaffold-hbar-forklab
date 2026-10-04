// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IHederaScheduleService } from "./IHederaScheduleService.sol";

/// @notice Small in-process target used only by the Forklab emulator tests.
contract ForklabScheduleTarget {
    /// @notice Error used to test captured revert data.
    error TargetReverted(uint256 marker);

    /// @notice The most recent caller observed by the target.
    address public lastSender;
    /// @notice The most recent msg.value observed by the target.
    uint256 public lastValue;
    /// @notice Number of successful record calls.
    uint256 public callCount;
    /// @notice Ordered markers from successful calls.
    uint256[] private _markers;

    /// @notice Records the payer and value of a scheduled call.
    /// @param marker The marker to append to the call order.
    function record(uint256 marker) external payable {
        lastSender = msg.sender;
        lastValue = msg.value;
        callCount++;
        _markers.push(marker);
    }

    /// @notice Reverts with a typed error for return-data assertions.
    /// @param marker The error marker.
    function revertWith(uint256 marker) external payable {
        revert TargetReverted(marker);
    }

    /// @notice Consumes its entire call budget.
    function burnGas() external pure {
        assembly {
            for { } 1 { } { }
        }
    }

    /// @notice Reads one marker from the successful call order.
    /// @param index The zero-based marker index.
    /// @return marker The recorded marker.
    function markerAt(uint256 index) external view returns (uint256 marker) {
        return _markers[index];
    }
}

/// @notice Implementation called through a proxy before making a normal HSS call.
contract ForklabDelegateSchedulerImplementation {
    /// @notice Creates a schedule while executing in the proxy's delegated frame.
    function schedule(address to, uint256 expiry, uint256 gasLimit, bytes calldata callData)
        external
        returns (int64 responseCode, address scheduleAddress)
    {
        return IHederaScheduleService(address(0x16b)).scheduleCall(to, expiry, gasLimit, 0, callData);
    }
}

/// @notice Minimal proxy fixture for the delegatecall-then-call pattern.
contract ForklabDelegateSchedulerProxy {
    address private immutable _IMPLEMENTATION;

    constructor(address implementation) {
        _IMPLEMENTATION = implementation;
    }

    fallback() external payable {
        (bool success, bytes memory response) = _IMPLEMENTATION.delegatecall(msg.data);
        if (!success) {
            assembly {
                revert(add(response, 0x20), mload(response))
            }
        }
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}

/// @notice Target that schedules itself until exactly five executions complete.
contract ForklabRecursiveScheduler {
    uint256 public callCount;

    function start() external returns (int64 responseCode, address scheduleAddress) {
        return _scheduleNext();
    }

    function tick() external {
        callCount++;
        if (callCount < 5) _scheduleNext();
    }

    function _scheduleNext() private returns (int64 responseCode, address scheduleAddress) {
        return IHederaScheduleService(address(0x16b))
            .scheduleCall(address(this), block.timestamp + 1, 2_000_000, 0, abi.encodeCall(this.tick, ()));
    }
}
