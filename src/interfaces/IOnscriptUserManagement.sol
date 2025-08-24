// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IOnscriptUserManagement {
    //////////////////////////////////////////////////////////////////////////////
    //// USER REGISTRATION AND INFORMATION
    //////////////////////////////////////////////////////////////////////////////
    /**
     * @notice This functions gets the address of the user from msg.sender
     * @param fid user fid
     */
    function registerUser(uint256 fid) external;

    /**
     * @notice This functions gets the address of the user from msg.sender then updates the user based on that address
     * @param fid user fid
     */
    function updateUser(uint256 fid) external;

    /**
     * @notice This functions gets the address of the user from msg.sender then deletes the user based on that address and the fid passed
     */
    function deleteUser() external;

    /**
     * @notice This functions gets the fid of the user
     * @param userAddress user address
     */
    function getUserFid(address userAddress) external view returns (uint256);

    event UserRegistered(address indexed userAddress, uint256 fid);
    event UserDetailsUpdated(address indexed userAddress, uint256 fid);
    event UserDeleted(address indexed userAddress, uint256 fid);

    //////////////////////////////////////////////////////////////////////////////
    //// USER PREMIUM
    //////////////////////////////////////////////////////////////////////////////
    /*
     * @notice This functions gets the premium amount, checks if the value sent is greater or equal t0 the premium amount and then
     * @param userFid user fid
     */
    function payForPremium() external payable;

    /**
     * @notice This functions sets the premium amount. This function should only be called by the owner or admin
     * @param amount premium amount
     */
    function setPremiumAmount(uint256 amount) external;

    /**
     *
     * @notice This functions gets the current premium amount
     */
    function getPremiumAmount() external view returns (uint256);

    /**
     *
     * @notice This functions gets the premium status of the user
     * @param userAddress user address
     */
    function getIsUserPremium(address userAddress) external view returns (bool);

    event PremiumPaid(address indexed userAddress, uint256 fid, uint256 amount);

    //////////////////////////////////////////////////////////////////////////////
    //// ADMINISTRATION
    //////////////////////////////////////////////////////////////////////////////
    /**
     *
     * @notice This functions gets the admin status of the user
     * @param userAddress user address
     */
    function getIsUserAdmin(address userAddress) external view returns (bool);

    /**
     *
     * @notice This functions grants a user admin status
     * @param userAddress user address
     */
    function grantAdmin(address userAddress) external;

    /**
     *
     * @notice This functions revokes a user admin status
     * @param userAddress user address
     */
    function revokeAdmin(address userAddress) external;

    function withdrawFunds() external;

    event AdminGranted(address indexed userAddress);
    event AdminRevoked(address indexed userAddress);
}
