// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title ISKUSD
 * @notice Interface for the sKUSD token contract
 */
interface ISKUSD {
    // ============ Custom Errors ============

    error AddressOnForbiddenList(address account);
    error InsufficientBalance();
    error SlippageExceeded();
    error ZeroAmountNotAllowed();

    // =========== Events ============

    event DepositWithReferral(
        address indexed depositor,
        address indexed receiver,
        uint256 kusdDepositAmount,
        uint256 skusdMintAmount,
        string referralId
    );

    event KUSDMintedForVault(address indexed stablecoin, uint256 stablecoinDepositAmount, uint256 kusdMintAmount);

    // ============ Functions ============

    function mintKUSDForVault(address stablecoin, uint256 amount) external;
    function getExchangeRate() external view returns (uint256);
}
