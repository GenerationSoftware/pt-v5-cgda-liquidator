// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

/// @title ContinuousGDA
/// @author G9 Software Inc.
/// @notice Implements the Continous Gradual Dutch Auction formula
/// See https://www.paradigm.xyz/2022/04/gda
/// @dev Pricing formula adapted from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {

  /// @notice a helpful constant
  SD59x18 internal constant ONE = SD59x18.wrap(1e18);

  /// @notice Calculate purchase price for a given amount of tokens
  /// @param _amount The amount of tokens to purchase
  /// @param _emissionRate The emission rate of the CGDA
  /// @param _k The initial price of the CGDA
  /// @param _decayConstant The decay constant of the CGDA
  /// @param _timeSinceLastAuctionStart The elapsed time since the last consumed timestamp
  /// @return The purchase price for the given amount of tokens
  function purchasePrice(
    SD59x18 _amount,
    SD59x18 _emissionRate,
    SD59x18 _k,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (SD59x18) {
    if (_amount.unwrap() == 0) {
      return SD59x18.wrap(0);
    }
    SD59x18 topE = _decayConstant.mul(_amount).div(_emissionRate);
    topE = topE.exp().sub(ONE);
    SD59x18 bottomE = _decayConstant.mul(_timeSinceLastAuctionStart);
    bottomE = bottomE.exp();
    SD59x18 result;
    result = _k.div(bottomE).mul(topE.div(_decayConstant));
    return result;
  }

  /// @notice Computes the amount of tokens that can be purchased for a given price
  /// @dev Note that this formula has significant floating point differences to the above. Either one, not both, should be used.
  /// @param _price The price willing to be paid
  /// @param _emissionRate The emission rate of the CGDA
  /// @param _k The initial price of the CGDA
  /// @param _decayConstant The decay constant of the CGDA
  /// @param _timeSinceLastAuctionStart The elapsed time since the last consumed timestamp
  /// @return The number of tokens that can be purchased for the given price
  function purchaseAmount(
    SD59x18 _price,
    SD59x18 _emissionRate,
    SD59x18 _k,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (SD59x18) {
    if (_price.unwrap() == 0) {
      return SD59x18.wrap(0);
    }
    SD59x18 exp = _decayConstant.mul(_timeSinceLastAuctionStart).exp();
    SD59x18 lnParam = ONE.add( exp.div(_k).mul(_decayConstant).mul(_price) );
    SD59x18 numerator = _emissionRate.mul(lnParam.ln());
    SD59x18 amount = numerator.div(_decayConstant);
    return amount;
  }

  /// @notice Computes an initial price for the CGDA such that the purchase amount will cost the price at the given timestamp
  /// @param _emissionRate The emission rate of the CGDA
  /// @param _decayConstant The decay constant of the CGDA
  /// @param _targetFirstSaleTime The timestamp at which the CGDA price for the given amount matches the given price
  /// @param _purchaseAmount The amount of tokens to purchase
  /// @param _price The price to be paid for the amount of tokens
  function computeK(
    SD59x18 _emissionRate,
    SD59x18 _decayConstant,
    SD59x18 _targetFirstSaleTime,
    SD59x18 _purchaseAmount,
    SD59x18 _price
  ) internal pure returns (SD59x18) {
    SD59x18 topE = _decayConstant.mul(_targetFirstSaleTime).exp();
    SD59x18 denominator = (_decayConstant.mul(_purchaseAmount).div(_emissionRate)).exp().sub(ONE);
    SD59x18 result = topE.div(denominator);
    SD59x18 multiplier = _decayConstant.mul(_price);
    return result.mul(multiplier);
  }
}
