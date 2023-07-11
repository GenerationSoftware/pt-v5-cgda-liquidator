// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

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
  ) internal pure returns (uint256) {
    // console2.log("_numTokens: ", _numTokens);
    // console2.log("_emissionRate: ", unwrap(_emissionRate));
    // console2.log("_k: ", unwrap(_k));
    // console2.log("_decayConstant: ", unwrap(_decayConstant));
    // console2.log("_timeSinceLastAuctionStart: ", unwrap(_timeSinceLastAuctionStart));

    SD59x18 quantity = convert(int256(_numTokens));

    SD59x18 topE = _decayConstant.mul(quantity).div(_emissionRate);
    topE = topE.exp().sub(convert(1));

    SD59x18 bottomE = _decayConstant.mul(_timeSinceLastAuctionStart);
    bottomE = bottomE.exp();
    bottomE = _emissionRate.mul(bottomE);

    SD59x18 result = _k.mul(topE).div(bottomE);

    return uint256(convert(result.ceil()));
  }

  function computeK(
    SD59x18 _emissionRate,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart,
    SD59x18 _purchaseAmount,
    SD59x18 _price
  ) internal pure returns (SD59x18) {
    // console2.log("_decayConstant: ", unwrap(_decayConstant));
    // console2.log("_timeSinceLastAuctionStart: ", unwrap(_timeSinceLastAuctionStart));
    SD59x18 exponent = _decayConstant.mul(_timeSinceLastAuctionStart);
    // console2.log("exponent: ", unwrap(exponent));
    SD59x18 eValue = exponent.exp();
    // console2.log("eValue: ", unwrap(eValue));
    SD59x18 numerator = _emissionRate.mul(_price).mul(eValue);
    // console2.log("numerator: ", unwrap(numerator));
    SD59x18 denominator = (_decayConstant.mul(_purchaseAmount).div(_emissionRate)).exp().sub(convert(1));
    // console2.log("denominator: ", unwrap(denominator));
    SD59x18 result = numerator.div(denominator);
    // console2.log("result: ", unwrap(result));
    return result;
  }
}
