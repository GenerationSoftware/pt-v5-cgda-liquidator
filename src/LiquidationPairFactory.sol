// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

import "./LiquidationPair.sol";

contract LiquidationPairFactory {
  /* ============ Events ============ */
  event PairCreated(
    ILiquidationSource source,
    address tokenIn,
    address tokenOut,
    uint32 periodLength,
    uint32 periodOffset,
    uint32 targetFirstSaleTime,
    SD59x18 decayConstant,
    uint112 initialAmountIn,
    uint112 initialAmountOut,
    uint256 minimumAuctionAmount
  );

  /* ============ Variables ============ */
  LiquidationPair[] public allPairs;

  /* ============ Mappings ============ */

  /**
   * @notice Mapping to verify if a LiquidationPair has been deployed via this factory.
   * @dev LiquidationPair address => boolean
   */
  mapping(LiquidationPair => bool) public deployedPairs;

  /* ============ External Functions ============ */
  function createPair(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _periodOffset,
    uint32 _targetFirstSaleTime,
    SD59x18 _decayConstant,
    uint112 _initialAmountIn,
    uint112 _initialAmountOut,
    uint112 _minimumAuctionAmount
  ) external returns (LiquidationPair) {
    LiquidationPair _liquidationPair = new LiquidationPair(
      _source,
      _tokenIn,
      _tokenOut,
      _periodLength,
      _periodOffset,
      _targetFirstSaleTime,
      _decayConstant,
      _initialAmountIn,
      _initialAmountOut,
      _minimumAuctionAmount
    );

    allPairs.push(_liquidationPair);
    deployedPairs[_liquidationPair] = true;

    emit PairCreated(
      _source,
      _tokenIn,
      _tokenOut,
      _periodLength,
      _periodOffset,
      _targetFirstSaleTime,
      _decayConstant,
      _initialAmountIn,
      _initialAmountOut,
      _minimumAuctionAmount
    );

    return _liquidationPair;
  }

  /**
   * @notice Total number of LiquidationPair deployed by this factory.
   * @return Number of LiquidationPair deployed by this factory.
   */
  function totalPairs() external view returns (uint256) {
    return allPairs.length;
  }
}
