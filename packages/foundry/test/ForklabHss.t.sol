// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../contracts/forklab/Forklab.sol";
import { ForklabScheduleTarget, ForklabDelegateCaller } from "../contracts/forklab/ForklabFixtures.sol";
import { IHederaScheduleService } from "../contracts/forklab/IHederaScheduleService.sol";

/// @notice Offline behavioural tests for the local schedule emulator.
contract ForklabHssTest is Test {
    IHederaScheduleService private constant HSS = IHederaScheduleService(address(0x16b));
    int64 private constant SUCCESS = 22;
    int64 private constant INVALID_CONTRACT_ID = 16;
    int64 private constant EXPIRY_NOT_IN_FUTURE = 307;
    int64 private constant EXPIRY_TOO_FAR = 306;
    int64 private constant EXPIRY_BUSY = 370;
    int64 private constant INVALID_SCHEDULE_ID = 201;
    int64 private constant SCHEDULE_ALREADY_EXECUTED = 213;
    int64 private constant INVALID_SIGNATURE = 7;
    int64 private constant INSUFFICIENT_PAYER_BALANCE = 10;
    int64 private constant UNAUTHORIZED = 157;
    uint64 private constant ONE_HBAR_TINYBARS = 100_000_000;

    ForklabScheduleTarget private target;

    function setUp() public {
        Forklab.setUp();
        target = new ForklabScheduleTarget();
        vm.deal(address(this), 10 ether);
    }

    function test_scheduleExecutesWithPayerSender() public {
        uint256 expiry = block.timestamp + 10;
        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (11));
        vm.expectEmit(false, true, true, true, address(0x16b));
        emit ScheduleCreated(address(0), address(this), address(target), expiry, 200_000, 0, callData);
        (int64 responseCode, address scheduleAddress) = HSS.scheduleCall(address(target), expiry, 200_000, 0, callData);

        assertEq(responseCode, SUCCESS);
        assertEq(Forklab.pending().length, 1);
        assertEq(Forklab.warp(10), 1);
        assertEq(target.lastSender(), address(this));
        assertEq(target.lastValue(), 0);
        assertEq(target.markerAt(0), 11);
        assertTrue(Forklab.schedule(scheduleAddress).success);
    }

    function test_valueTransfersAndInsufficientPayerIsRecorded() public {
        uint256 value = ONE_HBAR_TINYBARS;
        uint256 expiry = block.timestamp + 1;
        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (12));
        (, address successfulSchedule) = HSS.scheduleCall(address(target), expiry, 200_000, ONE_HBAR_TINYBARS, callData);
        uint256 targetBefore = address(target).balance;
        assertEq(Forklab.warp(1), 1);
        assertEq(address(target).balance, targetBefore + value);
        assertEq(target.lastValue(), value);
        assertEq(Forklab.schedule(successfulSchedule).status, SUCCESS);

        (, address failedSchedule) =
            HSS.scheduleCall(address(target), block.timestamp + 1, 200_000, ONE_HBAR_TINYBARS, callData);
        vm.deal(address(this), 0);
        assertEq(Forklab.warp(1), 1);
        Forklab.ScheduleInfo memory info = Forklab.schedule(failedSchedule);
        assertEq(info.status, INSUFFICIENT_PAYER_BALANCE);
        assertFalse(info.success);
        assertEq(target.callCount(), 1);
    }

    function test_targetFailureAndOutOfGasAreCaptured() public {
        bytes memory revertData = abi.encodeCall(ForklabScheduleTarget.revertWith, (99));
        (, address revertingSchedule) = HSS.scheduleCall(address(target), block.timestamp + 1, 200_000, 0, revertData);
        assertEq(Forklab.warp(1), 1);
        Forklab.ScheduleInfo memory reverted = Forklab.schedule(revertingSchedule);
        assertFalse(reverted.success);
        assertEq(reverted.returnData, abi.encodeWithSelector(ForklabScheduleTarget.TargetReverted.selector, 99));

        bytes memory gasData = abi.encodeCall(ForklabScheduleTarget.burnGas, ());
        (, address gasSchedule) = HSS.scheduleCall(address(target), block.timestamp + 1, 20_000, 0, gasData);
        assertEq(Forklab.warp(1), 1);
        assertFalse(Forklab.schedule(gasSchedule).success);
    }

    function test_responseCodesAndCapacityAgree() public {
        (int64 invalidTarget,) = HSS.scheduleCall(address(0), block.timestamp + 1, 1, 0, bytes(""));
        assertEq(invalidTarget, INVALID_CONTRACT_ID);
        (int64 pastExpiry,) = HSS.scheduleCall(address(target), block.timestamp, 1, 0, bytes(""));
        assertEq(pastExpiry, EXPIRY_NOT_IN_FUTURE);
        (int64 farExpiry,) = HSS.scheduleCall(address(target), block.timestamp + 5_356_801, 1, 0, bytes(""));
        assertEq(farExpiry, EXPIRY_TOO_FAR);

        Forklab.setMaxSchedulesPerSecond(2);
        Forklab.setMaxGasPerSecond(100);
        uint256 expiry = block.timestamp + 10;
        assertTrue(HSS.hasScheduleCapacity(expiry, 50));
        HSS.scheduleCall(address(target), expiry, 50, 0, bytes(""));
        assertTrue(HSS.hasScheduleCapacity(expiry, 50));
        HSS.scheduleCall(address(target), expiry, 50, 0, bytes(""));
        assertFalse(HSS.hasScheduleCapacity(expiry, 1));
        (int64 busy,) = HSS.scheduleCall(address(target), expiry, 1, 0, bytes(""));
        assertEq(busy, EXPIRY_BUSY);
    }

    function test_deleteCreatorStrangerRedirectAndExecuted() public {
        uint256 expiry = block.timestamp + 10;
        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (1));
        (, address first) = HSS.scheduleCall(address(target), expiry, 100_000, 0, callData);
        int64 creatorCode = HSS.deleteSchedule(first);
        assertEq(creatorCode, SUCCESS);

        (, address second) = HSS.scheduleCall(address(target), expiry, 100_000, 0, callData);
        ForklabDelegateCaller stranger = new ForklabDelegateCaller();
        vm.prank(address(stranger));
        int64 unauthorizedCode = HSS.deleteSchedule(second);
        assertEq(unauthorizedCode, UNAUTHORIZED);

        int64 redirectedCode = IHederaScheduleService(second).deleteSchedule();
        assertEq(redirectedCode, SUCCESS);

        (, address third) = HSS.scheduleCall(address(target), block.timestamp + 1, 100_000, 0, callData);
        assertEq(Forklab.warp(1), 1);
        (int64 executedCode) = HSS.deleteSchedule(third);
        assertEq(executedCode, SCHEDULE_ALREADY_EXECUTED);
        int64 unknownCode = HSS.deleteSchedule(address(uint160(0xf0000011)));
        assertEq(unknownCode, INVALID_SCHEDULE_ID);
    }

    function test_signatureExecutionAndExpiry() public {
        uint256 expiry = block.timestamp + 100;
        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (7));
        (, address signedSchedule) =
            HSS.executeCallOnPayerSignature(address(target), address(this), expiry, 200_000, 0, callData);
        Forklab.signAsPayer(signedSchedule);
        assertEq(target.lastSender(), address(this));
        assertEq(Forklab.schedule(signedSchedule).executedAt, expiry);

        (, address unsignedSchedule) =
            HSS.scheduleCallWithPayer(address(target), address(this), block.timestamp + 1, 200_000, 0, callData);
        assertEq(Forklab.warp(1), 1);
        assertEq(Forklab.schedule(unsignedSchedule).status, INVALID_SIGNATURE);

        (, address lateSchedule) =
            HSS.executeCallOnPayerSignature(address(target), address(this), block.timestamp + 1, 200_000, 0, callData);
        assertEq(Forklab.warp(1), 1);
        Forklab.signAsPayer(lateSchedule);
        assertEq(Forklab.schedule(lateSchedule).status, INVALID_SIGNATURE);
    }

    function test_executionCapAndCreationOrdering() public {
        Forklab.setMaxExecutionsPerRun(2);
        uint256 expiry = block.timestamp + 1;
        bytes memory first = abi.encodeCall(ForklabScheduleTarget.record, (1));
        bytes memory second = abi.encodeCall(ForklabScheduleTarget.record, (2));
        bytes memory third = abi.encodeCall(ForklabScheduleTarget.record, (3));
        HSS.scheduleCall(address(target), expiry, 200_000, 0, first);
        HSS.scheduleCall(address(target), expiry, 200_000, 0, second);
        HSS.scheduleCall(address(target), expiry, 200_000, 0, third);
        assertEq(Forklab.warp(1), 2);
        assertEq(target.markerAt(0), 1);
        assertEq(target.markerAt(1), 2);
        assertEq(Forklab.pending().length, 1);
        assertEq(Forklab.runDue(), 1);
        assertEq(target.markerAt(2), 3);
        Forklab.setMaxExecutionsPerRun(100);
    }

    function test_delegatecallRuleCanBeDisabled() public {
        ForklabDelegateCaller caller = new ForklabDelegateCaller();
        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (44));
        bytes memory payload =
            abi.encodeCall(HSS.scheduleCall, (address(target), block.timestamp + 1, 200_000, 0, callData));
        bytes memory strictResult = caller.scheduleThroughDelegate(payload);
        (int64 strictCode,) = abi.decode(strictResult, (int64, address));
        assertEq(strictCode, INVALID_SIGNATURE);

        Forklab.strictDelegatecallRule(false);
        vm.deal(address(caller), 1 ether);
        bytes memory allowedResult = caller.scheduleThroughDelegate(payload);
        (int64 allowedCode, address scheduleAddress) = abi.decode(allowedResult, (int64, address));
        assertEq(allowedCode, SUCCESS);
        assertNotEq(scheduleAddress, address(0));
        assertEq(Forklab.warp(1), 1);
        Forklab.strictDelegatecallRule(true);
    }

    function testFuzz_scheduleInputsDoNotRevert(uint64 secondsForward, uint256 gasLimit) public {
        uint256 expiry = block.timestamp + (uint256(secondsForward) % 5_356_802);
        HSS.scheduleCall(address(target), expiry, gasLimit, 0, bytes(""));
    }

    event ScheduleCreated(
        address indexed schedule,
        address indexed payer,
        address indexed to,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes callData
    );
}
