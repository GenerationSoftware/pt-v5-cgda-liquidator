// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "openzeppelin/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { LiquidationPair } from "./LiquidationPair.sol";
import { LiquidationPairFactory } from "./LiquidationPairFactory.sol";

contract LiquidationRouter {
  using SafeERC20 for IERC20;

  /* ============ Events ============ */
  event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);

  /* ============ Variables ============ */
  LiquidationPairFactory internal immutable _liquidationPairFactory;

  /* ============ Constructor ============ */
  constructor(LiquidationPairFactory liquidationPairFactory_) {
    require(address(liquidationPairFactory_) != address(0), "LR/LPF-not-address-zero");
    _liquidationPairFactory = liquidationPairFactory_;

    emit LiquidationRouterCreated(liquidationPairFactory_);
  }

  /* ============ Modifiers ============ */
  modifier onlyTrustedLiquidationPair(LiquidationPair _liquidationPair) {
    require(_liquidationPairFactory.deployedPairs(_liquidationPair), "LR/LP-not-from-LPF");
    _;
  }

  /* ============ External Methods ============ */

  function swapExactAmountIn(
    LiquidationPair _liquidationPair,
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external onlyTrustedLiquidationPair(_liquidationPair) returns (uint256) {
    IERC20(_liquidationPair.tokenIn()).safeTransferFrom(
      msg.sender,
      _liquidationPair.target(),
      _amountIn
    );

    return _liquidationPair.swapExactAmountIn(_receiver, _amountIn, _amountOutMin);
  }

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

    return _liquidationPair.swapExactAmountOut(_receiver, _amountOut, _amountInMax);
  }
}
