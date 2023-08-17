// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { SD59x18, convert, wrap, unwrap } from "prb-math/SD59x18.sol";

import { LiquidationPair, ILiquidationSource } from "../../src/LiquidationPair.sol";

contract LiquidationPairFuzzTest is Test {

    LiquidationPair pair;

    ILiquidationSource source;
    address tokenIn;
    address tokenOut;

    uint32 periodLength = 1 days;
    uint32 periodOffset = 10 days;
    uint32 targetFirstSaleTime = 12 hours;
    SD59x18 decayConstant = wrap(0.0012e18);

    uint112 initialAmountIn = 1e18;
    uint112 initialAmountOut = 1e18;
    uint256 minimumAuctionAmount = 2e18;

    function setUp() public {
        vm.warp(periodOffset);
        source = ILiquidationSource(makeAddr("ILiquidationSource"));
        // always have 1000 available
        tokenIn = makeAddr("tokenIn");
        tokenOut = makeAddr("tokenOut");
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(1000e18));
        pair = new LiquidationPair(
            source,
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
    }

    function testEstimateAmountOut(uint96 liquidity, uint32 waitingTime) public {
        uint amountOut = pair.maxAmountOut();
        uint amountIn = pair.computeExactAmountIn(amountOut);
        assertLe(pair.estimateAmountOut(amountIn), amountOut);
    }

    function testSwapMaxAmountOut(uint96 liquidity, uint32 waitingTime) public {
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(liquidity));

        vm.warp(uint(periodOffset) + waitingTime);
        uint amountOut = pair.maxAmountOut();
        uint amountIn = pair.computeExactAmountIn(amountOut);
        if (amountIn > 0) {
            vm.mockCall(address(source), abi.encodeWithSelector(source.liquidate.selector, address(this), tokenIn, amountIn, tokenOut, amountOut), abi.encode(true));
            pair.swapExactAmountOut(address(this), amountOut, amountIn);
        }
    }
}
