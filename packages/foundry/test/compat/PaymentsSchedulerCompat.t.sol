// SPDX-License-Identifier: MIT
// Adapted from hedera-dev/scaffold-hbar, templates/payments-scheduler.
// Original ScheduledVault and test: https://github.com/hedera-dev/scaffold-hbar/tree/templates/payments-scheduler
// Changes: the record-only MockHederaScheduleService is replaced by Forklab execution.
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../../contracts/forklab/Forklab.sol";
import { IHederaScheduleService } from "../../contracts/forklab/IHederaScheduleService.sol";

interface ICompatExecutionStrategy {
    struct Action {
        address target;
        uint256 value;
        bytes data;
    }

    function validateConfig(bytes calldata config) external view returns (bool);
    function plan(bytes calldata config) external view returns (Action[] memory actions);
}

/// @notice Payments-scheduler vault adapted only to the interfaces used by its execution scenario.
contract ScheduledVaultCompat {
    IHederaScheduleService private constant HSS = IHederaScheduleService(address(0x16b));
    uint256 private constant SCHEDULE_GAS_LIMIT = 3_000_000;
    int64 private constant HSS_SUCCESS = 22;

    address public immutable owner;
    ICompatExecutionStrategy public strategy;
    bytes public strategyConfig;
    uint256 public intervalSeconds;
    address public nextSchedule;

    error NotOwner();
    error InvalidConfig();
    error ScheduleFailed();

    constructor(address strategyAddress, address ownerAddress) {
        strategy = ICompatExecutionStrategy(strategyAddress);
        owner = ownerAddress;
    }

    function configure(bytes calldata config, uint256 interval) external {
        if (msg.sender != owner) revert NotOwner();
        if (interval == 0 || !strategy.validateConfig(config)) revert InvalidConfig();
        strategyConfig = config;
        intervalSeconds = interval;
    }

    function scheduleNextRun() external {
        if (msg.sender != owner) revert NotOwner();
        _schedule();
    }

    function executeScheduled() external {
        ICompatExecutionStrategy.Action[] memory actions = strategy.plan(strategyConfig);
        for (uint256 i; i < actions.length; i++) {
            (bool success,) = actions[i].target.call{ value: actions[i].value }(actions[i].data);
            require(success, "action failed");
        }
        _schedule();
    }

    function _schedule() private {
        uint256 expiry = block.timestamp + intervalSeconds;
        if (!HSS.hasScheduleCapacity(expiry, SCHEDULE_GAS_LIMIT)) revert ScheduleFailed();
        (int64 code, address scheduleAddress) =
            HSS.scheduleCall(address(this), expiry, SCHEDULE_GAS_LIMIT, 0, abi.encodeCall(this.executeScheduled, ()));
        if (code != HSS_SUCCESS || scheduleAddress == address(0)) revert ScheduleFailed();
        nextSchedule = scheduleAddress;
    }
}

contract CompatExecutionTarget {
    uint256 public executions;
    address public lastSender;

    function increment() external {
        executions++;
        lastSender = msg.sender;
    }
}

contract CompatExecutionStrategy is ICompatExecutionStrategy {
    function validateConfig(bytes calldata config) external pure returns (bool) {
        return config.length == 32;
    }

    function plan(bytes calldata config) external pure returns (Action[] memory actions) {
        address target = abi.decode(config, (address));
        actions = new Action[](1);
        actions[0] = Action({ target: target, value: 0, data: abi.encodeCall(CompatExecutionTarget.increment, ()) });
    }
}

contract PaymentsSchedulerCompatTest is Test {
    function setUp() public {
        Forklab.setUp();
    }

    /// @notice Upstream's mock records calls; this port runs and reschedules them.
    function test_scheduledVaultActionsReallyExecuteThroughForklab() external {
        address owner = makeAddr("owner");
        CompatExecutionTarget target = new CompatExecutionTarget();
        CompatExecutionStrategy strategy = new CompatExecutionStrategy();
        ScheduledVaultCompat vault = new ScheduledVaultCompat(address(strategy), owner);

        vm.startPrank(owner);
        vault.configure(abi.encode(address(target)), 1);
        vault.scheduleNextRun();
        vm.stopPrank();

        address firstSchedule = vault.nextSchedule();
        assertEq(Forklab.warp(1), 1);
        assertEq(target.executions(), 1);
        assertEq(target.lastSender(), address(vault));
        assertTrue(Forklab.schedule(firstSchedule).success);

        address secondSchedule = vault.nextSchedule();
        assertNotEq(secondSchedule, firstSchedule);
        assertEq(Forklab.warp(1), 1);
        assertEq(target.executions(), 2);
        assertTrue(Forklab.schedule(secondSchedule).success);
    }
}
