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
    uint32 targetFirstSaleTime = periodLength / 2;
    SD59x18 decayConstant = wrap(0.001e18);
    uint104 initialAmountIn = 1e18;
    uint104 initialAmountOut = 1e18;
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

    function testEstimateAmountOut(uint104 liquidity, uint32 waitingTime) public {
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(liquidity));
        vm.warp(waitingTime);
        uint amountOut = pair.maxAmountOut();
        if (amountOut > 0) {
            uint amountIn = pair.computeExactAmountIn(amountOut);
            uint estimatedAmountOut = pair.estimateAmountOut(amountIn);
            assertApproxEqAbs(estimatedAmountOut, amountOut, 1e9);
        }
    }

    function testEstimateAmountOut_counterExample1() public {
        uint104 liquidity = 1356230770579;
        uint32 waitingTime = 883162;
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(liquidity));
        vm.warp(waitingTime);
        uint amountOut = pair.maxAmountOut();
        uint amountIn = pair.computeExactAmountIn(amountOut);
        uint estimatedAmountOut = pair.estimateAmountOut(amountIn);
        assertApproxEqAbs(estimatedAmountOut, amountOut, 1e9);
    }

    function testEstimateAmountOut_counterExample2() public {
        uint104 liquidity = 6524647850586847196313838081;
        uint32 waitingTime = 1862006487;
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(liquidity));
        vm.warp(waitingTime);
        uint amountOut = pair.maxAmountOut();
        uint amountIn = pair.computeExactAmountIn(amountOut);
        uint estimatedAmountOut = pair.estimateAmountOut(amountIn);
        assertApproxEqAbs(estimatedAmountOut, amountOut, 1e9);
    }

    function testSwapMaxAmountOut(uint104 liquidity, uint32 waitingTime) public {
        vm.mockCall(address(source), abi.encodeWithSelector(source.liquidatableBalanceOf.selector, tokenOut), abi.encode(liquidity));

        vm.warp(uint(periodOffset) + waitingTime);
        uint amountOut = pair.maxAmountOut();
        if (amountOut > 0) {
            uint amountIn = pair.computeExactAmountIn(amountOut);
            if (amountIn > 0) {
                vm.mockCall(address(source), abi.encodeCall(source.transferTokensOut, (address(this), address(this), tokenOut, amountOut)), abi.encode("somedata"));
                vm.mockCall(address(source), abi.encodeCall(source.verifyTokensIn, (tokenIn, amountIn, "somedata")), abi.encode());
                pair.swapExactAmountOut(address(this), amountOut, amountIn, "");
            }
        }
    }
}
