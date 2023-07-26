// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPair } from "./LiquidationPair.sol";
import { LiquidationPairFactory } from "./LiquidationPairFactory.sol";

error UndefinedLiquidationPairFactory();
error UnknownLiquidationPair(LiquidationPair liquidationPair);

contract LiquidationRouter {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */
  event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);

  event SwappedExactAmountOut(
    LiquidationPair indexed liquidationPair,
    address indexed receiver,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 amountIn
  );

  /* ============ Variables ============ */
  LiquidationPairFactory internal immutable _liquidationPairFactory;

  /* ============ Constructor ============ */
  constructor(LiquidationPairFactory liquidationPairFactory_) {
    if(address(liquidationPairFactory_) == address(0)) {
      revert UndefinedLiquidationPairFactory();
    }
    _liquidationPairFactory = liquidationPairFactory_;

    emit LiquidationRouterCreated(liquidationPairFactory_);
  }

  /* ============ Modifiers ============ */
  modifier onlyTrustedLiquidationPair(LiquidationPair _liquidationPair) {
    if (!_liquidationPairFactory.deployedPairs(_liquidationPair)) {
      revert UnknownLiquidationPair(_liquidationPair);
    }
    _;
  }

  /* ============ External Methods ============ */

  function swapExactAmountOut(
    LiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external onlyTrustedLiquidationPair(_liquidationPair) returns (uint256) {
    IERC20(_liquidationPair.tokenIn()).safeTransferFrom(
      msg.sender,
      _liquidationPair.target(),
      _liquidationPair.computeExactAmountIn(_amountOut)
    );

    uint256 amountIn = _liquidationPair.swapExactAmountOut(_receiver, _amountOut, _amountInMax);

    emit SwappedExactAmountOut(_liquidationPair, _receiver, _amountOut, _amountInMax, amountIn);

    return amountIn;
  }
}
