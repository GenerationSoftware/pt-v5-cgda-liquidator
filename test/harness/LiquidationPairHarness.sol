// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";
import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { LiquidationPair } from "../../src/LiquidationPair.sol";

contract LiquidationPairHarness is LiquidationPair {

  /* ============ Constructor ============ */

  /// @notice Construct a new pair
  /// @param _source The liquidation source to use for the pair
  /// @param _tokenIn The token that is used to pay for auctions
  /// @param _tokenOut The token that is being auctioned
  /// @param _periodLength The duration of each auction.
  /// @param _periodOffset Sets the beginning timestamp for the first period
  /// @param _targetFirstSaleTime The time within an auction at which the price of available tokens matches the previous non-zero exchange rate
  /// @param _decayConstant The rate at which the price decays
  /// @param _initialAmountIn The initial amount of tokens in for the first auction (used for the initial exchange rate)
  /// @param _initialAmountOut The initial amount of tokens out for the first auction (used for the initial exchange rate)
  /// @param _minimumAuctionAmount Require a minimum number of tokens before an auction is triggered.
  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _periodOffset,
    uint32 _targetFirstSaleTime,
    SD59x18 _decayConstant,
    uint104 _initialAmountIn,
    uint104 _initialAmountOut,
    uint256 _minimumAuctionAmount
  ) LiquidationPair(
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
  ) { }

  function updateAuction(uint256 __period) external {
    _updateAuction(__period);
  }

}