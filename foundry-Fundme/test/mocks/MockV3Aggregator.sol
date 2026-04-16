// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

///  Minimal Chainlink AggregatorV3Interface mock for unit tests.
contract MockV3Aggregator {
    uint8 public decimals;
    int256 public latestAnswer;
    uint256 public version = 4;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        latestAnswer = _initialAnswer;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, latestAnswer, block.timestamp, block.timestamp, 1);
    }

    function updateAnswer(int256 _answer) external {
        latestAnswer = _answer;
    }
}
