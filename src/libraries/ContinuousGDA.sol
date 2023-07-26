// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {

  /// See https://www.paradigm.xyz/2022/04/gda
  /// @notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _k,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (SD59x18) {
    // console2.log("_numTokens: ", _numTokens);
    // console2.log("_emissionRate: ", unwrap(_emissionRate));
    // console2.log("_k: ", unwrap(_k));
    // console2.log("_decayConstant: ", unwrap(_decayConstant));
    // console2.log("_timeSinceLastAuctionStart: ", unwrap(_timeSinceLastAuctionStart));

    SD59x18 quantity = convert(int256(_numTokens));

    // console2.log("purchasePrice 1");

    SD59x18 topE = _decayConstant.mul(quantity).div(_emissionRate);
    // console2.log("purchasePrice 2", topE.unwrap()); //129598444800000000000
    topE = topE.exp().sub(convert(1));
    // console2.log("purchasePrice 3", topE.unwrap());
    SD59x18 bottomE = _decayConstant.mul(_timeSinceLastAuctionStart);
    // console2.log("purchasePrice 4", bottomE.unwrap());
    bottomE = bottomE.exp();

    // console2.log("purchasePrice 5", bottomE.unwrap());

    SD59x18 result;
    if (_emissionRate.unwrap() > 1e18) {
      result = _k.div(_emissionRate).mul(topE.div(bottomE));
    } else {
      result = _k.mul(topE.div(_emissionRate.mul(bottomE)));
    }

    return result;
  }

  function computeK(
    SD59x18 _emissionRate,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart,
    SD59x18 _purchaseAmount,
    SD59x18 _price
  ) internal pure returns (SD59x18) {
    // console2.log("_emissionRate: ", unwrap(_emissionRate));
    // console2.log("_decayConstant: ", unwrap(_decayConstant));
    // console2.log("_timeSinceLastAuctionStart: ", unwrap(_timeSinceLastAuctionStart));
    // console2.log("_purchaseAmount: ", unwrap(_purchaseAmount));
    // console2.log("_price: ", unwrap(_price));
    SD59x18 exponent = _decayConstant.mul(_timeSinceLastAuctionStart);
    // console2.log("exponent: ", unwrap(exponent));
    SD59x18 eValue = exponent.exp();
    // console2.log("eValue: ", unwrap(eValue));
    SD59x18 multiplier = _emissionRate.mul(_price);
    // console2.log("numerator: ", unwrap(eValue));
    SD59x18 denominator = (_decayConstant.mul(_purchaseAmount).div(_emissionRate)).exp().sub(convert(1));
    // console2.log("denominator: ", unwrap(denominator));
    SD59x18 result = eValue.div(denominator);
    // console2.log("result: ", unwrap(result.mul(multiplier)));
    return result.mul(multiplier);
  }
}
