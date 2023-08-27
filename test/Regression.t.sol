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

contract RegressionTest is Test {
  
  /* ============ Variables ============ */

  address public alice;

  ILiquidationSource source;
  address public target;
  address public tokenIn;
  address public tokenOut;
  SD59x18 initialTokenOutPrice;
  SD59x18 decayConstant = wrap(0.00102777777777e18);
  uint periodLength = 4 hours;
  uint periodOffset = 1692835200;
  uint32 targetFirstSaleTime = 1 hours;
  uint104 initialAmountIn =  200e18;
  uint104 initialAmountOut = 10e18;
  uint256 minimumAuctionAmount = 1e18;

  LiquidationPair pair;

// 117x
// 10x
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
    mockLiquidatableBalanceOf(28752953447121192965);
    pair = newPair();
  }

  function testSwaps() public {
    uint amountOut;

    uint nextEnd = pair.getPeriodEnd();

    console2.log("emissionRate", pair.emissionRate().unwrap());
    console2.log("initialPrice", pair.initialPrice().unwrap());

    console2.log("nextEnd", nextEnd);

    for (uint i = nextEnd; i < nextEnd + periodLength; i += periodLength / 32) {
        vm.warp(i);
        uint max = pair.maxAmountOut();
        amountOut = max; //max > 1e18 ? 1e18 : max;
        uint amountIn = pair.computeExactAmountIn(amountOut);
        console2.log("@ %s price for %e is %e", (i-nextEnd), amountOut, amountIn);
        if (amountOut > 0) {
            console2.log("\t ratio: %e", (amountIn/amountOut));
        }
    }
  }

//   7188238361780298241
//   284164091232280019274

  function swapAmountOut(uint256 amountOut) public returns (uint256 amountIn) {
    amountIn = pair.computeExactAmountIn(amountOut);
    mockLiquidate(address(source), alice, tokenIn, amountIn, tokenOut, amountOut, "hello", true);
    assertEq(amountIn, pair.swapExactAmountOut(alice, amountOut, type(uint256).max, "hello"));
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
    bytes memory _flashSwapData,
    bool _result
  ) internal {
    vm.mockCall(
      _source,
      abi.encodeWithSelector(
        ILiquidationSource.liquidate.selector,
        address(this),
        _user,
        _tokenIn,
        _amountIn,
        _tokenOut,
        _amountOut,
        _flashSwapData
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
