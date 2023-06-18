// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "./libraries/LiquidatorLib.sol";
import "./libraries/FixedMathLib.sol";
import "./interfaces/ILiquidationSource.sol";
import { Math } from "openzeppelin/utils/math/Math.sol";

contract LiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;
  
  /* ============ Events ============ */

  event Swapped(address indexed account, uint256 amountIn, uint256 amountOut);

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
  }

  /* ============ External Function ============ */

  function maxAmountIn() external returns (uint256) {
  }

  function maxAmountOut() external returns (uint256) {
  }

  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
  }

  function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
  }

  function swapExactAmountIn(
    address _account,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external returns (uint256) {

  }

  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {

  }

  /**
   * @notice Get the address that will receive `tokenIn`.
   * @return address Address of the target
   */
  function target() external returns (address) {
    return source.targetOf(tokenIn);
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }
}
