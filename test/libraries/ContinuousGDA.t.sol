// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { SD59x18, convert, wrap, unwrap } from "prb-math/SD59x18.sol";

import { ContinuousGDA } from "../../src/libraries/ContinuousGDA.sol";
import { ContinuousGDAWrapper } from "./wrapper/ContinuousGDAWrapper.sol";

contract ContinuousGDATest is Test {

  ContinuousGDAWrapper wrapper;

  function setUp() public {
    wrapper = new ContinuousGDAWrapper();
  }

  function testPurchasePrice_arbitrary() public {
    // 1 per 10 seconds
    uint256 purchaseAmount = 1;
    SD59x18 emissionRate = wrap(0.1e18); // 1 per second
    SD59x18 initialPrice = convert(18);
    SD59x18 decayConstant = wrap(0.05e18);
    SD59x18 elapsedTime = convert(1);

    uint256 amountIn = wrapper.purchasePrice(
      purchaseAmount,
      emissionRate,
      initialPrice,
      decayConstant,
      elapsedTime
    );

    assertEq(amountIn, 112);
  }

  function testComputeK() public {
    SD59x18 exchangeRateAmountOutToAmountIn = wrap(10e18);
    SD59x18 emissionRate = wrap(0.1e18);
    SD59x18 decayConstant = wrap(0.0005e18);

    SD59x18 targetTime = convert(100);
    SD59x18 auctionStartingPrice = computeK(emissionRate, decayConstant, targetTime, exchangeRateAmountOutToAmountIn);
    SD59x18 amountOut = targetTime.mul(emissionRate);
    // console2.log("purchase price for", amountOut);
    uint amountIn = ContinuousGDA.purchasePrice(
      uint(convert(amountOut)),
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      targetTime
    );

    assertEq(amountIn, uint(convert(amountOut.div(exchangeRateAmountOutToAmountIn))));
  }

  function computeK(
    SD59x18 emissionRate,
    SD59x18 decayConstant,
    SD59x18 targetTime,
    SD59x18 exchangeRateAmountOutToAmountIn
  ) public view returns (SD59x18) {
    SD59x18 purchasedAmountOut = emissionRate.mul(targetTime);
    SD59x18 priceAmountIn = purchasedAmountOut.div(exchangeRateAmountOutToAmountIn);

    // console2.log("COMPUTE_K purchasedAmountOut", uint(convert(purchasedAmountOut)));
    // console2.log("COMPUTE_K priceAmountIn", uint(convert(priceAmountIn)));
    return wrapper.computeK(
      emissionRate,
      decayConstant,
      targetTime,
      purchasedAmountOut,
      priceAmountIn
    );
  }

  function computeArbitrageStart(
    SD59x18 emissionRate,
    SD59x18 auctionStartingPrice,
    SD59x18 decayConstant,
    SD59x18 exchangeRateAmountOutToAmountIn,
    uint maxElapsedTime,
    uint timePeriod
  ) public view returns (uint elapsedTime, uint bestAmountOut, uint bestProfit, uint bestAmountIn) {
    for (elapsedTime = 0; elapsedTime < maxElapsedTime; elapsedTime += timePeriod) {
      (bestAmountOut, bestProfit, bestAmountIn) = computeBestAmountOut(
        emissionRate,
        auctionStartingPrice,
        decayConstant,
        exchangeRateAmountOutToAmountIn,
        int(elapsedTime)
      );

      if (bestProfit > 0) {
        break;
      }
    }
  }

  function computeBestAmountOut(
    SD59x18 emissionRate,
    SD59x18 auctionStartingPrice,
    SD59x18 decayConstant,
    SD59x18 marketRateAmountOutToAmountIn,
    int elapsedTime
  ) public view returns (uint amountOut, uint profit, uint amountIn) {
    SD59x18 availableAmountOut = convert(elapsedTime).mul(emissionRate);
    uint costAmountIn = ContinuousGDA.purchasePrice(
      uint(convert(availableAmountOut)),
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      convert(elapsedTime)
    );
    uint revenueAmountIn = uint(convert(availableAmountOut.div(marketRateAmountOutToAmountIn)));

    amountOut = uint(convert(availableAmountOut));
    amountIn = costAmountIn;
    profit = revenueAmountIn > costAmountIn ? revenueAmountIn - costAmountIn : 0;
  }

}
