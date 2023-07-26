// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";

import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";

contract LiquidationPairFactoryTest is Test {
  /* ============ Variables ============ */
  LiquidationPairFactory public factory;
  address public source;
  address public target;
  address tokenIn;
  address tokenOut;
  uint32 periodLength = 1 days;
  uint32 periodOffset = 7 days;
  uint32 targetFirstSaleTime = 1 hours;
  SD59x18 decayConstant = wrap(0.001e18);
  uint112 initialAmountIn = 1e18;
  uint112 initialAmountOut = 2e18;
  uint256 minimumAuctionAmount = 1e18;

  /* ============ Events ============ */

  event PairCreated(
    LiquidationPair indexed pair,
    ILiquidationSource source,
    address tokenIn,
    address tokenOut,
    uint32 periodLength,
    uint32 periodOffset,
    uint32 targetFirstSaleTime,
    SD59x18 decayConstant,
    uint112 initialAmountIn,
    uint112 initialAmountOut,
    uint256 minimumAuctionAmount
  );

  /* ============ Set up ============ */

  function setUp() public {
    // Contract setup
    factory = new LiquidationPairFactory();
    tokenIn = makeAddr("tokenIn");
    tokenOut = makeAddr("tokenOut");
    source = makeAddr("source");
    vm.etch(source, "ILiquidationSource");
    target = makeAddr("target");
  }

  /* ============ External functions ============ */

  /* ============ createPair ============ */

  function testCreatePair() public {


    vm.expectEmit(false, false, false, true);
    emit PairCreated(
      LiquidationPair(0x0000000000000000000000000000000000000000),
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      periodLength,
      periodOffset,
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut,
      minimumAuctionAmount
    );

    mockLiquidatableBalanceOf(0);

    assertEq(factory.totalPairs(), 0, "no pairs exist");

    LiquidationPair lp = factory.createPair(
      ILiquidationSource(source),
      tokenIn,
      tokenOut,
      periodLength,
      periodOffset,
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut,
      minimumAuctionAmount
    );

    assertEq(factory.totalPairs(), 1, "one pair exists");
    assertEq(address(factory.allPairs(0)), address(lp), "pair is in array");

    assertTrue(factory.deployedPairs(lp));

    assertEq(address(lp.source()), source);
    assertEq(address(lp.tokenIn()), tokenIn);
    assertEq(address(lp.tokenOut()), tokenOut);
    assertEq(lp.periodLength(), periodLength);
    assertEq(lp.periodOffset(), periodOffset);
    assertEq(lp.targetFirstSaleTime(), targetFirstSaleTime);
    assertEq(lp.decayConstant().unwrap(), decayConstant.unwrap());
    assertEq(lp.lastNonZeroAmountIn(), initialAmountIn);
    assertEq(lp.lastNonZeroAmountOut(), initialAmountOut);
    assertEq(lp.minimumAuctionAmount(), minimumAuctionAmount);
  }

  function mockLiquidatableBalanceOf(uint256 amount) public {
    vm.mockCall(
      address(source),
      abi.encodeWithSelector(ILiquidationSource.liquidatableBalanceOf.selector, tokenOut),
      abi.encode(amount)
    );
  }

}
