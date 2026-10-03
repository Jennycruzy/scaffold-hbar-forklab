// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../contracts/forklab/Forklab.sol";
import {
    ForklabScheduleTarget,
    ForklabDelegateSchedulerImplementation,
    ForklabDelegateSchedulerProxy,
    ForklabRecursiveScheduler
} from "../contracts/forklab/ForklabFixtures.sol";
import { IHederaScheduleService } from "../contracts/forklab/IHederaScheduleService.sol";
import { ForklabHss } from "../contracts/forklab/ForklabHss.sol";

/// @notice Offline behavioural tests for the local schedule emulator.
contract ForklabHssTest is Test {
    IHederaScheduleService private constant HSS = IHederaScheduleService(address(0x16b));
    int64 private constant SUCCESS = 22;
    int64 private constant INVALID_CONTRACT_ID = 16;
    int64 private constant EXPIRY_NOT_IN_FUTURE = 307;
    int64 private constant EXPIRY_TOO_FAR = 306;
    int64 private constant EXPIRY_BUSY = 370;
    int64 private constant INVALID_SCHEDULE_ID = 201;
    int64 private constant SCHEDULE_ALREADY_DELETED = 212;
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
        Forklab.setScheduleFeeTinybars(100);
        uint256 payerBefore = address(this).balance;
        uint256 hssBefore = address(0x16b).balance;
        bytes memory revertData = abi.encodeCall(ForklabScheduleTarget.revertWith, (99));
        (, address revertingSchedule) = HSS.scheduleCall(address(target), block.timestamp + 1, 200_000, 50, revertData);
        vm.expectEmit(true, false, false, false, address(0x16b));
        emit ScheduleExecuted(revertingSchedule, false, bytes(""));
        assertEq(Forklab.warp(1), 1);
        Forklab.ScheduleInfo memory reverted = Forklab.schedule(revertingSchedule);
        assertFalse(reverted.success);
        assertEq(reverted.returnData, abi.encodeWithSelector(ForklabScheduleTarget.TargetReverted.selector, 99));
        assertEq(address(this).balance, payerBefore - 100);
        assertEq(address(0x16b).balance, hssBefore + 100);

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
        assertTrue(HSS.hasScheduleCapacity(block.timestamp + 5_356_800, 1));
        assertFalse(HSS.hasScheduleCapacity(block.timestamp + 5_356_801, 1));

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
        vm.expectEmit(true, false, false, true, address(0x16b));
        emit ScheduleDeleted(first);
        int64 creatorCode = HSS.deleteSchedule(first);
        assertEq(creatorCode, SUCCESS);
        assertEq(HSS.deleteSchedule(first), SCHEDULE_ALREADY_DELETED);

        (, address second) = HSS.scheduleCall(address(target), expiry, 100_000, 0, callData);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        int64 unauthorizedCode = HSS.deleteSchedule(second);
        assertEq(unauthorizedCode, UNAUTHORIZED);

        vm.prank(stranger);
        int64 unauthorizedRedirectCode = IHederaScheduleService(second).deleteSchedule();
        assertEq(unauthorizedRedirectCode, UNAUTHORIZED);

        vm.expectEmit(true, false, false, true, address(0x16b));
        emit ScheduleDeleted(second);
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
        vm.expectEmit(true, false, false, true, address(0x16b));
        emit ScheduleExpired(unsignedSchedule);
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

    function test_sameSecondSchedulesExecuteInCreationOrder() public {
        uint256 expiry = block.timestamp + 1;
        HSS.scheduleCall(address(target), expiry, 200_000, 0, abi.encodeCall(target.record, (10)));
        HSS.scheduleCall(address(target), expiry, 200_000, 0, abi.encodeCall(target.record, (20)));
        HSS.scheduleCall(address(target), expiry, 200_000, 0, abi.encodeCall(target.record, (30)));
        assertEq(Forklab.warp(1), 3);
        assertEq(target.markerAt(0), 10);
        assertEq(target.markerAt(1), 20);
        assertEq(target.markerAt(2), 30);
    }

    function test_lateExecutionRecordsCurrentTimestamp() public {
        (, address scheduleAddress) = HSS.scheduleCall(
            address(target), block.timestamp + 1, 200_000, 0, abi.encodeCall(ForklabScheduleTarget.record, (55))
        );
        uint256 lateTimestamp = block.timestamp + 100;
        assertEq(Forklab.warpTo(lateTimestamp), 1);
        assertEq(Forklab.schedule(scheduleAddress).executedAt, lateTimestamp);
    }

    function test_externalRunnerRecordsObservedPayerExecution() public {
        uint256 expiry = block.timestamp + 10;
        (, address scheduleAddress) =
            HSS.scheduleCall(address(target), expiry, 100_000, 0, abi.encodeCall(ForklabScheduleTarget.record, (77)));

        vm.warp(expiry);
        target.record(77);
        vm.expectEmit(true, false, false, true, address(0x16b));
        emit ScheduleExecuted(scheduleAddress, true, bytes(""));
        assertEq(ForklabHss(address(0x16b)).recordExternalExecution(scheduleAddress, true, bytes("")), SUCCESS);

        Forklab.ScheduleInfo memory info = Forklab.schedule(scheduleAddress);
        assertTrue(info.success);
        assertEq(info.executedAt, expiry);
        assertEq(target.markerAt(0), 77);
        assertEq(Forklab.pending().length, 0);
    }

    function test_externalRunnerRejectsStrangerAndEarlySettlement() public {
        uint256 expiry = block.timestamp + 10;
        (, address scheduleAddress) =
            HSS.scheduleCall(address(target), expiry, 100_000, 0, abi.encodeCall(ForklabScheduleTarget.record, (78)));

        assertEq(
            ForklabHss(address(0x16b)).recordExternalExecution(scheduleAddress, true, bytes("")), EXPIRY_NOT_IN_FUTURE
        );
        vm.warp(expiry);
        vm.prank(makeAddr("stranger"));
        assertEq(ForklabHss(address(0x16b)).recordExternalExecution(scheduleAddress, true, bytes("")), UNAUTHORIZED);
        assertEq(Forklab.pending().length, 1);
    }

    function test_contractReschedulesItselfFiveTimesThenStops() public {
        ForklabRecursiveScheduler recursive = new ForklabRecursiveScheduler();
        (int64 code,) = recursive.start();
        assertEq(code, SUCCESS);
        for (uint256 i; i < 5; i++) {
            assertEq(Forklab.warp(1), 1);
        }
        assertEq(recursive.callCount(), 5);
        assertEq(Forklab.pending().length, 0);
    }

    function test_delegatecallScheduleCreatesThenFailsAtExecutionAndRuleCanBeDisabled() public {
        ForklabDelegateSchedulerImplementation implementation = new ForklabDelegateSchedulerImplementation();
        ForklabDelegateSchedulerProxy proxy = new ForklabDelegateSchedulerProxy(address(implementation));
        ForklabDelegateSchedulerImplementation scheduler = ForklabDelegateSchedulerImplementation(address(proxy));
        Forklab.markDelegateScheduler(address(proxy), true);

        bytes memory callData = abi.encodeCall(ForklabScheduleTarget.record, (44));
        (int64 strictCode, address rejectedAtExecution) =
            scheduler.schedule(address(target), block.timestamp + 1, 200_000, callData);
        assertEq(strictCode, SUCCESS);
        assertNotEq(rejectedAtExecution, address(0));
        assertEq(Forklab.warp(1), 1);
        assertEq(Forklab.schedule(rejectedAtExecution).status, INVALID_SIGNATURE);
        assertFalse(Forklab.schedule(rejectedAtExecution).success);
        assertEq(target.callCount(), 0);

        Forklab.strictDelegatecallRule(false);
        (int64 allowedCode, address scheduleAddress) =
            scheduler.schedule(address(target), block.timestamp + 1, 200_000, callData);
        assertEq(allowedCode, SUCCESS);
        assertNotEq(scheduleAddress, address(0));
        assertEq(Forklab.warp(1), 1);
        assertTrue(Forklab.schedule(scheduleAddress).success);
        assertEq(target.callCount(), 1);
        assertEq(target.lastSender(), address(proxy));
        Forklab.strictDelegatecallRule(true);
    }

    function testFuzz_scheduleInputsDoNotRevert(uint256 expiryOffsetSeed, uint256 gasLimitSeed) public {
        uint256 expiryOffset = expiryOffsetSeed % 5_356_802;
        uint256 gasLimit = gasLimitSeed % 15_000_002;
        (int64 code,) = HSS.scheduleCall(address(target), block.timestamp + expiryOffset, gasLimit, 0, bytes(""));
        assertTrue(code == SUCCESS || code == EXPIRY_NOT_IN_FUTURE || code == EXPIRY_TOO_FAR || code == EXPIRY_BUSY);
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
    event ScheduleExecuted(address indexed schedule, bool success, bytes returnData);
    event ScheduleDeleted(address indexed schedule);
    event ScheduleExpired(address indexed schedule);
}
