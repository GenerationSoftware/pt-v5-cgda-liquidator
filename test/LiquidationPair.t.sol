// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { LiquidationPair } from "src/LiquidationPair.sol";
import { ILiquidationSource } from "src/interfaces/ILiquidationSource.sol";

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

  function testMaxAmountOut() public {
    uint256 amount = 1e18;
    mockLiquidatableBalanceOf(amount);

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
/*
  function testGetAuction_init() public {
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountIn, 0);
    assertEq(auction.amountOut, 0);
    assertEq(auction.period, 0);
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET);
    assertEq(auction.emissionRate.unwrap(), convert(1e18).div(convert(int(PERIOD_LENGTH))).unwrap());
  }

  function testGetAuction_elapsedOne() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountIn, 0);
    assertEq(auction.amountOut, 0);
    assertEq(auction.period, 1);
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(auction.emissionRate.unwrap(), convert(1e18).div(convert(int(PERIOD_LENGTH))).unwrap());
  }

  function testGetAuction_elapsedOne_lessClaimed() public {
    mockLiquidatableBalanceOf(0.25e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountIn, 0);
    assertEq(auction.amountOut, 0);
    assertEq(auction.period, 1, "period");
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(auction.emissionRate.unwrap(), convert(0.25e18).div(convert(int(PERIOD_LENGTH))).unwrap());
  }

  function testGetAuction_jumpMany() public {
    mockLiquidatableBalanceOf(1.25e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 4);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountIn, 0);
    assertEq(auction.amountOut, 0);
    assertEq(auction.period, 4, "period");
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH * 4);
    assertEq(auction.emissionRate.unwrap(), convert(1.25e18).div(convert(int(PERIOD_LENGTH))).unwrap());
  }
*/
  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    assertEq(pair.computeExactAmountIn(amountOut), amountOut-1, "equal at target sale time (with rounding error of -1)");
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;

    vm.warp(PERIOD_OFFSET + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(
      address(source),
      alice,
      tokenIn,
      amountOut-1,
      tokenOut,
      amountOut,
      true
    );

    assertEq(pair.swapExactAmountOut(alice, amountOut, amountOut), amountOut-1, "equal at target sale time (with rounding error of -1)");
  }

  function swapAmountOut(uint256 amountOut) public returns (uint256 amountIn) {
    amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidate(
      address(source),
      alice,
      tokenIn,
      amountIn,
      tokenOut,
      amountOut,
      true
    );
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
