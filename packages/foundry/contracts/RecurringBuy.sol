// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IHederaScheduleService } from "./forklab/IHederaScheduleService.sol";
import { ISupraSValueFeed } from "./ISupraSValueFeed.sol";
import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

interface IERC20RecurringBuy {
    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address tokenOwner, address spender) external view returns (uint256);
}

interface IBonzoLendingPoolRecurringBuy {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
}

interface ISaucerSwapRouterRecurringBuy {
    function WHBAR() external view returns (address);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface IWhbarHelperRecurringBuy {
    function token() external view returns (address);
}

/// @title RecurringBuy
/// @notice A self-scheduling HBAR-to-token vault for real SaucerSwap V1 forks.
/// @dev The owner must use a real Hedera account that can receive tokenOut. The
///      vault itself is associated during start and is the HSS payer.
contract RecurringBuy {
    address internal constant HTS_ADDRESS = 0x0000000000000000000000000000000000000167;
    address internal constant HSS_ADDRESS = 0x000000000000000000000000000000000000016B;

    int64 internal constant SUCCESS_RESPONSE = 22;
    int64 internal constant TOKEN_ALREADY_ASSOCIATED = 194;
    int64 internal constant EXPIRY_BUSY = 370;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_SCHEDULE_ATTEMPTS = 3;
    uint256 internal constant TINYBARS_PER_HBAR = 100_000_000;
    uint256 internal constant SWAP_DEADLINE_SECONDS = 5 minutes;
    uint256 internal constant MAX_EXPIRY_FUTURE_SECONDS = 5_356_800;
    uint256 internal constant MIN_EXECUTION_GAS = 1_500_000;
    uint256 internal constant MAX_EXECUTION_GAS = 15_000_000;
    uint256 internal constant PURCHASE_FAILURE_GAS_RESERVE = 50_000;

    /// @notice Default gas limit for each scheduled run.
    /// @dev Measured on Hedera testnet on 4 October 2026: the HSS `scheduleCall` made
    ///      by `start()` used 1,409,649 gas, and the Supra read, quote, SaucerSwap
    ///      swap, and owner transfer used about 258,000 gas before the next schedule.
    ///      A 1,500,000 limit failed with INSUFFICIENT_GAS; see docs/TESTNET_PROOF.md.
    uint256 public constant DEFAULT_EXECUTION_GAS = 2_500_000;

    /// @notice Supra's HBAR/USD data-pair index.
    uint256 public constant HBAR_USD_PAIR_INDEX = 432;

    /// @notice Recommended staleness limit for Hedera's one-hour Supra push interval.
    uint256 public constant DEFAULT_MAX_PRICE_AGE = 2 hours;

    /// @notice The account that owns this vault.
    address public owner;

    /// @notice The Supra push-oracle contract used for HBAR/USD prices.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    ISupraSValueFeed public immutable supra;

    /// @notice The SaucerSwap V1 router used for each purchase.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    ISaucerSwapRouterRecurringBuy public immutable router;

    /// @notice The WHBAR token resolved through the router's wrapper helper.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable whbar;

    /// @notice The token purchased by each run.
    address public tokenOut;

    /// @notice The HBAR amount per purchase, in tinybars.
    uint256 public amountPerBuy;

    /// @notice The number of seconds between scheduled runs.
    uint256 public interval;

    /// @notice The accepted pool-versus-Supra difference in basis points.
    uint256 public maxDeviationBps;

    /// @notice The maximum accepted age of a Supra price in seconds.
    uint256 public maxPriceAge;

    /// @notice The currently pending HSS schedule, or zero when none exists.
    address public nextSchedule;

    /// @notice Bonzo Lend pool used when bought tokens are swept for the owner.
    address public bonzoPool;

    /// @notice Whether successful purchases are deposited into Bonzo for the owner.
    bool public sweepToBonzo;

    /// @notice The next requested run time in consensus seconds.
    uint256 public nextRunAt;

    /// @notice The most recent HSS response code produced by this vault.
    int64 public lastScheduleStatus;

    /// @notice The time of the most recent execution attempt.
    uint256 public lastRunAt;

    /// @notice Whether the vault accepts scheduled executions.
    bool public running;

    /// @notice The gas limit attached to each scheduled run.
    uint256 public executionGas = DEFAULT_EXECUTION_GAS;

    /// @notice Raised when a non-owner calls an owner-only function.
    error NotOwner();

    /// @notice Raised when a caller other than the vault reaches execute.
    error OnlyVault();

    /// @notice Raised when ownership would be assigned to the zero address.
    error InvalidOwner();

    /// @notice Raised when the configuration is incomplete or unsafe.
    error InvalidConfiguration();

    /// @notice Raised when the HTS association response is not successful.
    error TokenAssociationFailed(int64 responseCode);

    /// @notice Raised when the owner cannot receive tokenOut.
    error OwnerTokenAssociationRequired();

    /// @notice Raised when a native HBAR transfer fails.
    error HbarTransferFailed();

    /// @notice Raised when Supra returns an unusable price observation.
    error InvalidSupraPrice();

    /// @notice Emitted after a new recurring schedule is created.
    event ScheduleCreated(address indexed schedule, uint256 runAt);

    /// @notice Emitted when an HSS call returns a non-success response code.
    event ScheduleFailed(int64 indexed responseCode);

    /// @notice Emitted when the pool quote is outside the configured Supra range.
    event SkippedDeviation(uint256 oracleAmountOut, uint256 poolAmountOut, uint256 deviationBps);

    /// @notice Emitted when the Supra price is older than maxPriceAge.
    event SkippedStalePrice(uint256 publishTime, uint256 currentTime);

    /// @notice Emitted after a successful purchase and owner transfer.
    event Bought(uint256 hbarAmount, uint256 tokenAmount, uint256 oracleAmountOut, uint256 poolAmountOut);

    /// @notice Emitted when a due run could not complete its purchase.
    /// @dev The next run is scheduled before the purchase, so one failure does not stop the vault.
    event PurchaseFailed(bytes reason);

    /// @notice Emitted when the owner changes the scheduled-run gas limit.
    event ExecutionGasConfigured(uint256 gasLimit);

    /// @notice Raised when the Bonzo pool approval is rejected.
    error BonzoApprovalFailed();

    /// @notice Emitted when the owner stops the vault.
    event Stopped(int64 responseCode);

    /// @notice Emitted when the Bonzo sweep setting changes.
    event BonzoSweepConfigured(address indexed pool, bool enabled);

    /// @notice Emitted after a purchase is deposited into Bonzo for the owner.
    event SweptToBonzo(address indexed asset, address indexed onBehalfOf, uint256 amount);

    /// @notice Emitted when the factory or current owner changes control.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @param supraAddress The deployed Supra push-oracle contract.
    /// @param routerAddress The deployed SaucerSwap V1 router.
    constructor(address supraAddress, address routerAddress) {
        if (supraAddress == address(0) || routerAddress == address(0)) revert InvalidConfiguration();
        owner = msg.sender;
        supra = ISupraSValueFeed(supraAddress);
        router = ISaucerSwapRouterRecurringBuy(routerAddress);
        address whbarHelper = ISaucerSwapRouterRecurringBuy(routerAddress).WHBAR();
        if (whbarHelper == address(0)) revert InvalidConfiguration();
        whbar = IWhbarHelperRecurringBuy(whbarHelper).token();
        if (whbar == address(0)) revert InvalidConfiguration();
    }

    /// @notice Allows the owner to deposit tinybars for future purchases and fees.
    function deposit() external payable onlyOwner { }

    /// @notice Transfers control to a new owner. The vault factory uses this
    ///      once, atomically, after deploying a vault on behalf of a wallet.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    /// @notice Accepts direct HBAR funding from an account or a scheduled call.
    receive() external payable { }

    /// @notice Sets the token and risk parameters before the vault is started.
    /// @dev The Supra feed is HBAR/USD, so the oracle check values one tokenOut unit
    ///      at one US dollar. Use a USD-pegged token; any other token will either skip
    ///      every run for deviation or, with a very wide deviation, lose slippage protection.
    /// @param tokenOutAddress The real USD-pegged HTS token purchased by the vault.
    /// @param amountTinybars The HBAR amount for each purchase.
    /// @param intervalSeconds The delay between runs.
    /// @param deviationBps The maximum pool/Supra difference in basis points.
    /// @param priceAgeSeconds The maximum Supra publish age.
    function configure(
        address tokenOutAddress,
        uint256 amountTinybars,
        uint256 intervalSeconds,
        uint256 deviationBps,
        uint256 priceAgeSeconds
    ) external onlyOwner {
        if (running) revert InvalidConfiguration();
        if (
            tokenOutAddress == address(0) || tokenOutAddress == whbar || amountTinybars == 0 || intervalSeconds == 0
                || intervalSeconds > MAX_EXPIRY_FUTURE_SECONDS || deviationBps > BPS || priceAgeSeconds == 0
        ) {
            revert InvalidConfiguration();
        }
        tokenOut = tokenOutAddress;
        amountPerBuy = amountTinybars;
        interval = intervalSeconds;
        maxDeviationBps = deviationBps;
        maxPriceAge = priceAgeSeconds;
    }

    /// @notice Sets the gas limit attached to future scheduled runs.
    /// @param gasLimit The limit, between 1,500,000 and 15,000,000.
    function setExecutionGas(uint256 gasLimit) external onlyOwner {
        if (running || gasLimit < MIN_EXECUTION_GAS || gasLimit > MAX_EXECUTION_GAS) revert InvalidConfiguration();
        executionGas = gasLimit;
        emit ExecutionGasConfigured(gasLimit);
    }

    /// @notice Enables or disables depositing bought tokens into Bonzo Lend.
    /// @param pool The Bonzo LendingPool address for the current network.
    /// @param enabled Whether future purchases should be deposited for the owner.
    function configureBonzo(address pool, bool enabled) external onlyOwner {
        if (enabled && pool == address(0)) revert InvalidConfiguration();
        bonzoPool = pool;
        sweepToBonzo = enabled;
        emit BonzoSweepConfigured(pool, enabled);
    }

    /// @notice Associates the vault, checks owner receipt, and creates the first schedule.
    /// @return responseCode The HSS response code.
    /// @return scheduleAddress The new schedule address on success.
    function start() external onlyOwner returns (int64 responseCode, address scheduleAddress) {
        if (running) revert InvalidConfiguration();
        _validateConfiguration();
        _associateVault();
        _checkOwnerCanReceive();

        (responseCode, scheduleAddress) = _createSchedule(block.timestamp + interval);
        lastScheduleStatus = responseCode;
        if (responseCode != SUCCESS_RESPONSE) {
            emit ScheduleFailed(responseCode);
            return (responseCode, address(0));
        }
        running = true;
        nextSchedule = scheduleAddress;
        nextRunAt = block.timestamp + interval;
        emit ScheduleCreated(scheduleAddress, nextRunAt);
    }

    /// @notice Executes one due run; HSS is the only intended caller.
    /// @dev The next run is scheduled first. The purchase then runs in a guarded
    ///      self-call, so a failed swap, transfer, or Bonzo deposit is reported with
    ///      PurchaseFailed instead of reverting the run and ending the schedule chain.
    function execute() external {
        if (msg.sender != address(this)) revert OnlyVault();
        if (!running) return;
        lastRunAt = block.timestamp;
        _scheduleNext();

        // Keep gas back so a purchase that exhausts its share cannot also revert
        // this frame and undo the schedule created above.
        uint256 available = gasleft();
        if (available <= PURCHASE_FAILURE_GAS_RESERVE) {
            emit PurchaseFailed(bytes("insufficient gas for purchase"));
            return;
        }
        try this.purchase{ gas: available - PURCHASE_FAILURE_GAS_RESERVE }() { }
        catch (bytes memory reason) {
            emit PurchaseFailed(reason);
        }
    }

    /// @notice Performs one oracle-checked purchase; callable only by the vault itself.
    function purchase() external {
        if (msg.sender != address(this)) revert OnlyVault();

        ISupraSValueFeed.PriceFeed memory price = supra.getSvalue(HBAR_USD_PAIR_INDEX);
        uint256 publishTime = _supraTimestampSeconds(price.time);
        if (publishTime > block.timestamp || block.timestamp - publishTime > maxPriceAge) {
            emit SkippedStalePrice(publishTime, block.timestamp);
            return;
        }

        uint256 oracleAmountOut = _supraTokenAmount(price);
        address[] memory path = _path();
        uint256[] memory quote = router.getAmountsOut(amountPerBuy, path);
        uint256 poolAmountOut = quote[quote.length - 1];
        uint256 deviationBps = _deviationBps(oracleAmountOut, poolAmountOut);
        if (deviationBps > maxDeviationBps) {
            emit SkippedDeviation(oracleAmountOut, poolAmountOut, deviationBps);
            return;
        }

        uint256 amountOutMin = (oracleAmountOut * (BPS - maxDeviationBps)) / BPS;
        uint256 balanceBefore = IERC20RecurringBuy(tokenOut).balanceOf(address(this));
        router.swapExactETHForTokens{ value: amountPerBuy }(
            amountOutMin, path, address(this), block.timestamp + SWAP_DEADLINE_SECONDS
        );
        uint256 amountBought = IERC20RecurringBuy(tokenOut).balanceOf(address(this)) - balanceBefore;
        if (sweepToBonzo) {
            if (!IERC20RecurringBuy(tokenOut).approve(bonzoPool, amountBought)) revert BonzoApprovalFailed();
            IBonzoLendingPoolRecurringBuy(bonzoPool).deposit(tokenOut, amountBought, owner, 0);
            emit SweptToBonzo(tokenOut, owner, amountBought);
        } else if (!IERC20RecurringBuy(tokenOut).transfer(owner, amountBought)) {
            revert OwnerTokenAssociationRequired();
        }
        emit Bought(amountPerBuy, amountBought, oracleAmountOut, poolAmountOut);
    }

    /// @notice Deletes the pending schedule and stops future purchases.
    /// @return responseCode The HSS response code, or success when no schedule remains.
    function stop() external onlyOwner returns (int64 responseCode) {
        running = false;
        address scheduleAddress = nextSchedule;
        nextSchedule = address(0);
        nextRunAt = 0;
        if (scheduleAddress == address(0)) {
            emit Stopped(SUCCESS_RESPONSE);
            return SUCCESS_RESPONSE;
        }
        responseCode = IHederaScheduleService(HSS_ADDRESS).deleteSchedule(scheduleAddress);
        lastScheduleStatus = responseCode;
        if (responseCode != SUCCESS_RESPONSE) emit ScheduleFailed(responseCode);
        emit Stopped(responseCode);
    }

    /// @notice Withdraws tinybars from the vault to the owner.
    /// @param amountTinybars The amount to withdraw.
    function withdraw(uint256 amountTinybars) external onlyOwner {
        if (running) revert InvalidConfiguration();
        (bool success,) = payable(owner).call{ value: amountTinybars }("");
        if (!success) revert HbarTransferFailed();
    }

    /// @notice Returns whether the vault is associated with tokenOut through HRC-719.
    /// @dev HRC-719 has no account argument; the call therefore checks this vault.
    function isVaultAssociated() external returns (bool associated) {
        if (tokenOut == address(0)) return false;
        (bool success, bytes memory result) = tokenOut.call(abi.encodeWithSelector(IHRC719.isAssociated.selector));
        if (!success || result.length < 32) return false;
        return abi.decode(result, (bool));
    }

    /// @notice Returns the current balance held for future scheduled purchases.
    /// @return balanceTinybars The vault's HBAR balance in tinybars.
    function hbarBalance() external view returns (uint256 balanceTinybars) {
        return address(this).balance;
    }

    function _validateConfiguration() private view {
        if (tokenOut == address(0) || amountPerBuy == 0 || interval == 0 || maxDeviationBps > BPS || maxPriceAge == 0) {
            revert InvalidConfiguration();
        }
    }

    function _associateVault() private {
        (bool success, bytes memory result) = tokenOut.call(abi.encodeWithSelector(IHRC719.isAssociated.selector));
        if (success && result.length >= 32 && abi.decode(result, (bool))) return;

        int64 responseCode = IHederaTokenService(HTS_ADDRESS).associateToken(address(this), tokenOut);
        if (responseCode != SUCCESS_RESPONSE && responseCode != TOKEN_ALREADY_ASSOCIATED) {
            revert TokenAssociationFailed(responseCode);
        }
    }

    function _checkOwnerCanReceive() private view {
        // HRC-719 cannot query another account, but this owner-specific approval
        // is established by a direct, signed token transaction from the owner.
        (bool success, bytes memory result) =
            tokenOut.staticcall(abi.encodeWithSelector(IERC20RecurringBuy.allowance.selector, owner, address(this)));
        if (!success || result.length < 32 || abi.decode(result, (uint256)) == 0) {
            revert OwnerTokenAssociationRequired();
        }
    }

    function _createSchedule(uint256 firstCandidate) private returns (int64 responseCode, address scheduleAddress) {
        uint256 candidate = firstCandidate;
        for (uint256 attempt; attempt < MAX_SCHEDULE_ATTEMPTS; attempt++) {
            if (IHederaScheduleService(HSS_ADDRESS).hasScheduleCapacity(candidate, executionGas)) {
                return IHederaScheduleService(HSS_ADDRESS)
                    .scheduleCall(address(this), candidate, executionGas, 0, abi.encodeCall(this.execute, ()));
            }
            candidate += interval;
        }
        return (EXPIRY_BUSY, address(0));
    }

    function _scheduleNext() private {
        if (!running) return;
        (int64 responseCode, address scheduleAddress) = _createSchedule(block.timestamp + interval);
        lastScheduleStatus = responseCode;
        if (responseCode != SUCCESS_RESPONSE) {
            running = false;
            nextSchedule = address(0);
            nextRunAt = 0;
            emit ScheduleFailed(responseCode);
            return;
        }
        nextSchedule = scheduleAddress;
        nextRunAt = block.timestamp + interval;
        emit ScheduleCreated(scheduleAddress, nextRunAt);
    }

    function _path() private view returns (address[] memory path) {
        path = new address[](2);
        path[0] = whbar;
        path[1] = tokenOut;
    }

    function _supraTokenAmount(ISupraSValueFeed.PriceFeed memory price) private view returns (uint256 tokenAmount) {
        uint256 tokenDecimals = IERC20RecurringBuy(tokenOut).decimals();
        if (price.price == 0 || price.decimals > 77 || tokenDecimals > 77) revert InvalidSupraPrice();
        uint256 usdValue = Math.mulDiv(amountPerBuy, price.price, TINYBARS_PER_HBAR);
        tokenAmount = Math.mulDiv(usdValue, 10 ** tokenDecimals, 10 ** price.decimals);
        if (tokenAmount == 0) revert InvalidSupraPrice();
    }

    function _supraTimestampSeconds(uint256 timestamp) private pure returns (uint256) {
        return timestamp / 1_000;
    }

    function _deviationBps(uint256 expectedAmount, uint256 actualAmount) private pure returns (uint256) {
        if (expectedAmount == 0) return type(uint256).max;
        uint256 difference =
            expectedAmount > actualAmount ? expectedAmount - actualAmount : actualAmount - expectedAmount;
        return (difference * BPS) / expectedAmount;
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        if (msg.sender != owner) revert NotOwner();
    }
}
