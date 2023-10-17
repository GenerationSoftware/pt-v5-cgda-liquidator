// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { ILiquidationSource, LiquidationPair, SD59x18 } from "./LiquidationPair.sol";

/// @title LiquidationPairFactory
/// @author G9 Software Inc.
/// @notice Factory contract for deploying LiquidationPair contracts.
contract LiquidationPairFactory {
  /* ============ Events ============ */

  /// @notice Emitted when a new LiquidationPair is created
  /// @param pair The address of the new pair
  /// @param tokenIn The input token for the pair
  /// @param tokenOut The output token for the pair
  /// @param source The liquidation source that the pair is using
  /// @param periodLength The duration of auctions
  /// @param firstPeriodStartsAt The start time offset of auctions
  /// @param targetFirstSaleTime The target time for the first auction
  /// @param decayConstant The decay constant that the pair is using
  /// @param initialAmountIn The initial amount of input tokens (used to compute initial exchange rate)
  /// @param initialAmountOut The initial amount of output tokens (used to compute initial exchange rate)
  /// @param minimumAuctionAmount The minimum auction size in output tokens
  event PairCreated(
    LiquidationPair indexed pair,
    address indexed tokenIn,
    address indexed tokenOut,
    ILiquidationSource source,
    uint32 periodLength,
    uint32 firstPeriodStartsAt,
    uint32 targetFirstSaleTime,
    SD59x18 decayConstant,
    uint104 initialAmountIn,
    uint104 initialAmountOut,
    uint256 minimumAuctionAmount
  );

  /* ============ Variables ============ */

  /// @notice Tracks an array of all pairs created by this factory
  LiquidationPair[] public allPairs;

  /* ============ Mappings ============ */

  /**
   * @notice Mapping to verify if a LiquidationPair has been deployed via this factory.
   * @dev LiquidationPair address => boolean
   */
  mapping(LiquidationPair => bool) public deployedPairs;

  /// @notice Creates a new LiquidationPair and registers it within the factory
  /// @param _source The liquidation source that the pair will use
  /// @param _tokenIn The input token for the pair
  /// @param _tokenOut The output token for the pair
  /// @param _periodLength The duration of auctions
  /// @param _firstPeriodStartsAt The start time offset of auctions
  /// @param _targetFirstSaleTime The target time for the first auction
  /// @param _decayConstant The decay constant that the pair will use. This determines how rapidly the price changes.
  /// @param _initialAmountIn The initial amount of input tokens (used to compute initial exchange rate)
  /// @param _initialAmountOut The initial amount of output tokens (used to compute initial exchange rate)
  /// @param _minimumAuctionAmount The minimum auction size in output tokens
  /// @return The address of the new pair
  function createPair(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _firstPeriodStartsAt,
    uint32 _targetFirstSaleTime,
    SD59x18 _decayConstant,
    uint104 _initialAmountIn,
    uint104 _initialAmountOut,
    uint256 _minimumAuctionAmount
  ) external returns (LiquidationPair) {
    LiquidationPair _liquidationPair = new LiquidationPair(
      _source,
      _tokenIn,
      _tokenOut,
      _periodLength,
      _firstPeriodStartsAt,
      _targetFirstSaleTime,
      _decayConstant,
      _initialAmountIn,
      _initialAmountOut,
      _minimumAuctionAmount
    );

    allPairs.push(_liquidationPair);
    deployedPairs[_liquidationPair] = true;

    emit PairCreated(
      _liquidationPair,
      _tokenIn,
      _tokenOut,
      _source,
      _periodLength,
      _firstPeriodStartsAt,
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
