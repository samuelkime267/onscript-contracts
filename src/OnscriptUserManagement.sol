// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Onscript user management
 * @author Wahala Dev
 * @notice Manages user registration and premium payments in ETH priced via Chainlink ETH/USD.
 * @dev Premium price is stored as a base USD integer (e.g. 1 => $1, 10 => $10).
 *      The contract reads the Chainlink feed decimals at runtime and performs scaling
 *      so callers do NOT need to know or pass feed decimals.
 */
contract OnscriptUserManagement is Ownable, ReentrancyGuard {
    //////////////////////////////////////////////////////////////////////////////
    //// TYPES
    //////////////////////////////////////////////////////////////////////////////
    enum UserStatus {
        UNREGISTERED,
        FREEMIUM,
        PREMIUM,
        PLUS
    }

    struct UserRecord {
        uint256 id;
        uint256 fid;
        UserStatus status;
        uint256 subscriptionExpiresAt;
    }

    //////////////////////////////////////////////////////////////////////////////
    //// STATE VARIABLES
    //////////////////////////////////////////////////////////////////////////////
    uint256 private s_premiumPriceUsdBase;
    uint256 private s_plusPriceUsdBase;
    uint256 private s_ID = 1;
    uint256 private s_PlusDuration = 30 days;
    uint256 private s_maxPaymentPeriod = 12;
    uint256 constant NO_EXPIRY_DURATION = 0;
    uint256 public constant MAX_STALE_TIME = 3 hours;

    mapping(address => bool) private s_addressToIsAdmin;
    mapping(address => UserRecord) private s_addressToUserRecord;

    AggregatorV3Interface internal s_dataFeed;

    //////////////////////////////////////////////////////////////////////////////
    //// EVENTS
    //////////////////////////////////////////////////////////////////////////////
    event UserRegistered(address indexed user, uint256 fid);
    event UserDetailsUpdated(address indexed user, uint256 fid);
    event UserDeleted(address indexed user, uint256 previousFid);
    event PremiumPaid(address indexed user, uint256 fid, uint256 amountPaid);
    event PremiumPriceUpdated(uint256 newPriceUsdBase);
    event PriceFeedUpdated(address indexed newFeed);
    event AdminGranted(address indexed admin);
    event AdminRevoked(address indexed admin);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event PlusSubscribed(address indexed user, uint256 indexed expiresAt, uint256 indexed amountPaid);
    event PlusDurationUpdated(uint256 indexed newDuration);
    event MaxPaymentPeriodUpdated(uint256 indexed newMaxPaymentPeriod);
    event PlusPriceUpdated(uint256 indexed newPriceUsdBase);
    event UserMadeFreemium(address indexed user, address indexed adminAddress);

    //////////////////////////////////////////////////////////////////////////////
    //// ERRORS
    //////////////////////////////////////////////////////////////////////////////
    error OnscriptUserManagement__InvalidAddress();
    error OnscriptUserManagement__UserAlreadyExists(address userAddress);
    error OnscriptUserManagement__UserDoesNotExists(address userAddress);
    error OnscriptUserManagement__InvalidFid();
    error OnscriptUserManagement__InvalidPrice();
    error OnscriptUserManagement__InsufficientFunds();
    error OnscriptUserManagement__NotPermitted();
    error OnscriptUserManagement__WithdrawalFailed();
    error OnscriptUserManagement__AlreadyPremium();
    error OnscriptUserManagement__RefundFailed();
    error OnscriptUserManagement__AlreadyAdmin(address);
    error OnscriptUserManagement__NotAdmin(address);
    error OnscriptUserManagement__InvalidChainlinkPrice();
    error OnscriptUserManagement__InvalidChainlinkUpdate();
    error OnscriptUserManagement__InvalidChainlinkRound();
    error OnscriptUserManagement__ChainlinkTimeout();
    error OnscriptUserManagement__UserIsPlus();
    error OnscriptUserManagement__InvalidPaymentPeriod();
    error OnscriptUserManagement__MaxPaymentPeriod();
    error OnscriptUserManagement__InvalidDuration();

    //////////////////////////////////////////////////////////////////////////////
    //// MODIFIERS
    //////////////////////////////////////////////////////////////////////////////
    modifier onlyRegisteredUser() {
        if (s_addressToUserRecord[msg.sender].status == UserStatus.UNREGISTERED) {
            revert OnscriptUserManagement__UserDoesNotExists(msg.sender);
        }
        _;
    }

    modifier validFid(uint256 fid) {
        if (fid < 1) {
            revert OnscriptUserManagement__InvalidFid();
        }
        _;
    }

    modifier onlyOwnerOrAdmin() {
        if (msg.sender != owner() && !s_addressToIsAdmin[msg.sender]) {
            revert OnscriptUserManagement__NotPermitted();
        }
        _;
    }

    //////////////////////////////////////////////////////////////////////////////
    //// FUNCITONS
    //////////////////////////////////////////////////////////////////////////////

    //////////////////////////////////////////////////////////////////////////////
    //// CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////////
    /**
     * @notice Creates the OnscriptUserManagement contract.
     * @param initialOwner Owner address. Will be set as contract owner via OpenZeppelin Ownable(initialOwner).
     * @param premiumUsdBase Premium price in whole USD (e.g., 10 = $10). The contract will scale this by the feed decimals.
     * @param priceFeedAddress Chainlink ETH/USD aggregator address.
     */
    constructor(address initialOwner, uint256 premiumUsdBase, address priceFeedAddress, uint256 plusPriceUsdBase)
        Ownable(initialOwner)
    {
        if (initialOwner == address(0) || priceFeedAddress == address(0)) {
            revert OnscriptUserManagement__InvalidAddress();
        }
        if (premiumUsdBase == 0) {
            revert OnscriptUserManagement__InvalidPrice();
        }
        if (plusPriceUsdBase == 0) {
            revert OnscriptUserManagement__InvalidPrice();
        }
        s_premiumPriceUsdBase = premiumUsdBase;
        s_plusPriceUsdBase = plusPriceUsdBase;
        s_dataFeed = AggregatorV3Interface(priceFeedAddress);
    }

    //////////////////////////////////////////////////////////////////////////////
    //// USER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Register the caller as a user with a fid.
     * @dev Reverts if already registered.
     * @param fid The user's fid (must be >= 1).
     */
    function registerUser(uint256 fid) public validFid(fid) {
        UserRecord storage user = s_addressToUserRecord[msg.sender];
        if (user.status != UserStatus.UNREGISTERED) {
            revert OnscriptUserManagement__UserAlreadyExists(msg.sender);
        }
        user.fid = fid;
        user.id = s_ID;
        user.status = UserStatus.FREEMIUM;
        user.subscriptionExpiresAt = NO_EXPIRY_DURATION;

        s_ID++;
        emit UserRegistered(msg.sender, fid);
    }

    /**
     * @notice Update the caller's fid.
     * @param fid New fid (must be >= 1).
     */
    function updateUser(uint256 fid) public onlyRegisteredUser validFid(fid) {
        s_addressToUserRecord[msg.sender].fid = fid;
        emit UserDetailsUpdated(msg.sender, fid);
    }

    /**
     * @notice Delete the caller's user record.
     * @dev Clears the UserRecord from storage.
     */
    function deleteUser() public onlyRegisteredUser {
        uint256 userFid = s_addressToUserRecord[msg.sender].fid;
        delete s_addressToUserRecord[msg.sender];
        emit UserDeleted(msg.sender, userFid);
    }

    /**
     * @notice Pay for premium using ETH at the current Chainlink ETH/USD rate.
     * @dev The contract reads Chainlink feed decimals and scales the base USD amount automatically.
     *      Refunds any excess ETH back to the payer via a direct `call`. If that refund fails the tx will revert.
     *      This function is protected by `nonReentrant`.
     *      Uses `_processPayment` internally for oracle check + refund.
     */
    function payForPremium() public payable onlyRegisteredUser nonReentrant {
        UserRecord storage user = s_addressToUserRecord[msg.sender];
        if (user.status == UserStatus.PREMIUM) revert OnscriptUserManagement__AlreadyPremium();

        uint256 paid = _processPayment(s_premiumPriceUsdBase);
        user.status = UserStatus.PREMIUM;
        user.subscriptionExpiresAt = NO_EXPIRY_DURATION;

        emit PremiumPaid(msg.sender, user.fid, paid);
    }

    function subscribePlus(uint256 periods) public payable onlyRegisteredUser nonReentrant {
        if (periods < 1) revert OnscriptUserManagement__InvalidPaymentPeriod();
        if (periods > s_maxPaymentPeriod) revert OnscriptUserManagement__MaxPaymentPeriod();

        UserRecord storage user = s_addressToUserRecord[msg.sender];

        uint256 paid = _processPayment(s_plusPriceUsdBase * periods);

        if (user.status != UserStatus.PLUS) {
            user.status = UserStatus.PLUS;
        }

        uint256 addedDuration = s_PlusDuration * periods;

        if (block.timestamp > user.subscriptionExpiresAt) {
            user.subscriptionExpiresAt = block.timestamp + addedDuration;
        } else {
            user.subscriptionExpiresAt += addedDuration;
        }

        emit PlusSubscribed(msg.sender, user.subscriptionExpiresAt, paid);
    }

    //////////////////////////////////////////////////////////////////////////////
    //// ADMIN / OWNER
    //////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Grants admin privileges to `userAddress`.
     * @dev Only owner can call this.
     * @param userAddress Address to grant admin rights to.
     */
    function grantAdmin(address userAddress) external onlyOwner {
        if (userAddress == address(0)) revert OnscriptUserManagement__InvalidAddress();
        if (s_addressToIsAdmin[userAddress]) revert OnscriptUserManagement__AlreadyAdmin(userAddress);
        if (s_addressToUserRecord[userAddress].status == UserStatus.UNREGISTERED) {
            revert OnscriptUserManagement__UserDoesNotExists(userAddress);
        }

        s_addressToIsAdmin[userAddress] = true;
        emit AdminGranted(userAddress);
    }

    /**
     * @notice Revokes admin privileges from `userAddress`.
     * @dev Only owner can call this.
     * @param userAddress Address to revoke admin rights from.
     */
    function revokeAdmin(address userAddress) external onlyOwner {
        if (!s_addressToIsAdmin[userAddress]) revert OnscriptUserManagement__NotAdmin(userAddress);
        s_addressToIsAdmin[userAddress] = false;
        emit AdminRevoked(userAddress);
    }

    /**
     * @notice Withdraws entire contract balance to the owner.
     * @dev Only owner can call and it is non-reentrant.
     */
    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        (bool success,) = payable(owner()).call{value: bal}("");
        if (!success) revert OnscriptUserManagement__WithdrawalFailed();
        emit FundsWithdrawn(owner(), bal);
    }

    function makeUserPremium(address userAddress) external onlyOwnerOrAdmin {
        if (
            s_addressToUserRecord[userAddress].status == UserStatus.PLUS
                && block.timestamp < s_addressToUserRecord[userAddress].subscriptionExpiresAt
        ) {
            revert OnscriptUserManagement__UserIsPlus();
        }
        if (s_addressToUserRecord[userAddress].status == UserStatus.UNREGISTERED) {
            revert OnscriptUserManagement__UserDoesNotExists(userAddress);
        }

        if (s_addressToUserRecord[userAddress].status == UserStatus.PREMIUM) {
            revert OnscriptUserManagement__AlreadyPremium();
        }

        UserRecord storage user = s_addressToUserRecord[userAddress];
        user.status = UserStatus.PREMIUM;
        emit PremiumPaid(userAddress, user.fid, 0);
    }

    function makeUserPlus(address userAddress, uint256 period) external onlyOwnerOrAdmin {
        if (s_addressToUserRecord[userAddress].status == UserStatus.UNREGISTERED) {
            revert OnscriptUserManagement__UserDoesNotExists(userAddress);
        }
        if (period < 1) revert OnscriptUserManagement__InvalidPaymentPeriod();
        if (period > s_maxPaymentPeriod) revert OnscriptUserManagement__MaxPaymentPeriod();

        UserRecord storage user = s_addressToUserRecord[userAddress];
        user.status = UserStatus.PLUS;

        uint256 addedDuration = s_PlusDuration * period;

        if (block.timestamp > user.subscriptionExpiresAt) {
            user.subscriptionExpiresAt = block.timestamp + addedDuration;
        } else {
            user.subscriptionExpiresAt += addedDuration;
        }

        emit PlusSubscribed(msg.sender, user.subscriptionExpiresAt, 0);
    }

    /**
     * @notice Set a new Chainlink price feed address.
     * @dev Only owner can call this.
     * @param newFeed Address of the new Chainlink AggregatorV3Interface.
     */
    function setPriceFeed(address newFeed) external onlyOwner {
        if (newFeed == address(0)) revert OnscriptUserManagement__InvalidAddress();
        s_dataFeed = AggregatorV3Interface(newFeed);
        emit PriceFeedUpdated(newFeed);
    }

    /**
     * @notice Set the premium amount in whole USD (e.g., 1 => $1, 10 => $10).
     * @dev Callable by owner or allowed admins.
     * @param amountUsdBase New premium base USD integer (must be > 0).
     */
    function setPremiumAmount(uint256 amountUsdBase) external onlyOwnerOrAdmin {
        if (amountUsdBase == 0) revert OnscriptUserManagement__InvalidPrice();
        s_premiumPriceUsdBase = amountUsdBase;
        emit PremiumPriceUpdated(amountUsdBase);
    }

    function setPlusAmount(uint256 amountUsdBase) external onlyOwnerOrAdmin {
        if (amountUsdBase == 0) revert OnscriptUserManagement__InvalidPrice();
        s_plusPriceUsdBase = amountUsdBase;
        emit PlusPriceUpdated(amountUsdBase);
    }

    function setPlusDuration(uint256 duration) external onlyOwnerOrAdmin {
        if (duration == 0) revert OnscriptUserManagement__InvalidDuration();
        s_PlusDuration = duration;
        emit PlusDurationUpdated(duration);
    }

    function setMaxPaymentPeriod(uint256 period) external onlyOwnerOrAdmin {
        if (period < 1) revert OnscriptUserManagement__InvalidPaymentPeriod();
        s_maxPaymentPeriod = period;
        emit MaxPaymentPeriodUpdated(period);
    }

    //////////////////////////////////////////////////////////////////////////////
    //// GETTERS
    //////////////////////////////////////////////////////////////////////////////
    /**
     * @notice Returns whether `userAddress` is registered.
     * @param userAddress Address to query.
     */
    function getIsUserRegistered(address userAddress) external view returns (bool) {
        return s_addressToUserRecord[userAddress].status != UserStatus.UNREGISTERED;
    }

    /**
     * @notice Returns the fid of `userAddress`.
     * @param userAddress Address of the user.
     * @return fid The stored fid for the address.
     */
    function getUserFid(address userAddress) external view returns (uint256) {
        return s_addressToUserRecord[userAddress].fid;
    }

    /**
     * @notice Returns the raw latest answer from the Chainlink feed.
     * @dev Use `getFeedDecimals()` to interpret value scale.
     * @return answer Latest feed answer (scaled by feed decimals).
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (, int256 answer,,,) = s_dataFeed.latestRoundData();
        return answer;
    }

    /**
     * @notice Returns the premium price stored in base USD units (e.g., 10 => $10).
     * @return baseUsd The base USD integer used to compute required ETH.
     */
    function getPremiumAmountUsdBase() external view returns (uint256) {
        return s_premiumPriceUsdBase;
    }

    function getId() external view returns (uint256) {
        return s_ID;
    }

    /**
     * @notice Returns whether `userAddress` has premium status.
     * @param userAddress Address to query.
     * @return isPremium True if premium, false otherwise.
     */
    function getIsUserPremium(address userAddress) external view returns (bool) {
        return s_addressToUserRecord[userAddress].status == UserStatus.PREMIUM;
    }

    /**
     * @notice Returns whether `userAddress` is an admin.
     * @param userAddress Address to query.
     * @return isAdmin True if admin, false otherwise.
     */
    function getIsUserAdmin(address userAddress) external view returns (bool) {
        return s_addressToIsAdmin[userAddress];
    }

    /**
     * @notice Returns the decimals used by the Chainlink feed.
     * @return decimals Feed decimals (e.g., 8).
     */
    function getFeedDecimals() external view returns (uint8) {
        return s_dataFeed.decimals();
    }

    /**
     * @notice Returns the required wei amount to pay for premium right now.
     * @dev Uses the current Chainlink answer and feed decimals to compute required wei.
     * @return requiredWei The wei amount required for the stored base USD premium.
     */
    function requiredWeiForPremium() public view returns (uint256) {
        int256 answer = getChainlinkDataFeedLatestAnswer();
        if (answer <= 0) revert OnscriptUserManagement__InvalidPrice();

        uint256 priceUsdPerEthEFeed = uint256(answer);
        uint8 feedDecimals = s_dataFeed.decimals();
        uint256 premiumUsdScaled = s_premiumPriceUsdBase * (10 ** uint256(feedDecimals));
        return _ceilDiv(premiumUsdScaled * 1e18, priceUsdPerEthEFeed);
    }

    function requiredWeiForPlus() public view returns (uint256) {
        int256 answer = getChainlinkDataFeedLatestAnswer();
        if (answer <= 0) revert OnscriptUserManagement__InvalidPrice();

        uint256 priceUsdPerEthEFeed = uint256(answer);
        uint8 feedDecimals = s_dataFeed.decimals();
        uint256 plusUsdScaled = s_plusPriceUsdBase * (10 ** uint256(feedDecimals));
        return _ceilDiv(plusUsdScaled * 1e18, priceUsdPerEthEFeed);
    }

    function getEffectiveStatus(address userAddress) public view returns (UserStatus) {
        UserRecord storage user = s_addressToUserRecord[userAddress];

        if (user.status == UserStatus.PLUS && block.timestamp > user.subscriptionExpiresAt) {
            return UserStatus.PREMIUM;
        }
        return user.status;
    }

    function getIsPlus(address userAddress) public view returns (bool) {
        return s_addressToUserRecord[userAddress].status == UserStatus.PLUS
            && block.timestamp < s_addressToUserRecord[userAddress].subscriptionExpiresAt;
    }

    function getPlusExpiresAt(address userAddress) public view returns (uint256) {
        return s_addressToUserRecord[userAddress].subscriptionExpiresAt;
    }

    function getDurationLeftForPlus(address userAddress) public view returns (uint256) {
        if (block.timestamp > s_addressToUserRecord[userAddress].subscriptionExpiresAt) {
            return 0;
        }

        return s_addressToUserRecord[userAddress].subscriptionExpiresAt - block.timestamp;
    }

    function getPlusDuration() public view returns (uint256) {
        return s_PlusDuration;
    }

    function getPlusPriceUsd() public view returns (uint256) {
        return s_plusPriceUsdBase;
    }

    function getPlusMaxPaymentPeriod() public view returns (uint256) {
        return s_maxPaymentPeriod;
    }

    //////////////////////////////////////////////////////////////////////////////
    //// INTERNAL
    //////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Internal helper that performs ceil division.
     */
    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : 1 + (a - 1) / b;
    }

    /// @dev Handles ETH payment using Chainlink feed and refunds any excess.
    ///      Returns the actual wei amount consumed.
    function _processPayment(uint256 usdPriceBase) internal returns (uint256 requiredWei) {
        // Get latest feed data
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = s_dataFeed.latestRoundData();

        // Basic oracle safety checks
        if (answer <= 0) revert OnscriptUserManagement__InvalidChainlinkPrice();
        if (updatedAt == 0) revert OnscriptUserManagement__InvalidChainlinkUpdate();
        if (answeredInRound < roundId) revert OnscriptUserManagement__InvalidChainlinkRound();
        if (block.timestamp - updatedAt > MAX_STALE_TIME) revert OnscriptUserManagement__ChainlinkTimeout();

        uint256 priceUsdPerEthFeed = uint256(answer);
        uint8 feedDecimals = s_dataFeed.decimals();

        // Scale the USD base to feed decimals
        uint256 usdScaled = usdPriceBase * (10 ** uint256(feedDecimals));
        requiredWei = _ceilDiv(usdScaled * 1e18, priceUsdPerEthFeed);

        if (msg.value < requiredWei) revert OnscriptUserManagement__InsufficientFunds();

        // Refund excess
        uint256 excess = msg.value - requiredWei;
        if (excess > 0) {
            (bool success,) = payable(msg.sender).call{value: excess}("");
            if (!success) revert OnscriptUserManagement__RefundFailed();
        }
    }

    //////////////////////////////////////////////////////////////////////////////
    //// RECEIVE / FALLBACK
    //////////////////////////////////////////////////////////////////////////////
    receive() external payable {}
    fallback() external payable {}
}
