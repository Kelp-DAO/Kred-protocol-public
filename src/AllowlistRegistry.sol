// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IAllowlistRegistry } from "src/interfaces/IAllowlistRegistry.sol";
import { KredConfigRoleChecker } from "src/KredConfigRoleChecker.sol";

/**
 * @title AllowlistRegistry
 * @notice Registry contract to manage allowlist for deposits and redemptions
 * @dev Uses KredConfig for role-based access control
 */
contract AllowlistRegistry is IAllowlistRegistry, Initializable, UUPSUpgradeable, KredConfigRoleChecker {
    // =========== State Variables ============

    /// @notice Mapping of addresses that are allowed to deposit and redeem
    mapping(address account => bool allowed) public isAllowed;

    /// @notice Mapping of addresses that are forbidden from receiving or sending KUSD
    mapping(address account => bool forbidden) public isForbidden;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /**
     * @notice Initialize the AllowlistRegistry contract
     * @param _kredConfig The KredConfig contract address for role management
     */
    function initialize(address _kredConfig) external initializer {
        if (_kredConfig == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __UUPSUpgradeable_init();
        __KredConfigRoleChecker_init(_kredConfig);
    }

    // ============ Allowlist Management ============

    /**
     * @notice Add an address to the allowlist
     * @param account The address to allow
     */
    function allowAddress(address account) external onlyManager {
        _allowAddress(account);
    }

    /**
     * @notice Remove an address from the allowlist
     * @param account The address to disallow
     */
    function disallowAddress(address account) external onlyManager {
        _disallowAddress(account);
    }

    /**
     * @notice Batch add addresses to the allowlist
     * @param accounts The addresses to allow
     */
    function allowAddresses(address[] calldata accounts) external onlyManager {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length;) {
            _allowAddress(accounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Batch remove addresses from the allowlist
     * @param accounts The addresses to disallow
     */
    function disallowAddresses(address[] calldata accounts) external onlyManager {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length;) {
            _disallowAddress(accounts[i]);
            unchecked {
                i++;
            }
        }
    }

    // ============ Forbidden List Management ============

    /**
     * @notice Add an address to the forbidden list
     * @param account The address to add
     */
    function addToForbiddenList(address account) external onlyManager {
        _addToForbiddenList(account);
    }

    /**
     * @notice Remove an address from the forbidden list
     * @param account The address to remove
     */
    function removeFromForbiddenList(address account) external onlyManager {
        _removeFromForbiddenList(account);
    }

    /**
     * @notice Batch add addresses to the forbidden list
     * @param accounts The addresses to add
     */
    function addToForbiddenListBatch(address[] calldata accounts) external onlyManager {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length;) {
            _addToForbiddenList(accounts[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Batch remove addresses from the forbidden list
     * @param accounts The addresses to remove
     */
    function removeFromForbiddenListBatch(address[] calldata accounts) external onlyManager {
        uint256 length = accounts.length;
        for (uint256 i = 0; i < length;) {
            _removeFromForbiddenList(accounts[i]);
            unchecked {
                i++;
            }
        }
    }

    // ============ View Functions ============

    /**
     * @notice Check if an address is allowed
     * @param account The address to check
     * @return bool True if the address is allowed
     */
    function checkAllowed(address account) external view returns (bool) {
        return isAllowed[account];
    }

    /**
     * @notice Check if an address is forbidden
     * @param account The address to check
     * @return bool True if the address is forbidden
     */
    function checkForbidden(address account) external view returns (bool) {
        return isForbidden[account];
    }

    // ============ Internal Functions ============

    /// @notice Internal function to add an address to the allowlist
    function _allowAddress(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (isAllowed[account]) {
            revert AlreadyAllowed(account);
        }

        isAllowed[account] = true;
        emit AddressAllowed(account);
    }

    /// @notice Internal function to remove an address from the allowlist
    function _disallowAddress(address account) internal {
        if (!isAllowed[account]) {
            revert NotAllowed(account);
        }

        isAllowed[account] = false;
        emit AddressDisallowed(account);
    }

    /// @notice Internal function to add an address to the forbidden list
    function _addToForbiddenList(address account) internal {
        if (account == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (isForbidden[account]) {
            revert AlreadyForbidden(account);
        }

        isForbidden[account] = true;
        emit AddressAddedToForbiddenList(account);
    }

    /// @notice Internal function to remove an address from the forbidden list
    function _removeFromForbiddenList(address account) internal {
        if (!isForbidden[account]) {
            revert NotForbidden(account);
        }

        isForbidden[account] = false;
        emit AddressRemovedFromForbiddenList(account);
    }

    // ============ Upgradeability ============

    /**
     * @notice Authorize an upgrade to a new implementation
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin { }
}
