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

    SD59x18 amountIn = wrapper.purchasePrice(
      purchaseAmount,
      emissionRate,
      initialPrice,
      decayConstant,
      elapsedTime
    );

    assertEq(convert(amountIn), 111);
  }

  function testPurchasePrice_minimum() public {
    SD59x18 emissionRate = convert(1000e18).div(convert(1 days));
    SD59x18 decayConstant = wrap(0.001e18);
    SD59x18 elapsed = convert(12 hours);
    SD59x18 purchaseAmount = elapsed.mul(emissionRate);
    SD59x18 initialPrice = wrapper.computeK(emissionRate, decayConstant, elapsed, purchaseAmount, purchaseAmount);
    uint amount = uint(convert(convert(1).mul(emissionRate).ceil()));
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

  function testPurchasePrice_overflow_regression() public {
    assertApproxEqAbs(
      wrapper.purchasePrice(
        749999999999999999,
        wrap(11574074074074074074074074074074),
        wrap(5787037037037037042824074074073999999999999999998),
        wrap(1000000000000000),
        wrap(64800000000000000000000)
      ).unwrap(),
      499999999999999957159018154855990645,
      8e18
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
      uint(convert(amountOut)),
      emissionRate,
      auctionStartingPrice,
      decayConstant,
      targetTime
    );

    assertApproxEqAbs(amountIn.unwrap(), amountOut.div(exchangeRateAmountOutToAmountIn).unwrap(), 10);
  }

  function testComputeK_overflow_regressionTest() public {
    // this call should not overflow.
    assertEq(
      ContinuousGDA.computeK(
        wrap(23148148148148148148148148148148),
        wrap(1000000000000000),
        wrap(43200000000000000000000),
        wrap(999999999999999999999999999999993600),
        wrap(105637550019019116932242000471999323919679878277)
      ).unwrap(),
      2445313657847664746247211816921707517861151783024312071540664
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
