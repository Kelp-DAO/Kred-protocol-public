// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IAllowlistRegistry
 * @notice Interface for AllowlistRegistry contract
 */
interface IAllowlistRegistry {
    // ============ Custom Errors ============

    error AlreadyAllowed(address account);
    error NotAllowed(address account);
    error AlreadyForbidden(address account);
    error NotForbidden(address account);

    // =========== Events ============

    event AddressAllowed(address indexed account);
    event AddressDisallowed(address indexed account);
    event AddressAddedToForbiddenList(address indexed account);
    event AddressRemovedFromForbiddenList(address indexed account);

    // =========== Functions ============
    function isAllowed(address account) external view returns (bool);
    function isForbidden(address account) external view returns (bool);
}
