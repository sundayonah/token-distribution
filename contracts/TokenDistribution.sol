// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenDistribution is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20;

    // === Constants ===
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    IERC20 public distributionToken;
    uint256 public distributionStartDate;
    uint256 public _totalSupply = 7_000_000_000 * 10 ** 18;
    uint256 public constant INITIAL_SUPPLY = 900_000_000 * 10 ** 18;

    // === Distribution Constants ===
    uint256 public constant NODE_TOTAL_ALLOCATION = 350_000_000 * 10 ** 18;
    uint256 public constant NODE_DISTRIBUTION_PERIOD = 5 * 365 days;
    uint256 public constant MONTHLY_NODE_TOKENS = 5_833_333 * 10 ** 18;
    uint256 public constant NODE_VESTING_PERIOD = 30 days;
    uint256 public constant MONTHS_IN_VESTING_PERIOD = 5 * 12; // 60 months

    uint256 public constant INITIAL_SERVICE_PROVIDER_TOKENS =
        500_000 * 10 ** 18;
    uint256 public constant REDUCED_SERVICE_PROVIDER_TOKENS =
        100_000 * 10 ** 18;
    uint256 public constant SERVICE_PROVIDER_PERIOD = 180 days;
    uint256 public constant INITIAL_DISTRIBUTION_CYCLES = 6;
    uint256 public constant TOTAL_DISTRIBUTION_CYCLES = 10;

    uint256 public constant GRANT_TOTAL_ALLOCATION = 42_000_000 * 10 ** 18;
    uint256 public constant GRANT_PERIOD = 365 days;
    uint256 public constant ANNUAL_GRANT_TOKENS = 6_000_000 * 10 ** 18;
    uint256 public constant TOTAL_GRANT_CYCLES = 7;
    uint256 private constant MAX_BATCH_SIZE = 100;

    // === State Variables ===
    address[] public nodeOperators;
    address[] public serviceProviders;
    address[] public grantRecipients;

    mapping(address => bool) public isNodeOperator;
    mapping(address => bool) public isServiceProvider;
    mapping(address => bool) public isGrantRecipient;

    uint256 public totalNodeAllocated;
    uint256 public totalGrantAllocated;
    uint256 public totalServiceProviderAllocated;

    mapping(address => mapping(uint256 => bool)) public hasClaimedNode;
    mapping(address => mapping(uint256 => bool)) public hasClaimedService;
    mapping(address => mapping(uint256 => bool)) public hasClaimedGrant;

    mapping(address => VestingSchedule) public vestingSchedules;
    uint256 public lastNodeDistribution;
    uint256 public lastServiceDistribution;
    uint256 public lastGrantDistribution;

    // === Events ===
    event NodeRecipientAdded(address indexed recipient, string recipientType);
    event TokensDistributed(
        address indexed recipient,
        uint256 amount,
        string distributionType
    );
    event ServiceProvidersAdded(address[] providers, uint256 successCount);
    event ServiceProviderRemoved(address indexed provider);
    event ServiceProviderTokensDistributed(
        address indexed provider,
        uint256 amount,
        uint256 cycle
    );
    event GrantRecipientAdded(address indexed recipient, string category);
    event GrantRecipientRemoved(address indexed recipient, string category);
    event GrantTokensDistributed(
        address indexed recipient,
        uint256 amount,
        string category
    );
    event VestingScheduleInitialized(
        address indexed recipient,
        uint256 amount,
        uint256 monthlyAllocation
    );

    // === Modifiers ===
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    // === Structs ===
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 amountClaimed;
        uint256 amountRemaining;
        uint256 monthlyAllocation;
        uint256 lastClaimedTime;
    }

    // === Initialization ===
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address tokenAddress,
        uint256 _distributionStartDate
    ) public initializer {
        require(Address.isContract(tokenAddress), "Invalid token address");
        require(_distributionStartDate > block.timestamp, "Invalid start date");

        // Add initial supply verification
        IERC20 token = IERC20(tokenAddress);
        require(
            token.balanceOf(address(this)) >= INITIAL_SUPPLY,
            "Insufficient initial supply"
        );

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        distributionToken = token;
        distributionStartDate = _distributionStartDate;
    }

    // === Node Operator Functions ===
    function initializeVestingSchedules(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        uint256 totalAllocation = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            totalAllocation += amounts[i];
            require(
                totalAllocation <= NODE_TOTAL_ALLOCATION,
                "Exceeds total allocation"
            );

            address recipient = recipients[i];
            uint256 amount = amounts[i];

            require(recipient != address(0), "Invalid recipient address");
            require(amount > 0, "Amount must be greater than 0");
            require(!isNodeOperator[recipient], "Node can only be added once");

            VestingSchedule storage schedule = vestingSchedules[recipient];
            uint256 _monthlyAllocation = amount / MONTHS_IN_VESTING_PERIOD;

            schedule.monthlyAllocation = _monthlyAllocation;
            schedule.totalAmount = amount;
            schedule.amountRemaining = amount;
            schedule.amountClaimed = 0;
            schedule.lastClaimedTime = distributionStartDate;

            nodeOperators.push(recipient);
            isNodeOperator[recipient] = true;

            emit NodeRecipientAdded(recipient, "Node Operator");
            emit VestingScheduleInitialized(
                recipient,
                amount,
                _monthlyAllocation
            );
        }
    }

    function getClaimableAmount(
        address recipient
    ) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[recipient];
        if (schedule.amountRemaining == 0) return 0;
        uint256 monthsSinceLastClaim = (block.timestamp -
            schedule.lastClaimedTime) / NODE_VESTING_PERIOD;
        if (monthsSinceLastClaim == 0) return 0;
        uint256 claimableAmount = monthsSinceLastClaim *
            schedule.monthlyAllocation;
        uint256 newClaimableAmount = claimableAmount > schedule.amountRemaining
            ? schedule.amountRemaining
            : claimableAmount;
        return newClaimableAmount;
    }

    function addNodeOperators(address[] calldata operators) external onlyAdmin {
        for (uint i = 0; i < operators.length; i++) {
            if (!isNodeOperator[operators[i]]) {
                nodeOperators.push(operators[i]);
                isNodeOperator[operators[i]] = true;
                emit NodeRecipientAdded(operators[i], "NODE_OPERATOR");
                initializeVestingSchedule(operators[i], distributionStartDate);
            }
        }
    }

    function nodeOperatorsClaim() external nonReentrant {
        require(isNodeOperator[msg.sender], "Not a node operator");
        require(
            block.timestamp >= distributionStartDate,
            "Distribution period not started"
        );
        uint256 claimableAmount = getClaimableAmount(msg.sender);
        require(claimableAmount > 0, "No tokens to claim");
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.amountRemaining > 0, "All tokens claimed");
        schedule.amountClaimed += claimableAmount;
        schedule.amountRemaining -= claimableAmount;
        schedule.lastClaimedTime = block.timestamp;
        require(
            distributionToken.safeTransfer(msg.sender, claimableAmount),
            "Transfer failed"
        );
        totalNodeAllocated += claimableAmount;
        emit TokensDistributed(msg.sender, claimableAmount, "NODE_OPERATOR");
    }

    // === Service Provider Functions ===
    function addServiceProviders(
        address[] calldata providers
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        require(providers.length > 0, "Empty providers array");
        require(providers.length <= MAX_BATCH_SIZE, "Batch too large");
        uint256 successCount = 0;
        for (uint256 i = 0; i < providers.length; i++) {
            address provider = providers[i];
            if (provider == address(0) || isServiceProvider[provider]) {
                continue;
            }
            serviceProviders.push(provider);
            isServiceProvider[provider] = true;
            successCount++;
        }
        emit ServiceProvidersAdded(providers, successCount);
        return successCount;
    }

    function removeServiceProvider(
        address provider
    ) external onlyRole(ADMIN_ROLE) {
        require(isServiceProvider[provider], "Not a service provider");
        require(serviceProviders.length > 0, "No providers to remove");

        // Find provider index using a helper function
        uint256 index = findServiceProviderIndex(provider);
        require(index < serviceProviders.length, "Provider not found");

        // Remove provider by swapping with last element
        uint256 lastIndex = serviceProviders.length - 1;
        if (index != lastIndex) {
            serviceProviders[index] = serviceProviders[lastIndex];
        }
        serviceProviders.pop();
        isServiceProvider[provider] = false;

        emit ServiceProviderRemoved(provider);
    }

    function findServiceProviderIndex(
        address provider
    ) internal view returns (uint256) {
        for (uint256 i = 0; i < serviceProviders.length; i++) {
            if (serviceProviders[i] == provider) {
                return i;
            }
        }
        return serviceProviders.length;
    }

    function distributeServiceProviderTokens()
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        require(serviceProviders.length > 0, "No service providers");
        require(
            block.timestamp >=
                lastServiceDistribution + SERVICE_PROVIDER_PERIOD,
            "Too early for distribution"
        );

        uint256 currentCycle = getCurrentCycle();
        require(
            currentCycle < TOTAL_DISTRIBUTION_CYCLES,
            "Distribution period ended"
        );

        uint256 cycleAmount = calculateCycleAmount(currentCycle);
        uint256 batchSize = 50; // Process in smaller batches
        uint256 successfulDistributions = 0;

        for (uint256 i = 0; i < serviceProviders.length; i += batchSize) {
            uint256 end = Math.min(i + batchSize, serviceProviders.length);

            for (uint256 j = i; j < end; j++) {
                address provider = serviceProviders[j];
                if (!hasClaimedService[provider][currentCycle]) {
                    require(
                        distributionToken.balanceOf(address(this)) >=
                            cycleAmount,
                        "Insufficient balance"
                    );

                    if (distributionToken.safeTransfer(provider, cycleAmount)) {
                        hasClaimedService[provider][currentCycle] = true;
                        successfulDistributions++;
                        emit ServiceProviderTokensDistributed(
                            provider,
                            cycleAmount,
                            currentCycle
                        );
                    }
                }
            }

            uint256 batchDistribution = cycleAmount * successfulDistributions;
            require(
                totalServiceProviderAllocated + batchDistribution <=
                    calculateTotalServiceProviderAllocation(),
                "Exceeds total allocation"
            );
            totalServiceProviderAllocated += batchDistribution;
        }

        require(successfulDistributions > 0, "No successful distributions");
        lastServiceDistribution = block.timestamp;
    }

    function getCurrentCycle() public view returns (uint256) {
        if (block.timestamp < distributionStartDate) {
            return 0;
        }
        return
            (block.timestamp - distributionStartDate) / SERVICE_PROVIDER_PERIOD;
    }

    function calculateCycleAmount(uint256 cycle) public pure returns (uint256) {
        if (cycle < INITIAL_DISTRIBUTION_CYCLES) {
            return INITIAL_SERVICE_PROVIDER_TOKENS;
        }
        return REDUCED_SERVICE_PROVIDER_TOKENS;
    }

    function calculateTotalServiceProviderAllocation()
        public
        pure
        returns (uint256)
    {
        uint256 initialPhase = INITIAL_SERVICE_PROVIDER_TOKENS *
            INITIAL_DISTRIBUTION_CYCLES;
        uint256 remainingPhase = REDUCED_SERVICE_PROVIDER_TOKENS *
            (TOTAL_DISTRIBUTION_CYCLES - INITIAL_DISTRIBUTION_CYCLES);
        return initialPhase + remainingPhase;
    }

    function validateServiceProviderStatus(
        address provider
    )
        external
        view
        returns (bool isActive, uint256 lastClaimedCycle, uint256 totalClaimed)
    {
        isActive = isServiceProvider[provider];
        uint256 currentCycle = getCurrentCycle();

        for (uint256 i = 0; i <= currentCycle; i++) {
            if (hasClaimedService[provider][i]) {
                lastClaimedCycle = i;
                totalClaimed += calculateCycleAmount(i);
            }
        }
    }

    // === Grant Functions ===
    function addGrantRecipients(
        address[] calldata recipients
    ) external onlyRole(ADMIN_ROLE) {
        require(recipients.length > 0, "No recipients provided");
        require(recipients.length <= MAX_BATCH_SIZE, "Batch too large");

        for (uint i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            require(recipient != address(0), "Invalid address");
            require(!isGrantRecipient[recipient], "Already a grant recipient");
            require(
                grantRecipients.length < 1000, // Example maximum
                "Maximum recipients reached"
            );

            grantRecipients.push(recipient);
            isGrantRecipient[recipient] = true;
            emit GrantRecipientAdded(recipient, "GRANT");
        }
    }

    function removeGrantRecipient(
        address recipient
    ) external onlyRole(ADMIN_ROLE) {
        require(isGrantRecipient[recipient], "Recipient not found");

        for (uint256 i = 0; i < grantRecipients.length; i++) {
            if (grantRecipients[i] == recipient) {
                // Swap with last element and pop
                grantRecipients[i] = grantRecipients[
                    grantRecipients.length - 1
                ];
                grantRecipients.pop();
                isGrantRecipient[recipient] = false;
                emit GrantRecipientRemoved(recipient, "GRANT");
                return;
            }
        }
        revert("Recipient not found");
    }

    function distributeGrantTokens()
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Period validation
        require(
            block.timestamp >= lastGrantDistribution + GRANT_PERIOD,
            "Too early for distribution"
        );

        uint256 currentPeriod = (block.timestamp - distributionStartDate) /
            GRANT_PERIOD;
        require(
            currentPeriod < TOTAL_GRANT_CYCLES,
            "Grant distribution period ended"
        );

        // Recipient validation
        uint256 recipientCount = grantRecipients.length;
        require(recipientCount > 0, "No grant recipients");

        // Amount calculations with remainder handling
        uint256 amountPerRecipient = ANNUAL_GRANT_TOKENS / recipientCount;
        uint256 remainder = ANNUAL_GRANT_TOKENS % recipientCount;

        // Balance checks
        require(
            distributionToken.balanceOf(address(this)) >= ANNUAL_GRANT_TOKENS,
            "Insufficient balance"
        );
        require(
            totalGrantAllocated + ANNUAL_GRANT_TOKENS <= GRANT_TOTAL_ALLOCATION,
            "Exceeds grant allocation"
        );

        // Distribution with batch processing
        uint256 totalDistributed = 0;
        uint256 batchSize = 50;

        for (uint256 i = 0; i < recipientCount; i += batchSize) {
            uint256 end = Math.min(i + batchSize, recipientCount);

            for (uint256 j = i; j < end; j++) {
                address recipient = grantRecipients[j];
                if (!hasClaimedGrant[recipient][currentPeriod]) {
                    uint256 amount = amountPerRecipient;
                    // Add remainder to last recipient
                    if (j == recipientCount - 1) {
                        amount += remainder;
                    }

                    require(
                        distributionToken.safeTransfer(recipient, amount),
                        "Transfer failed"
                    );
                    hasClaimedGrant[recipient][currentPeriod] = true;
                    totalDistributed += amount;
                    emit GrantTokensDistributed(recipient, amount, "GRANT");
                }
            }
        }

        // Update state with actual distributed amount
        require(totalDistributed > 0, "No tokens distributed");
        totalGrantAllocated += totalDistributed;
        lastGrantDistribution = block.timestamp;
    }

    function getGrantStatus(
        address recipient
    )
        external
        view
        returns (
            bool isActive,
            uint256 lastClaimedPeriod,
            uint256 totalReceived
        )
    {
        isActive = isGrantRecipient[recipient];
        uint256 currentPeriod = (block.timestamp - distributionStartDate) /
            GRANT_PERIOD;

        for (uint256 i = 0; i <= currentPeriod; i++) {
            if (hasClaimedGrant[recipient][i]) {
                lastClaimedPeriod = i;
                totalReceived += ANNUAL_GRANT_TOKENS / grantRecipients.length;
            }
        }
    }

    // === Utility Functions ===
    function reclaimUnclaimedNodeTokens()
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        uint256 currentPeriod = (block.timestamp - distributionStartDate) /
            NODE_VESTING_PERIOD;
        for (uint i = 0; i < nodeOperators.length; i++) {
            if (!hasClaimedNode[nodeOperators[i]][currentPeriod]) {
                VestingSchedule storage schedule = vestingSchedules[
                    nodeOperators[i]
                ];
                uint256 unclaimedAmount = schedule.monthlyAllocation;
                if (
                    unclaimedAmount > 0 &&
                    schedule.amountRemaining >= unclaimedAmount
                ) {
                    schedule.amountRemaining -= unclaimedAmount;
                    require(
                        distributionToken.safeTransfer(
                            msg.sender,
                            unclaimedAmount
                        ),
                        "Transfer failed"
                    );
                    hasClaimedNode[nodeOperators[i]][currentPeriod] = true;
                    emit TokensDistributed(
                        msg.sender,
                        unclaimedAmount,
                        "RECLAIMED"
                    );
                }
            }
        }
    }

    function getVestingSchedule(
        address operator
    )
        external
        view
        returns (
            uint256 totalAmount,
            uint256 amountClaimed,
            uint256 amountRemaining,
            uint256 monthlyAllocation,
            uint256 lastClaimedTime
        )
    {
        VestingSchedule storage schedule = vestingSchedules[operator];
        return (
            schedule.totalAmount,
            schedule.amountClaimed,
            schedule.amountRemaining,
            schedule.monthlyAllocation,
            schedule.lastClaimedTime
        );
    }

    function cancelTransaction(
        address recipient,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(
            distributionToken.safeTransfer(msg.sender, amount),
            "Transfer failed"
        );
        emit TokensDistributed(recipient, amount, "CANCELLED");
    }

    // === View Functions ===
    function getTotalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function getNodeOperators() external view returns (address[] memory) {
        return nodeOperators;
    }

    function getServiceProviders() external view returns (address[] memory) {
        return serviceProviders;
    }

    function getGrantRecipients() external view returns (address[] memory) {
        return grantRecipients;
    }

    function hasNodeOperatorClaimed(
        address operator,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedNode[operator][period];
    }

    function hasServiceProviderClaimed(
        address provider,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedService[provider][period];
    }

    function hasGrantRecipientClaimed(
        address recipient,
        uint256 period
    ) external view returns (bool) {
        return hasClaimedGrant[recipient][period];
    }

    function getServiceProviderCount() external view returns (uint256) {
        return serviceProviders.length;
    }

    function getClaimStatus(
        address provider,
        uint256 cycle
    ) external view returns (bool) {
        return hasClaimedService[provider][cycle];
    }

    function getRemainingCycles() external view returns (uint256) {
        uint256 currentCycle = getCurrentCycle();
        if (currentCycle >= TOTAL_DISTRIBUTION_CYCLES) {
            return 0;
        }
        return TOTAL_DISTRIBUTION_CYCLES - currentCycle;
    }

    // === Emergency Functions ===
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Invalid amount");
        if (token == address(distributionToken)) {
            require(
                amount <=
                    distributionToken.balanceOf(address(this)) -
                        (totalNodeAllocated - getTotalClaimed()),
                "Cannot withdraw allocated tokens"
            );
        }
        IERC20Upgradeable(token).transfer(to, amount);
        emit TokensDistributed(to, amount, "EMERGENCY_WITHDRAW");
    }

    // === Control Functions ===
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function getTotalClaimed() public view returns (uint256) {
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < nodeOperators.length; i++) {
            VestingSchedule storage schedule = vestingSchedules[
                nodeOperators[i]
            ];
            totalClaimed += schedule.amountClaimed;
        }
        return totalClaimed;
    }
}
