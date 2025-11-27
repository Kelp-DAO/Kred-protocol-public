// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

// ============ Structs ============

/// @notice Struct to store the stablecoin yield distribution information
struct Distribution {
    address stablecoin; // stablecoin for this distribution (e.g., USDT)
    uint256 totalAmount; // total amount scheduled (in stablecoin decimals)
    uint256 releasedAmount; // cumulative released amount
    uint64 startTime; // linear start
    uint64 endTime; // linear end (exclusive)
    bool active; // active flag
}

/**
 * @title IYieldDistributor
 * @notice Interface for the YieldDistributor contract
 */
interface IYieldDistributor {
    // ============ Custom Errors ============

    error ZeroAmountNotAllowed();
    error InvalidDistributionStartTime();
    error InvalidDurationBounds(uint256 minDuration, uint256 maxDuration);
    error InvalidDuration(uint256 minDuration, uint256 maxDuration, uint256 providedDuration);
    error StablecoinNotAccepted(address stablecoin);
    error NotActive(uint256 distributionId);
    error NothingDue();
    error ActiveDistributionsLimitReached(uint256 limit);
    error InsufficientStablecoinBalance(address stablecoin, uint256 required, uint256 available);

    // =========== Events ============

    event DurationBoundsUpdated(uint256 minDuration, uint256 maxDuration);
    event MaxActiveDistributionsUpdated(uint256 maxActiveDistributions);
    event DistributionRegistered(
        uint256 indexed distributionId,
        address indexed stablecoin,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    );
    event YieldReleased(
        uint256 indexed distributionId, uint256 amountReleased, uint256 cumulativeReleased, uint256 timestamp
    );
    event DistributionCompleted(uint256 indexed distributionId, uint256 totalAmount);
    event DistributionCancelled(uint256 indexed distributionId, address indexed refundTo, uint256 amountRefunded);

    // ============ Functions ============
}
