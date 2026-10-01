// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
    function revertWith(uint256 marker) external pure {
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

/// @notice Fixture that reaches the schedule emulator through delegatecall.
contract ForklabDelegateCaller {
    /// @notice Calls the emulator code using delegatecall.
    /// @param callData The encoded schedule call.
    /// @return result The emulator response bytes.
    function scheduleThroughDelegate(bytes calldata callData) external returns (bytes memory result) {
        (bool success, bytes memory response) = address(0x16b).delegatecall(callData);
        if (!success) {
            assembly {
                revert(add(response, 0x20), mload(response))
            }
        }
        return response;
    }
}
