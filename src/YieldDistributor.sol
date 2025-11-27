// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IKUSD } from "src/interfaces/IKUSD.sol";
import { ISKUSD } from "src/interfaces/ISKUSD.sol";
import { IYieldDistributor, Distribution } from "src/interfaces/IYieldDistributor.sol";
import { KredConfigRoleChecker } from "src/KredConfigRoleChecker.sol";

/**
 * @title YieldDistributor
 * @notice Flexible distributor with multiple concurrent, linearly released stablecoin release schedules.
 * @dev Each distribution is pre-funded on registration. Anyone can `release` against schedule.
 */
contract YieldDistributor is
    IYieldDistributor,
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    KredConfigRoleChecker
{
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice The address of the KUSD stablecoin
    address public KUSD;

    /// @notice The address of the staked KUSD vault contract
    address public sKUSD;

    /// @notice Minimum allowed duration for a stablecoin distribution (in seconds)
    uint256 public minDuration;

    /// @notice Maximum allowed duration for a stablecoin distribution (in seconds; zero means there's no upper bound)
    uint256 public maxDuration;

    /// @notice Optional cap on the number of concurrently active distributions (0 means uncapped)
    uint256 public maxActiveDistributions;

    /// @notice Auto-incrementing id for distributions
    uint256 public nextDistributionId;

    /// @notice All distributions by id
    mapping(uint256 distributionId => Distribution) public distributions;

    /// @notice Active distribution ids for iteration
    uint256[] public activeDistributionIds;

    /// @notice Index of id in activeDistributionIds array (1-based to allow 0 as "not found")
    mapping(uint256 distributionId => uint256 indexPlusOne) private activeIndexPlusOne;

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /**
     * @notice Initialize the distributor
     * @param _kredConfig KredConfig address for role checks
     * @param _KUSD KUSD stablecoin address
     * @param _sKUSD sKUSD vault address
     * @param _minDuration Minimum allowed duration for a program (in seconds, must be > 0)
     * @param _maxDuration Maximum allowed duration (0 means uncapped). If non-zero, must be >= _minDuration
     * @param _maxActiveDistributions Optional cap on concurrent active distributions (0 means uncapped)
     */
    function initialize(
        address _kredConfig,
        address _KUSD,
        address _sKUSD,
        uint256 _minDuration,
        uint256 _maxDuration,
        uint256 _maxActiveDistributions
    )
        external
        initializer
    {
        if (_kredConfig == address(0) || _KUSD == address(0) || _sKUSD == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        if (_minDuration == 0) {
            revert InvalidDurationBounds(_minDuration, _maxDuration);
        }
        if (_maxDuration != 0 && _maxDuration < _minDuration) {
            revert InvalidDurationBounds(_minDuration, _maxDuration);
        }

        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __KredConfigRoleChecker_init(_kredConfig);

        KUSD = _KUSD;
        sKUSD = _sKUSD;
        minDuration = _minDuration;
        maxDuration = _maxDuration;
        maxActiveDistributions = _maxActiveDistributions;

        emit DurationBoundsUpdated(_minDuration, _maxDuration);
        emit MaxActiveDistributionsUpdated(_maxActiveDistributions);
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

    // ============ Admin Configuration ============

    /**
     * @notice Update min/max duration bounds
     * @param newMinDuration New minimum duration (in seconds, must be > 0)
     * @param newMaxDuration New maximum duration (0 means uncapped). If non-zero, must be >= newMinDuration
     */
    function setDurationBounds(uint256 newMinDuration, uint256 newMaxDuration) external onlyManager {
        if (newMinDuration == 0) {
            revert InvalidDurationBounds(newMinDuration, newMaxDuration);
        }
        if (newMaxDuration != 0 && newMaxDuration < newMinDuration) {
            revert InvalidDurationBounds(newMinDuration, newMaxDuration);
        }
        minDuration = newMinDuration;
        maxDuration = newMaxDuration;
        emit DurationBoundsUpdated(newMinDuration, newMaxDuration);
    }

    /**
     * @notice Update the cap on concurrently active distributions (0 means uncapped)
     */
    function setMaxActiveDistributions(uint256 newMax) external onlyManager {
        maxActiveDistributions = newMax;
        emit MaxActiveDistributionsUpdated(newMax);
    }

    // ============ Manager: Register / Cancel ============

    /**
     * @notice Registers a new linear distribution and pre-funds it.
     * @param totalAmount Total amount (stablecoin decimals) to drip linearly
     * @param startTime Start timestamp for the distribution (cannot be in the past)
     * @param duration Duration in seconds (bounded by min/max duration)
     * @param stablecoinForDistribution Stablecoin address for this distribution (must be accepted collateral for
     * minting KUSD)
     * @return distributionId The id of the newly registered distribution
     */
    function registerDistribution(
        uint256 totalAmount,
        uint64 startTime,
        uint64 duration,
        address stablecoinForDistribution
    )
        external
        whenNotPaused
        nonReentrant
        onlyManager
        returns (uint256 distributionId)
    {
        if (totalAmount == 0) revert ZeroAmountNotAllowed();
        if (startTime < block.timestamp) {
            revert InvalidDistributionStartTime();
        }
        if (duration < minDuration || (maxDuration != 0 && duration > maxDuration)) {
            revert InvalidDuration(minDuration, maxDuration, duration);
        }
        if (maxActiveDistributions != 0 && activeDistributionIds.length >= maxActiveDistributions) {
            revert ActiveDistributionsLimitReached(maxActiveDistributions);
        }
        if (IKUSD(KUSD).acceptedStablecoins(stablecoinForDistribution) == false) {
            revert StablecoinNotAccepted(stablecoinForDistribution);
        }

        // Pull funds upfront so schedule math is independent of live balances.
        IERC20(stablecoinForDistribution).safeTransferFrom(msg.sender, address(this), totalAmount);

        uint64 endTime = startTime + duration;

        distributionId = nextDistributionId++;
        distributions[distributionId] = Distribution({
            stablecoin: stablecoinForDistribution,
            totalAmount: totalAmount,
            releasedAmount: 0,
            startTime: startTime,
            endTime: endTime,
            active: true
        });

        _activeAdd(distributionId);

        emit DistributionRegistered(distributionId, stablecoinForDistribution, totalAmount, startTime, endTime);
    }

    /**
     * @notice Cancels an active distribution and refund remaining amount to `refundTo`.
     * @param distributionId Id of the distribution to cancel
     * @param refundTo Address to refund remaining stablecoin to
     */
    function cancelDistribution(uint256 distributionId, address refundTo) external nonReentrant onlyManager {
        if (refundTo == address(0)) revert ZeroAddressNotAllowed();

        Distribution storage distribution = distributions[distributionId];
        if (!distribution.active) revert NotActive(distributionId);

        uint256 remaining = distribution.totalAmount - distribution.releasedAmount;
        distribution.active = false;
        _activeRemove(distributionId);

        if (remaining != 0) {
            IERC20(distribution.stablecoin).safeTransfer(refundTo, remaining);
        }

        emit DistributionCancelled(distributionId, refundTo, remaining);
    }

    // ============ Permissionless Release ============

    /**
     * @notice Release due amounts for specific distribution ids.
     * @dev Anyone can call this function. Skips ids with nothing due.
     * @param distributionIds List of ids to process (use small batches to avoid out-of-gas)
     */
    function release(uint256[] calldata distributionIds) external whenNotPaused nonReentrant {
        uint256 length = distributionIds.length;
        bool anyReleased;

        for (uint256 i = 0; i < length;) {
            if (_releaseDistribution(distributionIds[i])) {
                anyReleased = true;
            }
            unchecked {
                i++;
            }
        }

        if (!anyReleased) revert NothingDue();
    }

    /**
     * @notice Release due amounts from the first `maxToProcess` active ids.
     * @dev The main purpose of this function is to provide simple pagination for automated operations. If
     * `maxToProcess` is 0, it processes all active distribution ids.
     */
    function releaseFromActive(uint256 maxToProcess) external whenNotPaused nonReentrant {
        uint256 length = activeDistributionIds.length;
        if (length == 0) revert NothingDue();

        uint256 limit = maxToProcess == 0 || maxToProcess > length ? length : maxToProcess;

        // Snapshot ids to avoid the issue of activeDistributionIds changing during processing due to distribution
        // completions
        uint256[] memory ids = new uint256[](limit);
        for (uint256 i = 0; i < limit;) {
            ids[i] = activeDistributionIds[i];
            unchecked {
                i++;
            }
        }

        bool anyReleased;
        for (uint256 i = 0; i < limit;) {
            if (_releaseDistribution(ids[i])) {
                anyReleased = true;
            }
            unchecked {
                i++;
            }
        }

        if (!anyReleased) revert NothingDue();
    }

    // ============ View Functions ============

    /**
     * @notice Returns the distribution struct for a given id.
     * @param distributionId Id of the distribution to query
     */
    function getDistribution(uint256 distributionId) external view returns (Distribution memory) {
        return distributions[distributionId];
    }

    /**
     * @notice Pending amount for a distribution id if `release()` function was to be called now.
     * @param distributionId Id of the distribution to query
     */
    function pendingAmount(uint256 distributionId) external view returns (uint256) {
        Distribution storage distribution = distributions[distributionId];
        if (!distribution.active) return 0;
        return _pendingAmount(distribution);
    }

    /**
     * @notice Returns the total number of active distributions.
     * @return count The number of active distributions
     */
    function activeCount() external view returns (uint256) {
        return activeDistributionIds.length;
    }

    /**
     * @notice Returns all active distribution ids.
     * @return ids The list of active distribution ids
     */
    function getActiveDistributionIds() external view returns (uint256[] memory) {
        return activeDistributionIds;
    }

    /**
     * @notice Returns active distribution ids in a paginated slice.
     * @param cursor Start index in activeDistributionIds
     * @param size Max number of ids to return
     */
    function getActiveDistributionIdsPaginated(
        uint256 cursor,
        uint256 size
    )
        external
        view
        returns (uint256[] memory slice)
    {
        uint256 length = activeDistributionIds.length;
        if (cursor >= length) return new uint256[](0);

        uint256 end = cursor + size;
        if (end > length) end = length;

        uint256 outLength = end - cursor;
        slice = new uint256[](outLength);
        for (uint256 i = 0; i < outLength;) {
            slice[i] = activeDistributionIds[cursor + i];
            unchecked {
                i++;
            }
        }
    }

    // ============ Internal Helper Functions ============

    /**
     * @notice Internal helper function to add a distribution id to the active list
     *  @param distributionId The id of the distribution to add
     */
    function _activeAdd(uint256 distributionId) internal {
        activeDistributionIds.push(distributionId);
        activeIndexPlusOne[distributionId] = activeDistributionIds.length; // 1-based
    }

    /**
     * @notice Internal helper function to remove a distribution id from the active list
     * @param distributionId The id of the distribution to remove
     */
    function _activeRemove(uint256 distributionId) internal {
        uint256 indexPlusOne = activeIndexPlusOne[distributionId];
        if (indexPlusOne == 0) return; // already removed or never added (not found)

        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = activeDistributionIds.length - 1;

        if (index != lastIndex) {
            uint256 lastId = activeDistributionIds[lastIndex];
            activeDistributionIds[index] = lastId;
            activeIndexPlusOne[lastId] = index + 1; // maintain 1-based index
        }

        activeDistributionIds.pop();
        activeIndexPlusOne[distributionId] = 0;
    }

    /**
     * @notice Internal helper to release one distribution if anything is due right now.
     * @return releasedSomething True if any amount was released
     */
    function _releaseDistribution(uint256 distributionId) internal returns (bool releasedSomething) {
        Distribution storage distribution = distributions[distributionId];
        if (!distribution.active) return false;

        uint256 amountDue = _pendingAmount(distribution);
        if (amountDue == 0) return false;

        // Safety balance check (funds were pre-pulled at registration)
        uint256 balance = IERC20(distribution.stablecoin).balanceOf(address(this));
        if (balance < amountDue) revert InsufficientStablecoinBalance(distribution.stablecoin, amountDue, balance);

        // 1) Send stablecoin to sKUSD
        IERC20(distribution.stablecoin).safeTransfer(sKUSD, amountDue);

        // 2) Ask sKUSD to mint KUSD into the vault (raises exchange rate)
        ISKUSD(sKUSD).mintKUSDForVault(distribution.stablecoin, amountDue);

        // Track
        distribution.releasedAmount += amountDue;
        emit YieldReleased(distributionId, amountDue, distribution.releasedAmount, block.timestamp);

        // Complete the distribution program if fully released
        if (distribution.releasedAmount == distribution.totalAmount) {
            distribution.active = false;
            _activeRemove(distributionId);
            emit DistributionCompleted(distributionId, distribution.totalAmount);
        }

        return true;
    }

    /**
     * @notice Compute pending amount from a distribution struct (linear release).
     * @param distribution The distribution struct
     * @return pending The pending amount due right now
     */
    function _pendingAmount(Distribution storage distribution) internal view returns (uint256) {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp <= distribution.startTime) return 0;

        uint256 cappedTime = currentTimestamp >= distribution.endTime ? distribution.endTime : currentTimestamp;
        uint256 elapsed = cappedTime - distribution.startTime;
        uint256 duration = distribution.endTime - distribution.startTime; // > 0 by construction

        // dueSoFar = total * elapsed / duration
        uint256 dueSoFar = (distribution.totalAmount * elapsed) / duration;
        if (dueSoFar <= distribution.releasedAmount) return 0; // defense in depth (should not happen in practice)
        return dueSoFar - distribution.releasedAmount;
    }

    // ============ Upgradeability ============

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin { }
}
