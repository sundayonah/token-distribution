// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";

// TokenDistribution contract manages the distribution of tokens for node sales, service providers, and grants
contract TokenDistribution is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public distributionStartDate;
    uint256 public _totalSupply = 7_000_000_000 * 10 ** 18; // 7 Billion total supply

    // Node Sale Distribution
    uint256 public constant NODE_TOTAL_ALLOCATION = 350_000_000 * 10 ** 18;
    uint256 public constant NODE_DISTRIBUTION_PERIOD = 5 * 365 days;
    uint256 public constant MONTHLY_NODE_TOKENS = 5_833_333 * 10 ** 18;
    uint256 public constant NODE_VESTING_PERIOD = 30 days;

    // Service Providers Distribution
    uint256 public constant INITIAL_SERVICE_PROVIDER_TOKENS =
        500_000 * 10 ** 18;
    uint256 public constant REDUCED_SERVICE_PROVIDER_TOKENS =
        100_000 * 10 ** 18;
    uint256 public constant SERVICE_PROVIDER_PERIOD = 180 days;
    uint256 public constant SERVICE_PROVIDER_CUTOFF = 3 * 365 days;

    // Grants Distribution
    uint256 public constant GRANT_TOTAL_ALLOCATION = 42_000_000 * 10 ** 18;
    uint256 public constant GRANT_PERIOD = 365 days;
    uint256 public constant ANNUAL_GRANT_TOKENS = 6_000_000 * 10 ** 18;

    // Recipient Lists
    address[] public nodeOperators;
    address[] public serviceProviders;
    address[] public grantRecipients;

    mapping(address => bool) public isNodeOperator;
    mapping(address => bool) public isServiceProvider;
    mapping(address => bool) public isGrantRecipient;

    mapping(address => mapping(uint256 => bool)) public hasClaimedNode;
    mapping(address => mapping(uint256 => bool)) public hasClaimedService;
    mapping(address => mapping(uint256 => bool)) public hasClaimedGrant;
    mapping(address => VestingSchedule) public vestingSchedules;

    uint256 public lastNodeDistribution;
    uint256 public lastServiceDistribution;
    uint256 public lastGrantDistribution;

    event RecipientAdded(address indexed recipient, string recipientType);
    event TokensDistributed(
        address indexed recipient,
        uint256 amount,
        string distributionType
    );

    struct VestingSchedule {
        uint256 startTime;
        uint256[] distributionDates;
    }

    constructor() {
        _disableInitializers();
    }

    // Initialize the contract with the admin address and distribution start date
    function initialize(
        address admin,
        uint256 _distributionStartDate
    ) public initializer onlyAdmin {
        __ERC20_init("Distribution Token", "DIST");
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(OWNER_ROLE, msg.sender);
        distributionStartDate = _distributionStartDate;
    }

    function initializeVestingSchedule(
        address recipient,
        uint256 startTime
    ) external onlyAdmin {
        VestingSchedule storage schedule = vestingSchedules[recipient];
        schedule.startTime = startTime;

        // Calculate distribution dates based on vesting period
        uint256 currentDate = startTime;
        while (currentDate <= startTime + NODE_DISTRIBUTION_PERIOD) {
            schedule.distributionDates.push(currentDate);
            currentDate += NODE_VESTING_PERIOD;
        }
    }

    // Add multiple Node Operators at once
    function addNodeOperators(address[] calldata operators) external onlyAdmin {
        for (uint i = 0; i < operators.length; i++) {
            if (!isNodeOperator[operators[i]]) {
                nodeOperators.push(operators[i]);
                isNodeOperator[operators[i]] = true;
                emit RecipientAdded(operators[i], "NODE_OPERATOR");

                // Initialize vesting schedule
                initializeVestingSchedule(operators[i], distributionStartDate);
            }
        }
    }

    // Add multiple Service Providers at once
    function addServiceProviders(
        address[] calldata providers
    ) external onlyAdmin {
        for (uint i = 0; i < providers.length; i++) {
            if (!isServiceProvider[providers[i]]) {
                serviceProviders.push(providers[i]);
                isServiceProvider[providers[i]] = true;
                emit RecipientAdded(providers[i], "SERVICE_PROVIDER");
            }
        }
    }

    // Add multiple Grant Recipients at once
    function addGrantRecipients(
        address[] calldata recipients
    ) external onlyAdmin {
        for (uint i = 0; i < recipients.length; i++) {
            if (!isGrantRecipient[recipients[i]]) {
                grantRecipients.push(recipients[i]);
                isGrantRecipient[recipients[i]] = true;
                emit RecipientAdded(recipients[i], "GRANT_RECIPIENT");
            }
        }
    }

    // Distribute Node Sale Tokens
    function distributeNodeTokens() external onlyAdmin {
        uint256 currentTimestamp = block.timestamp;

        for (uint i = 0; i < nodeOperators.length; i++) {
            address operator = nodeOperators[i];
            VestingSchedule storage schedule = vestingSchedules[operator];

            // Find next distribution date
            for (uint j = 0; j < schedule.distributionDates.length; j++) {
                if (schedule.distributionDates[j] <= currentTimestamp) {
                    transferFrom(msg.sender, operator, MONTHLY_NODE_TOKENS);
                    emit TokensDistributed(
                        operator,
                        MONTHLY_NODE_TOKENS,
                        "NODE"
                    );
                }
            }
        }
    }

    // Distribute Service Provider Tokens
    function distributeServiceProviderTokens() external onlyAdmin {
        require(
            block.timestamp >=
                lastServiceDistribution + SERVICE_PROVIDER_PERIOD,
            "Too early for distribution"
        );

        uint256 amount;
        uint256 cyclesSinceStart = (block.timestamp - distributionStartDate) /
            SERVICE_PROVIDER_PERIOD;

        // First 6 cycles (3 years), 500,000 tokens each
        if (cyclesSinceStart < 6) {
            amount = INITIAL_SERVICE_PROVIDER_TOKENS;
        }
        // After 3 years, 100,000 tokens every 6 months
        else {
            amount = REDUCED_SERVICE_PROVIDER_TOKENS;
        }

        for (uint i = 0; i < serviceProviders.length; i++) {
            if (!hasClaimedService[serviceProviders[i]][cyclesSinceStart]) {
                _transfer(msg.sender, serviceProviders[i], amount);
                hasClaimedService[serviceProviders[i]][cyclesSinceStart] = true;
                emit TokensDistributed(
                    serviceProviders[i],
                    amount,
                    "SERVICE_PROVIDER"
                );
            }
        }
        lastServiceDistribution = block.timestamp;
    }

    // Distribute Grant Tokens
    function distributeGrantTokens() external onlyAdmin {
        require(
            block.timestamp >= lastGrantDistribution + GRANT_PERIOD,
            "Too early for distribution"
        );

        uint256 currentPeriod = (block.timestamp - distributionStartDate) /
            GRANT_PERIOD;

        for (uint i = 0; i < grantRecipients.length; i++) {
            if (!hasClaimedGrant[grantRecipients[i]][currentPeriod]) {
                _transfer(msg.sender, grantRecipients[i], ANNUAL_GRANT_TOKENS);
                hasClaimedGrant[grantRecipients[i]][currentPeriod] = true;
                emit TokensDistributed(
                    grantRecipients[i],
                    ANNUAL_GRANT_TOKENS,
                    "GRANT"
                );
            }
        }
        lastGrantDistribution = block.timestamp;
    }

    // Handle unclaimed tokens after the defined period
    function reclaimUnclaimedNodeTokens() external onlyAdmin {
        uint256 currentPeriod = (block.timestamp - distributionStartDate) /
            30 days;
        for (uint i = 0; i < nodeOperators.length; i++) {
            if (!hasClaimedNode[nodeOperators[i]][currentPeriod]) {
                _transfer(nodeOperators[i], msg.sender, MONTHLY_NODE_TOKENS);
                hasClaimedNode[nodeOperators[i]][currentPeriod] = false; // Revert claim status
            }
        }
    }

    // Cancel a transaction
    function cancelTransaction(
        address recipient,
        uint256 amount
    ) external onlyAdmin {
        _transfer(recipient, msg.sender, amount);
        emit TokensDistributed(recipient, amount, "CANCELLED");
    }

    // Modifier to restrict access to admin only
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    // Custom function to get total supply (if you need it)
    function getTotalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // Get the list of node operators
    function getNodeOperators() external view returns (address[] memory) {
        return nodeOperators;
    }

    // Get the list of service providers
    function getServiceProviders() external view returns (address[] memory) {
        return serviceProviders;
    }

    // Get the list of grant recipients
    function getGrantRecipients() external view returns (address[] memory) {
        return grantRecipients;
    }

    // Check if a node operator has claimed tokens for a given period
    function hasNodeOperatorClaimed(
        address operator,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedNode[operator][period];
    }

    // Check if a service provider has claimed tokens for a given period
    function hasServiceProviderClaimed(
        address provider,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedService[provider][period];
    }

    // Check if a grant recipient has claimed tokens for a given period
    function hasGrantRecipientClaimed(
        address recipient,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedGrant[recipient][period];
    }
}
