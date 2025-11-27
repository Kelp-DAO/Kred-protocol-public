// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IKredConfig } from "src/interfaces/IKredConfig.sol";

/**
 * @title KredConfigRoleChecker - Kred Config Role Checker Contract
 * @notice Abstract contract that provides role-based access control modifiers
 */
abstract contract KredConfigRoleChecker is Initializable {
    // =========== State Variables ============

    /// @notice KredConfig contract instance
    IKredConfig public kredConfig;

    // =========== Events ============

    event KredConfigUpdated(address indexed kredConfig);

    // =========== Custom Errors ============

    error CallerNotKredConfigManager();
    error CallerNotKredConfigPauser();
    error CallerNotKredConfigAdmin();
    error ZeroAddressNotAllowed();

    // =========== Modifiers ============

    /// @notice Modifier to restrict access to only KredConfig admins
    modifier onlyAdmin() {
        _checkAdminRole();
        _;
    }

    /// @notice Modifier to restrict access to only KredConfig managers
    modifier onlyManager() {
        _checkManagerRole();
        _;
    }

    /// @notice Modifier to restrict access to only KredConfig pausers
    modifier onlyPauser() {
        _checkPauserRole();
        _;
    }

    // ============ Internal Initializer ============

    /**
     * @notice Initializes the KredConfigRoleChecker contract
     * @dev To be called in the initializer of the child contract
     * @param kredConfigAddr The KredConfig contract address
     */
    function __KredConfigRoleChecker_init(address kredConfigAddr) internal onlyInitializing {
        if (kredConfigAddr == address(0)) {
            revert IKredConfig.ZeroAddressNotAllowed();
        }
        kredConfig = IKredConfig(kredConfigAddr);
        emit KredConfigUpdated(kredConfigAddr);
    }

    // ============ Admin Functions ============

    /**
     * @notice Updates the KredConfig contract address
     * @param kredConfigAddr The new KredConfig contract address
     */
    function updateKredConfig(address kredConfigAddr) external virtual onlyAdmin {
        if (kredConfigAddr == address(0)) {
            revert IKredConfig.ZeroAddressNotAllowed();
        }
        kredConfig = IKredConfig(kredConfigAddr);
        emit KredConfigUpdated(kredConfigAddr);
    }

    // ============ Internal Functions ============

    /// @notice Internal function to check if the caller has the admin role in KredConfig
    function _checkAdminRole() internal view {
        if (!kredConfig.hasRole(kredConfig.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert CallerNotKredConfigAdmin();
        }
    }

    /// @notice Internal function to check if the caller has the manager role in KredConfig
    function _checkManagerRole() internal view {
        if (!kredConfig.hasRole(kredConfig.MANAGER_ROLE(), msg.sender)) {
            revert CallerNotKredConfigManager();
        }
    }

    /// @notice Internal function to check if the caller has the pauser role in KredConfig
    function _checkPauserRole() internal view {
        if (!kredConfig.hasRole(kredConfig.PAUSER_ROLE(), msg.sender)) {
            revert CallerNotKredConfigPauser();
        }
    }
}
