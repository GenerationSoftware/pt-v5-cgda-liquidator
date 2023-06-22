// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { PrizePool } from "v5-prize-pool/PrizePool.sol";
import "./interfaces/ILiquidationSource.sol";
import "./interfaces/ILiquidationPair.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  PrizePool public immutable prizePool;
  SD59x18 public immutable decayRate;
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
    SD59x18 _decayRate
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    tokenOutPrice = _initialTokenOutPrice;
    // How to configure this?
    // You effectively need to set a target amount of tokens that you want to be liquidated after a target amount of time.
    // That is extremely rigid. As TVL grows, the target amount needs to grow as well.
    // Yield may accrue on a different schedule than the decaying. We would need a translation layer between the yield source to expose the yield. (ex. yield accrues once a week in a large chunk. Need to expose that to the liquidation pair in a nice way so it can be accounted for.)
    decayRate = _decayRate;
    prizePool = _prizePool;
    lastAvailableAuctionStartTime = toSD59x18(int256(block.timestamp));
  }

  /* ============ External Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external view returns (uint256) {
    SD59x18 elapsed = toSD59x18(int256(block.timestamp)).sub(lastAvailableAuctionStartTime);
    SD59x18 maxAvailable = emissionRate.mul(elapsed);
    // This isn't accounting for the accrued yield, just the decay constant and time elapsed.
    // That makes the true amount available hard since the yield accrual doesn't line up with the decay rate.
    return uint256(fromSD59x18(maxAvailable));
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external view returns (uint256) {
    return _computeExactAmountIn(_amountOut);
  }

  // /// @inheritdoc ILiquidationPair
  // function computeExactAmountOut(uint256 _amountIn) external view returns (uint256) {}

  /* ============ External Write Methods ============ */

  // /// @inheritdoc ILiquidationPair
  // function swapExactAmountIn(
  //   address _account,
  //   uint256 _amountIn,
  //   uint256 _amountOutMin
  // ) external returns (uint256) {}

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    uint256 amountIn = _computeExactAmountIn(_amountOut);
    require(amountIn <= _amountInMax, "LiquidationPair/exceeds-max-amount-in");

    SD59x18 secondsOfEmissionsToPurchase = toSD59x18(int256(_amountOut)).div(emissionRate);
    lastAvailableAuctionStartTime = lastAvailableAuctionStartTime.add(secondsOfEmissionsToPurchase);

    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  function _purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (uint256) {
    SD59x18 quantity = toSD59x18(int256(_numTokens));
    SD59x18 num1 = _initialPrice.div(_decayConstant);
    SD59x18 num2 = _decayConstant.mul(quantity).div(_emissionRate).exp().sub(toSD59x18(1));
    SD59x18 den = _decayConstant.mul(_timeSinceLastAuctionStart).exp();
    return uint256(fromSD59x18(num1.mul(num2).div(den)));
  }

  function _computeExactAmountIn(uint256 _amountOut) internal view returns (uint256) {
    SD59x18 elapsed = toSD59x18(int256(block.timestamp)).sub(lastAvailableAuctionStartTime);
    SD59x18 maxAvailable = emissionRate.mul(elapsed);
    require(_amountOut <= uint256(fromSD59x18(maxAvailable)), "exceeds available");
    return _purchasePrice(_amountOut, emissionRate, tokenOutPrice, decayRate, elapsed);
  }
}
