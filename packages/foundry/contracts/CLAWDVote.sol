// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CLAWDVote
 * @notice Onchain proposal & voting system for $CLAWD holders.
 *         Create proposals (burn CLAWD), vote by staking CLAWD,
 *         unstake anytime. Admin resolves proposals, stakes returned.
 */
contract CLAWDVote is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable clawd;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public proposalCost;       // CLAWD burned to create proposal
    uint256 public minVoteAmount;      // minimum stake per vote
    uint256 public nextProposalId;
    uint256 public totalBurned;        // total CLAWD burned via proposal creation

    struct Proposal {
        uint256 id;
        address creator;
        string title;
        string description;
        uint256 totalStaked;
        uint256 voterCount;
        bool resolved;
        uint256 createdAt;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => uint256)) public stakes;
    mapping(uint256 => address[]) internal _voters;

    event ProposalCreated(uint256 indexed id, address indexed creator, string title, string description, uint256 cost);
    event Voted(uint256 indexed proposalId, address indexed voter, uint256 amount);
    event Unvoted(uint256 indexed proposalId, address indexed voter, uint256 amount);
    event ProposalResolved(uint256 indexed proposalId);
    event ProposalCostUpdated(uint256 newCost);
    event MinVoteUpdated(uint256 newMin);

    constructor(
        address _clawd,
        uint256 _proposalCost,
        uint256 _minVoteAmount,
        address _owner
    ) Ownable(_owner) {
        clawd = IERC20(_clawd);
        proposalCost = _proposalCost;
        minVoteAmount = _minVoteAmount;
    }

    // ── Create Proposal ─────────────────────────────────────────
    function createProposal(string calldata title, string calldata description) external nonReentrant returns (uint256) {
        require(bytes(title).length > 0 && bytes(title).length <= 100, "Title: 1-100 chars");
        require(bytes(description).length <= 500, "Description: max 500 chars");

        // Burn CLAWD
        clawd.safeTransferFrom(msg.sender, DEAD, proposalCost);
        totalBurned += proposalCost;

        uint256 id = nextProposalId++;
        proposals[id] = Proposal({
            id: id,
            creator: msg.sender,
            title: title,
            description: description,
            totalStaked: 0,
            voterCount: 0,
            resolved: false,
            createdAt: block.timestamp
        });

        emit ProposalCreated(id, msg.sender, title, description, proposalCost);
        return id;
    }

    // ── Vote (stake) ────────────────────────────────────────────
    function vote(uint256 proposalId, uint256 amount) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(p.createdAt > 0, "Proposal not found");
        require(!p.resolved, "Proposal resolved");
        require(amount >= minVoteAmount, "Below minimum vote");

        clawd.safeTransferFrom(msg.sender, address(this), amount);

        if (stakes[proposalId][msg.sender] == 0) {
            p.voterCount++;
            _voters[proposalId].push(msg.sender);
        }
        stakes[proposalId][msg.sender] += amount;
        p.totalStaked += amount;

        emit Voted(proposalId, msg.sender, amount);
    }

    // ── Unvote (unstake) ────────────────────────────────────────
    function unvote(uint256 proposalId) external nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(!p.resolved, "Proposal resolved");

        uint256 staked = stakes[proposalId][msg.sender];
        require(staked > 0, "No stake");

        stakes[proposalId][msg.sender] = 0;
        p.totalStaked -= staked;
        p.voterCount--;

        clawd.safeTransfer(msg.sender, staked);

        emit Unvoted(proposalId, msg.sender, staked);
    }

    // ── Resolve (admin) ─────────────────────────────────────────
    function resolve(uint256 proposalId) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(p.createdAt > 0, "Proposal not found");
        require(!p.resolved, "Already resolved");

        p.resolved = true;

        // Return all stakes to voters
        address[] storage voters = _voters[proposalId];
        for (uint256 i = 0; i < voters.length; i++) {
            uint256 staked = stakes[proposalId][voters[i]];
            if (staked > 0) {
                stakes[proposalId][voters[i]] = 0;
                clawd.safeTransfer(voters[i], staked);
            }
        }

        emit ProposalResolved(proposalId);
    }

    // ── Views ───────────────────────────────────────────────────
    function getProposal(uint256 id) external view returns (
        address creator, string memory title, string memory description,
        uint256 totalStaked, uint256 voterCount, bool resolved, uint256 createdAt
    ) {
        Proposal storage p = proposals[id];
        return (p.creator, p.title, p.description, p.totalStaked, p.voterCount, p.resolved, p.createdAt);
    }

    function getStake(uint256 proposalId, address voter) external view returns (uint256) {
        return stakes[proposalId][voter];
    }

    function getVoters(uint256 proposalId) external view returns (address[] memory) {
        return _voters[proposalId];
    }

    // ── Admin ───────────────────────────────────────────────────
    function setProposalCost(uint256 _newCost) external onlyOwner {
        require(_newCost > 0, "Cost must be > 0");
        proposalCost = _newCost;
        emit ProposalCostUpdated(_newCost);
    }

    function setMinVoteAmount(uint256 _newMin) external onlyOwner {
        require(_newMin > 0, "Min must be > 0");
        minVoteAmount = _newMin;
        emit MinVoteUpdated(_newMin);
    }
}
