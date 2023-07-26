// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

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

  function testParadigmDocPurchasePrice() public {
    // 1 per 10 seconds
    uint256 purchaseAmount = 1e18;
    SD59x18 emissionRate = convert(1e18); // 1 per second
    SD59x18 initialPrice = convert(10e18);
    SD59x18 decayConstant = wrap(0.5e18);
    SD59x18 elapsedTime = convert(10);

    console2.log("purchaseAmount", purchaseAmount);
    console2.log("emissionRate", unwrap(emissionRate));
    console2.log("initialPrice", unwrap(initialPrice));
    console2.log("decayConstant", unwrap(decayConstant));
    console2.log("elapsedTime", unwrap(elapsedTime));

    uint256 amountIn = wrapper.purchasePrice(
      purchaseAmount,
      emissionRate,
      initialPrice,
      decayConstant,
      elapsedTime
    );

    console2.log((amountIn * 1e18) / purchaseAmount);

    assertEq(amountIn, 87420990783136780);
  }

  function testPurchasePrice_ignoreTime() public {
    SD59x18 emissionRate = convert(1); // 1 per second
    SD59x18 initialPrice = convert(26);
    SD59x18 decayConstant = wrap(0.00000001e18); // time does not affect price
    SD59x18 elapsedTime = convert(0);

    assertEq(
      wrapper.purchasePrice(
        1,
        emissionRate,
        initialPrice,
        decayConstant,
        elapsedTime
      ),
      26
    );
  }

  function testPurchasePrice_cheaperBefore() public {
    SD59x18 emissionRate = convert(1); // 1 per second
    SD59x18 initialPrice = convert(1);
    SD59x18 decayConstant = wrap(0.3e18); // time does not affect price
    SD59x18 elapsedTime = convert(1);

    assertLt(
      wrapper.purchasePrice(
        1,
        emissionRate,
        initialPrice,
        decayConstant,
        elapsedTime
      ),
      uint256(convert(initialPrice))
    );
  }

  function testPurchasePrice_moreExpensiveAfter() public {
    SD59x18 emissionRate = convert(1); // 1 per second
    SD59x18 initialPrice = convert(1);
    SD59x18 decayConstant = wrap(0.3e18); // time does not affect price
    SD59x18 elapsedTime = convert(0);

    assertGe(
      wrapper.purchasePrice(
        1,
        emissionRate,
        initialPrice,
        decayConstant,
        elapsedTime
      ),
      uint256(convert(initialPrice))
    );
  }

  function testPurchasePrice_largeAmounts() public {
    SD59x18 emissionRate = convert(1e18); // 1 full token per second
    SD59x18 auctionStartingPrice = convert(1);
    SD59x18 decayConstant = wrap(0.3e18); // time does not affect price
    SD59x18 elapsedTime = convert(0); // we're ahead of schedule, so it should be expensive

    uint yieldPurchased = 1e18;

    // uint marketCostInPrizeTokens = uint(convert(auctionStartingPrice.mul(convert(int(yieldPurchased)))));

    assertGe(
      wrapper.purchasePrice(
        yieldPurchased,
        emissionRate,
        auctionStartingPrice,
        decayConstant,
        elapsedTime
      ),
      uint(convert(auctionStartingPrice))
    );
  }

  function testComputeK() public {
    uint availableAmount = 100; // 1000 USDC
    SD59x18 exchangeRateAmountOutToAmountIn = wrap(10e18);

    uint duration = 1000;
    SD59x18 emissionRate = wrap(0.1e18);//convert(int(availableAmount)).div(convert(int(duration/2)));
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
/*
  function testComputeK_bestTime() public {
    uint availableAmount = 1000e6; // 1000 USDC
    SD59x18 exchangeRateAmountOutToAmountIn = wrap(1e20);

    uint duration = 1 days;
    SD59x18 emissionRate = convert(int(availableAmount)).div(convert(int(duration/2)));
    SD59x18 decayConstant = wrap(0.0005e18);

    SD59x18 targetTime = convert(4 hours);
    SD59x18 auctionStartingPrice = computeK(emissionRate, decayConstant, targetTime, exchangeRateAmountOutToAmountIn);

    (uint elapsedTime, uint bestAmountOut, uint bestProfit, uint bestAmountIn) = computeArbitrageStart(
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      exchangeRateAmountOutToAmountIn,
      duration,
      5 minutes
    );

    console2.log("elapsedTime", elapsedTime);
    console2.log("bestAmountOut", bestAmountOut);
    console2.log("bestProfit", bestProfit);
    console2.log("bestAmountIn", bestAmountIn);
  }

  function testPurchasePrice_bestAmount() public {

    uint availableAmount = 1000e6; // 1000 USDC
    uint duration = 1 days;
    SD59x18 emissionRate = convert(int(availableAmount)).div(convert(int(duration)));
    // amount in per amount out
    SD59x18 auctionStartingPrice = convert(1000e18);
    SD59x18 decayConstant = wrap(0.001e18);

    // 1 USDC = 1 POOL => usdc/pool = 1e6/1e18 = 1e-12
    // say there is a 26 decimal token.  Pool is 18 decimals.
    // exchange rate is billion to one
    SD59x18 exchangeRateAmountOutToAmountIn = wrap(1e18);

    (uint elapsedTime, uint bestAmountOut, uint bestProfit, uint bestAmountIn) = computeArbitrageStart(
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      exchangeRateAmountOutToAmountIn,
      duration,
      5 minutes
    );

    console2.log("arbitrageStart", elapsedTime);
    console2.log("bestAmountOut", bestAmountOut);
    console2.log("bestAmountIn", bestAmountIn);
    // console2.log("bestProfit", bestProfit / 1e18);
    if (bestAmountIn > 0) {
      console2.log("trade price", uint(convert(convert(int(bestAmountOut)).div(convert(int(bestAmountIn))))));
    }
  }
  */

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
