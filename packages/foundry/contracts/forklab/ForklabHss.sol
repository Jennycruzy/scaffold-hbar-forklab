// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { IHederaScheduleService } from "./IHederaScheduleService.sol";

/// @notice A deterministic Hedera Schedule Service emulator for Foundry tests.
/// @dev This contract is etched at 0x16b by Forklab.setUp(). Its cheatcode calls
///      are enabled by the test harness, which lets it reproduce payer execution.
contract ForklabHss is IHederaScheduleService {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Hedera success response code.
    int64 public constant SUCCESS = 22;
    /// @notice Invalid target response code.
    int64 public constant INVALID_CONTRACT_ID = 16;
    /// @notice Expiry is not after the current consensus second.
    int64 public constant EXPIRY_NOT_IN_FUTURE = 307;
    /// @notice Expiry is beyond the configured horizon.
    int64 public constant EXPIRY_TOO_FAR = 306;
    /// @notice The requested second has no remaining capacity.
    int64 public constant EXPIRY_BUSY = 370;
    /// @notice The schedule id is unknown.
    int64 public constant INVALID_SCHEDULE_ID = 201;
    /// @notice The schedule has already reached a terminal state.
    int64 public constant SCHEDULE_ALREADY_DELETED = 212;
    /// @notice The schedule has already executed.
    int64 public constant SCHEDULE_ALREADY_EXECUTED = 213;
    /// @notice The payer did not authorize the operation.
    int64 public constant INVALID_SIGNATURE = 7;
    /// @notice The payer could not fund the scheduled operation.
    int64 public constant INSUFFICIENT_PAYER_BALANCE = 10;
    /// @notice The caller is not the schedule creator.
    int64 public constant UNAUTHORIZED = 157;

    /// @notice The first long-zero schedule address used by this emulator.
    address public constant FIRST_SCHEDULE = 0x00000000000000000000000000000000f0000000;
    /// @notice The emulator's fixed address.
    address public constant HSS_ADDRESS = 0x000000000000000000000000000000000000016B;

    /// @notice Public information recorded for one schedule.
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

    struct ScheduleState {
        ScheduleInfo info;
        address creator;
        bool exists;
        bool requiresSignature;
        bool executeOnSignature;
        bool signed;
        bool terminal;
        bool deleted;
        bool rejectPayerAtExecution;
    }

    struct Capacity {
        uint256 scheduleCount;
        uint256 gasUsed;
    }

    mapping(address scheduleAddress => ScheduleState state) private _schedules;
    mapping(uint256 second => Capacity capacity) private _capacity;
    mapping(address scheduler => bool marked) private _delegateSchedulers;
    address[] private _scheduleOrder;
    uint160 private _nextSchedule;
    // Horizon and per-run cap: Hiero SchedulingConfig.java (maxExpirationFutureSeconds,
    // maxExecutionsPerUserTxn). Per-second capacity on the network is a 1:10 fraction of
    // the live throttle definitions; the count and gas values here are configurable
    // approximations. See docs/VERIFIED.md, "Live schedule-capacity probe".
    uint256 private _maxSchedulesPerSecond = 10;
    uint256 private _maxGasPerSecond = 15_000_000;
    uint256 private _maxExpiryFutureSeconds = 5_356_800;
    uint256 private _maxExecutionsPerRun = 100;
    uint256 private _scheduleFeeTinybars;
    uint256 private _scheduleCreateGas = 1_409_649;
    uint256 private _gasPriceTinybars = 83;
    bool private _strictDelegatecall = true;
    bool private _installDeleteForwarders = true;

    /// @notice Emitted when a schedule is created.
    event ScheduleCreated(
        address indexed schedule,
        address indexed payer,
        address indexed to,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes callData
    );

    /// @notice Emitted after an eligible schedule attempts its target call.
    event ScheduleExecuted(address indexed schedule, bool success, bytes returnData);

    /// @notice Emitted when a pending schedule is deleted.
    event ScheduleDeleted(address indexed schedule);

    /// @notice Emitted when an unsigned schedule reaches expiry.
    event ScheduleExpired(address indexed schedule);

    /// @dev Charges the configured HSS creation gas to the caller's frame. Hedera
    ///      prices a schedule created from a contract like a system-contract call:
    ///      on testnet, `scheduleCall` from RecurringBuy.start() used 1,409,649 gas.
    ///      When the remaining gas cannot cover that cost, the frame consumes all of
    ///      its gas and fails, as the real call did with INSUFFICIENT_GAS.
    // forge-lint: disable-start(unwrapped-modifier-logic)
    modifier chargesCreateGas() {
        uint256 startGas = _beginCreateCharge();
        _;
        _finishCreateCharge(startGas);
    }

    // forge-lint: disable-end(unwrapped-modifier-logic)

    /// @notice Creates a schedule paid by the calling contract.
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata callData)
        external
        chargesCreateGas
        returns (int64 responseCode, address scheduleAddress)
    {
        return _create(to, msg.sender, expirySecond, gasLimit, value, callData, false, false);
    }

    /// @notice Creates a schedule that waits until expiry for a payer signature.
    function scheduleCallWithPayer(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes calldata callData
    ) external chargesCreateGas returns (int64 responseCode, address scheduleAddress) {
        return _create(to, payer, expirySecond, gasLimit, value, callData, true, false);
    }

    /// @notice Creates a schedule that executes when the payer signs before expiry.
    function executeCallOnPayerSignature(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes calldata callData
    ) external chargesCreateGas returns (int64 responseCode, address scheduleAddress) {
        return _create(to, payer, expirySecond, gasLimit, value, callData, true, true);
    }

    /// @notice Deletes a schedule when called by its creator.
    function deleteSchedule(address scheduleAddress) external returns (int64 responseCode) {
        return _delete(scheduleAddress, msg.sender);
    }

    /// @notice Receives the redirected delete call from a schedule address.
    /// @dev Only the forwarder etched at that schedule address may call this entry point.
    function deleteScheduleAt(address scheduleAddress, address originalCaller) external returns (int64 responseCode) {
        if (msg.sender != scheduleAddress) return UNAUTHORIZED;
        return _delete(scheduleAddress, originalCaller);
    }

    /// @notice Deletes the schedule represented by the current schedule address.
    function deleteSchedule() external returns (int64 responseCode) {
        return _delete(msg.sender, msg.sender);
    }

    /// @notice Reports whether the next schedule fits the configured limits.
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool available) {
        return _hasCapacity(expirySecond, gasLimit);
    }

    /// @notice Records a payer signature and executes signature-triggered schedules.
    /// @dev Only the recorded payer may sign; `Forklab.signAsPayer` pranks that payer.
    /// @param scheduleAddress The schedule being signed.
    /// @return responseCode SUCCESS, INVALID_SCHEDULE_ID, a terminal-state code, or INVALID_SIGNATURE.
    function signAsPayer(address scheduleAddress) external returns (int64 responseCode) {
        ScheduleState storage state = _schedules[scheduleAddress];
        if (!state.exists) return INVALID_SCHEDULE_ID;
        if (state.deleted) return SCHEDULE_ALREADY_DELETED;
        if (state.terminal) return SCHEDULE_ALREADY_EXECUTED;
        if (msg.sender != state.info.payer) return INVALID_SIGNATURE;
        if (block.timestamp >= state.info.expiry) {
            _expire(scheduleAddress);
            return INVALID_SIGNATURE;
        }
        state.signed = true;
        if (state.executeOnSignature) _execute(scheduleAddress);
        return SUCCESS;
    }

    /// @notice Executes all eligible schedules in creation order.
    /// @return executed The number of schedules inspected and made terminal.
    function runDue() external returns (uint256 executed) {
        uint256 limit = _maxExecutionsPerRun;
        while (executed < limit) {
            address scheduleAddress = _nextDue();
            if (scheduleAddress == address(0)) return executed;
            _execute(scheduleAddress);
            executed++;
        }
        return executed;
    }

    /// @notice Records an execution sent directly by an external Anvil runner.
    /// @dev Foundry cheatcodes are unavailable to bytecode installed with
    ///      `anvil_setCode`, so the local runner impersonates the recorded payer,
    ///      calls the target, then settles the observed receipt here as that payer.
    function recordExternalExecution(address scheduleAddress, bool success, bytes calldata returnData)
        external
        returns (int64 responseCode)
    {
        ScheduleState storage state = _schedules[scheduleAddress];
        bytes memory observedReturnData = returnData;
        if (!state.exists) return INVALID_SCHEDULE_ID;
        if (state.deleted) return SCHEDULE_ALREADY_DELETED;
        if (state.terminal) return SCHEDULE_ALREADY_EXECUTED;
        if (msg.sender != state.info.payer) return UNAUTHORIZED;
        if (block.timestamp < state.info.expiry) return EXPIRY_NOT_IN_FUTURE;
        if (state.requiresSignature && !state.signed) {
            _expire(scheduleAddress);
            return INVALID_SIGNATURE;
        }
        if (state.rejectPayerAtExecution) {
            state.info.status = INVALID_SIGNATURE;
            success = false;
            observedReturnData = bytes("");
        } else {
            state.info.status = SUCCESS;
        }
        state.info.success = success;
        state.info.returnData = observedReturnData;
        state.info.executedAt = block.timestamp;
        state.terminal = true;
        emit ScheduleExecuted(scheduleAddress, success, observedReturnData);
        return state.info.status;
    }

    /// @notice Tells an external runner whether it may call the target.
    /// @dev False means the runner must settle without calling the target; the
    ///      settlement function records the applicable signature status.
    function shouldExternalRunnerCall(address scheduleAddress) external view returns (bool) {
        ScheduleState storage state = _schedules[scheduleAddress];
        if (!state.exists || state.terminal || block.timestamp < state.info.expiry) return false;
        if (state.requiresSignature && !state.signed) return false;
        return !state.rejectPayerAtExecution;
    }

    /// @notice Sets the per-second schedule count limit used by this emulator.
    /// @param value The maximum number of schedules for one second.
    function setMaxSchedulesPerSecond(uint256 value) external {
        _maxSchedulesPerSecond = value;
    }

    /// @notice Sets the per-second gas capacity used by this emulator.
    /// @param value The maximum aggregate gas limit for one second.
    function setMaxGasPerSecond(uint256 value) external {
        _maxGasPerSecond = value;
    }

    /// @notice Sets the maximum schedule horizon in seconds.
    /// @param value The maximum number of seconds after now.
    function setMaxExpiryFutureSeconds(uint256 value) external {
        _maxExpiryFutureSeconds = value;
    }

    /// @notice Sets the fee debited from a payer for every execution attempt.
    /// @param value The fee in tinybars.
    function setScheduleFeeTinybars(uint256 value) external {
        _scheduleFeeTinybars = value;
    }

    /// @notice Sets the gas charged to the caller for each schedule creation.
    /// @param value The gas cost; 0 disables the charge.
    function setScheduleCreateGas(uint256 value) external {
        _scheduleCreateGas = value;
    }

    /// @notice Sets the tinybar price per gas charged to payers at execution.
    /// @param value Tinybars per gas; 0 disables gas fees.
    function setGasPriceTinybars(uint256 value) external {
        _gasPriceTinybars = value;
    }

    /// @notice Returns the gas model used for creation and execution.
    /// @return createGas Gas charged per schedule creation.
    /// @return gasPriceTinybars Tinybars charged per execution gas unit.
    function gasModel() external view returns (uint256 createGas, uint256 gasPriceTinybars) {
        return (_scheduleCreateGas, _gasPriceTinybars);
    }

    /// @notice Sets whether code reached through delegatecall is rejected.
    /// @param value True to reproduce Hedera's strict contract-key rule.
    function setStrictDelegatecallRule(bool value) external {
        _strictDelegatecall = value;
    }

    /// @notice Enables schedule-address delete redirect bytecode in Foundry.
    /// @dev Leave disabled for code installed in Anvil, where VM cheatcodes do not exist.
    function setInstallDeleteForwarders(bool value) external {
        _installDeleteForwarders = value;
    }

    /// @notice Marks a proxy whose implementation reaches HSS through delegatecall.
    /// @dev The EVM call into 0x16b is ordinary, so this explicit marker is required;
    ///      the emulator cannot inspect the caller's preceding call frames.
    function markDelegateScheduler(address scheduler, bool marked) external {
        _delegateSchedulers[scheduler] = marked;
    }

    /// @notice Returns whether delegatecall entry is rejected.
    /// @return enabled True when the strict contract-key rule is enabled.
    function strictDelegatecallRule() external view returns (bool enabled) {
        return _strictDelegatecall;
    }

    /// @notice Sets the maximum number of executions returned by one runDue call.
    /// @param value The execution cap.
    function setMaxExecutionsPerRun(uint256 value) external {
        _maxExecutionsPerRun = value;
    }

    /// @notice Returns one schedule's recorded information.
    /// @param scheduleAddress The schedule address.
    /// @return info The schedule record.
    function schedule(address scheduleAddress) external view returns (ScheduleInfo memory info) {
        return _schedules[scheduleAddress].info;
    }

    /// @notice Returns all currently pending schedule addresses.
    /// @return schedules The pending addresses in creation order.
    function pending() external view returns (address[] memory schedules) {
        schedules = new address[](_scheduleOrder.length);
        uint256 count;
        for (uint256 i; i < _scheduleOrder.length; i++) {
            ScheduleState storage state = _schedules[_scheduleOrder[i]];
            if (!state.terminal) schedules[count++] = _scheduleOrder[i];
        }
        assembly {
            mstore(schedules, count)
        }
    }

    /// @notice Returns the current emulator configuration.
    /// @return schedulesPerSecond The configured schedule count limit.
    /// @return gasPerSecond The configured aggregate gas limit.
    /// @return expiryFutureSeconds The configured expiry horizon.
    /// @return executionFeeTinybars The configured execution fee.
    function configuration()
        external
        view
        returns (
            uint256 schedulesPerSecond,
            uint256 gasPerSecond,
            uint256 expiryFutureSeconds,
            uint256 executionFeeTinybars
        )
    {
        return (_maxSchedulesPerSecond, _maxGasPerSecond, _maxExpiryFutureSeconds, _scheduleFeeTinybars);
    }

    function _create(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes calldata callData,
        bool requiresSignature,
        bool executeOnSignature
    ) private returns (int64 responseCode, address scheduleAddress) {
        if (to == address(0)) return (INVALID_CONTRACT_ID, address(0));
        if (expirySecond <= block.timestamp) return (EXPIRY_NOT_IN_FUTURE, address(0));
        if (expirySecond - block.timestamp > _maxExpiryFutureSeconds) return (EXPIRY_TOO_FAR, address(0));
        if (!_hasCapacity(expirySecond, gasLimit)) return (EXPIRY_BUSY, address(0));

        scheduleAddress = address(uint160(FIRST_SCHEDULE) + _nextSchedule);
        _nextSchedule++;

        ScheduleState storage state = _schedules[scheduleAddress];
        state.exists = true;
        state.info.to = to;
        state.info.payer = payer;
        state.info.expiry = expirySecond;
        state.info.gasLimit = gasLimit;
        state.info.value = value;
        state.info.data = callData;
        state.info.status = SUCCESS;
        state.info.createdAt = block.timestamp;
        state.creator = msg.sender;
        state.requiresSignature = requiresSignature;
        state.executeOnSignature = executeOnSignature;
        state.rejectPayerAtExecution = _strictDelegatecall && _delegateSchedulers[msg.sender];
        _scheduleOrder.push(scheduleAddress);
        _capacity[expirySecond].scheduleCount++;
        _capacity[expirySecond].gasUsed += gasLimit;
        if (_installDeleteForwarders) _installDeleteForwarder(scheduleAddress);

        emit ScheduleCreated(scheduleAddress, payer, to, expirySecond, gasLimit, value, callData);
        return (SUCCESS, scheduleAddress);
    }

    function _hasCapacity(uint256 expirySecond, uint256 gasLimit) private view returns (bool) {
        if (expirySecond <= block.timestamp) return false;
        if (expirySecond - block.timestamp > _maxExpiryFutureSeconds) return false;
        Capacity storage capacity = _capacity[expirySecond];
        if (capacity.scheduleCount >= _maxSchedulesPerSecond) return false;
        if (gasLimit > _maxGasPerSecond) return false;
        return capacity.gasUsed <= _maxGasPerSecond - gasLimit;
    }

    /// @dev Returns the due schedule with the earliest expiry second; creation order breaks ties.
    function _nextDue() private view returns (address scheduleAddress) {
        uint256 bestExpiry = type(uint256).max;
        for (uint256 i; i < _scheduleOrder.length; i++) {
            address candidate = _scheduleOrder[i];
            ScheduleState storage state = _schedules[candidate];
            if (state.terminal) continue;
            bool due = block.timestamp >= state.info.expiry
                || (state.executeOnSignature && state.signed && block.timestamp < state.info.expiry);
            if (due && state.info.expiry < bestExpiry) {
                bestExpiry = state.info.expiry;
                scheduleAddress = candidate;
            }
        }
    }

    function _execute(address scheduleAddress) private {
        ScheduleState storage state = _schedules[scheduleAddress];
        if (state.terminal) return;
        if (block.timestamp >= state.info.expiry && state.requiresSignature && !state.signed) {
            _expire(scheduleAddress);
            return;
        }
        if (state.executeOnSignature && !state.signed) return;

        uint256 executionTime = block.timestamp < state.info.expiry ? state.info.expiry : block.timestamp;
        if (executionTime > block.timestamp) VM.warp(executionTime);

        if (state.rejectPayerAtExecution) {
            state.info.status = INVALID_SIGNATURE;
            state.info.success = false;
            state.info.returnData = bytes("");
            state.info.executedAt = block.timestamp;
            state.terminal = true;
            emit ScheduleExecuted(scheduleAddress, false, bytes(""));
            return;
        }

        // The payer must cover the call value, the flat fee, and the gas reservation at the full limit.
        uint256 gasPrice = _gasPriceTinybars;
        if (
            state.info.gasLimit > type(uint128).max || gasPrice > type(uint128).max
                || state.info.value > type(uint128).max || _scheduleFeeTinybars > type(uint128).max
        ) {
            _recordInsufficient(state, scheduleAddress);
            return;
        }
        uint256 required = _scheduleFeeTinybars + state.info.value + state.info.gasLimit * gasPrice;
        if (state.info.payer.balance < required) {
            _recordInsufficient(state, scheduleAddress);
            return;
        }

        VM.prank(state.info.payer);
        uint256 gasBefore = gasleft();
        (bool success, bytes memory returnData) =
            state.info.to.call{ gas: state.info.gasLimit, value: state.info.value }(state.info.data);
        uint256 gasUsed = gasBefore - gasleft();
        if (gasUsed > state.info.gasLimit) gasUsed = state.info.gasLimit;

        // Hedera reserves gas at the full limit, charges the gas used, and refunds the rest
        // (docs.hedera.com, smart-contracts/gas-and-fees, "Gas Reservation and Unused Gas Refund").
        uint256 fee = _scheduleFeeTinybars + gasUsed * gasPrice;
        uint256 payerAfter = state.info.payer.balance;
        if (fee > payerAfter) fee = payerAfter;
        VM.deal(state.info.payer, payerAfter - fee);
        VM.deal(address(this), address(this).balance + fee);

        state.info.success = success;
        state.info.returnData = returnData;
        state.info.executedAt = block.timestamp;
        state.info.status = SUCCESS;
        state.terminal = true;
        emit ScheduleExecuted(scheduleAddress, success, returnData);
    }

    function _recordInsufficient(ScheduleState storage state, address scheduleAddress) private {
        state.info.status = INSUFFICIENT_PAYER_BALANCE;
        state.info.success = false;
        state.info.returnData = bytes("");
        state.info.executedAt = block.timestamp;
        state.terminal = true;
        emit ScheduleExecuted(scheduleAddress, false, bytes(""));
    }

    function _expire(address scheduleAddress) private {
        ScheduleState storage state = _schedules[scheduleAddress];
        if (state.terminal) return;
        state.info.status = INVALID_SIGNATURE;
        state.info.success = false;
        state.info.executedAt = block.timestamp;
        state.terminal = true;
        emit ScheduleExpired(scheduleAddress);
    }

    function _delete(address scheduleAddress, address caller) private returns (int64 responseCode) {
        ScheduleState storage state = _schedules[scheduleAddress];
        if (!state.exists) return INVALID_SCHEDULE_ID;
        if (state.deleted) return SCHEDULE_ALREADY_DELETED;
        if (state.info.executedAt != 0 || state.terminal) return SCHEDULE_ALREADY_EXECUTED;
        if (caller != state.creator) return UNAUTHORIZED;
        state.deleted = true;
        state.terminal = true;
        state.info.status = SUCCESS;
        emit ScheduleDeleted(scheduleAddress);
        return SUCCESS;
    }

    function _beginCreateCharge() private view returns (uint256 startGas) {
        startGas = gasleft();
        if (startGas < _scheduleCreateGas) _consumeAllGas();
    }

    function _finishCreateCharge(uint256 startGas) private view {
        uint256 used = startGas - gasleft();
        if (used < _scheduleCreateGas) _burnGas(_scheduleCreateGas - used);
    }

    function _burnGas(uint256 amount) private view {
        if (gasleft() < amount) _consumeAllGas();
        uint256 target = gasleft() - amount;
        while (gasleft() > target) { }
    }

    function _consumeAllGas() private pure {
        assembly {
            invalid()
        }
    }

    function _installDeleteForwarder(address scheduleAddress) private {
        ScheduleDeleteForwarder forwarder = new ScheduleDeleteForwarder(scheduleAddress);
        VM.etch(scheduleAddress, address(forwarder).code);
        VM.allowCheatcodes(scheduleAddress);
    }
}

/// @notice Tiny forwarder etched at each emulator schedule address.
contract ScheduleDeleteForwarder {
    address private immutable _SCHEDULE;
    address private constant _HSS = 0x000000000000000000000000000000000000016B;

    /// @param scheduleAddress The schedule address this forwarder represents.
    constructor(address scheduleAddress) {
        _SCHEDULE = scheduleAddress;
    }

    /// @notice Redirects deleteSchedule() to the emulator while preserving the original caller.
    fallback() external payable {
        if (msg.sig != bytes4(keccak256("deleteSchedule()"))) return;
        (bool success, bytes memory returnData) =
            _HSS.call(abi.encodeWithSignature("deleteScheduleAt(address,address)", _SCHEDULE, msg.sender));
        if (!success) return;
        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }
}
