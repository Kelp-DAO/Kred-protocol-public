// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

/**
 * @title IKredConfig
 * @notice Interface for KredConfig contract
 */
interface IKredConfig {
    // =========== Custom Errors ============

    error ZeroAddressNotAllowed();

    // =========== Role Getters ============

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function MANAGER_ROLE() external view returns (bytes32);
    function PAUSER_ROLE() external view returns (bytes32);

    // =========== Role Checking ============

    function hasRole(bytes32 role, address account) external view returns (bool);
}
