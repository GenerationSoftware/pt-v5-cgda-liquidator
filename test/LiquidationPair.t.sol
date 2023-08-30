// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { IFlashSwapCallback } from "pt-v5-liquidator-interfaces/IFlashSwapCallback.sol";

import {
  LiquidationPair,
  AmountInZero,
  AmountOutZero,
  TargetFirstSaleTimeGePeriodLength,
  SwapExceedsAvailable,
  DecayConstantTooLarge,
  PurchasePriceIsZero,
  SwapExceedsMax,
  LiquidationSourceZeroAddress,
  TokenInZeroAddress,
  ReceiverIsZero,
  EmissionRateIsZero,
  TokenOutZeroAddress
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
  uint firstPeriodStartsAt = 1 days;
  uint32 targetFirstSaleTime = 12 hours;
  uint104 initialAmountIn = 1e18;
  uint104 initialAmountOut = 1e18;
  uint256 minimumAuctionAmount = 0;

  LiquidationPair pair;

  /* ============ Events ============ */

  /// @notice Emitted when a new auction is started
  /// @param lastNonZeroAmountIn The total tokens in for the previous non-zero auction
  /// @param lastNonZeroAmountOut The total tokens out for the previous non-zero auction
  /// @param lastAuctionTime The timestamp at which the auction starts
  /// @param period The current auction period
  /// @param emissionRate The rate of token emissions for the current auction
  /// @param initialPrice The initial price for the current auction
  event StartedAuction(
    uint104 lastNonZeroAmountIn,
    uint104 lastNonZeroAmountOut,
    uint48 lastAuctionTime,
    uint48 indexed period,
    SD59x18 emissionRate,
    SD59x18 initialPrice
  );

  /// @notice Emitted when a swap is made
  /// @param sender The sender of the swap
  /// @param receiver The receiver of the swap
  /// @param amountOut The amount of tokens out
  /// @param amountInMax The maximum amount of tokens in
  /// @param amountIn The actual amount of tokens in
  /// @param flashSwapData The data for the flash swap
  event SwappedExactAmountOut(
    address indexed sender,
    address indexed receiver,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 amountIn,
    bytes flashSwapData
  );

  /* ============ Set up ============ */

  function setUp() public {
    vm.warp(firstPeriodStartsAt);

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

  function testMaxAmountIn_EmissionRateIsZero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(firstPeriodStartsAt + periodLength * 2);
    assertEq(pair.maxAmountIn(), 0);
  }

  function testMaxAmountIn() public {
    vm.warp(firstPeriodStartsAt + 1);
    assertApproxEqAbs(pair.maxAmountIn(), 499750083312544, 44);
  }

  function testConstructor_maxDecayConstant() public {
    decayConstant = wrap(0.01e18);
    vm.expectRevert(abi.encodeWithSelector(DecayConstantTooLarge.selector, wrap(1540327067910989), wrap(10000000000000000)));
    pair = newPair();
  }

  function testConstructor_LiquidationSourceZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(LiquidationSourceZeroAddress.selector));
    pair = new LiquidationPair(
      ILiquidationSource(address(0)),
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      1e18,
      minimumAuctionAmount
    );
  }

  function testConstructor_TokenInZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(TokenInZeroAddress.selector));
    pair = new LiquidationPair(
      source,
      address(0),
      tokenOut,
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      1e18,
      minimumAuctionAmount
    );
  }

  function testConstructor_TokenOutZeroAddress() public {
    vm.expectRevert(abi.encodeWithSelector(TokenOutZeroAddress.selector));
    pair = new LiquidationPair(
      source,
      tokenIn,
      address(0),
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      1e18,
      minimumAuctionAmount
    );
  }

  function testConstructor_amountInZero() public {
    vm.expectRevert(abi.encodeWithSelector(AmountInZero.selector));
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
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
      uint32(firstPeriodStartsAt),
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
      uint32(firstPeriodStartsAt),
      targetFirstSaleTime,
      decayConstant,
      1e18,
      1e18,
      minimumAuctionAmount
    );
  }

  function testConstructor_StartedAuction() public {
    mockLiquidatableBalanceOf(1e18 * 86400);
    vm.expectEmit(true, true, true, true);
    emit StartedAuction(
      initialAmountIn,
      initialAmountOut,
      uint48(firstPeriodStartsAt),
      0,
      wrap(1000000000000000000000000000000000000),
      wrap(43200000000000000000000000000000000000)
    );
    pair = new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
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
    vm.warp(firstPeriodStartsAt);
    assertEq(pair.maxAmountOut(), 0);

    vm.warp(firstPeriodStartsAt + (periodLength / 2));
    assertEq(pair.maxAmountOut(), 0.499999999999999999e18, "half amount");

    vm.warp(firstPeriodStartsAt + periodLength - 1);
    assertEq(pair.maxAmountOut(), 0.999988425925925925e18, "max");
  }

  function testGetElapsedTime_beginning() public {
    vm.warp(firstPeriodStartsAt);
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetElapsedTime_middle() public {
    vm.warp(firstPeriodStartsAt + (periodLength / 2));
    assertEq(pair.getElapsedTime(), (periodLength / 2));
  }

  function testGetElapsedTime_end() public {
    vm.warp(firstPeriodStartsAt + periodLength - 1);
    assertEq(pair.getElapsedTime(), periodLength - 1);
  }

  function testGetElapsedTime_next() public {
    vm.warp(firstPeriodStartsAt + (periodLength));
    assertEq(pair.getElapsedTime(), 0);
  }

  function testGetPeriodStart_before() public {
    vm.warp(firstPeriodStartsAt / 2);
    assertEq(pair.getPeriodStart(), firstPeriodStartsAt);
  }

  function testGetPeriodStart_beginning() public {
    assertEq(pair.getPeriodStart(), firstPeriodStartsAt);
  }

  function testGetPeriodStart_middle() public {
    vm.warp(firstPeriodStartsAt + (periodLength / 2));
    assertEq(pair.getPeriodStart(), firstPeriodStartsAt);
  }

  function testGetPeriodStart_end() public {
    vm.warp(firstPeriodStartsAt + periodLength - 1);
    assertEq(pair.getPeriodStart(), firstPeriodStartsAt);
  }

  function testGetPeriodStart_next() public {
    vm.warp(firstPeriodStartsAt + periodLength);
    assertEq(pair.getPeriodStart(), firstPeriodStartsAt + periodLength);
  }

  function testGetPeriodEnd_beginning() public {
    assertEq(pair.getPeriodEnd(), firstPeriodStartsAt + periodLength);
  }

  function testMaxAmountOut_insufficientYield() public {
    mockLiquidatableBalanceOf(1e18 - 1); // just under the minimum
    vm.warp(firstPeriodStartsAt + (periodLength / 2));
    minimumAuctionAmount = 1e18;
    pair = newPair();
    assertEq(pair.maxAmountOut(), 0, "max");
  }

  /* ============ computeExactAmountIn ============ */

  function testComputeExactAmountIn_targetTime() public {
    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
    uint available = pair.maxAmountOut();
    // halfway through the auction time, but we're trying to liquidate everything
    uint256 amountIn = pair.computeExactAmountIn(available);
    // price should match the exchange rate (less one from rounding)
    assertApproxEqAbs(amountIn, available, 6e13);
  }

  function testComputeExactAmountIn_EmissionRateIsZero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(firstPeriodStartsAt + periodLength * 10);
    vm.expectRevert(abi.encodeWithSelector(EmissionRateIsZero.selector));
    pair.computeExactAmountIn(1e18);
  }

  function testComputeExactAmountIn_HappyPath() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
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
    vm.warp(firstPeriodStartsAt + periodLength - 1); // at very end of period; price should be cheapest (or zero)
    uint amountOut = pair.maxAmountOut();
    assertEq(pair.computeExactAmountIn(amountOut), 0);
  }

  function testComputeExactAmountIn_exceedsAvailable() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);
    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsAvailable.selector, amountOut*2, amountOut));
    pair.computeExactAmountIn(amountOut*2);
  }

  function testComputeExactAmountIn_jumpToFutureWithNoLiquidity() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(firstPeriodStartsAt * 3 + targetFirstSaleTime);
    vm.expectEmit(true, true, true, true);
    emit StartedAuction(
      initialAmountIn,
      initialAmountOut,
      uint48(firstPeriodStartsAt + periodLength*2),
      2,
      wrap(0),
      wrap(0)
    );
    assertEq(pair.maxAmountOut(), 0);
    assertEq(pair.maxAmountIn(), 0);
  }

  function testComputeExactAmountIn_jumpToFutureWithMoreLiquidity() public {
    mockLiquidatableBalanceOf(2e18);
    vm.warp(firstPeriodStartsAt * 3 + targetFirstSaleTime);
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
    vm.warp(firstPeriodStartsAt + elapsed); // first sale is later than normal. approximately 1:2 instead of 1:1.
    uint amountOut = pair.maxAmountOut();
    assertGt(amountOut, 0, "amount out is non-zero");
    uint amountIn = swapAmountOut(amountOut); // incur the price change, because first sale is so delayed

    // console2.log("amountOut", amountOut);
    // console2.log("amountIn", amountIn);

    SD59x18 exchangeRate = convert(int(amountOut)).div(convert(int(amountIn)));

    // go to next period, and nothing should be available
    vm.warp(firstPeriodStartsAt * 2);
    // console2.log("next period");
    mockLiquidatableBalanceOf(0);
    assertEq(pair.maxAmountOut(), 0, "no yield available");

    // go to later period, and the price should adjust
    // console2.log("mock two dollars");
    mockLiquidatableBalanceOf(2e18);
    vm.warp(firstPeriodStartsAt * 4 + targetFirstSaleTime);
    // console2.log("computin max");
    uint laterAmountOut = pair.maxAmountOut();
    uint laterAmountIn = pair.computeExactAmountIn(laterAmountOut);

    SD59x18 laterExchangeRate = convert(int(laterAmountOut)).div(convert(int(laterAmountIn)));

    assertApproxEqAbs(exchangeRate.unwrap(), laterExchangeRate.unwrap(), 4e14, "exchange rate has been updated");
  }

  function testEstimateAmountOut() public {
    uint256 amountAvailable = 1e18;
    mockLiquidatableBalanceOf(amountAvailable);

    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
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
    vm.warp(firstPeriodStartsAt + periodLength);
    assertEq(pair.emissionRate().unwrap(), 0);
  }

  function testEmissionRate_insufficient() public {
    minimumAuctionAmount = 2e18;
    pair = newPair();
    mockLiquidatableBalanceOf(1e18);
    vm.warp(firstPeriodStartsAt + periodLength);
    assertEq(pair.emissionRate().unwrap(), 0);
  }

  function testEmissionRate_safeCap() public {
    minimumAuctionAmount = 2e18;
    pair = newPair();
    mockLiquidatableBalanceOf(type(uint256).max);
    vm.warp(firstPeriodStartsAt + periodLength);
    assertEq(pair.emissionRate().unwrap(), convert(int(uint(type(uint192).max))).div(convert(int(periodLength))).unwrap());
  }

  function testInitialPrice() public {
    assertNotEq(pair.initialPrice().unwrap(), 0);
  }

  function testInitialPrice_zero() public {
    mockLiquidatableBalanceOf(0);
    vm.warp(firstPeriodStartsAt + periodLength);
    assertEq(pair.initialPrice().unwrap(), 0);
  }

  function testSwapExactAmountOut_ReceiverIsZero() public {
    vm.expectRevert(abi.encodeWithSelector(ReceiverIsZero.selector));
    pair.swapExactAmountOut(address(0), 1e18, 1e18, "");
  }

  function testSwapExactAmountOut_HappyPath() public {
    uint256 amountAvailable = 1e18;

    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut);

    assertEq(pair.amountInForPeriod(), 0, "amount in for period is zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out for period is zero");
    assertEq(pair.lastAuctionTime(), firstPeriodStartsAt);

    vm.expectEmit(true, true, true, true);
    emit SwappedExactAmountOut(address(this), alice, amountOut, amountOut, amountIn, "");
    assertEq(
      pair.swapExactAmountOut(alice, amountOut, amountOut, ""),
      amountIn,
      "equal at target sale time (with rounding error of -1)"
    );

    assertEq(pair.amountInForPeriod(), amountIn, "amount in was increased");
    assertEq(pair.amountOutForPeriod(), amountOut, "amount out was increased");
    assertEq(pair.lastAuctionTime(), firstPeriodStartsAt + targetFirstSaleTime - 1, "last auction increased to target time (less loss of precision)");

    vm.warp(firstPeriodStartsAt + periodLength);

    assertEq(pair.amountInForPeriod(), 0, "amount in was reset to zero");
    assertEq(pair.amountOutForPeriod(), 0, "amount out was reset to zero");
    assertEq(pair.lastAuctionTime(), firstPeriodStartsAt + periodLength);
  }

  function testSwapExactAmountOut_flashSwap() public {
    uint256 amountAvailable = 1e18;

    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);

    mockLiquidatableBalanceOf(amountAvailable);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut);

    vm.mockCall(alice, abi.encodeCall(IFlashSwapCallback.flashSwapCallback, (address(pair), address(this), amountIn, amountOut, "hello")), abi.encode());
    
    vm.expectEmit(true, true, true, true);
    emit SwappedExactAmountOut(address(this), alice, amountOut, amountOut, amountIn, "hello");
    pair.swapExactAmountOut(alice, amountOut, amountOut, "hello");
  }

  function testSwapExactAmountOut_PurchasePriceIsZero() public {
    vm.warp(firstPeriodStartsAt + periodLength - 1);
    mockLiquidatableBalanceOf(1e18);
    uint amountOut = pair.maxAmountOut();
    vm.expectRevert(abi.encodeWithSelector(PurchasePriceIsZero.selector, amountOut));
    pair.swapExactAmountOut(alice, amountOut, amountOut, "");
  }

  function testSwapExactAmountOut_EmissionRateIsZero() public {
    vm.warp(firstPeriodStartsAt + periodLength * 2);
    mockLiquidatableBalanceOf(0);
    vm.expectRevert(abi.encodeWithSelector(EmissionRateIsZero.selector));
    pair.swapExactAmountOut(alice, 1e18, 1e18, "");
  }

  function testSwapExactAmountOut_insufficient() public {
    uint256 amountAvailable = 1e18;
    vm.warp(firstPeriodStartsAt + targetFirstSaleTime);
    uint amountOut = pair.maxAmountOut();
    uint amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidatableBalanceOf(amountAvailable);
    uint maxAmountIn = amountOut/2; // assume it's almost 1:1 exchange rate
    vm.expectRevert(abi.encodeWithSelector(SwapExceedsMax.selector, maxAmountIn, amountIn));
    pair.swapExactAmountOut(alice, amountOut, maxAmountIn, "");
  }

  function swapAmountOut(uint256 amountOut) public returns (uint256 amountIn) {
    amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut);
    assertEq(amountIn, pair.swapExactAmountOut(alice, amountOut, type(uint256).max, ""));
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
    uint256 _amountOut
  ) internal {
    vm.mockCall(
      _source,
      abi.encodeCall(
        ILiquidationSource.transferTokensOut,
        (
          address(this),
          _user,
          _tokenOut,
          _amountOut
        )
      ),
      abi.encode()
    );
    vm.mockCall(
      _source,
      abi.encodeCall(
        ILiquidationSource.verifyTokensIn,
          (
            address(this),
            _user,
            _tokenIn,
            _amountIn
          )
        ),
        abi.encode()
    );
  }

  function newPair() public returns (LiquidationPair) {
    return new LiquidationPair(
      source,
      tokenIn,
      tokenOut,
      uint32(periodLength),
      uint32(firstPeriodStartsAt),
      targetFirstSaleTime,
      decayConstant,
      initialAmountIn,
      initialAmountOut,
      minimumAuctionAmount
    );
  }
}
