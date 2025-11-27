// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AllowlistRegistry } from "src/AllowlistRegistry.sol";
import { IKUSD, Redemption } from "src/interfaces/IKUSD.sol";
import { KredConfigRoleChecker } from "src/KredConfigRoleChecker.sol";

/**
 * @title KUSD
 * @notice Kred USD - An upgradeable stablecoin backed by other stablecoins (USDT, USDC, etc.)
 * @dev Uses UUPS proxy pattern for upgradeability and KredConfig for role-based access control
 */
contract KUSD is
    IKUSD,
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    KredConfigRoleChecker
{
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @notice Decimals for KUSD (18)
    uint8 private constant KUSD_DECIMALS = 18;

    // ============ State Variables ============

    /// @notice Minimum deposit amount in KUSD decimals (18)
    /// @dev 0 means no minimum deposit amount is enforced
    uint256 public minDepositAmount;

    /// @notice Minimum redemption amount in KUSD decimals (18)
    /// @dev 0 means no minimum redemption amount is enforced
    uint256 public minRedemptionAmount;

    /// @notice Redemption delay in seconds
    uint256 public redemptionDelay;

    /// @notice Maximum number of open redemptions allowed per user at any given point in time
    uint256 public maxOpenRedemptionsPerUser;

    /// @notice Minimum redemption delay in seconds
    /// @dev A min delay of 0 means no floor for the redemptionDelay value
    uint256 public minRedemptionDelay;

    /// @notice Maximum redemption delay in seconds
    /// @dev A max delay of 0 means no ceiling for the redemptionDelay value
    uint256 public maxRedemptionDelay;

    /// @notice Registry contract that manages the allowlist
    AllowlistRegistry public allowlistRegistry;

    /// @notice Global deposit limit across all accepted stablecoins (in KUSD decimals - 18)
    /// @dev A limit of 0 means no deposits allowed. Use type(uint256).max for unlimited deposits.
    uint256 public globalDepositLimit;

    /// @notice Total amount deposited globally across all stablecoins (in KUSD decimals - 18)
    uint256 public totalDepositedGlobal;

    /// @notice Mapping of deposit limits per stablecoin (in KUSD decimals - 18)
    /// @dev A limit of 0 means no deposits allowed. Use type(uint256).max for unlimited deposits.
    mapping(address stablecoin => uint256 limit) public depositLimits;

    /// @notice Mapping to track total deposits per stablecoin (in KUSD decimals - 18)
    mapping(address stablecoin => uint256 totalDeposited) public totalDepositedPerStablecoin;

    /// @notice Mapping of stablecoins that can be used for deposits/redemptions
    mapping(address stablecoin => bool accepted) public acceptedStablecoins;

    /// @notice Mapping from user => redemptionId => Redemption
    mapping(address user => mapping(uint256 redemptionId => Redemption)) public redemptions;

    /// @notice Counter for redemptions per user
    mapping(address user => uint256 count) public redemptionCounter;

    /// @notice Mapping to track the number of open redemptions per user
    /// @dev Set to 0 to disable the limit on open redemptions
    mapping(address => uint256) public openRedemptionCount;

    /// @notice Address that receives stablecoins when moveAssetsToCustody is called
    address public custodyAddress;

    // ============ Modifiers ============

    /// @notice Modifier to restrict access to only allowlisted (i.e. whitelisted) addresses
    modifier onlyAllowlisted() {
        _onlyAllowlisted(msg.sender);
        _;
    }

    /// @notice Modifier to restrict access to non-forbidden (i.e. non-blacklisted) addresses
    modifier notForbidden(address account) {
        _notForbidden(account);
        _;
    }

    /// @notice Modifier to limit the action to only supported stablecoins
    modifier onlySupportedStablecoin(address stablecoin) {
        _onlySupportedStablecoin(stablecoin);
        _;
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /**
     * @notice Initialize the contract
     * @param _kredConfig The address of the KredConfig contract
     * @param _allowlistRegistry The address of the allowlist registry
     */
    function initialize(address _kredConfig, address _allowlistRegistry) external initializer {
        if (_kredConfig == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (_allowlistRegistry == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __ERC20_init("Kred USD", "KUSD");
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __KredConfigRoleChecker_init(_kredConfig);

        allowlistRegistry = AllowlistRegistry(_allowlistRegistry);
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

    // ============ Stablecoin Management ============

    /**
     * @notice Set the minimum deposit amount
     * @param newMinDepositAmount The new minimum deposit amount in KUSD decimals (18)
     */
    function setMinDepositAmount(uint256 newMinDepositAmount) external onlyManager {
        minDepositAmount = newMinDepositAmount;
        emit MinDepositAmountUpdated(newMinDepositAmount);
    }

    /**
     * @notice Set the global deposit limit across all stablecoins
     * @param newLimit The new global deposit limit (in KUSD decimals - 18).
     *                 Set to 0 to prevent all deposits. Set to type(uint256).max for unlimited deposits.
     */
    function setGlobalDepositLimit(uint256 newLimit) external onlyManager {
        globalDepositLimit = newLimit; // use type(uint256).max for “no cap”
        emit GlobalDepositLimitUpdated(newLimit);
    }

    /**
     * @notice Set the deposit limit for a specific stablecoin
     * @param stablecoin The address of the stablecoin
     * @param limit The maximum amount of KUSD that can be minted from this stablecoin (18 decimals).
     *              Set to 0 to prevent all deposits. Set to type(uint256).max for unlimited deposits.
     */
    function setDepositLimit(
        address stablecoin,
        uint256 limit
    )
        external
        onlyManager
        onlySupportedStablecoin(stablecoin)
    {
        depositLimits[stablecoin] = limit;
        emit DepositLimitUpdated(stablecoin, limit);
    }

    /**
     * @notice Set whether a stablecoin is accepted for deposits/redemptions
     * @param stablecoin The address of the stablecoin
     * @param accepted Whether the stablecoin is accepted
     */
    function setStablecoinAccepted(address stablecoin, bool accepted) external onlyManager {
        if (stablecoin == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        acceptedStablecoins[stablecoin] = accepted;
        emit StablecoinAccepted(stablecoin, accepted);
    }

    /**
     * @notice Set the custody address that receives stablecoins when moveAssetsToCustody is called
     * @dev Only callable by addresses with DEFAULT_ADMIN_ROLE
     * @param newCustodyAddress The new custody address
     */
    function setCustodyAddress(address newCustodyAddress) external onlyAdmin {
        if (newCustodyAddress == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        custodyAddress = newCustodyAddress;
        emit CustodyAddressUpdated(newCustodyAddress);
    }

    /**
     * @notice Move stablecoins from the contract to the custody address
     * @dev Only callable by addresses with MANAGER_ROLE
     * @param stablecoin The address of the stablecoin to move
     * @param amount The amount of stablecoin to move (in stablecoin's decimals)
     */
    function moveAssetsToCustody(
        address stablecoin,
        uint256 amount
    )
        external
        onlyManager
        onlySupportedStablecoin(stablecoin)
    {
        if (custodyAddress == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Check contract has enough stablecoin
        uint256 contractBalance = IERC20(stablecoin).balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientStablecoinBalance(stablecoin, amount, contractBalance);
        }

        // Transfer stablecoin to custody address
        IERC20(stablecoin).safeTransfer(custodyAddress, amount);

        emit AssetsMovedToCustody(stablecoin, custodyAddress, amount);
    }

    // ============ Redemption Settings Management ============

    /**
     * @notice Set the minimum redemption amount
     * @param newMinRedemptionAmount The new minimum redemption amount in KUSD decimals (18)
     */
    function setMinRedemptionAmount(uint256 newMinRedemptionAmount) external onlyManager {
        minRedemptionAmount = newMinRedemptionAmount;
        emit MinRedemptionAmountUpdated(newMinRedemptionAmount);
    }

    /**
     * @notice Set the redemption delay
     * @dev The new delay must be within the min and max bounds (if set)
     * @param newDelay The new redemption delay in seconds
     */
    function setRedemptionDelay(uint256 newDelay) external onlyManager {
        if (newDelay < minRedemptionDelay || (maxRedemptionDelay != 0 && newDelay > maxRedemptionDelay)) {
            revert RedemptionDelayOutOfBounds(minRedemptionDelay, maxRedemptionDelay, newDelay);
        }
        redemptionDelay = newDelay;
        emit RedemptionDelayUpdated(newDelay);
    }

    /**
     * @notice Set the redemption delay bounds
     * @dev If ceiling is desired, set newMaxDelay >= newMinDelay, else set newMaxDelay = 0 to remove ceiling
     * @param newMinDelay The new minimum redemption delay in seconds
     * @param newMaxDelay The new maximum redemption delay in seconds
     */
    function setRedemptionDelayBounds(uint256 newMinDelay, uint256 newMaxDelay) external onlyManager {
        if (newMaxDelay != 0 && newMaxDelay < newMinDelay) {
            revert InvalidRedemptionDelayBounds(newMinDelay, newMaxDelay);
        }

        // Auto-clamp current redemptionDelay to fit within the new bounds
        if (redemptionDelay < newMinDelay) redemptionDelay = newMinDelay;
        if (newMaxDelay != 0 && redemptionDelay > newMaxDelay) redemptionDelay = newMaxDelay;

        // Set the new bounds
        minRedemptionDelay = newMinDelay;
        maxRedemptionDelay = newMaxDelay;
        emit RedemptionDelayBoundsUpdated(newMinDelay, newMaxDelay);
    }

    /**
     * @notice Set the maximum number of open redemptions allowed per user
     * @param newMax The new maximum number of open redemptions
     */
    function setMaxOpenRedemptionsPerUser(uint256 newMax) external onlyManager {
        maxOpenRedemptionsPerUser = newMax;
        emit MaxOpenRedemptionsPerUserUpdated(newMax);
    }

    // ============ Deposit Functions ============

    /**
     * @notice Deposit stablecoins to mint KUSD
     * @param stablecoin The address of the stablecoin to deposit
     * @param amount The amount of stablecoin to deposit (in that stablecoin's decimals)
     * @param referralId Referral ID for tracking purposes
     */
    function deposit(
        address stablecoin,
        uint256 amount,
        string calldata referralId
    )
        external
        whenNotPaused
        nonReentrant
        onlyAllowlisted
        notForbidden(msg.sender)
        onlySupportedStablecoin(stablecoin)
    {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Calculate KUSD amount (convert to KUSD decimals - 18)
        uint256 kusdAmount = _convertToKUSD(stablecoin, amount);
        if (minDepositAmount != 0 && kusdAmount < minDepositAmount) {
            revert BelowMinDeposit(minDepositAmount);
        }

        // Check global deposit limit (0 means no deposits allowed, type(uint256).max means unlimited)
        if (globalDepositLimit != type(uint256).max) {
            uint256 newGlobal = totalDepositedGlobal + kusdAmount;
            if (newGlobal > globalDepositLimit) {
                revert GlobalDepositLimitExceeded(globalDepositLimit, totalDepositedGlobal, kusdAmount);
            }
            totalDepositedGlobal = newGlobal;
        }

        // Check per-stablecoin deposit limit (0 means no deposits allowed, type(uint256).max means unlimited)
        uint256 limit = depositLimits[stablecoin];
        if (limit != type(uint256).max) {
            uint256 currentTotal = totalDepositedPerStablecoin[stablecoin];
            uint256 newTotal = currentTotal + kusdAmount;
            if (newTotal > limit) {
                revert DepositLimitExceeded(stablecoin, limit, currentTotal, kusdAmount);
            }
            totalDepositedPerStablecoin[stablecoin] = newTotal;
        }

        // Transfer stablecoin from user
        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);

        // Mint KUSD to user
        _mint(msg.sender, kusdAmount);

        emit Deposit(msg.sender, stablecoin, amount, kusdAmount, referralId);
    }

    // ============ Redemption Functions ============

    /**
     * @notice Initiate a redemption of KUSD for stablecoins (step 1)
     * @param kusdAmount The amount of KUSD to redeem (18 decimals)
     * @param stablecoin The stablecoin to receive
     * @return redemptionId The ID of the redemption
     */
    function initiateRedemption(
        uint256 kusdAmount,
        address stablecoin
    )
        external
        whenNotPaused
        nonReentrant
        onlyAllowlisted
        notForbidden(msg.sender)
        onlySupportedStablecoin(stablecoin)
        returns (uint256 redemptionId)
    {
        if (kusdAmount == 0) {
            revert ZeroAmount();
        }
        if (minRedemptionAmount != 0 && kusdAmount < minRedemptionAmount) {
            revert BelowMinRedemption(minRedemptionAmount);
        }
        if (maxOpenRedemptionsPerUser != 0) {
            uint256 currentCount = openRedemptionCount[msg.sender];
            if (currentCount >= maxOpenRedemptionsPerUser) {
                revert TooManyOpenRedemptions(currentCount, maxOpenRedemptionsPerUser);
            }
        }

        // Transfer KUSD from user to the contract
        _transfer(msg.sender, address(this), kusdAmount);

        // Create redemption record
        redemptionId = redemptionCounter[msg.sender]++;
        uint256 unlockTime = block.timestamp + redemptionDelay;
        redemptions[msg.sender][redemptionId] =
            Redemption({ amount: kusdAmount, stablecoin: stablecoin, completed: false, unlockTime: unlockTime });

        // Increment open redemption count
        openRedemptionCount[msg.sender]++;

        emit RedemptionInitiated(msg.sender, redemptionId, kusdAmount, stablecoin, unlockTime);
    }

    /**
     * @notice Complete a redemption (step 2)
     * @param redemptionId The ID of the redemption
     */
    function completeRedemption(uint256 redemptionId) external whenNotPaused nonReentrant notForbidden(msg.sender) {
        _completeRedemption(msg.sender, redemptionId);
    }

    /**
     * @notice Complete a redemption as a manager
     * @param user The user who initiated the redemption
     * @param redemptionId The ID of the redemption
     */
    function completeRedemptionAsManager(
        address user,
        uint256 redemptionId
    )
        external
        nonReentrant
        onlyManager
        notForbidden(user)
    {
        _completeRedemption(user, redemptionId);
    }

    /**
     * @notice Cancel a redemption and return KUSD to user
     * @param redemptionId The ID of the redemption to cancel
     */
    function cancelRedemption(uint256 redemptionId) external nonReentrant whenNotPaused notForbidden(msg.sender) {
        Redemption storage redemption = redemptions[msg.sender][redemptionId];

        if (redemption.completed) {
            revert RedemptionAlreadyCompleted(redemptionId);
        }
        if (redemption.amount == 0) {
            revert InvalidRedemption(redemptionId);
        }

        uint256 kusdAmount = redemption.amount;

        // Mark as completed (cancelled)
        redemption.completed = true;

        // Return KUSD to user
        _transfer(address(this), msg.sender, kusdAmount);

        // Decrement open redemption count
        if (openRedemptionCount[msg.sender] != 0) openRedemptionCount[msg.sender] -= 1;

        emit RedemptionCancelled(msg.sender, redemptionId);
    }

    // ============ Limits View Functions ============

    /**
     *  @notice Gets the remaining global capacity available for new deposits (in KUSD decimals - 18)
     * @return The remaining global capacity
     */
    function remainingGlobalCapacity() public view returns (uint256) {
        uint256 limit = globalDepositLimit;

        // Unlimited cap
        if (limit == type(uint256).max) return type(uint256).max;

        // Hard block or fully used
        if (limit == 0 || totalDepositedGlobal >= limit) return 0;

        return limit - totalDepositedGlobal;
    }

    /**
     * @notice Gets the remaining capacity for a specific stablecoin (in KUSD decimals - 18)
     * @param stablecoin The address of the stablecoin
     * @return The remaining capacity for the stablecoin
     */
    function remainingPerAssetCapacity(address stablecoin)
        public
        view
        onlySupportedStablecoin(stablecoin)
        returns (uint256)
    {
        uint256 limit = depositLimits[stablecoin];

        // Unlimited per-asset cap
        if (limit == type(uint256).max) return type(uint256).max;

        // Hard block or fully used
        uint256 usedCapacity = totalDepositedPerStablecoin[stablecoin];
        if (limit == 0 || usedCapacity >= limit) return 0;

        return limit - usedCapacity;
    }

    /**
     * @notice Gets the effective remaining capacity for a specific asset as min(global, per-asset cap)
     * @param stablecoin The address of the stablecoin
     * @return The effective remaining capacity for the stablecoin
     */
    function effectivePerAssetCapacity(address stablecoin)
        external
        view
        onlySupportedStablecoin(stablecoin)
        returns (uint256)
    {
        uint256 remainingGlobal = remainingGlobalCapacity();
        uint256 remainingPerAsset = remainingPerAssetCapacity(stablecoin);
        return remainingGlobal < remainingPerAsset ? remainingGlobal : remainingPerAsset;
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
        override
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
        override
        whenNotPaused
        notForbidden(from)
        notForbidden(to)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    // ============ Internal Helper Functions ============

    /**
     * @notice Convert stablecoin amount to KUSD amount
     * @param stablecoin The address of the stablecoin
     * @param amount The amount in stablecoin decimals
     * @return The amount in KUSD decimals (18)
     */
    function _convertToKUSD(address stablecoin, uint256 amount) internal view returns (uint256) {
        uint8 stablecoinDecimals = IERC20Metadata(stablecoin).decimals();

        if (stablecoinDecimals == KUSD_DECIMALS) {
            return amount;
        } else if (stablecoinDecimals < KUSD_DECIMALS) {
            return amount * (10 ** (KUSD_DECIMALS - stablecoinDecimals));
        } else {
            return amount / (10 ** (stablecoinDecimals - KUSD_DECIMALS));
        }
    }

    /**
     * @notice Convert KUSD amount to stablecoin amount
     * @param stablecoin The address of the stablecoin
     * @param kusdAmount The amount in KUSD decimals (18)
     * @return The amount in stablecoin decimals
     */
    function _convertFromKUSD(address stablecoin, uint256 kusdAmount) internal view returns (uint256) {
        uint8 stablecoinDecimals = IERC20Metadata(stablecoin).decimals();

        if (stablecoinDecimals == KUSD_DECIMALS) {
            return kusdAmount;
        } else if (stablecoinDecimals < KUSD_DECIMALS) {
            return kusdAmount / (10 ** (KUSD_DECIMALS - stablecoinDecimals));
        } else {
            return kusdAmount * (10 ** (stablecoinDecimals - KUSD_DECIMALS));
        }
    }

    /**
     * @notice Internal function to complete a redemption
     * @param user The user who initiated the redemption
     * @param redemptionId The ID of the redemption
     */
    function _completeRedemption(address user, uint256 redemptionId) internal {
        Redemption storage redemption = redemptions[user][redemptionId];

        if (redemption.completed) {
            revert RedemptionAlreadyCompleted(redemptionId);
        }
        if (redemption.amount == 0) {
            revert InvalidRedemption(redemptionId);
        }
        if (block.timestamp < redemption.unlockTime) {
            revert RedemptionNotReady();
        }

        // Calculate stablecoin amount (convert from KUSD decimals to stablecoin decimals)
        uint256 stablecoinAmount = _convertFromKUSD(redemption.stablecoin, redemption.amount);
        if (stablecoinAmount == 0) {
            revert AmountTooSmall();
        }

        // Check contract has enough stablecoin
        uint256 contractBalance = IERC20(redemption.stablecoin).balanceOf(address(this));
        if (contractBalance < stablecoinAmount) {
            revert InsufficientStablecoinBalance(redemption.stablecoin, stablecoinAmount, contractBalance);
        }

        // Mark as completed
        redemption.completed = true;

        // Burn escrowed KUSD
        _burn(address(this), redemption.amount);

        // Transfer stablecoin to user
        IERC20(redemption.stablecoin).safeTransfer(user, stablecoinAmount);

        // Decrement open redemption count
        if (openRedemptionCount[user] != 0) openRedemptionCount[user] -= 1;

        emit RedemptionCompleted(user, redemptionId, redemption.stablecoin, stablecoinAmount);
    }

    /// @notice Internal function to check if an address is allowlisted
    function _onlyAllowlisted(address account) internal view {
        if (!allowlistRegistry.isAllowed(account)) {
            revert NotAllowlisted();
        }
    }

    /// @notice Internal function to check if an address is not forbidden
    function _notForbidden(address account) internal view {
        if (allowlistRegistry.isForbidden(account)) {
            revert AddressOnForbiddenList(account);
        }
    }

    /// @notice Internal function to check if a stablecoin is supported
    function _onlySupportedStablecoin(address stablecoin) internal view {
        if (!acceptedStablecoins[stablecoin]) {
            revert StablecoinNotAccepted(stablecoin);
        }
    }

    // ============ Upgradeability ============

    /**
     * @notice Authorize an upgrade to a new implementation
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin { }
}
