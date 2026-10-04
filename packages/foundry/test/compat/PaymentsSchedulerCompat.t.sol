// SPDX-License-Identifier: MIT
// Port of the HSS scenarios in hedera-dev/scaffold-hbar, branch templates/payments-scheduler,
// commit 5bda7868322a2c7aab8cb681df01c756840bb464, file packages/foundry/test/ScheduledVault.t.sol
// (MIT, Copyright (c) 2023 BuidlGuidl, (c) 2026 hedera-dev). Upstream etches a
// MockHederaScheduleService that only records the last call and lets the test call
// executeScheduled() directly. Here the unchanged upstream ScheduledVault runs against
// ForklabHss: schedules are created, paid for, executed by Forklab.warp as the vault,
// rescheduled, and deleted, and each assertion reads the resulting schedule record.
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { ScheduledVault } from "./upstream/ScheduledVault.sol";
import { MockExecutionStrategy } from "./upstream/MockExecutionStrategy.sol";

/// @notice Action target: records each call made by the vault.
contract CompatExecutionTarget {
    uint256 public executions;
    address public lastSender;

    function increment() external {
        executions++;
        lastSender = msg.sender;
    }
}

contract PaymentsSchedulerCompatTest is Test {
    int64 private constant SUCCESS = 22;
    uint256 private constant INTERVAL = 1 days;
    uint256 private constant UPSTREAM_GAS_LIMIT = 3_000_000;

    ScheduledVault private vault;
    MockExecutionStrategy private strategy;
    CompatExecutionTarget private target;
    address private owner = makeAddr("owner");
    bytes private validConfig = abi.encode(uint256(42));

    function setUp() public {
        Forklab.setUp();
        strategy = new MockExecutionStrategy();
        target = new CompatExecutionTarget();
        vault = new ScheduledVault(address(strategy), owner);
        // The vault is the HSS payer: it must hold the gas reservation for its 3,000,000 limit.
        vm.deal(address(vault), 100 * 100_000_000);
        strategy.pushAction(address(target), 0, abi.encodeCall(CompatExecutionTarget.increment, ()));
    }

    /// @notice Upstream test_scheduleNextRunCreatesSchedule: the record now comes from the emulator.
    function test_scheduleNextRunCreatesRealSchedule() external {
        _configureAndSchedule();
        Forklab.ScheduleInfo memory info = Forklab.schedule(vault.nextSchedule());
        assertEq(info.to, address(vault));
        assertEq(info.payer, address(vault));
        assertEq(info.gasLimit, UPSTREAM_GAS_LIMIT);
        assertEq(info.expiry, block.timestamp + INTERVAL);
        assertEq(info.data, abi.encodeCall(ScheduledVault.executeScheduled, ()));
    }

    /// @notice Upstream test_executeScheduledRunsActionsAndReschedules, executed by HSS at expiry.
    function test_scheduledRunExecutesActionsAndReschedules() external {
        _configureAndSchedule();
        address firstSchedule = vault.nextSchedule();

        assertEq(Forklab.warp(INTERVAL), 1);
        assertTrue(Forklab.schedule(firstSchedule).success);
        assertEq(target.executions(), 1);
        assertEq(target.lastSender(), address(vault));
        assertEq(vault.consecutiveFailures(), 0);

        address secondSchedule = vault.nextSchedule();
        assertNotEq(secondSchedule, firstSchedule);
        assertEq(Forklab.warp(INTERVAL), 1);
        assertTrue(Forklab.schedule(secondSchedule).success);
        assertEq(target.executions(), 2);
    }

    /// @notice Upstream test_cancelNextScheduleDeletesFromHSS: the schedule is really deleted.
    function test_cancelNextScheduleDeletesRealSchedule() external {
        _configureAndSchedule();
        address schedule = vault.nextSchedule();
        vm.prank(owner);
        vault.cancelNextSchedule();

        assertEq(vault.nextSchedule(), address(0));
        assertEq(Forklab.pending().length, 0);
        assertEq(Forklab.warp(INTERVAL), 0);
        assertEq(target.executions(), 0);
        assertEq(Forklab.schedule(schedule).executedAt, 0);
    }

    /// @notice Upstream test_configureCancelsPendingSchedule against the emulator.
    function test_configureCancelsRealPendingSchedule() external {
        _configureAndSchedule();
        vm.prank(owner);
        vault.configure(validConfig, 2 days);
        assertEq(vault.nextSchedule(), address(0));
        assertEq(Forklab.pending().length, 0);
    }

    /// @notice Upstream test_scheduleNextRunRevertsOnNoCapacity, with capacity actually exhausted.
    function test_scheduleNextRunRevertsWhenSecondIsFull() external {
        Forklab.setMaxSchedulesPerSecond(0);
        vm.startPrank(owner);
        vault.configure(validConfig, INTERVAL);
        vm.expectRevert(ScheduledVault.ScheduledVault__NoScheduleCapacity.selector);
        vault.scheduleNextRun();
        vm.stopPrank();
    }

    /// @notice Upstream test_executeScheduledEmitsPlanFailedOnRevert: the failed run still reschedules.
    function test_planFailureStillReschedules() external {
        strategy.setShouldRevertOnPlan(true, "strategy broke");
        _configureAndSchedule();
        address firstSchedule = vault.nextSchedule();

        vm.expectEmit(false, false, false, false, address(vault));
        emit ScheduledVault.PlanFailed("");
        assertEq(Forklab.warp(INTERVAL), 1);

        assertTrue(Forklab.schedule(firstSchedule).success);
        assertEq(vault.consecutiveFailures(), 1);
        assertNotEq(vault.nextSchedule(), firstSchedule);
        assertEq(Forklab.pending().length, 1);
    }

    /// @notice Upstream test_executeScheduledStopsReschedulingAfterMaxFailures. Upstream could not
    ///         observe the stop with its mock; here no schedule remains after the second failure.
    function test_maxFailuresStopsRealRescheduling() external {
        strategy.setShouldRevertOnPlan(true, "broken");
        vm.startPrank(owner);
        vault.configure(validConfig, INTERVAL);
        vault.setMaxConsecutiveFailures(2);
        vault.scheduleNextRun();
        vm.stopPrank();

        assertEq(Forklab.warp(INTERVAL), 1);
        assertEq(Forklab.pending().length, 1);

        vm.expectEmit(false, false, false, true, address(vault));
        emit ScheduledVault.MaxFailuresReached(2);
        assertEq(Forklab.warp(INTERVAL), 1);
        assertEq(vault.consecutiveFailures(), 2);
        assertEq(Forklab.pending().length, 0);
        assertEq(Forklab.warp(INTERVAL), 0);
    }

    /// @notice Upstream test_executeScheduledEmitsActionFailedOnBadCall, executed by HSS.
    function test_actionFailureIsRecordedAndReschedules() external {
        strategy.clearActions();
        uint256 tooMuch = address(vault).balance + 1;
        strategy.pushAction(address(0xdead), tooMuch, "");
        _configureAndSchedule();

        vm.expectEmit(true, true, false, false, address(vault));
        emit ScheduledVault.ActionFailed(0, address(0xdead), "");
        assertEq(Forklab.warp(INTERVAL), 1);
        assertEq(vault.consecutiveFailures(), 1);
        assertEq(Forklab.pending().length, 1);
    }

    /// @notice Not in upstream: an unfunded vault cannot pay for its scheduled run.
    function test_unfundedVaultRunRecordsPayerBalanceFailure() external {
        _configureAndSchedule();
        address schedule = vault.nextSchedule();
        vm.deal(address(vault), 0);
        assertEq(Forklab.warp(INTERVAL), 1);
        assertEq(Forklab.schedule(schedule).status, int64(10));
        assertEq(target.executions(), 0);
    }

    function _configureAndSchedule() private {
        vm.startPrank(owner);
        vault.configure(validConfig, INTERVAL);
        vault.scheduleNextRun();
        vm.stopPrank();
        assertNotEq(vault.nextSchedule(), address(0));
    }
}
