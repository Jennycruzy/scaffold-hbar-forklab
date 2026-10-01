// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { ForklabHss } from "./ForklabHss.sol";
import { ForklabHts } from "./ForklabHts.sol";
import { ForklabMirrorNode } from "./ForklabMirrorNode.sol";
import { MirrorNode } from "hedera-forking/MirrorNode.sol";
import { HTS_ADDRESS } from "hedera-forking/HtsSystemContract.sol";

/// @notice Test helpers for real Hedera forks and the local schedule emulator.
library Forklab {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address internal constant HSS_ADDRESS = 0x000000000000000000000000000000000000016B;

    /// @notice A copyable view of one scheduled call.
    struct ScheduleInfo {
        address to;
        address payer;
        uint256 expiry;
        uint256 gasLimit;
        uint64 value;
        bytes data;
        int64 status;
        bool success;
        bytes returnData;
        uint256 createdAt;
        uint256 executedAt;
    }

    /// @notice Installs ForklabHts at 0x167 and ForklabHss at 0x16b.
    function setUp() internal {
        ForklabMirrorNode mirrorNode = new ForklabMirrorNode();
        _deployCodeTo("out/ForklabHts.sol/ForklabHts.json", HTS_ADDRESS);
        ForklabHts(HTS_ADDRESS).setMirrorNodeProvider(MirrorNode(address(mirrorNode)));
        ForklabHts(HTS_ADDRESS).setForklabMirrorNode(MirrorNode(address(mirrorNode)));
        VM.allowCheatcodes(HTS_ADDRESS);
        VM.allowCheatcodes(address(mirrorNode));

        _deployCodeTo("out/ForklabHss.sol/ForklabHss.json", HSS_ADDRESS);
        VM.allowCheatcodes(HSS_ADDRESS);
    }

    /// @notice Re-etches HIP-719 code over declared EIP-7702-style HTS tokens.
    /// @param tokens The token addresses used by a test.
    function useTokens(address[] memory tokens) internal {
        for (uint256 i; i < tokens.length; i++) {
            ForklabHts(HTS_ADDRESS).ensureHip719Proxy(tokens[i]);
            ForklabHts(HTS_ADDRESS).repairProtobufSupplyKey(tokens[i]);
        }
    }

    /// @notice Advances time and executes all schedules that become eligible.
    /// @param secondsForward The number of seconds to advance.
    /// @return executed The number of terminal schedules processed.
    function warp(uint256 secondsForward) internal returns (uint256 executed) {
        VM.warp(block.timestamp + secondsForward);
        return runDue();
    }

    /// @notice Sets the emulator clock and executes eligible schedules.
    /// @param timestamp The new consensus timestamp.
    /// @return executed The number of terminal schedules processed.
    function warpTo(uint256 timestamp) internal returns (uint256 executed) {
        VM.warp(timestamp);
        return runDue();
    }

    /// @notice Executes all eligible schedules in creation order.
    /// @return executed The number of schedules processed.
    function runDue() internal returns (uint256 executed) {
        return ForklabHss(HSS_ADDRESS).runDue();
    }

    /// @notice Marks a payer signature and runs its signature-triggered schedule.
    /// @param scheduleAddress The schedule being signed.
    function signAsPayer(address scheduleAddress) internal {
        ForklabHss(HSS_ADDRESS).signAsPayer(scheduleAddress);
    }

    /// @notice Returns the emulator record for a schedule.
    /// @param scheduleAddress The schedule address.
    /// @return info The recorded schedule information.
    function schedule(address scheduleAddress) internal view returns (ScheduleInfo memory info) {
        ForklabHss.ScheduleInfo memory remote = ForklabHss(HSS_ADDRESS).schedule(scheduleAddress);
        info.to = remote.to;
        info.payer = remote.payer;
        info.expiry = remote.expiry;
        info.gasLimit = remote.gasLimit;
        info.value = remote.value;
        info.data = remote.data;
        info.status = remote.status;
        info.success = remote.success;
        info.returnData = remote.returnData;
        info.createdAt = remote.createdAt;
        info.executedAt = remote.executedAt;
    }

    /// @notice Returns all schedules that have not reached a terminal state.
    /// @return schedules The pending schedule addresses.
    function pending() internal view returns (address[] memory schedules) {
        return ForklabHss(HSS_ADDRESS).pending();
    }

    /// @notice Sets the per-second schedule count limit.
    /// @param value The limit to use for subsequent schedules.
    function setMaxSchedulesPerSecond(uint256 value) internal {
        ForklabHss(HSS_ADDRESS).setMaxSchedulesPerSecond(value);
    }

    /// @notice Sets the per-second aggregate gas limit.
    /// @param value The limit to use for subsequent schedules.
    function setMaxGasPerSecond(uint256 value) internal {
        ForklabHss(HSS_ADDRESS).setMaxGasPerSecond(value);
    }

    /// @notice Sets the maximum expiry horizon.
    /// @param value The maximum number of future seconds.
    function setMaxExpiryFutureSeconds(uint256 value) internal {
        ForklabHss(HSS_ADDRESS).setMaxExpiryFutureSeconds(value);
    }

    /// @notice Sets the per-execution payer fee in tinybars.
    /// @param value The fee charged for each execution attempt.
    function setScheduleFeeTinybars(uint256 value) internal {
        ForklabHss(HSS_ADDRESS).setScheduleFeeTinybars(value);
    }

    /// @notice Enables or disables the strict delegatecall contract-key rule.
    /// @param value True to reject schedule calls reached through delegatecall.
    function strictDelegatecallRule(bool value) internal {
        ForklabHss(HSS_ADDRESS).setStrictDelegatecallRule(value);
    }

    /// @notice Sets the per-call execution cap used by runDue.
    /// @param value The maximum number of schedules processed in one run.
    function setMaxExecutionsPerRun(uint256 value) internal {
        ForklabHss(HSS_ADDRESS).setMaxExecutionsPerRun(value);
    }

    function _deployCodeTo(string memory artifact, address where) private {
        bytes memory creationCode = VM.getCode(artifact);
        VM.etch(where, creationCode);
        (bool success, bytes memory runtimeBytecode) = where.call("");
        require(success, "Forklab deployment failed");
        VM.etch(where, runtimeBytecode);
    }
}
