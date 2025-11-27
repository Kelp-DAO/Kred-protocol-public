// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IKredConfig } from "src/interfaces/IKredConfig.sol";

/**
 * @title KredConfig
 * @notice Centralized configuration contract for the Kred protocol with role-based access control
 * @dev Manages admin and pauser roles for all protocol contracts
 */
contract KredConfig is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    // =========== Role Definitions ============

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /**
     * @notice Initialize the contract with initial admin
     * @param initialAdmin The address that will have the default admin role
     */
    function initialize(address initialAdmin) external initializer {
        if (initialAdmin == address(0)) {
            revert IKredConfig.ZeroAddressNotAllowed();
        }

        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Grant roles to initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MANAGER_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
    }

    // ============ Upgradeability ============

    /**
     * @notice Authorize an upgrade to a new implementation
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
