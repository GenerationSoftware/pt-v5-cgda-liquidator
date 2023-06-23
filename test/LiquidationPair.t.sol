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
  SD59x18 initialAuctionPrice;
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
    initialTokenOutPrice = convert(10e18);
    initialAuctionPrice = convert(100000e18); // Really high initial starting price. Ideally as high as possible.
    decayConstant = wrap(0.001e18);

    // Mock any yield that has accrued prior to the first auction.
    mockAvailableBalanceOf(1e18);
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      PERIOD_LENGTH,
      PERIOD_OFFSET,
      initialTokenOutPrice,
      initialAuctionPrice,
      decayConstant
    );
  }

  function testMaxAmountOut() public {
    uint256 amount = 1e18;
    uint256 amountOut;
    mockAvailableBalanceOf(amount);

    // At the start of the first period.
    // Nothing has been emitted yet.
    vm.warp(PERIOD_OFFSET);
    amountOut = pair.maxAmountOut();
    assertEq(amountOut, amount);

    // Near the start of the first period.
    // One chunk has been emitted.
    vm.warp(PERIOD_OFFSET + 1 seconds);
    amountOut = pair.maxAmountOut();
    assertEq(amountOut, 2 * amount);

    // Half way through the next period.
    // Target amount has been emitted.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    amountOut = pair.maxAmountOut();
    assertEq(amountOut, 2 * amount);

    // Near the end of the period.
    // Almost all available tokens have been emitted.
    vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1 seconds);
    amountOut = pair.maxAmountOut();
    assertEq(amountOut, 2 * amount);
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_TEST() public {
    uint256 amountAvailable = 1e18;
    uint256 amountIn;
    mockAvailableBalanceOf(amountAvailable);

    // At the start of the first period.
    // The price should be approaching infinity.
    // Nothing has been emitted.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    amountIn = pair.computeExactAmountIn(1e18);
    assertEq(amountIn, 99999999999999999900000000);
  }

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    uint256 amountIn;
    mockAvailableBalanceOf(amountAvailable);

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
    assertEq(amountIn, 577459616663383446511500241753705050600000000);

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
    mockAvailableBalanceOf(amountAvailable);
    mockLiquidate(
      address(source),
      alice,
      tokenIn,
      577459616663383446511500241753705050600000000,
      tokenOut,
      2000000000000000000,
      true
    );

    // // Near the start of the first period.
    // // The price should be very unfavourable, approaching infinity.
    // // One chunk has been emitted.
    // vm.warp(PERIOD_OFFSET + 1 seconds);
    // amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);
    // assertEq(amountIn, type(uint256).max);

    // // At the start of the first period.
    // // The price should be approaching infinity.
    // // Nothing has been emitted.
    // vm.expectRevert(bytes("exceeds available"));
    // amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);

    // // Near the start of the first period.
    // // The price should be very unfavourable, approaching infinity.
    // // One chunk has been emitted.
    // vm.warp(PERIOD_OFFSET + 1 seconds);
    // amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);
    // assertEq(amountIn, type(uint256).max);

    // Half way through the next period.
    // Our target price for a desired amount out should be achieved.
    // Target amount has been emitted.
    vm.warp(PERIOD_OFFSET + (PERIOD_LENGTH / 2));
    amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);
    assertEq(amountIn, 577459616663383446511500241753705050600000000);

    // // Near the end of the period.
    // // The price should be very favourable, approaching 0.
    // // All available tokens have been emitted.
    // vm.warp(PERIOD_OFFSET + PERIOD_LENGTH - 1 seconds);
    // amountIn = pair.swapExactAmountOut(alice, pair.maxAmountOut(), type(uint256).max);
    // assertEq(amountIn, 0);
  }

  /* ============ Mocks ============ */

  function mockAvailableBalanceOf(uint256 amount) public {
    vm.mockCall(
      address(source),
      abi.encodeWithSelector(source.availableBalanceOf.selector, tokenOut),
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
