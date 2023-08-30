// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
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
    SD59x18 purchaseAmount = convert(1);
    SD59x18 emissionRate = wrap(0.1e18); // 1 per second
    SD59x18 initialPrice = convert(18);
    SD59x18 decayConstant = wrap(0.05e18);
    SD59x18 elapsedTime = convert(1);

    SD59x18 amountIn = wrapper.purchasePrice(
      purchaseAmount,
      emissionRate,
      initialPrice,
      decayConstant,
      elapsedTime
    );

    assertEq(convert(amountIn), 222);
  }

  function testPurchasePrice_minimum() public {
    SD59x18 emissionRate = convert(1000e18).div(convert(1 days));
    SD59x18 decayConstant = wrap(0.001e18);
    SD59x18 elapsed = convert(12 hours);
    SD59x18 purchaseAmount = elapsed.mul(emissionRate);
    SD59x18 initialPrice = wrapper.computeK(emissionRate, decayConstant, elapsed, purchaseAmount, purchaseAmount);
    SD59x18 amount = convert(1).mul(emissionRate).ceil();
    console2.log("testPurchasePrice_minimum amount:", amount.unwrap());
    assertApproxEqAbs(
      wrapper.purchasePrice(
        amount,
        emissionRate,
        initialPrice,
        decayConstant,
        convert(1)
      ).unwrap(),
      499750083312503833111582646342332181,
      1e21
    );
  }

  function testPurchasePrice_happy() public {
    SD59x18 emissionRate = convert(1);
    SD59x18 decayConstant = wrap(0.001e18);
    SD59x18 elapsed = convert(1);
    SD59x18 initialPrice = convert(55);

    assertEq(
      wrapper.purchasePrice(
        convert(500),
        emissionRate,
        initialPrice,
        decayConstant,
        elapsed
      ).unwrap(),
      35644008052508359911616
    );
  }

  function testPurchasePrice_zero() public {
    assertApproxEqAbs(
      wrapper.purchasePrice(
        wrap(0),
        convert(1),
        convert(55),
        wrap(0.001e18),
        convert(1)
      ).unwrap(),
      0,
      1
    );
  }

  function testComputeK() public {
    SD59x18 exchangeRateAmountOutToAmountIn = wrap(10e18);
    SD59x18 emissionRate = wrap(0.1e18);
    SD59x18 decayConstant = wrap(0.0005e18);

    SD59x18 targetTime = convert(100);
    SD59x18 auctionStartingPrice = computeK(emissionRate, decayConstant, targetTime, exchangeRateAmountOutToAmountIn);
    SD59x18 amountOut = targetTime.mul(emissionRate);
    // console2.log("purchase price for", amountOut);
    SD59x18 amountIn = ContinuousGDA.purchasePrice(
      amountOut,
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      targetTime
    );

    assertApproxEqAbs(amountIn.unwrap(), amountOut.div(exchangeRateAmountOutToAmountIn).unwrap(), 100);
  }

  function testComputeK_overflow_regressionTest() public pure {
    // this call should not overflow.
    ContinuousGDA.computeK(
      wrap(23148148148148148148148148148148),
      wrap(1000000000000000),
      wrap(43200000000000000000000),
      wrap(999999999999999999999999999999993600),
      wrap(105637550019019116932242000471999323919679878277)
    );
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

}
