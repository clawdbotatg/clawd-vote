// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CLAWDVote.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCLAWD is ERC20 {
    constructor() ERC20("CLAWD", "CLAWD") {
        _mint(msg.sender, 100_000_000_000 * 1e18);
    }
}

contract CLAWDVoteTest is Test {
    CLAWDVote public vote;
    MockCLAWD public clawd;

    address public owner = address(0xBEEF);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA201);

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 constant PROPOSAL_COST = 50_000 * 1e18;
    uint256 constant MIN_VOTE = 1_000 * 1e18;

    function setUp() public {
        clawd = new MockCLAWD();
        vote = new CLAWDVote(address(clawd), PROPOSAL_COST, MIN_VOTE, owner);

        clawd.transfer(alice, 10_000_000 * 1e18);
        clawd.transfer(bob, 10_000_000 * 1e18);
        clawd.transfer(carol, 10_000_000 * 1e18);

        vm.prank(alice); clawd.approve(address(vote), type(uint256).max);
        vm.prank(bob); clawd.approve(address(vote), type(uint256).max);
        vm.prank(carol); clawd.approve(address(vote), type(uint256).max);
    }

    function test_InitialState() public view {
        assertEq(vote.proposalCost(), PROPOSAL_COST);
        assertEq(vote.minVoteAmount(), MIN_VOTE);
        assertEq(vote.nextProposalId(), 0);
        assertEq(vote.totalBurned(), 0);
    }

    function test_CreateProposal() public {
        uint256 aliceBefore = clawd.balanceOf(alice);
        uint256 deadBefore = clawd.balanceOf(DEAD);

        vm.prank(alice);
        uint256 id = vote.createProposal("Build a DEX", "We should build a simple DEX for CLAWD");

        assertEq(id, 0);
        assertEq(vote.nextProposalId(), 1);
        assertEq(clawd.balanceOf(alice), aliceBefore - PROPOSAL_COST);
        assertEq(clawd.balanceOf(DEAD), deadBefore + PROPOSAL_COST);
        assertEq(vote.totalBurned(), PROPOSAL_COST);

        (address creator, string memory title,,,,, ) = vote.getProposal(0);
        assertEq(creator, alice);
        assertEq(title, "Build a DEX");
    }

    function test_Vote() public {
        vm.prank(alice);
        vote.createProposal("Test", "Test desc");

        vm.prank(bob);
        vote.vote(0, 100_000 * 1e18);

        (,,, uint256 totalStaked, uint256 voterCount,,) = vote.getProposal(0);
        assertEq(totalStaked, 100_000 * 1e18);
        assertEq(voterCount, 1);
        assertEq(vote.getStake(0, bob), 100_000 * 1e18);
    }

    function test_MultipleVoters() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vote.vote(0, 50_000 * 1e18);

        vm.prank(carol);
        vote.vote(0, 75_000 * 1e18);

        (,,, uint256 totalStaked, uint256 voterCount,,) = vote.getProposal(0);
        assertEq(totalStaked, 125_000 * 1e18);
        assertEq(voterCount, 2);
    }

    function test_AdditionalVote() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vote.vote(0, 50_000 * 1e18);

        vm.prank(bob);
        vote.vote(0, 30_000 * 1e18);

        assertEq(vote.getStake(0, bob), 80_000 * 1e18);
        (,,, uint256 totalStaked, uint256 voterCount,,) = vote.getProposal(0);
        assertEq(totalStaked, 80_000 * 1e18);
        // voterCount should still be 1 (same voter)
        assertEq(voterCount, 1);
    }

    function test_Unvote() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vote.vote(0, 100_000 * 1e18);

        uint256 bobBefore = clawd.balanceOf(bob);
        vm.prank(bob);
        vote.unvote(0);

        assertEq(clawd.balanceOf(bob), bobBefore + 100_000 * 1e18);
        assertEq(vote.getStake(0, bob), 0);
    }

    function test_Resolve() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vote.vote(0, 100_000 * 1e18);
        vm.prank(carol);
        vote.vote(0, 50_000 * 1e18);

        uint256 bobBefore = clawd.balanceOf(bob);
        uint256 carolBefore = clawd.balanceOf(carol);

        vm.prank(owner);
        vote.resolve(0);

        (,,,,,bool resolved,) = vote.getProposal(0);
        assertTrue(resolved);
        assertEq(clawd.balanceOf(bob), bobBefore + 100_000 * 1e18);
        assertEq(clawd.balanceOf(carol), carolBefore + 50_000 * 1e18);
    }

    // Edge cases
    function test_RevertEmptyTitle() public {
        vm.prank(alice);
        vm.expectRevert("Title: 1-100 chars");
        vote.createProposal("", "Desc");
    }

    function test_RevertBelowMinVote() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vm.expectRevert("Below minimum vote");
        vote.vote(0, 500 * 1e18); // below 1K min
    }

    function test_RevertVoteOnResolved() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(owner);
        vote.resolve(0);

        vm.prank(bob);
        vm.expectRevert("Proposal resolved");
        vote.vote(0, MIN_VOTE);
    }

    function test_RevertUnvoteOnResolved() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(bob);
        vote.vote(0, MIN_VOTE);

        vm.prank(owner);
        vote.resolve(0);

        vm.prank(bob);
        vm.expectRevert("Proposal resolved");
        vote.unvote(0);
    }

    function test_RevertNonOwnerResolve() public {
        vm.prank(alice);
        vote.createProposal("Test", "Desc");

        vm.prank(alice);
        vm.expectRevert();
        vote.resolve(0);
    }

    function test_AdminSetCost() public {
        vm.prank(owner);
        vote.setProposalCost(100_000 * 1e18);
        assertEq(vote.proposalCost(), 100_000 * 1e18);
    }

    function test_AdminSetMinVote() public {
        vm.prank(owner);
        vote.setMinVoteAmount(5_000 * 1e18);
        assertEq(vote.minVoteAmount(), 5_000 * 1e18);
    }

    function test_MultipleProposals() public {
        vm.prank(alice);
        vote.createProposal("Proposal 1", "First");
        vm.prank(bob);
        vote.createProposal("Proposal 2", "Second");

        assertEq(vote.nextProposalId(), 2);

        vm.prank(carol);
        vote.vote(0, 100_000 * 1e18);
        vm.prank(carol);
        vote.vote(1, 200_000 * 1e18);

        (,,, uint256 staked0,,,) = vote.getProposal(0);
        (,,, uint256 staked1,,,) = vote.getProposal(1);
        assertEq(staked0, 100_000 * 1e18);
        assertEq(staked1, 200_000 * 1e18);
    }
}
