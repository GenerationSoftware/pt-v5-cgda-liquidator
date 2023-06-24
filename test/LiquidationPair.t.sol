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
  uint32 PERIOD_LENGTH = 1 days;
  uint32 PERIOD_OFFSET = 1 days;

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
    initialTokenOutPrice = convert(100000e18);
    decayConstant = wrap(0.001e18);

    // Mock any yield that has accrued prior to the first auction.
    mockLiquidatableBalanceOf(1e18);
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      initialTokenOutPrice,
      decayConstant,
      wrap(0.9e18)
    );
  }

  function testMaxAmountOut() public {
    uint256 amount = 1e18;
    uint256 amountOut;
    mockLiquidatableBalanceOf(amount);

    // At the start of the first period.
    // Nothing has been emitted yet.
    vm.warp(PERIOD_OFFSET);
    amountOut = pair.maxAmountOut();
    assertEq(amountOut, amount);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_TEST() public {
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    // halfway through the auction time, but we're trying to liquidate everything
    uint256 amountIn = pair.computeExactAmountIn(1e18);
    // price should be very high
    assertEq(amountIn, 577459616663383446511500241753705134190300000);
  }

  function testGetAuction_init() public {
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountAccrued, 1e18);
    assertEq(auction.amountClaimed, 0);
    assertEq(auction.period, 0);
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET);
    assertEq(auction.targetPrice.unwrap(), initialTokenOutPrice.unwrap());
  }

  function testGetAuction_elapsedOne() public {
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.amountAccrued, 1e18); // same as before
    assertEq(auction.amountClaimed, 0);
    assertEq(auction.period, 1);
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(auction.targetPrice.unwrap(), initialTokenOutPrice.unwrap());
  }

  function testGetAuction_elapsedOne_lessClaimed() public {
    mockLiquidatableBalanceOf(0.25e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.period, 1, "period");
    assertEq(auction.amountAccrued, 0.25e18, "amount accrued"); // update with latest available
    assertEq(auction.amountClaimed, 0, "amount claimed");
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH);
    assertEq(auction.targetPrice.unwrap(), initialTokenOutPrice.unwrap());
  }

  function testGetAuction_jumpMany() public {
    mockLiquidatableBalanceOf(1.25e18);
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH * 4);
    LiquidationPair.Auction memory auction = pair.getAuction();
    assertEq(auction.period, 4, "period");
    assertEq(auction.amountAccrued, 1.25e18, "amount accrued"); // update with latest available
    assertEq(auction.amountClaimed, 0, "amount claimed");
    assertEq(auction.lastAuctionTime, PERIOD_OFFSET + PERIOD_LENGTH * 4);
    assertEq(auction.targetPrice.unwrap(), initialTokenOutPrice.unwrap());
  }

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    uint256 amountIn;
    mockLiquidatableBalanceOf(amountAvailable);

    // // At the start of the first period.
    // // The price should be approaching infinity.
    // // Nothing has been emitted.
    // vm.warp(PERIOD_OFFSET);
    // amountIn = pair.computeExactAmountIn(pair.maxAmountOut());
    // assertEq(amountIn, type(uint256).max);

    // // Near the start of the first period.
    // // The price should be very unfavourable, approaching infinity.
    // // One chunk has been emitted.
    // vm.warp(PERIOD_OFFSET + 1 seconds);
    // amountIn = pair.computeExactAmountIn(pair.maxAmountOut());
    // assertEq(amountIn, type(uint256).max);

    // Half way through the next period.
    // Our target price for a desired amount out should be achieved.
    // Target amount has been emitted.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    amountIn = pair.computeExactAmountIn(pair.maxAmountOut());
    assertEq(amountIn, 577459616663383446511500241753705134190300000);

    // // Near the end of the period.
    // // The price should be very favourable, approaching 0.
    // // All available tokens have been emitted.
    // vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1 seconds);
    // amountIn = pair.computeExactAmountIn(pair.maxAmountOut());
    // assertEq(amountIn, 0);
  }

  /* ============ swapExactAmountOut ============ */

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;
    uint256 amountIn;

    uint expectedAmountIn = 577459616663383446511500241753705134190300000;

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(
      address(source),
      alice,
      tokenIn,
      expectedAmountIn,
      tokenOut,
      1000000000000000000,
      true
    );

    // Half way through the next period.
    // Our target price for a desired amount out should be achieved.
    // Target amount has been emitted.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);
    assertEq(amountIn, expectedAmountIn);
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
