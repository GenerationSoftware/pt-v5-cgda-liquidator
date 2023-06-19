// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { PrizePool } from "v5-prize-pool/PrizePool.sol";
import "./interfaces/ILiquidationSource.sol";
import "./libraries/ContinuousGDA.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

contract LiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  PrizePool public immutable prizePool;
  SD59x18 public immutable decayConstant;

  SD59x18 internal tokenOutPrice;
  SD59x18 internal lastAvailableAuctionStartTime;
  SD59x18 internal emissionRate;

  /* ============ Constructor ============ */

  constructor(
    PrizePool _prizePool,
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    SD59x18 _initialTokenOutPrice,
    SD59x18 _decayConstant
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    tokenOutPrice = _initialTokenOutPrice;
    decayConstant = _decayConstant;
    prizePool = _prizePool;
    lastAvailableAuctionStartTime = toSD59x18(int256(block.timestamp));
  }

  /* ============ External Function ============ */

  function maxAmountOut() external view returns (uint256) {
    SD59x18 elapsed = toSD59x18(int256(block.timestamp)).sub(lastAvailableAuctionStartTime);
    SD59x18 maxAvailable = emissionRate.mul(elapsed);
    return uint256(fromSD59x18(maxAvailable));
  }

  function computeExactAmountIn(uint256 _amountOut) public view returns (uint256) {
    SD59x18 elapsed = toSD59x18(int256(block.timestamp)).sub(lastAvailableAuctionStartTime);
    SD59x18 maxAvailable = emissionRate.mul(elapsed);
    require(_amountOut <= uint256(fromSD59x18(maxAvailable)), "exceeds available");
    return ContinuousGDA.purchasePrice(
      _amountOut,
      emissionRate,
      tokenOutPrice,
      decayConstant,
      elapsed
    );
  }

  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    uint256 amountIn = computeExactAmountIn(_amountOut);
    require(amountIn <= _amountInMax, "LiquidationPair/exceeds-max-amount-in");

    SD59x18 secondsOfEmissionsToPurchase = toSD59x18(int256(_amountOut)).div(emissionRate);
    lastAvailableAuctionStartTime = lastAvailableAuctionStartTime.add(secondsOfEmissionsToPurchase);

    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  /**
   * @notice Get the address that will receive `tokenIn`.
   * @return address Address of the target
   */
  function target() external returns (address) {
    return source.targetOf(tokenIn);
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }
}
