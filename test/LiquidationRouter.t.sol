// // SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";

import {
    UnknownLiquidationPair,
    UndefinedLiquidationPairFactory,
    SwapExpired,
    LiquidationRouter
} from "../src/LiquidationRouter.sol";

contract LiquidationRouterTest is Test {
    using SafeERC20 for IERC20;

    IERC20 tokenIn;
    IERC20 tokenOut;
    address target;
    LiquidationPairFactory factory;
    LiquidationPair liquidationPair;

    LiquidationRouter router;

    event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);
    event SwappedExactAmountOut(
        LiquidationPair indexed liquidationPair,
        address indexed sender,
        address indexed receiver,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 amountIn,
        uint256 deadline
    );

    function setUp() public {
        factory = LiquidationPairFactory(makeAddr("LiquidationPairFactory"));
        vm.etch(address(factory), "LiquidationPairFactory");

        tokenIn = IERC20(makeAddr("tokenIn"));
        vm.etch(address(tokenIn), "tokenIn");
        tokenOut = IERC20(makeAddr("tokenOut"));
        vm.etch(address(tokenOut), "tokenOut");

        liquidationPair = LiquidationPair(makeAddr("LiquidationPair"));
        vm.etch(address(liquidationPair), "LiquidationPair");

        vm.mockCall(address(liquidationPair), abi.encodeWithSelector(liquidationPair.tokenIn.selector), abi.encode(tokenIn));
        vm.mockCall(address(liquidationPair), abi.encodeWithSelector(liquidationPair.tokenOut.selector), abi.encode(tokenOut));
        vm.mockCall(address(liquidationPair), abi.encodeWithSelector(liquidationPair.target.selector), abi.encode(target));
        vm.mockCall(address(factory), abi.encodeWithSelector(factory.deployedPairs.selector, liquidationPair), abi.encode(true));

        router = new LiquidationRouter(factory);
    }

    function testConstructor_badFactory() public {
        vm.expectRevert(abi.encodeWithSelector(UndefinedLiquidationPairFactory.selector));
        new LiquidationRouter(LiquidationPairFactory(address(0)));
    }

    function testSwapExactAmountOut_happyPath() public {
        vm.warp(10 days);
        address receiver = address(this);
        uint256 amountOut = 1e18;
        uint256 amountIn = 1.5e18;
        uint256 amountInMax = 2e18;
        uint256 deadline = block.timestamp;

        vm.mockCall(
            address(liquidationPair),
            abi.encodeWithSelector(liquidationPair.computeExactAmountIn.selector, amountOut),
            abi.encode(amountIn)
        );
        vm.mockCall(
            address(tokenIn),
            abi.encodeWithSelector(tokenIn.transferFrom.selector, address(this), target, amountIn),
            abi.encode(true)
        );
        vm.mockCall(
            address(tokenOut),
            abi.encodeWithSelector(tokenOut.transfer.selector, address(this), amountOut),
            abi.encode(true)
        );
        vm.mockCall(
            address(liquidationPair),
            abi.encodeWithSelector(liquidationPair.swapExactAmountOut.selector, address(router), amountOut, amountInMax),
            abi.encode(amountIn)
        );

        vm.expectEmit(true, true, false, true);
        emit SwappedExactAmountOut(
            liquidationPair,
            address(this),
            receiver,
            amountOut,
            amountInMax,
            amountIn,
            deadline
        );

        router.swapExactAmountOut(
            liquidationPair,
            address(this),
            amountOut,
            amountInMax,
            deadline
        );
    }

    function testSwapExactAmountOut_SwapExpired() public {
        vm.warp(10 days);
        vm.expectRevert(abi.encodeWithSelector(SwapExpired.selector, 10 days - 1));
        router.swapExactAmountOut(liquidationPair, makeAddr("alice"), 1e18, 1e18, 10 days - 1);
    }

    function testSwapExactAmountOut_illegalRouter() public {
        vm.mockCall(address(factory), abi.encodeWithSelector(factory.deployedPairs.selector, liquidationPair), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(UnknownLiquidationPair.selector, liquidationPair));
        router.swapExactAmountOut(
            liquidationPair,
            address(this),
            1e18,
            2e18,
            block.timestamp
        );
    }

}
