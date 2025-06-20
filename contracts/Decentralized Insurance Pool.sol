// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // State variables
    address public owner;
    uint256 public totalPoolFunds;
    uint256 public constant MINIMUM_CONTRIBUTION = 0.01 ether;
    uint256 public constant CLAIM_VOTING_PERIOD = 7 days;
    
    struct Participant {
        uint256 contribution;
        uint256 joinedAt;
        bool isActive;
    }
    
    struct Claim {
        address claimant;
        uint256 amount;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 createdAt;
        uint256 votingDeadline;
        bool isResolved;
        bool isPaid;
        mapping(address => bool) hasVoted;
    }
    
    mapping(address => Participant) public participants;
    mapping(uint256 => Claim) public claims;
    uint256 public claimCounter;
    address[] public participantsList;
    
    // Events
    event ParticipantJoined(address indexed participant, uint256 contribution);
    event ClaimSubmitted(uint256 indexed claimId, address indexed claimant, uint256 amount);
    event ClaimVoted(uint256 indexed claimId, address indexed voter, bool vote);
    event ClaimResolved(uint256 indexed claimId, bool approved, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyParticipant() {
        require(participants[msg.sender].isActive, "Only active participants can call this function");
        _;
    }
    
    modifier validClaim(uint256 _claimId) {
        require(_claimId < claimCounter, "Invalid claim ID");
        require(!claims[_claimId].isResolved, "Claim already resolved");
        require(block.timestamp <= claims[_claimId].votingDeadline, "Voting period ended");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Core Function 1: Join Insurance Pool
    function joinPool() external payable {
        require(msg.value >= MINIMUM_CONTRIBUTION, "Minimum contribution not met");
        require(!participants[msg.sender].isActive, "Already a participant");
        
        participants[msg.sender] = Participant({
            contribution: msg.value,
            joinedAt: block.timestamp,
            isActive: true
        });
        
        participantsList.push(msg.sender);
        totalPoolFunds += msg.value;
        
        emit ParticipantJoined(msg.sender, msg.value);
    }
    
    // Core Function 2: Submit Insurance Claim
    function submitClaim(uint256 _amount, string memory _description) external onlyParticipant {
        require(_amount > 0, "Claim amount must be greater than 0");
        require(_amount <= totalPoolFunds / 2, "Claim amount too high");
        require(bytes(_description).length > 0, "Description required");
        
        uint256 claimId = claimCounter;
        Claim storage newClaim = claims[claimId];
        
        newClaim.claimant = msg.sender;
        newClaim.amount = _amount;
        newClaim.description = _description;
        newClaim.createdAt = block.timestamp;
        newClaim.votingDeadline = block.timestamp + CLAIM_VOTING_PERIOD;
        newClaim.isResolved = false;
        newClaim.isPaid = false;
        
        claimCounter++;
        
        emit ClaimSubmitted(claimId, msg.sender, _amount);
    }
    
    // Core Function 3: Vote on Claims
    function voteOnClaim(uint256 _claimId, bool _vote) external onlyParticipant validClaim(_claimId) {
        Claim storage claim = claims[_claimId];
        require(claim.claimant != msg.sender, "Cannot vote on own claim");
        require(!claim.hasVoted[msg.sender], "Already voted on this claim");
        
        claim.hasVoted[msg.sender] = true;
        
        if (_vote) {
            claim.votesFor++;
        } else {
            claim.votesAgainst++;
        }
        
        emit ClaimVoted(_claimId, msg.sender, _vote);
        
        // Auto-resolve if majority reached
        uint256 totalVotes = claim.votesFor + claim.votesAgainst;
        uint256 requiredMajority = (participantsList.length - 1) / 2 + 1; // Excluding claimant
        
        if (totalVotes >= requiredMajority) {
            _resolveClaim(_claimId);
        }
    }
    
    // Internal function to resolve claims
    function _resolveClaim(uint256 _claimId) internal {
        Claim storage claim = claims[_claimId];
        require(!claim.isResolved, "Claim already resolved");
        
        claim.isResolved = true;
        bool approved = claim.votesFor > claim.votesAgainst;
        
        if (approved && totalPoolFunds >= claim.amount) {
            totalPoolFunds -= claim.amount;
            claim.isPaid = true;
            payable(claim.claimant).transfer(claim.amount);
        }
        
        emit ClaimResolved(_claimId, approved, claim.amount);
    }
    
    // Resolve expired claims
    function resolveExpiredClaim(uint256 _claimId) external {
        require(_claimId < claimCounter, "Invalid claim ID");
        require(!claims[_claimId].isResolved, "Claim already resolved");
        require(block.timestamp > claims[_claimId].votingDeadline, "Voting period not ended");
        
        _resolveClaim(_claimId);
    }
    
    // View functions
    function getParticipantCount() external view returns (uint256) {
        return participantsList.length;
    }
    
    function getClaimDetails(uint256 _claimId) external view returns (
        address claimant,
        uint256 amount,
        string memory description,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 votingDeadline,
        bool isResolved,
        bool isPaid
    ) {
        require(_claimId < claimCounter, "Invalid claim ID");
        Claim storage claim = claims[_claimId];
        
        return (
            claim.claimant,
            claim.amount,
            claim.description,
            claim.votesFor,
            claim.votesAgainst,
            claim.votingDeadline,
            claim.isResolved,
            claim.isPaid
        );
    }
    
    function hasVotedOnClaim(uint256 _claimId, address _voter) external view returns (bool) {
        require(_claimId < claimCounter, "Invalid claim ID");
        return claims[_claimId].hasVoted[_voter];
    }
    
    // Emergency function (only owner)
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
        totalPoolFunds = 0;
    }
}
