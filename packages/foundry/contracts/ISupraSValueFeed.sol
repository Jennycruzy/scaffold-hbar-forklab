// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Supra S-Value Feed Interface
/// @notice Reads push-oracle prices already published on-chain by Supra.
interface ISupraSValueFeed {
    /// @notice A single Supra trading-pair observation.
    /// @param round The Supra oracle round identifier.
    /// @param decimals The number of decimal places used by price.
    /// @param time The observation time in milliseconds since the Unix epoch.
    /// @param price The unsigned price scaled by decimals.
    struct PriceFeed {
        uint256 round;
        uint256 decimals;
        uint256 time;
        uint256 price;
    }

    /// @notice Returns the latest on-chain observation for a pair.
    /// @param pairIndex The Supra data-pair index.
    /// @return observation The latest price observation.
    function getSvalue(uint256 pairIndex) external view returns (PriceFeed memory observation);
}
