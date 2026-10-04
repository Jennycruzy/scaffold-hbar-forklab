// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// This file is the README's "Write your first scheduled-call test" sample, kept
// as a real test so the documented code always compiles and passes.

import { Test } from "forge-std/Test.sol";
import { Forklab } from "../contracts/forklab/Forklab.sol";
import { IHederaScheduleService } from "../contracts/forklab/IHederaScheduleService.sol";

contract Counter {
    uint256 public value;

    function increment() external {
        value++;
    }
}

contract FirstScheduledCallTest is Test {
    function test_scheduledCallRuns() external {
        Forklab.setUp();
        Counter counter = new Counter();
        // This test contract is the payer, so it must hold HBAR for gas at the limit.
        vm.deal(address(this), 100_000_000);

        (int64 code, address id) = IHederaScheduleService(address(0x16b))
            .scheduleCall(address(counter), block.timestamp + 60, 100_000, 0, abi.encodeCall(Counter.increment, ()));

        assertEq(code, 22);
        assertTrue(id != address(0));
        assertEq(Forklab.warp(60), 1);
        assertEq(counter.value(), 1);
    }
}
