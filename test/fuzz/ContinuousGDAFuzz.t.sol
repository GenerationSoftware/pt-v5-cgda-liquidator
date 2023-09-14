// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { SD59x18, convert, wrap, unwrap } from "prb-math/SD59x18.sol";

import { ContinuousGDA } from "../../src/libraries/ContinuousGDA.sol";

contract ContinuousGDAFuzzTest is Test {
  SD59x18 decayConstant = wrap(0.001e18);
  SD59x18 auctionDuration = convert(1 days);
  SD59x18 targetFirstSaleTime = convert(12 hours);

  /**
     Fuzz exchange rates.

     POOL:USDC = 1e18:1e6 = 1e12
     */
  function testComputeK_fuzzExchangeRate(
    uint96 exchangeRate // amountIn:amountOut, 2**96 = exchange rates up to 1e28
  ) public {
    vm.assume(exchangeRate > 0);
    SD59x18 auctionSizeAmountIn = convert(1e12 * 1e18); // 1 trillion amount in "amount in" tokens
    SD59x18 exchangeRateAmountInToAmountOut = convert(int(uint(exchangeRate)));
    SD59x18 auctionAmount = auctionSizeAmountIn.div(exchangeRateAmountInToAmountOut);
    SD59x18 emissionRate = auctionAmount.div(auctionDuration);
    SD59x18 purchaseAmount = targetFirstSaleTime.mul(emissionRate);
    SD59x18 price = exchangeRateAmountInToAmountOut.mul(purchaseAmount);
    assertNotEq(
      ContinuousGDA
        .computeK(emissionRate, decayConstant, targetFirstSaleTime, purchaseAmount, price)
        .unwrap(),
      0
    );
  }

  function testComputeK_fuzzAuctionAmount(
    uint56 auctionAmount // For USDC at 1e6, this caps at ~72 billion
  ) public {
    vm.assume(auctionAmount > 0);
    SD59x18 exchangeRateAmountInToAmountOut = convert(1e12); // Pretend it's USDC
    // SD59x18 auctionAmount = auctionSizeAmountIn.div(exchangeRateAmountInToAmountOut);
    SD59x18 emissionRate = convert(int(uint(auctionAmount))).div(auctionDuration);
    SD59x18 purchaseAmount = targetFirstSaleTime.mul(emissionRate);
    SD59x18 price = exchangeRateAmountInToAmountOut.mul(purchaseAmount);
    assertNotEq(
      ContinuousGDA
        .computeK(emissionRate, decayConstant, targetFirstSaleTime, purchaseAmount, price)
        .unwrap(),
      0
    );
  }

  function testUsdc() public {
    // 1e18/1e6 => 1e12 is the exchange rate
    testComputeK_fuzzExchangeRate(1e12);
  }
}
