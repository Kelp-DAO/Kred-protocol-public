// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

// ============ Structs ============

/// @notice Struct to store redemption information
struct Redemption {
    uint256 amount; // Amount of KUSD to redeem
    address stablecoin; // Stablecoin to receive
    bool completed; // Whether redemption has been completed
    uint256 unlockTime; // Time when redemption can be completed
}

/**
 * @title IKUSD
 * @notice Interface for the KUSD token contract
 */
interface IKUSD {
    // ============ Custom Errors ============

    error NotAllowlisted();
    error AddressOnForbiddenList(address account);
    error StablecoinNotAccepted(address stablecoin);
    error ZeroAmount();
    error RedemptionAlreadyCompleted(uint256 redemptionId);
    error InvalidRedemption(uint256 redemptionId);
    error AmountTooSmall();
    error InsufficientStablecoinBalance(address stablecoin, uint256 required, uint256 available);
    error GlobalDepositLimitExceeded(uint256 limit, uint256 currentTotal, uint256 attemptedDeposit);
    error DepositLimitExceeded(address stablecoin, uint256 limit, uint256 currentTotal, uint256 attemptedDeposit);
    error RedemptionNotReady();
    error TooManyOpenRedemptions(uint256 current, uint256 maxAllowed);
    error RedemptionDelayOutOfBounds(uint256 minAllowed, uint256 maxAllowed, uint256 requested);
    error InvalidRedemptionDelayBounds(uint256 newMinDelay, uint256 newMaxDelay);
    error BelowMinDeposit(uint256 minRequired);
    error BelowMinRedemption(uint256 minRequired);

    // =========== Events ============

    event StablecoinAccepted(address indexed stablecoin, bool accepted);
    event GlobalDepositLimitUpdated(uint256 newLimit);
    event DepositLimitUpdated(address indexed stablecoin, uint256 newLimit);
    event Deposit(
        address indexed user,
        address indexed stablecoin,
        uint256 stablecoinAmount,
        uint256 kusdAmount,
        string referralId
    );
    event RedemptionInitiated(
        address indexed user, uint256 indexed redemptionId, uint256 kusdAmount, address stablecoin, uint256 unlockTime
    );
    event RedemptionCompleted(
        address indexed user, uint256 indexed redemptionId, address stablecoin, uint256 stablecoinAmount
    );
    event RedemptionCancelled(address indexed user, uint256 indexed redemptionId);
    event RedemptionDelayUpdated(uint256 newRedemptionDelay);
    event MaxOpenRedemptionsPerUserUpdated(uint256 newMax);
    event RedemptionDelayBoundsUpdated(uint256 newMinDelay, uint256 newMaxDelay);
    event MinDepositAmountUpdated(uint256 newMinDepositAmount);
    event MinRedemptionAmountUpdated(uint256 newMinRedemptionAmount);
    event CustodyAddressUpdated(address indexed newCustodyAddress);
    event AssetsMovedToCustody(address indexed stablecoin, address indexed custodyAddress, uint256 amount);

    // ============ Functions ============

    function deposit(address stablecoin, uint256 amount, string calldata referralId) external;
    function acceptedStablecoins(address stablecoin) external view returns (bool accepted);
}
