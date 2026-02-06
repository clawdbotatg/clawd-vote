// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import "../contracts/CLAWDVote.sol";

contract DeployCLAWDVote is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        address clawdToken = 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07;
        uint256 proposalCost = 50_000 * 1e18;   // 50K CLAWD to create proposal
        uint256 minVoteAmount = 1_000 * 1e18;   // 1K CLAWD minimum vote
        address owner = 0x11ce532845cE0eAcdA41f72FDc1C88c335981442;

        CLAWDVote vote = new CLAWDVote(clawdToken, proposalCost, minVoteAmount, owner);
        console.logString(string.concat("CLAWDVote deployed at: ", vm.toString(address(vote))));
    }
}
