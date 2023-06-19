// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { LiquidationPair, PrizePool, SD59x18, sd } from "src/LiquidationPair.sol";
import { ILiquidationSource } from "src/interfaces/ILiquidationSource.sol";

contract LiquidationPairTest is Test {
    /* ============ Variables ============ */

    PrizePool prizePool;
    ILiquidationSource source;
    address public target;
    address public tokenIn;
    address public tokenOut;
    SD59x18 initialTokenOutPrice;
    SD59x18 decayConstant;

    uint drawPeriodSeconds = 1 days;

    LiquidationPair pair;

    /* ============ Events ============ */

    event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

    /* ============ Set up ============ */

    function setUp() public {
        vm.warp(1 days); // for safe measure
        target = makeAddr("target"); // nicely labeled address in forge console
        tokenIn = makeAddr("tokenIn");
        tokenOut = makeAddr("tokenOut");
        prizePool = PrizePool(makeAddr("prizePool"));
        vm.etch(address(prizePool), "prizePool");
        source = ILiquidationSource(makeAddr("source"));
        vm.etch(address(source), "liquidationSource");
        initialTokenOutPrice = sd(1e18);
        decayConstant = sd(1.01e18);

        pair = new LiquidationPair(
            prizePool,
            source,
            tokenIn,
            tokenOut,
            initialTokenOutPrice,
            decayConstant
        );
    }

    function testMaxAmountOut() public {
        mockInitialPrizePool();
        vm.mockCall(address(source), abi.encodeWithSelector(source.availableBalanceOf.selector, tokenOut), abi.encode(1e18));
        assertEq(pair.maxAmountOut(), 0);
    }

    // function testComputeExactAmountIn() public {
    //     mockInitialPrizePool();
    //     vm.mockCall(address(source), abi.encodeWithSelector(source.availableBalanceOf.selector, tokenOut), abi.encode(1e18));
    //     assertEq(pair.computeExactAmountIn(1e18), 1e18);
    // }

    function mockInitialPrizePool() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.nextDrawStartsAt.selector), abi.encode(block.timestamp));
    }

}
