// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract AutheoRewardDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Token configuration
    IERC20 public immutable Autheo;
    uint256 public immutable totalSupply;

    // Constants for decimal handling
    uint256 private immutable SCALE = 10 ** 18;

    // Allocation percentages (scaled by DECIMALS)
    uint256 public constant BUG_BOUNTY_ALLOCATION_PERCENTAGE = 6000; // 60%  of total supply
    uint256 public constant DAPP_REWARD_ALLOCATION_PERCENTAGE = 400; // 4%  of total supply
    uint256 public constant DEVELOPER_REWARD_ALLOCATION_PERCENTAGE = 200; // 2%  of total supply
    uint256 private constant MAX_BPS = 10000;

    // Fixed reward amounts
    uint256 public immutable MONTHLY_DAPP_REWARD = 5000 * SCALE;
    uint256 public immutable MONTHLY_UPTIME_BONUS = 500 * SCALE; // more than three smart contract deployed and more than fitfteen txs
    uint256 public immutable DEVELOPER_DEPLOYMENT_REWARD = 1500 * SCALE; // monthly reward

    // TGE status
    bool public isTestnet;

    // Claim amounts
    uint256 public claimPerContractDeployer;
    uint256 public claimPerDappUser;

    // Tracking variables
    uint256 public totalDappRewardsIds;
    uint256 public totalDappRewardsClaimed;
    uint256 public totalContractDeploymentClaimed;

    // Bug bounty reward calculations
    uint256 public lowRewardPerUser;
    uint256 public mediumRewardPerUser;
    uint256 public highRewardPerUser;

    uint256 public totalBugBountyRewardsClaimed;
    uint256 public totalLowBugBountyUserNumber;
    uint256 public totalMediumBugBountyUserNumber;
    uint256 public totalHighBugBountyUserNumber;
    // Constants for reward percentages
    uint256 public constant LOW_PERCENTAGE = 500;
    uint256 public constant MEDIUM_PERCENTAGE = 3500;
    uint256 public constant HIGH_PERCENTAGE = 6000;

    // User registration arrays
    address[] public lowBugBountyUsers;
    address[] public mediumBugBountyUsers;
    address[] public highBugBountyUsers;
    address[] public whitelistedContractDeploymentUsers;
    address[] public whitelistedDappRewardUsers;

    address[] public allUsers;

    uint256 public dappUserCurrentId;
    uint256 public contractDeployerCurrentId;
    uint256 public lowBugBountyCurrentId;
    uint256 public mediumBugBountyCurrentId;
    uint256 public highBugBountyCurrentId;

    // Mapping to track bug bounty criticality for users
    mapping(address => mapping(uint256 => bool))
        public isWhitelistedContractDeploymentUsersForId;
    mapping(address => mapping(uint256 => bool))
        public isWhitelistedDappUsersForId;

    mapping(address => bool) public isContractDeploymentUsersClaimed;
    mapping(address => bool) public isWhitelistedDappUsers;
    mapping(address => bool) public isDappUsersClaimed;
    mapping(address => bool) public isBugBountyUsersClaimed;
    mapping(address => bool) public hasGoodUptime;
    mapping(address => mapping(uint256 => BugCriticality))
        public bugBountyCriticality;

    mapping(address => bool) public hasReward;
    mapping(address => bool) public iswhitelistedContractDeploymentUsers;
    mapping(address => bool) public iswhitelistedDappRewardUsers;

    mapping(address => uint256) public lastContractDeploymentClaim;
    mapping(address => uint256) public contractDeploymentRegistrationTime;

    // Bug Criticality Enum
    enum BugCriticality {
        NONE,
        LOW,
        MEDIUM,
        HIGH
    }

    // Events
    event WhitelistUpdated(string claimType, address indexed user, uint256 id);
    event Claimed(string claimType, address indexed user, uint256 time);
    event ClaimAmountUpdated(uint256 newClaimedAmount);
    event EmergencyWithdraw(address token, uint256 amount);
    event TestnetStatusUpdated(bool status);

    event Received(address sender, uint256 amount);

    error USER_HAS_NO_CLAIM(address user);

    // Modifiers
    modifier whenTestnetInactive() {
        require(!isTestnet, "Contract is in testnet mode");
        _;
    }

    modifier onlyOwnerOrTestnetInactive() {
        require(
            owner() == msg.sender || !isTestnet,
            "Only owner can call during testnet"
        );
        _;
    }

    constructor() Ownable(msg.sender) {
        totalSupply = 10500000000000000000000000;
        isTestnet = true; // Start in testnet mode
    }

    /**
     * @dev Toggle testnet status
     * @param _status New testnet status
     */
    function setTestnetStatus(bool _status) external onlyOwner {
        isTestnet = _status;
        emit TestnetStatusUpdated(_status);
    }

    function transferNativeToken(
        address payable recipient,
        uint256 amount
    ) private {
        // Transfer native tokens using call
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function setClaimPerContractDeployer(
        uint256 _claimAmount
    ) public onlyOwner {
        claimPerContractDeployer = _claimAmount;
        emit ClaimAmountUpdated(_claimAmount);
    }

    function setClaimPerDappUser(uint256 _claimAmount) public onlyOwner {
        claimPerDappUser = _claimAmount;
        emit ClaimAmountUpdated(_claimAmount);
    }

    /**
     * @dev Register low criticality bug bounty users
     * @param _lowBugBountyUsers Array of addresses for low criticality bug bounties
     */

    function registerLowBugBountyUsers(
        address[] memory _lowBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");

        lowBugBountyCurrentId++;

        for (uint256 i = 0; i < _lowBugBountyUsers.length; ) {
            address user = _lowBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user][lowBugBountyCurrentId] ==
                    BugCriticality.NONE,
                "User already assigned to a criticality"
            );

            totalLowBugBountyUserNumber++;

            if (!hasReward[user]) {
                allUsers.push(user);
            }

            bugBountyCriticality[user][lowBugBountyCurrentId] = BugCriticality
                .LOW;
            hasReward[user] = true;
            emit WhitelistUpdated(
                "Low Bug Bounty",
                user,
                lowBugBountyCurrentId
            );

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Register medium criticality bug bounty users
     * @param _mediumBugBountyUsers Array of addresses for medium criticality bug bounties
     */
    function registerMediumBugBountyUsers(
        address[] memory _mediumBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");

        mediumBugBountyCurrentId++;

        for (uint256 i = 0; i < _mediumBugBountyUsers.length; ) {
            address user = _mediumBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user][mediumBugBountyCurrentId] ==
                    BugCriticality.NONE,
                "User already assigned to a criticality"
            );

            totalMediumBugBountyUserNumber++;

            if (!hasReward[user]) {
                allUsers.push(user);
            }

            bugBountyCriticality[user][
                mediumBugBountyCurrentId
            ] = BugCriticality.MEDIUM;
            hasReward[user] = true;
            emit WhitelistUpdated(
                "Medium Bug Bounty",
                user,
                mediumBugBountyCurrentId
            );

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Register high criticality bug bounty users
     * @param _highBugBountyUsers Array of addresses for high criticality bug bounties
     */
    function registerHighBugBountyUsers(
        address[] memory _highBugBountyUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");

        highBugBountyCurrentId++;

        for (uint256 i = 0; i < _highBugBountyUsers.length; ) {
            address user = _highBugBountyUsers[i];

            require(user != address(0), "Invalid address");
            require(
                bugBountyCriticality[user][highBugBountyCurrentId] ==
                    BugCriticality.NONE,
                "User already assigned to a criticality"
            );

            totalHighBugBountyUserNumber++;

            if (!hasReward[user]) {
                allUsers.push(user);
            }

            bugBountyCriticality[user][highBugBountyCurrentId] = BugCriticality
                .HIGH;
            hasReward[user] = true;
            emit WhitelistUpdated(
                "High Bug Bounty",
                user,
                highBugBountyCurrentId
            );

            unchecked {
                i++;
            }
        }
    }

    function registerContractDeploymentUsers(
        address[] memory _contractDeploymentUsers
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");

        uint256 _contractDeploymentUsersLength = _contractDeploymentUsers
            .length;
        require(
            _contractDeploymentUsersLength > 0,
            "Empty contract deployment users array"
        );

        contractDeployerCurrentId++;

        for (uint256 i = 0; i < _contractDeploymentUsersLength; ) {
            address user = _contractDeploymentUsers[i];

            require(user != address(0), "Invalid contract deployment address");
            require(
                !isWhitelistedContractDeploymentUsersForId[user][
                    contractDeployerCurrentId
                ],
                "Address already registered for contract deployment"
            );

            isWhitelistedContractDeploymentUsersForId[user][
                contractDeployerCurrentId
            ] = true;

            //Register user to whitelistedContractDeploymentUsers array
            if (!iswhitelistedContractDeploymentUsers[user]) {
                whitelistedContractDeploymentUsers.push(user);
                iswhitelistedContractDeploymentUsers[user] = true;
            }

            if (!hasReward[user]) {
                allUsers.push(user);
                hasReward[user] = true;
            }

            emit WhitelistUpdated(
                "Contract Deployment",
                user,
                contractDeployerCurrentId
            );

            unchecked {
                i++;
            }
        }
    }

    function registerDappUsers(
        address[] memory _dappRewardsUsers,
        bool[] memory _userUptime
    ) external onlyOwner {
        require(isTestnet, "Registration period has ended");

        uint256 _dappRewardsUsersLength = _dappRewardsUsers.length;
        require(
            _userUptime.length == _dappRewardsUsersLength,
            "Users must be equal length"
        );
        require(_dappRewardsUsersLength > 0, "Empty dapp rewards users array");

        // Increment ID for new registration period
        dappUserCurrentId++;

        for (uint256 i = 0; i < _dappRewardsUsersLength; i++) {
            address user = _dappRewardsUsers[i];

            require(user != address(0), "Invalid dapp rewards address");
            // Check for duplicates in current registration period
            require(
                !isWhitelistedDappUsersForId[user][dappUserCurrentId],
                "Address already registered for this period"
            );

            // Set uptime if applicable
            if (_userUptime[i]) {
                hasGoodUptime[user] = true;
            }

            // Register for current period
            isWhitelistedDappUsersForId[user][dappUserCurrentId] = true;

            //Register user to whitelistedDappRewardUsers array
            if (!iswhitelistedDappRewardUsers[user]) {
                whitelistedDappRewardUsers.push(user);
                iswhitelistedDappRewardUsers[user] = true;
            }

            // Add to allUsers if first time receiving any reward
            if (!hasReward[user]) {
                allUsers.push(user);
                hasReward[user] = true;
            }

            emit WhitelistUpdated("Dapp Users", user, dappUserCurrentId);
        }
    }

    /**
     * @dev Claim rewards for whitelisted address - Only accessible when testnet is inactive
     */
    function claimReward(
        bool _contractDeploymentClaim,
        bool _dappUserClaim,
        bool _bugBountyClaim
    ) external nonReentrant whenNotPaused whenTestnetInactive {
        // Ensure that claims can only be made after the testnet ends
        require(!isTestnet, "Claims are only allowed after the testnet ends");

        if (_contractDeploymentClaim) {
            __contractDeploymentClaim(msg.sender);
        } else if (_dappUserClaim) {
            __claimDappRewards(msg.sender);
        } else if (_bugBountyClaim) {
            __bugBountyClaim(msg.sender);
        } else {
            revert USER_HAS_NO_CLAIM(msg.sender);
        }
    }

    function __bugBountyClaim(address _user) private {
        //check if user already claimed
        require(
            !isBugBountyUsersClaimed[_user],
            "User already claimed rewards"
        );

        //calculate total amount allocated to BugBunty users
        uint256 totalBugBountyAllocation = (totalSupply *
            BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS;

        //calculate lowBugBounty amount per user
        lowRewardPerUser =
            ((totalBugBountyAllocation * LOW_PERCENTAGE) / 10000) /
            totalLowBugBountyUserNumber;

        //calculate mediumBugBounty amount per user
        mediumRewardPerUser =
            ((totalBugBountyAllocation * MEDIUM_PERCENTAGE) / 10000) /
            totalMediumBugBountyUserNumber;

        //calculate highBugBounty amount per user
        highRewardPerUser =
            ((totalBugBountyAllocation * HIGH_PERCENTAGE) / 10000) /
            totalHighBugBountyUserNumber;

        //initiate total number of registering
        uint256 numOfRegistering;

        if (lowBugBountyCurrentId > numOfRegistering)
            numOfRegistering = lowBugBountyCurrentId;
        if (mediumBugBountyCurrentId > numOfRegistering)
            numOfRegistering = mediumBugBountyCurrentId;
        if (highBugBountyCurrentId > numOfRegistering)
            numOfRegistering = highBugBountyCurrentId;

        uint256 totalRewardAmount;

        for (uint256 i = 1; i <= numOfRegistering; i++) {
            uint256 rewardAmountForId = 0;

            if (bugBountyCriticality[_user][i] == BugCriticality.LOW) {
                rewardAmountForId = lowRewardPerUser;
            } else if (
                bugBountyCriticality[_user][i] == BugCriticality.MEDIUM
            ) {
                rewardAmountForId = mediumRewardPerUser;
            } else if (bugBountyCriticality[_user][i] == BugCriticality.HIGH) {
                rewardAmountForId = highRewardPerUser;
            }

            totalRewardAmount += rewardAmountForId;
        }

        isBugBountyUsersClaimed[_user] = true;

        totalBugBountyRewardsClaimed += totalRewardAmount;

        //check total BugBounty User Rewards exceed to the 30 % of total supply
        require(
            totalBugBountyRewardsClaimed <=
                (totalSupply * BUG_BOUNTY_ALLOCATION_PERCENTAGE) / MAX_BPS,
            "exceed total reward amount allocated to Bug Bounty users"
        );

        transferNativeToken(payable(_user), totalRewardAmount);

        emit Claimed("Bug Bounty", _user, totalRewardAmount);
    }

    function __contractDeploymentClaim(address _user) private {
        // Check if user is whitelisted for deployment rewards

        uint256 actingMonths;

        for (uint256 i = 1; i <= contractDeployerCurrentId; i++) {
            if (isWhitelistedContractDeploymentUsersForId[_user][i])
                actingMonths++;
        }

        require(actingMonths != 0, "User not eligible");

        // Check if user has claimed before
        require(
            !isContractDeploymentUsersClaimed[_user],
            "User has already claimed accumulated rewards"
        );

        // Calculate total reward
        uint256 totalReward = DEVELOPER_DEPLOYMENT_REWARD * actingMonths;

        // Mark as claimed
        isContractDeploymentUsersClaimed[_user] = true;

        // Track total claimed amount
        totalContractDeploymentClaimed += totalReward;

        //check total Contract Deployment User Rewards exceed to the 1 % of total supply
        require(
            totalContractDeploymentClaimed <=
                (totalSupply * DEVELOPER_REWARD_ALLOCATION_PERCENTAGE) /
                    MAX_BPS,
            "exceed total reward amount allocated to Contract Deployment users"
        );

        // Transfer the accumulated reward
        transferNativeToken(payable(_user), totalReward);

        // Emit claim event with multiplier information
        emit Claimed(
            string.concat(
                "Contract Deployment Reward - ",
                StringsUpgradeable.toString(actingMonths),
                " months"
            ),
            _user,
            totalReward
        );
    }

    function __claimDappRewards(address _user) private {
        uint256 actingMonths;

        for (uint256 i = 1; i <= dappUserCurrentId; i++) {
            if (isWhitelistedDappUsersForId[_user][i]) actingMonths++;
        }

        require(actingMonths != 0, "User not eligible");

        // Check if the user has already claimed their rewards for the specified ID
        require(!isDappUsersClaimed[_user], "Rewards already claimed");

        uint256 rewardAmount = MONTHLY_DAPP_REWARD * actingMonths;

        // Add uptime bonus if applicable
        if (hasGoodUptime[_user]) {
            rewardAmount += MONTHLY_UPTIME_BONUS;
        }

        // Mark the user as having claimed their rewards
        isDappUsersClaimed[_user] = true;
        totalDappRewardsClaimed += rewardAmount;

        //check total Dapp User Rewards exceed to the 2 % of total supply
        require(
            totalDappRewardsClaimed <=
                (totalSupply * DAPP_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS,
            "exceed total reward amount allocated to Dapp users"
        );

        // Transfer the calculated reward to the user
        transferNativeToken(payable(_user), rewardAmount);

        // Emit claim event with multiplier information
        emit Claimed(
            string.concat(
                "Dapp User Reward - ",
                StringsUpgradeable.toString(actingMonths),
                " months"
            ),
            _user,
            rewardAmount
        );
    }

    /**
     * @dev Calculate remaining bug bounty rewards for each criticality level
     */
    function calculateRemainingClaimedAmount() public view returns (uint256) {
        return (totalBugBountyRewardsClaimed +
            totalContractDeploymentClaimed +
            totalDappRewardsClaimed);
    }

    /**
     * @dev Retrieve all whitelisted contract deployment users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedContractDeploymentUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedContractDeploymentUsers;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Function to withdraw Ether from this contract
    function withdraw() external {
        payable(msg.sender).transfer(address(this).balance);
    }

    // Function to get the balance of this contract
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Calculate remaining contract deployment rewards allocation
     * @notice Returns the amount of tokens still available for contract deployment rewards
     * @return uint256 The remaining amount of tokens available for contract deployment distribution
     */
    function calculateRemainingContractDeploymentReward()
        public
        view
        returns (uint256)
    {
        // calculate total allocation for contract deployment rewards (0.1 of total supply)
        uint256 totalDeploymentAllocation = (totalSupply *
            DEVELOPER_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;

        // Return 0 if all rewards have been claimed

        if (totalContractDeploymentClaimed >= totalDeploymentAllocation) {
            return 0;
        }

        return totalDeploymentAllocation - totalContractDeploymentClaimed;
    }

    /**
     * @dev Retrieve all whitelisted dApp reward users
     * @return address[] Array of whitelisted addresses
     */
    function getWhitelistedDappRewardUsers()
        external
        view
        returns (address[] memory)
    {
        return whitelistedDappRewardUsers;
    }

    /**
     * @dev Emergency withdraw any accidentally sent tokens
     * @param token Address of token to withdraw
     */
    function emergencyWithdraw(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        IERC20(token).safeTransfer(owner(), balance);
        emit EmergencyWithdraw(token, balance);
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Calculate remaining dApp rewards allocation
     */
    function calculateRemainingDappRewards() public view returns (uint256) {
        // get the percentage of Dapp rewards from total supply
        uint256 totalDappAllocation = (totalSupply *
            DAPP_REWARD_ALLOCATION_PERCENTAGE) / MAX_BPS;
        // substite amount claimed from this percentage and return it
        if (totalDappRewardsClaimed >= totalDappAllocation) {
            return 0;
        }

        return totalDappAllocation - totalDappRewardsClaimed;
    }

    function getAllUsers() external view returns (address[] memory) {
        return allUsers;
    }

    function getCurrentDeploymentMultiplier(
        address _user
    ) external view returns (uint256) {
        uint256 actingMonths;

        for (uint256 i = 1; i <= contractDeployerCurrentId; i++) {
            if (isWhitelistedContractDeploymentUsersForId[_user][i])
                actingMonths++;
        }

        require(actingMonths != 0, "User not eligible");

        return actingMonths;
    }
}
