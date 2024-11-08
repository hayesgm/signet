// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Logger} from "../src/Logger.sol";

contract LoggerTest is Test {
    function test_Logger() public pure {
        Logger.log("hello");
    }
}
