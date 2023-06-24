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
    SD59x18 initialPrice,
    SD59x18 decayConstant
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
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _smoothing
  ) external returns (LiquidationPair) {
    LiquidationPair _liquidationPair = new LiquidationPair(
      _source,
      _tokenIn,
      _tokenOut,
      _periodLength,
      _periodOffset,
      _initialPrice,
      _decayConstant,
      _smoothing
    );

    allPairs.push(_liquidationPair);
    deployedPairs[_liquidationPair] = true;

    emit PairCreated(
      _source,
      _tokenIn,
      _tokenOut,
      _periodLength,
      _periodOffset,
      _initialPrice,
      _decayConstant
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
