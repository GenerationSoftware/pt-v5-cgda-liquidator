// // SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
import { LiquidationPair } from "../src/LiquidationPair.sol";

import { UnknownLiquidationPair, UndefinedLiquidationPairFactory, SwapExpired, InvalidSender, LiquidationRouter } from "../src/LiquidationRouter.sol";

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

    vm.mockCall(
      address(liquidationPair),
      abi.encodeCall(liquidationPair.tokenIn, ()),
      abi.encode(tokenIn)
    );
    vm.mockCall(
      address(liquidationPair),
      abi.encodeCall(liquidationPair.tokenOut, ()),
      abi.encode(tokenOut)
    );
    vm.mockCall(
      address(liquidationPair),
      abi.encodeCall(liquidationPair.target, ()),
      abi.encode(target)
    );
    vm.mockCall(
      address(factory),
      abi.encodeCall(factory.deployedPairs, liquidationPair),
      abi.encode(true)
    );

    router = new LiquidationRouter(factory);
  }

  function testConstructor_badFactory() public {
    vm.expectRevert(abi.encodeWithSelector(UndefinedLiquidationPairFactory.selector));
    new LiquidationRouter(LiquidationPairFactory(address(0)));
  }

  function testSwapExactAmountOut_happyPath() public {
    vm.warp(10 days);
    address receiver = makeAddr("bob");
    uint256 amountOut = 1e18;
    uint256 amountIn = 1.5e18;
    uint256 amountInMax = 2e18;
    uint256 deadline = block.timestamp;

    vm.mockCall(
      address(liquidationPair),
      abi.encodeCall(liquidationPair.computeExactAmountIn, (amountOut)),
      abi.encode(amountIn)
    );
    vm.mockCall(
      address(tokenIn),
      abi.encodeCall(tokenIn.transferFrom, (address(this), target, amountIn)),
      abi.encode(true)
    );
    vm.mockCall(
      address(tokenOut),
      abi.encodeCall(tokenOut.transfer, (address(this), amountOut)),
      abi.encode(true)
    );
    vm.mockCall(
      address(liquidationPair),
      abi.encodeCall(
        liquidationPair.swapExactAmountOut,
        (address(router), amountOut, amountInMax, abi.encode(address(this)))
      ),
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

    router.swapExactAmountOut(liquidationPair, receiver, amountOut, amountInMax, deadline);
  }

  function testFlashSwapCallback_InvalidSender() public {
    vm.expectRevert(abi.encodeWithSelector(InvalidSender.selector, address(this)));
    vm.startPrank(address(liquidationPair));
    router.flashSwapCallback(address(this), 0, 0, abi.encode(address(this)));
    vm.stopPrank();
  }

  function testFlashSwapCallback_UnknownLiquidationPair() public {
    vm.mockCall(
      address(factory),
      abi.encodeCall(factory.deployedPairs, LiquidationPair(address(this))),
      abi.encode(false)
    );
    vm.expectRevert(abi.encodeWithSelector(UnknownLiquidationPair.selector, address(this)));
    router.flashSwapCallback(address(this), 0, 0, abi.encode(address(this)));
  }

  function testFlashSwapCallback_success() public {
    vm.mockCall(
      address(tokenIn),
      abi.encodeCall(tokenIn.transferFrom, (address(this), target, 11e18)),
      abi.encode(true)
    );
    vm.startPrank(address(liquidationPair));
    router.flashSwapCallback(address(router), 11e18, 0, abi.encode(address(this)));
    vm.stopPrank();
  }

  function testSwapExactAmountOut_SwapExpired() public {
    vm.warp(10 days);
    vm.expectRevert(abi.encodeWithSelector(SwapExpired.selector, 10 days - 1));
    router.swapExactAmountOut(liquidationPair, makeAddr("alice"), 1e18, 1e18, 10 days - 1);
  }

  function testSwapExactAmountOut_UnknownLiquidationPair() public {
    vm.mockCall(
      address(factory),
      abi.encodeCall(factory.deployedPairs, liquidationPair),
      abi.encode(false)
    );
    vm.expectRevert(abi.encodeWithSelector(UnknownLiquidationPair.selector, liquidationPair));
    router.swapExactAmountOut(liquidationPair, address(this), 1e18, 2e18, block.timestamp);
  }
}
