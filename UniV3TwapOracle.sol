//SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@uniswap/v3-core/contracts/libraries/Oracle.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";


contract UniV3TwapOracle {
    // Returns uint256 TWAP price of a Uniswap pool token1 in terms of token0 i.e. 1 token0 = x token1
    function convertToHumanReadable(address _factory, address _token0, address _token1, uint24 _fee, uint32 _twapInterval,
        uint8 _token1Decimals) public view returns(uint256) {
        int24 _tick = getTwap(_factory, _token0, _token1, _fee, _twapInterval);
        uint256 _sqrtPriceX96 = convertTickToSqrtPriceX96(_tick);
        return sqrtPriceX96ToUint(_sqrtPriceX96, _token1Decimals);
    }

/// Fetches time-weighted average price in ticks from Uniswap pool.
    function getTwap(address _factory, address _token0, address _token1, uint24 _fee, uint32 _twapInterval) public view returns (int24) {
        address _poolAddress = IUniswapV3Factory(_factory).getPool(_token0, _token1, _fee);
        require(_poolAddress != address(0), "pool doesn't exist");
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _twapInterval;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(_poolAddress).observe(secondsAgo);
        return int24((tickCumulatives[1] - tickCumulatives[0]) / _twapInterval);
        // to get tick in human readable format: 1.0001 ** tick then account for each token's decimals
        
    }

    // Converts tick to X96 price
   function convertTickToSqrtPriceX96(int24 _tick) public pure returns(uint256) {
        return TickMath.getSqrtRatioAtTick(_tick);
    }

    // Converts X96 price to uint256 price
    function sqrtPriceX96ToUint(uint256 sqrtPriceX96, uint8 decimalsToken1) public pure returns (uint256) {
        uint256 numerator1 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 numerator2 = 10**decimalsToken1;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }
   
   function getToken0FromPool(address _poolAddress) public view returns (address) {
       return IUniswapV3PoolImmutables(_poolAddress).token0();
    }

   function getToken0(address _factory, address _tokenA, address _tokenB, uint24 _fee) public view returns(address) {
       address _poolAddress = IUniswapV3Factory(_factory).getPool(_tokenA, _tokenB, _fee);
       return IUniswapV3PoolImmutables(_poolAddress).token0();
    }

   function getPoolAddress(address _factory, address _tokenA, address _tokenB, uint24 _fee) public view returns(address) {
       return IUniswapV3Factory(_factory).getPool(_tokenA, _tokenB, _fee);
    }
}
