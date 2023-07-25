// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { LiquidationPair, AmountInZero, AmountOutZero, TargetFirstSaleTimeLtPeriodLength } from "src/LiquidationPair.sol";

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
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(PERIOD_LENGTH),
      uint32(PERIOD_OFFSET),
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut
    );
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
      1e18
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
      0
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
      1e18
    );
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

  // function testSwapExactAmountIn_sequential() public {
  //   uint256 amountAvailable = 1e18;
  //   mockLiquidatableBalanceOf(amountAvailable);
  //   vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
  //   uint amountOut = pair.maxAmountOut();
  //   assertEq(pair.swapExactAmountOut(address(this), amountOut), amountOut-1, "equal at target sale time (with rounding error of -1)");

  //   // now warp to next period

  //   vm.warp(PERIOD_OFFSET*2 + targetFirstSaleTime);

  // }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;

    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(address(source), alice, tokenIn, amountOut - 1, tokenOut, amountOut, true);

    assertEq(
      pair.swapExactAmountOut(alice, amountOut, amountOut),
      amountOut - 1,
      "equal at target sale time (with rounding error of -1)"
    );
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
}
