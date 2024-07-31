// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

contract Rock {
    error Stumble(uint256 c);

    struct Fun {
        uint256 beats;
        string song;
    }

    function jam(uint256 beats) pure public returns (Fun memory f) {
        return Fun({
            beats: beats,
            song: "Band on the Run"
        });
    }

    function stumble() pure public returns (uint256) {
        revert Stumble(55);
    }
}
