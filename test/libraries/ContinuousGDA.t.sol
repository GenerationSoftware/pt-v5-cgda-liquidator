// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ContinuousGDA } from "src/libraries/ContinuousGDA.sol";
import { SD59x18, convert, wrap, unwrap } from "prb-math/SD59x18.sol";

contract ContinuousGDATest is Test {
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

    uint256 amountIn = ContinuousGDA.purchasePrice(
      purchaseAmount,
      emissionRate,
      initialPrice,
      decayConstant,
      elapsedTime
    );

    console2.log((amountIn * 1e18) / purchaseAmount);

    assertEq(amountIn, 87420990783136780);

    // purchaseAmount = 5e18;
    // assertEq(
    //   ContinuousGDA.purchasePrice(
    //     purchaseAmount,
    //     emissionRate,
    //     initialPrice,
    //     decayConstant,
    //     elapsedTime
    //   ),
    //   1506941032496266561
    // );

    // purchaseAmount = 10e18;
    // assertEq(
    //   ContinuousGDA.purchasePrice(
    //     purchaseAmount,
    //     emissionRate,
    //     initialPrice,
    //     decayConstant,
    //     elapsedTime
    //   ),
    //   19865241060018290657
    // );
  }

  // function testRealisticPurchasePrice() public {
  //   // 1 per 10 seconds
  //   uint256 purchaseAmount = 499999999999999999;
  //   SD59x18 emissionRate = wrap(11574074074074074074074074074074074074074074074074); // 1 per second
  //   SD59x18 initialPrice = wrap(10000000000000000000000000000000000000);
  //   SD59x18 elapsedTime = convert(12 hours);
  //   SD59x18 decayConstant = convert(5)

  //   // console2.log("purchaseAmount", purchaseAmount);
  //   // console2.log("emissionRate", unwrap(emissionRate));
  //   // console2.log("initialPrice", unwrap(initialPrice));
  //   // console2.log("decayConstant", unwrap(decayConstant));
  //   // console2.log("elapsedTime", unwrap(elapsedTime));

  //   assertEq(
  //     ContinuousGDA.purchasePrice(
  //       purchaseAmount,
  //       emissionRate,
  //       initialPrice,
  //       decayConstant,
  //       elapsedTime
  //     ),
  //     87420990783136787
  //   );

  //   purchaseAmount = 5e18;
  //   assertEq(
  //     ContinuousGDA.purchasePrice(
  //       purchaseAmount,
  //       emissionRate,
  //       initialPrice,
  //       decayConstant,
  //       elapsedTime
  //     ),
  //     1506941032496266561
  //   );

  //   purchaseAmount = 10e18;
  //   assertEq(
  //     ContinuousGDA.purchasePrice(
  //       purchaseAmount,
  //       emissionRate,
  //       initialPrice,
  //       decayConstant,
  //       elapsedTime
  //     ),
  //     19865241060018290657
  //   );
  // }
}
