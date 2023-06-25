// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ContinuousGDA } from "src/libraries/ContinuousGDA.sol";
import { ContinuousGDAWrapper } from "./wrapper/ContinuousGDAWrapper.sol";
import { SD59x18, convert, wrap, unwrap } from "prb-math/SD59x18.sol";

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

  function testPurchasePrice_onTime() public {
    SD59x18 emissionRate = convert(10); // 1 per second
    SD59x18 initialPrice = convert(26);
    SD59x18 decayConstant = wrap(1e18);
    SD59x18 elapsedTime = convert(0);

    assertEq(
      wrapper.purchasePrice(
        5,
        emissionRate,
        initialPrice,
        decayConstant,
        elapsedTime
      ),
      16
    );
  }
}
