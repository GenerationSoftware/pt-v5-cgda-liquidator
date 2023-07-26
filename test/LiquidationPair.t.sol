// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";
import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";

import {
  LiquidationPair,
  AmountInZero,
  AmountOutZero,
  TargetFirstSaleTimeLtPeriodLength,
  SwapExceedsAvailable,
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
  SD59x18 decayConstant;
  uint PERIOD_LENGTH = 1 days;
  uint PERIOD_OFFSET = 1 days;
  uint32 targetFirstSaleTime = 1 hours;
  uint112 initialAmountIn = 1e18;
  uint112 initialAmountOut = 1e18;
  uint256 minimumAuctionAmount = 1e18;

  LiquidationPair pair;

  /* ============ Events ============ */

  event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

  /* ============ Set up ============ */

  function setUp() public {
    vm.warp(PERIOD_OFFSET);

    alice = makeAddr("Alice");

    target = makeAddr("target"); // nicely labeled address in forge console
    tokenIn = makeAddr("tokenIn");
    tokenOut = makeAddr("tokenOut");
    source = ILiquidationSource(makeAddr("source"));
    vm.etch(address(source), "liquidationSource");
    decayConstant = wrap(0.001e18);

    // Mock any yield that has accrued prior to the first auction.
    mockLiquidatableBalanceOf(1e18);
    pair = newPair();
  }

  function testConstructor_amountInZero() public {
    vm.expectRevert(abi.encodeWithSelector(AmountInZero.selector));
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(PERIOD_LENGTH),
      uint32(PERIOD_OFFSET),
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
      uint32(PERIOD_LENGTH),
      uint32(PERIOD_OFFSET),
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
      uint32(PERIOD_LENGTH),
      uint32(PERIOD_OFFSET),
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
    vm.warp(PERIOD_OFFSET);
    assertEq(pair.maxAmountOut(), 0);

    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    assertEq(pair.maxAmountOut(), 0.499999999999999999e18, "half amount");

    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1);
    assertEq(pair.maxAmountOut(), 0.999988425925925925e18, "max");
  }

  function testGetElapsedTime_beginning() public {
    vm.warp(PERIOD_OFFSET);
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetElapsedTime_middle() public {
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    assertEq(pair.getElapsedTime(), (PERIOD_LENGTH / 2));
  }

  function testGetElapsedTime_end() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1);
    assertEq(pair.getElapsedTime(), PERIOD_LENGTH - 1);
  }

  function testGetElapsedTime_next() public {
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH));
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetPeriodStart_before() public {
    vm.warp(PERIOD_OFFSET / 2);
    assertEq(pair.getPeriodStart(), PERIOD_OFFSET);
  }

  function testGetPeriodStart_beginning() public {
    assertEq(pair.getPeriodStart(), PERIOD_OFFSET);
  }

  function testGetPeriodStart_middle() public {
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    assertEq(pair.getPeriodStart(), PERIOD_OFFSET);
  }

  function testGetPeriodStart_end() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1);
    assertEq(pair.getPeriodStart(), PERIOD_OFFSET);
  }

  function testGetPeriodStart_next() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(pair.getPeriodStart(), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  function testGetPeriodEnd_beginning() public {
    assertEq(pair.getPeriodEnd(), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  function testMaxAmountOut_insufficientYield() public {
    mockLiquidatableBalanceOf(1e18 - 1); // just under the minimum
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    minimumAuctionAmount = 1e18;
    pair = newPair();
    assertEq(pair.maxAmountOut(), 0, "max");
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_targetTime() public {
    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint available = pair.maxAmountOut();
    // halfway through the auction time, but we're trying to liquidate everything
    uint256 amountIn = pair.computeExactAmountIn(available);
    // price should match the exchange rate (less one from rounding)
    assertEq(amountIn, available - 1);
  }

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0);
    assertEq(
      pair.computeExactAmountIn(amountOut),
      amountOut - 1,
      "equal at target sale time (with rounding error of -1)"
    );
  }

  function testComputeExactAmountIn_exceedsAvailable() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);
    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsAvailable.selector, amountOut*2, amountOut));
    pair.computeExactAmountIn(amountOut*2);
  }

  function testComputeExactAmountIn_jumpToFutureWithNoLiquidity() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(PERIOD_OFFSET * 3 + targetFirstSaleTime);
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
    vm.warp(PERIOD_OFFSET * 3 + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0);
    assertEq(pair.computeExactAmountIn(amountOut), amountOut, "equal at target sale time");
  }

  /**
    Run a successful swap, then have a couple of empty periods and ensure price doesn't change
   */
  function testComputeExactAmountIn_priceChangeThenGap() public {
    mockLiquidatableBalanceOf(2e18);
    vm.warp(PERIOD_OFFSET + targetFirstSaleTime*2); // first sale is later than normal. approximately 1:2 instead of 1:1.
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0, "amount out is non-zero");
    uint amountIn = swapAmountOut(amountOut); // incur the price change, because first sale is so delayed

    // go to next period, and nothing should be available
    vm.warp(PERIOD_OFFSET * 2);
    mockLiquidatableBalanceOf(0);
    assertEq(pair.maxAmountOut(), 0, "no yield available");

    // go to later period, and the price should adjust
    mockLiquidatableBalanceOf(2e18);
    vm.warp(PERIOD_OFFSET * 4 + targetFirstSaleTime);
    uint laterAmountOut = pair.maxAmountOut();
    assertEq(amountOut, laterAmountOut, "same amount of yield is available");
    assertEq(pair.computeExactAmountIn(laterAmountOut), amountIn, "price has adjusted so that target time is the same");
  }

  function testComputeExactAmountIn_overflow() public {
    mockLiquidatableBalanceOf(2e18);
    vm.warp(type(uint256).max);
    uint amountOut = pair.maxAmountOut();
    assertEq(pair.computeExactAmountIn(amountOut), type(uint256).max, "overflow caught and max returned");
  }

  /* ============ swapExactAmountOut ============ */

  function testEmissionRate_nonZero() public {
    assertEq(pair.emissionRate().unwrap(), convert(1e18).div(convert(int(PERIOD_LENGTH))).unwrap());
  }

  function testEmissionRate_zero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(pair.emissionRate().unwrap(), 0);
  }

  function testInitialPrice() public {
    assertNotEq(pair.initialPrice().unwrap(), 0);
  }

  function testInitialPrice_zero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(pair.initialPrice().unwrap(), 0);
  }

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;

    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(address(source), alice, tokenIn, amountOut - 1, tokenOut, amountOut, true);

    assertEq(pair.amountInForPeriod(), 0, "amount in for period is zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out for period is zero");
    assertEq(pair.lastAuctionTime(), PERIOD_OFFSET);

    assertEq(
      pair.swapExactAmountOut(alice, amountOut, amountOut),
      amountOut - 1,
      "equal at target sale time (with rounding error of -1)"
    );

    assertEq(pair.amountInForPeriod(), amountOut - 1, "amount in was increased");
    assertEq(pair.amountOutForPeriod(), amountOut, "amount out was increased");
    assertEq(pair.lastAuctionTime(), PERIOD_OFFSET + targetFirstSaleTime - 1, "last auction increased to target time (less loss of precision)");

    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);

    assertEq(pair.amountInForPeriod(), 0, "amount in was reset to zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out was reset to zero");
    assertEq(pair.lastAuctionTime(), PERIOD_OFFSET + PERIOD_LENGTH);
  }

  function testSwapExactAmountOut_insufficient() public {
    uint256 amountAvailable = 1e18;
    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    mockLiquidatableBalanceOf(amountAvailable);
    uint maxAmountIn = amountOut/2; // assume it's almost 1:1 exchange rate
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsMax.selector, maxAmountIn, amountOut - 1));
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
      uint32(PERIOD_LENGTH),
      uint32(PERIOD_OFFSET),
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut,
      minimumAuctionAmount
    );
  }
}
