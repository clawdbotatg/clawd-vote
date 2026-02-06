//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployCLAWDVote } from "./DeployCLAWDVote.s.sol";

contract DeployScript is ScaffoldETHDeploy {
  function run() external {
    DeployCLAWDVote deployVote = new DeployCLAWDVote();
    deployVote.run();
  }
}
