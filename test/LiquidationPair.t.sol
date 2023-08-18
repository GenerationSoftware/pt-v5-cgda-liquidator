// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";

import {
  LiquidationPair,
  AmountInZero,
  AmountOutZero,
  TargetFirstSaleTimeLtPeriodLength,
  SwapExceedsAvailable,
  DecayConstantTooLarge,
  PurchasePriceIsZero,
  SwapExceedsMax
} from "../src/LiquidationPair.sol";

contract LiquidationPairTest is Test {
  /* ============ Variables ============ */

  address public alice;

  ILiquidationSource source;
  address public target;
  address public tokenIn;
  address public tokenOut;
  SD59x18 initialTokenOutPrice;
  SD59x18 decayConstant = wrap(0.001e18);
  uint periodLength = 1 days;
  uint periodOffset = 1 days;
  uint32 targetFirstSaleTime = 12 hours;
  uint112 initialAmountIn = 1e18;
  uint112 initialAmountOut = 1e18;
  uint256 minimumAuctionAmount = 0;

  LiquidationPair pair;

  /* ============ Events ============ */

  event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

  /* ============ Set up ============ */

  function setUp() public {
    vm.warp(periodOffset);

    alice = makeAddr("Alice");

    target = makeAddr("target"); // nicely labeled address in forge console
    tokenIn = makeAddr("tokenIn");
    tokenOut = makeAddr("tokenOut");
    source = ILiquidationSource(makeAddr("source"));
    vm.etch(address(source), "liquidationSource");
    decayConstant;

    // Mock any yield that has accrued prior to the first auction.
    mockLiquidatableBalanceOf(1e18);
    pair = newPair();
  }

  function testMaxAmountIn_before() public {
    vm.warp(0);
    assertEq(pair.maxAmountIn(), 0);
  }

  function testMaxAmountIn() public {
    vm.warp(periodOffset + 1);
    assertApproxEqAbs(pair.maxAmountIn(), 499750083312544, 44);
  }

  function testConstructor_maxDecayConstant() public {
    decayConstant = wrap(0.01e18);
    vm.expectRevert(abi.encodeWithSelector(DecayConstantTooLarge.selector, wrap(1540327067910989), wrap(10000000000000000)));
    pair = newPair();
  }

  function testConstructor_amountInZero() public {
    vm.expectRevert(abi.encodeWithSelector(AmountInZero.selector));
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(periodOffset),
      targetFirstSaleTime,
      decayConstant,
      0,
      1e18,
      minimumAuctionAmount
    );
  }

  function testConstructor_amountOutZero() public {
    vm.expectRevert(abi.encodeWithSelector(AmountOutZero.selector));
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(periodOffset),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      0,
      minimumAuctionAmount
    );
  }

  function testConstructor_zeroLiquidity() public {
    mockLiquidatableBalanceOf(0);
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(periodOffset),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      1e18,
      minimumAuctionAmount
    );
  }

  function testTarget() public {
    vm.mockCall(address(source), abi.encodeWithSelector(source.targetOf.selector, tokenIn), abi.encode(target));
    assertEq(pair.target(), target);
  }

  function testMaxAmountOut() public {
    // At the start of the first period.
    // Nothing has been emitted yet.
    vm.warp(periodOffset);
    assertEq(pair.maxAmountOut(), 0);

    vm.warp(periodOffset + (periodLength / 2));
    assertEq(pair.maxAmountOut(), 0.499999999999999999e18, "half amount");

    vm.warp(periodOffset + periodLength - 1);
    assertEq(pair.maxAmountOut(), 0.999988425925925925e18, "max");
  }

  function testGetElapsedTime_beginning() public {
    vm.warp(periodOffset);
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetElapsedTime_middle() public {
    vm.warp(periodOffset + (periodLength / 2));
    assertEq(pair.getElapsedTime(), (periodLength / 2));
  }

  function testGetElapsedTime_end() public {
    vm.warp(periodOffset + periodLength - 1);
    assertEq(pair.getElapsedTime(), periodLength - 1);
  }

  function testGetElapsedTime_next() public {
    vm.warp(periodOffset + (periodLength));
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetPeriodStart_before() public {
    vm.warp(periodOffset / 2);
    assertEq(pair.getPeriodStart(), periodOffset);
  }

  function testGetPeriodStart_beginning() public {
    assertEq(pair.getPeriodStart(), periodOffset);
  }

  function testGetPeriodStart_middle() public {
    vm.warp(periodOffset + (periodLength / 2));
    assertEq(pair.getPeriodStart(), periodOffset);
  }

  function testGetPeriodStart_end() public {
    vm.warp(periodOffset + periodLength - 1);
    assertEq(pair.getPeriodStart(), periodOffset);
  }

  function testGetPeriodStart_next() public {
    vm.warp(periodOffset + periodLength);
    assertEq(pair.getPeriodStart(), periodOffset + periodLength);
  }

  function testGetPeriodEnd_beginning() public {
    assertEq(pair.getPeriodEnd(), periodOffset + periodLength);
  }

  function testMaxAmountOut_insufficientYield() public {
    mockLiquidatableBalanceOf(1e18 - 1); // just under the minimum
    vm.warp(periodOffset + (periodLength / 2));
    minimumAuctionAmount = 1e18;
    pair = newPair();
    assertEq(pair.maxAmountOut(), 0, "max");
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_targetTime() public {
    vm.warp(periodOffset + targetFirstSaleTime);
    uint available = pair.maxAmountOut();
    // halfway through the auction time, but we're trying to liquidate everything
    uint256 amountIn = pair.computeExactAmountIn(available);
    // price should match the exchange rate (less one from rounding)
    assertApproxEqAbs(amountIn, available, 6e13);
  }

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(periodOffset + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0);
    assertApproxEqAbs(
      pair.computeExactAmountIn(amountOut),
      amountOut,
      6e13,
      "equal at target sale time (with rounding error of -1)"
    );
  }

  function testComputeExactAmountIn_at_end() public {
    mockLiquidatableBalanceOf(1e27);
    vm.warp(periodOffset + periodLength - 1); // at very end of period; price should be cheapest (or zero)
    uint amountOut = pair.maxAmountOut();
    assertEq(pair.computeExactAmountIn(amountOut), 0);
  }

  function testComputeExactAmountIn_exceedsAvailable() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);
    vm.warp(periodOffset + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsAvailable.selector, amountOut*2, amountOut));
    pair.computeExactAmountIn(amountOut*2);
  }

  function testComputeExactAmountIn_jumpToFutureWithNoLiquidity() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(periodOffset * 3 + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertEq(amountOut, 0);
    assertEq(
      pair.computeExactAmountIn(0),
      0,
      "equal at target sale time (with rounding error of -1)"
    );
  }

  function testComputeExactAmountIn_jumpToFutureWithMoreLiquidity() public {
    mockLiquidatableBalanceOf(2e18);
    vm.warp(periodOffset * 3 + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0);
    assertApproxEqAbs(pair.computeExactAmountIn(amountOut), amountOut, 3e14, "equal at target sale time");
  }

  /**
    Run a successful swap, then have a couple of empty periods and ensure price doesn't change
   */
  function testComputeExactAmountIn_priceChangeThenGap() public {
    mockLiquidatableBalanceOf(2e18);
    // we're some way past the first sale time
    uint elapsed = targetFirstSaleTime + (periodLength - targetFirstSaleTime) / 2;
    // console2.log("elapsed: ", elapsed);
    vm.warp(periodOffset + elapsed); // first sale is later than normal. approximately 1:2 instead of 1:1.
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0, "amount out is non-zero");
    uint amountIn = swapAmountOut(amountOut); // incur the price change, because first sale is so delayed

    // console2.log("amountOut", amountOut);
    // console2.log("amountIn", amountIn);

    SD59x18 exchangeRate = convert(int(amountOut)).div(convert(int(amountIn)));

    // go to next period, and nothing should be available
    vm.warp(periodOffset * 2);
    // console2.log("next period");
    mockLiquidatableBalanceOf(0);
    assertEq(pair.maxAmountOut(), 0, "no yield available");

    // go to later period, and the price should adjust
    // console2.log("mock two dollars");
    mockLiquidatableBalanceOf(2e18);
    vm.warp(periodOffset * 4 + targetFirstSaleTime);
    // console2.log("computin max");
    uint laterAmountOut = pair.maxAmountOut();
    uint laterAmountIn = pair.computeExactAmountIn(laterAmountOut);

    SD59x18 laterExchangeRate = convert(int(laterAmountOut)).div(convert(int(laterAmountIn)));

    assertApproxEqAbs(exchangeRate.unwrap(), laterExchangeRate.unwrap(), 4e14, "exchange rate has been updated");
  }

  function testEstimateAmountOut() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(periodOffset + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);

    assertApproxEqAbs(
      pair.estimateAmountOut(amountIn),
      amountOut,
      1e18,
      "equal at target sale time (with rounding error of -1)"
    );
  }

  /* ============ swapExactAmountOut ============ */

  function testEmissionRate_nonZero() public {
    assertEq(pair.emissionRate().unwrap(), convert(1e18).div(convert(int(periodLength))).unwrap());
  }

  function testEmissionRate_zero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(periodOffset + periodLength);
    assertEq(pair.emissionRate().unwrap(), 0);
  }

  function testEmissionRate_insufficient() public {
    minimumAuctionAmount = 2e18;
    pair = newPair();
    mockLiquidatableBalanceOf(1e18);
    vm.warp(periodOffset + periodLength);
    assertEq(pair.emissionRate().unwrap(), 0);
  }

  function testEmissionRate_safeCap() public {
    minimumAuctionAmount = 2e18;
    pair = newPair();
    mockLiquidatableBalanceOf(type(uint256).max);
    vm.warp(periodOffset + periodLength);
    assertEq(pair.emissionRate().unwrap(), convert(int(uint(type(uint192).max))).div(convert(int(periodLength))).unwrap());
  }

  function testInitialPrice() public {
    assertNotEq(pair.initialPrice().unwrap(), 0);
  }

  function testInitialPrice_zero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(periodOffset + periodLength);
    assertEq(pair.initialPrice().unwrap(), 0);
  }

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;

    vm.warp(periodOffset + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut, true);

    assertEq(pair.amountInForPeriod(), 0, "amount in for period is zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out for period is zero");
    assertEq(pair.lastAuctionTime(), periodOffset);

    assertEq(
      pair.swapExactAmountOut(alice, amountOut, amountOut),
      amountIn,
      "equal at target sale time (with rounding error of -1)"
    );

    assertEq(pair.amountInForPeriod(), amountIn, "amount in was increased");
    assertEq(pair.amountOutForPeriod(), amountOut, "amount out was increased");
    assertEq(pair.lastAuctionTime(), periodOffset + targetFirstSaleTime - 1, "last auction increased to target time (less loss of precision)");

    vm.warp(periodOffset + periodLength);

    assertEq(pair.amountInForPeriod(), 0, "amount in was reset to zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out was reset to zero");
    assertEq(pair.lastAuctionTime(), periodOffset + periodLength);
  }

  function testSwapExactAmountOut_PurchasePriceIsZero() public {
    vm.warp(periodOffset + periodLength - 1);
    mockLiquidatableBalanceOf(1e18);
    uint amountOut = pair.maxAmountOut();
    vm.expectRevert(abi.encodeWithSelector(PurchasePriceIsZero.selector, amountOut));
    pair.swapExactAmountOut(alice, amountOut, amountOut);
  }

  function testSwapExactAmountOut_insufficient() public {
    uint256 amountAvailable = 1e18;
    vm.warp(periodOffset + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidatableBalanceOf(amountAvailable);
    uint maxAmountIn = amountOut/2; // assume it's almost 1:1 exchange rate
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsMax.selector, maxAmountIn, amountIn));
    pair.swapExactAmountOut(alice, amountOut, maxAmountIn);
  }

  function swapAmountOut(uint256 amountOut) public returns (uint256 amountIn) {
    amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut, true);
    assertEq(amountIn, pair.swapExactAmountOut(alice, amountOut, type(uint256).max));
  }

  /* ============ Mocks ============ */

  function mockLiquidatableBalanceOf(uint256 amount) public {
    vm.mockCall(
      address(source),
      abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut),
      abi.encode(amount)
    );
  }

  function mockLiquidate(
    address _source,
    address _user,
    address _tokenIn,
    uint256 _amountIn,
    address _tokenOut,
    uint256 _amountOut,
    bool _result
  ) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(
        ILiquidationSource.liquidate.selector,
        _user,
        _tokenIn,
        _amountIn,
        _tokenOut,
        _amountOut
      ),
      abi.encode(_result)
    );
  }

  function newPair() public returns (LiquidationPair) {
    return new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(periodOffset),
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut,
      minimumAuctionAmount
    );
  }
}
