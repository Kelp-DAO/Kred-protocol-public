// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {
    ERC4626Upgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AllowlistRegistry } from "src/AllowlistRegistry.sol";
import { IKUSD } from "src/interfaces/IKUSD.sol";
import { ISKUSD } from "src/interfaces/ISKUSD.sol";
import { KredConfigRoleChecker } from "src/KredConfigRoleChecker.sol";

/**
 * @title sKUSD
 * @notice Staked KUSD - A yield-bearing token backed by KUSD stablecoin
 * @dev Uses UUPS proxy pattern for upgradeability and KredConfig for role-based access control
 */
contract SKUSD is
    ISKUSD,
    Initializable,
    ERC4626Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    KredConfigRoleChecker
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Constant representing one share of sKUSD
    uint256 public constant ONE_SHARE = 1e18;

    // ============ State Variables ============

    /// @notice Registry contract that manages the allowlist and forbidden list
    AllowlistRegistry public allowlistRegistry;

    // ============ Modifiers ============

    /// @notice Modifier to restrict access to non-forbidden (i.e. non-blacklisted) addresses
    modifier notForbidden(address account) {
        _notForbidden(account);
        _;
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /**
     * @notice Initialize the sKUSD contract
     * @param _kusdAddress The underlying asset address (KUSD)
     * @param _kredConfig The KredConfig contract address for role management
     * @param _allowlistRegistry The address of the allowlist registry
     */
    function initialize(IERC20 _kusdAddress, address _kredConfig, address _allowlistRegistry) external initializer {
        if (address(_kusdAddress) == address(0)) revert ZeroAddressNotAllowed();
        if (_kredConfig == address(0)) revert ZeroAddressNotAllowed();
        if (_allowlistRegistry == address(0)) revert ZeroAddressNotAllowed();

        __ERC20_init("Staked KUSD", "sKUSD");
        __ERC4626_init(_kusdAddress);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __KredConfigRoleChecker_init(_kredConfig);

        allowlistRegistry = AllowlistRegistry(_allowlistRegistry);
    }

    // ============ ERC4626 Overrides ============

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overrides ERC4626 `deposit` to add whenNotPaused, nonReentrant, and notForbidden modifiers
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        override
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overrides ERC4626 `mint` to add whenNotPaused, nonReentrant, and notForbidden modifiers
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        override
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overrides ERC4626 `withdraw` to add whenNotPaused, nonReentrant, and notForbidden modifiers
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        notForbidden(owner)
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @inheritdoc ERC4626Upgradeable
     * @dev Overrides ERC4626 `redeem` to add whenNotPaused, nonReentrant, and notForbidden modifiers
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        notForbidden(owner)
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    // ============ Slippage-Protected ERC4626 Functions ============

    /**
     * @notice Deposit KUSD and mint sKUSD with a referral ID and slippage protection
     * @param assets The amount of KUSD to deposit
     * @param receiver The address receiving the minted sKUSD
     * @param minShares The minimum amount of sKUSD a user is willing to accept for `assets` KUSD
     * @param referralId The referral ID associated with the deposit
     * @return shares The amount of sKUSD minted
     */
    function deposit(
        uint256 assets,
        address receiver,
        uint256 minShares,
        string calldata referralId
    )
        external
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        returns (uint256 shares)
    {
        uint256 preview = previewDeposit(assets);
        if (preview < minShares) revert SlippageExceeded();

        shares = super.deposit(assets, receiver);

        emit DepositWithReferral(msg.sender, receiver, assets, shares, referralId);
    }

    /**
     * @notice Mint sKUSD by depositing KUSD with a referral ID and slippage protection
     * @param shares The amount of sKUSD to mint
     * @param receiver The address receiving the minted sKUSD
     * @param maxAssets The maximum amount of KUSD a user is willing to pay for `shares` sKUSD
     * @param referralId The referral ID associated with the deposit
     * @return assets The amount of KUSD deposited
     */
    function mint(
        uint256 shares,
        address receiver,
        uint256 maxAssets,
        string calldata referralId
    )
        external
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        returns (uint256 assets)
    {
        uint256 preview = previewMint(shares);
        if (preview > maxAssets) revert SlippageExceeded();

        assets = super.mint(shares, receiver);

        emit DepositWithReferral(msg.sender, receiver, assets, shares, referralId);
    }

    /**
     * @notice Withdraw KUSD by burning sKUSD with slippage protection
     * @param assets The amount of KUSD to withdraw
     * @param receiver The address receiving the withdrawn KUSD
     * @param owner The address of the owner of the sKUSD being burned
     * @param maxShares The maximum amount of sKUSD a user is willing to burn to receive `assets` KUSD
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxShares
    )
        external
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        notForbidden(owner)
        returns (uint256 shares)
    {
        uint256 preview = previewWithdraw(assets);
        if (preview > maxShares) revert SlippageExceeded();

        shares = super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Redeem sKUSD for KUSD with slippage protection
     * @param shares The amount of sKUSD to redeem
     * @param receiver The address receiving the redeemed KUSD
     * @param owner The address of the owner of the sKUSD being redeemed
     * @param minAssets The minimum amount of KUSD a user is willing to accept for burning `shares` sKUSD
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    )
        external
        whenNotPaused
        nonReentrant
        notForbidden(msg.sender)
        notForbidden(receiver)
        notForbidden(owner)
        returns (uint256 assets)
    {
        uint256 preview = previewRedeem(shares);
        if (preview < minAssets) revert SlippageExceeded();

        assets = super.redeem(shares, receiver, owner);
    }

    // ============ View Functions ============

    /**
     * @notice Get the current exchange rate of sKUSD to KUSD
     * @return The exchange rate scaled by 1e18
     */
    function getExchangeRate() external view returns (uint256) {
        return totalSupply() == 0 ? ONE_SHARE : convertToAssets(ONE_SHARE);
    }

    // ============ Yield Conversion ============

    /**
     * @notice Mint KUSD into the vault from a specified stablecoin
     * @dev `stablecoin` must be approved as an accepted asset in the KUSD contract and sKUSD must be allowlisted to
     * mint KUSD
     * @param stablecoin The address of the stablecoin to convert to KUSD
     * @param amount The amount of the stablecoin to convert to KUSD
     */
    function mintKUSDForVault(address stablecoin, uint256 amount) external nonReentrant onlyManager {
        if (stablecoin == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert ZeroAmountNotAllowed();

        if (IERC20(stablecoin).balanceOf(address(this)) < amount) revert InsufficientBalance();

        address kusd = address(asset());

        IERC20(stablecoin).safeIncreaseAllowance(kusd, amount);

        uint256 balanceBefore = totalAssets();
        IKUSD(kusd).deposit(stablecoin, amount, "");
        uint256 kusdMintAmount = totalAssets() - balanceBefore;

        emit KUSDMintedForVault(stablecoin, amount, kusdMintAmount);
    }

    // ============ ERC20 Overrides ============

    /**
     * @notice Override transfer to check forbidden list and pause status
     */
    function transfer(
        address to,
        uint256 value
    )
        public
        override(ERC20Upgradeable, IERC20)
        whenNotPaused
        notForbidden(msg.sender)
        notForbidden(to)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /**
     * @notice Override transferFrom to check forbidden list and pause status
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        override(ERC20Upgradeable, IERC20)
        whenNotPaused
        notForbidden(from)
        notForbidden(to)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    // ============ Pause Management ============

    /**
     * @notice Pause the contract
     * @dev Only callable by addresses with PAUSER_ROLE
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     */
    function unpause() external onlyAdmin {
        _unpause();
    }

    // ============ Internal Helper Functions ============

    /// @notice Internal function to check if an address is not forbidden
    function _notForbidden(address account) internal view {
        if (allowlistRegistry.isForbidden(account)) {
            revert AddressOnForbiddenList(account);
        }
    }

    // ============ Upgradeability ============

    /**
     * @notice Authorizes an upgrade to a new implementation contract.
     * @param newImplementation The address of the new implementation contract to upgrade to.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin { }
}
