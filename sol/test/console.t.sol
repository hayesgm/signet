// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "../src/console.sol";

contract ConsoleTest is Test {
    function test_Logger() public view {
        console.log("hello");
    }
}
