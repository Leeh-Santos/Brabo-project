// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// Minimal Uniswap V3 pool mock.
/// Public state variables generate ABI-compatible getters for token0(), token1(), fee(), tickSpacing().
contract MockUniswapV3Pool {
    address public token0;
    address public token1;
    uint24  public fee;
    int24   public tickSpacing;

    uint160 private _sqrtPriceX96;

    constructor(address _token0, address _token1, uint160 sqrtPriceX96_) {
        token0          = _token0;
        token1          = _token1;
        _sqrtPriceX96   = sqrtPriceX96_;
        fee             = 3000;
        tickSpacing     = 60;
    }

    /// Returns the pool's current price. Only sqrtPriceX96 is non-zero; other fields unused in tests.
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24   tick,
            uint16  observationIndex,
            uint16  observationCardinality,
            uint16  observationCardinalityNext,
            uint8   feeProtocol,
            bool    unlocked
        )
    {
        return (_sqrtPriceX96, 0, 0, 1, 1, 0, true);
    }

    function setSqrtPriceX96(uint160 sqrtPriceX96_) external {
        _sqrtPriceX96 = sqrtPriceX96_;
    }
}
