// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {OnscriptUserManagement} from "../../src/OnscriptUserManagement.sol";
import {DeployOnScriptUserManagement} from "../../script/DeployOnScriptUserManagement.s.sol";
import {console} from "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract OnscriptManagementTest is Test {
    OnscriptUserManagement public onscriptUserManagement;
    HelperConfig public helperConfig;
    address public ethUsdPriceFeed;
    uint256 public deployerKey;
    uint256 public premiumUsdBase;
    uint256 public plusPriceUsdBase;
    MockV3Aggregator mockFeed;
    address public OWNER;
    uint256 public constant MAX_STALE_TIME = 3 hours;

    address public USER = makeAddr("user");
    address public USER2 = makeAddr("user2");
    address public USER3 = makeAddr("user3");
    address public USER4 = makeAddr("user4");
    address public USER5 = makeAddr("user5");
    address[] public users = [USER, USER2, USER3, USER4, USER5];
    uint256 public constant STARTING_BALANCE = 10 ether;
    uint256 public constant USER_FID = 100;
    uint256 public constant USER2_FID = 200;

    function setUp() external {
        DeployOnScriptUserManagement deployer = new DeployOnScriptUserManagement();
        (onscriptUserManagement, helperConfig) = deployer.run();

        (ethUsdPriceFeed, deployerKey, premiumUsdBase, OWNER, plusPriceUsdBase) = helperConfig.activeNetworkConfig();
        mockFeed = MockV3Aggregator(ethUsdPriceFeed);
        // Funding dummy users
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], STARTING_BALANCE);
        }
    }

    function testIfOwnerIsSet() public view {
        assert(onscriptUserManagement.owner() == OWNER);
    }

    function testBaseAmountIsSet() public view {
        assert(onscriptUserManagement.getPremiumAmountUsdBase() == premiumUsdBase);
    }

    function testAggregatorWorksWorks() public view {
        assert(onscriptUserManagement.getChainlinkDataFeedLatestAnswer() > 0);
    }

    function testRegistrationRevertsIfFidIsInvalid() public {
        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidFid.selector);
        onscriptUserManagement.registerUser(0);
    }

    function testRegisterRevertsIfUserExists() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__UserAlreadyExists.selector, USER)
        );
        onscriptUserManagement.registerUser(USER_FID);
    }

    function testUserIsRegisteredSuccessfully() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        assert(onscriptUserManagement.getUserFid(USER) != 0);
    }

    function testEventIsEmittedAfterRegistration() public {
        vm.expectEmit(true, false, false, true);
        emit OnscriptUserManagement.UserRegistered(USER, USER_FID);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);
    }

    function testOnlyRegisteredUserCanUpdateInfo() public {
        vm.prank(USER2);
        vm.expectRevert(
            abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__UserDoesNotExists.selector, USER2)
        );
        onscriptUserManagement.updateUser(USER2_FID);
    }

    function testRevertsIfUpdateFidIsInvalid() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidFid.selector);
        onscriptUserManagement.updateUser(0);
    }

    function testUserCanUpdateInformation() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.updateUser(USER2_FID);

        assert(onscriptUserManagement.getUserFid(USER) == USER2_FID);
    }

    function testOnlyRegisteredUserCanDeleteInfo() public {
        vm.prank(USER2);
        vm.expectRevert(
            abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__UserDoesNotExists.selector, USER2)
        );
        onscriptUserManagement.deleteUser();
    }

    function testUserInformationIsClearedAfterDeletion() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.deleteUser();

        assert(onscriptUserManagement.getUserFid(USER) == 0);
    }

    function testOnlyRegisteredUserCanPayPremium() public {
        vm.prank(USER2);
        vm.expectRevert(
            abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__UserDoesNotExists.selector, USER2)
        );
        onscriptUserManagement.payForPremium();
    }

    function testUserCanPayPremium() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: 0.1 ether}();

        assert(onscriptUserManagement.getIsUserPremium(USER));
    }

    function testPaymentRevertsIfNotEnoughFunds() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InsufficientFunds.selector);
        onscriptUserManagement.payForPremium();
    }

    function testIsPremiumForAddressIsRemovedAfterDeletion() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: 0.1 ether}();

        vm.prank(USER);
        onscriptUserManagement.deleteUser();

        assert(!onscriptUserManagement.getIsUserPremium(USER));
    }

    function testExcessFundsIsSentBackToUser() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        uint256 requiredWei = onscriptUserManagement.requiredWeiForPremium();
        uint256 amountSent = 1 ether;
        uint256 prevUserBalance = USER.balance;
        uint256 expectedFinalBalance = prevUserBalance - requiredWei;

        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: amountSent}();

        uint256 currentUserBalance = USER.balance;
        assert(currentUserBalance == expectedFinalBalance);
    }

    function testPaymentEventIsEmittedAfterPayment() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        uint256 requiredWei = onscriptUserManagement.requiredWeiForPremium();

        vm.prank(USER);
        vm.expectEmit(true, false, false, true);
        emit OnscriptUserManagement.PremiumPaid(USER, USER_FID, requiredWei);
        onscriptUserManagement.payForPremium{value: requiredWei}();
    }

    function testOnlyOwnerCanAddAdmins() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        onscriptUserManagement.grantAdmin(USER);
    }

    function testOnlyOwnerCanRemoveAdmins() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        onscriptUserManagement.revokeAdmin(USER);
    }

    function testAdminCanBeAddedSuccessfully() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(OWNER);
        onscriptUserManagement.grantAdmin(USER);
        assert(onscriptUserManagement.getIsUserAdmin(USER));
    }

    function testAdminCanBeRemovedSuccessfully() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(OWNER);
        onscriptUserManagement.grantAdmin(USER);
        vm.prank(OWNER);
        onscriptUserManagement.revokeAdmin(USER);
        assert(!onscriptUserManagement.getIsUserAdmin(USER));
    }

    function testRevertsIfNotOwnerOrAdminSetPremiumAmount() public {
        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__NotPermitted.selector);
        onscriptUserManagement.setPremiumAmount(1 ether);
    }

    function testOwnerCanSetPremiumAmount() public {
        vm.prank(OWNER);
        onscriptUserManagement.setPremiumAmount(1 ether);
        assert(onscriptUserManagement.getPremiumAmountUsdBase() == 1 ether);
    }

    function testAdminCanSetPremiumAmount() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(OWNER);
        onscriptUserManagement.grantAdmin(USER);
        vm.prank(USER);
        onscriptUserManagement.setPremiumAmount(1 ether);
        assert(onscriptUserManagement.getPremiumAmountUsdBase() == 1 ether);
    }

    function testSetPremiumFailsIfAmountIsZeroForOwner() public {
        vm.prank(OWNER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidPrice.selector);
        onscriptUserManagement.setPremiumAmount(0);
    }

    function testSetPremiumFailsIfAmountIsZeroForAdmin() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(OWNER);
        onscriptUserManagement.grantAdmin(USER);
        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidPrice.selector);
        onscriptUserManagement.setPremiumAmount(0);
    }

    function testOnlyOWnerCanSetPriceFeedAddress() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        onscriptUserManagement.setPriceFeed(USER);
    }

    function testEventIsEmittedAfterSettingFeed() public {
        vm.expectEmit(true, false, false, true);
        emit OnscriptUserManagement.PriceFeedUpdated(USER);
        vm.prank(OWNER);
        onscriptUserManagement.setPriceFeed(USER);
    }

    function testRevertsIfOwnerIsNotWithdrawing() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        onscriptUserManagement.withdrawFunds();
    }

    function testOwnerCanWithdrawFunds() public {
        uint256 requiredWei = onscriptUserManagement.requiredWeiForPremium();

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);
        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: requiredWei}();

        uint256 currentOwnerBalance = OWNER.balance;

        vm.prank(OWNER);
        onscriptUserManagement.withdrawFunds();
        assert(OWNER.balance == currentOwnerBalance + requiredWei);
    }

    function testMultipleUsersCanRegisterAndPayPremium() public {
        uint256 requiredWei = onscriptUserManagement.requiredWeiForPremium();
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            onscriptUserManagement.registerUser(USER_FID + i);
            vm.prank(users[i]);
            onscriptUserManagement.payForPremium{value: requiredWei}();
        }

        for (uint256 i = 0; i < users.length; i++) {
            assert(onscriptUserManagement.getIsUserPremium(users[i]));
        }
    }

    function testDecimalsAreCorrect() public view {
        assert(onscriptUserManagement.getFeedDecimals() == 8);
        assert(onscriptUserManagement.getFeedDecimals() == mockFeed.decimals());
    }

    function testConstructorRevertsWhenOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new OnscriptUserManagement(address(0), premiumUsdBase, ethUsdPriceFeed, plusPriceUsdBase);
    }

    function testConstructorRevertsWhenPriceFeedIsZero() public {
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidAddress.selector);
        new OnscriptUserManagement(OWNER, premiumUsdBase, address(0), plusPriceUsdBase);
    }

    function testConstructorRevertsWhenPremiumUsdBaseIsZero() public {
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidPrice.selector);
        new OnscriptUserManagement(OWNER, 0, ethUsdPriceFeed, plusPriceUsdBase);
    }

    function testRevertsWhenAnswerNonPositive() public {
        mockFeed.updateRoundData(1, 0, block.timestamp, 1);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidChainlinkPrice.selector);

        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testRevertsWhenUpdatedAtZero() public {
        mockFeed.updateRoundData(1, 4923.27e8, 0, 1);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidChainlinkUpdate.selector);
        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testRevertsWhenStalePrice() public {
        uint256 startTime = MAX_STALE_TIME * 2;
        vm.warp(startTime);

        uint256 oldTime = block.timestamp - (MAX_STALE_TIME + 1);

        mockFeed.updateRoundData(1, 4923.27e8, oldTime, 1);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__ChainlinkTimeout.selector);
        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testRevertsWhenAnsweredInRoundLessThanRoundId() public {
        mockFeed.updateRoundData(1, 4923.27e8, block.timestamp, 2);
        mockFeed.setAnsweredInRound(1, 0);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidChainlinkRound.selector);
        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testPassesWithValidOracle() public {
        mockFeed.updateRoundData(1, 4923.27e8, block.timestamp, 1);

        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testPaymentReversIfUserISAlreadyPremium() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(USER);
        onscriptUserManagement.payForPremium{value: 1 ether}();

        vm.prank(USER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__AlreadyPremium.selector);
        onscriptUserManagement.payForPremium{value: 1 ether}();
    }

    function testSetPriceFeedsRevertsIfAddressZero() public {
        vm.prank(OWNER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidAddress.selector);
        onscriptUserManagement.setPriceFeed(address(0));
    }

    function testGrantAdminRevertsIfAddressZero() public {
        vm.prank(OWNER);
        vm.expectRevert(OnscriptUserManagement.OnscriptUserManagement__InvalidAddress.selector);
        onscriptUserManagement.grantAdmin(address(0));
    }

    function testRevertsIfAddressIsAlreadyAnAdmin() public {
        vm.prank(USER);
        onscriptUserManagement.registerUser(USER_FID);

        vm.prank(OWNER);
        onscriptUserManagement.grantAdmin(USER);
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__AlreadyAdmin.selector, USER)
        );
        onscriptUserManagement.grantAdmin(USER);
    }

    function testRevertsIfAddressIsNotAnAdmin() public {
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(OnscriptUserManagement.OnscriptUserManagement__NotAdmin.selector, USER));
        onscriptUserManagement.revokeAdmin(USER);
    }
}
