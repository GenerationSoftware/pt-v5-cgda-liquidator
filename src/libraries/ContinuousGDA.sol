// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {

  SD59x18 internal constant ONE = SD59x18.wrap(1e18);

  /// See https://www.paradigm.xyz/2022/04/gda
  /// @notice calculate price to purchased _numTokens using exponential continuous GDA formula
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
    // console2.log("_amount", _amount.unwrap());
    // console2.log("_emissionRate", _emissionRate.unwrap());
    // console2.log("_k", _k.unwrap());
    // console2.log("_decayConstant", _decayConstant.unwrap());
    // console2.log("_timeSinceLastAuctionStart", _timeSinceLastAuctionStart.unwrap());

    // console2.log("got here", _amount.unwrap());
    SD59x18 topE = _decayConstant.mul(_amount).div(_emissionRate);
    // console2.log("got here 2", topE.unwrap());
    topE = topE.exp().sub(ONE);
    // console2.log("got here 3", topE.unwrap());
    SD59x18 bottomE = _decayConstant.mul(_timeSinceLastAuctionStart);
    // console2.log("got here 4", bottomE.unwrap());
    bottomE = bottomE.exp();
    // console2.log("got here 5", bottomE.unwrap());
    SD59x18 result;
    // result = _k.mul(topE).div(_emissionRate.mul(bottomE));
    if (_emissionRate.unwrap() > 1e18) {
      // console2.log("emission > 1");
      result = _k.div(_emissionRate).mul(topE).div(bottomE);
    } else {
      result = _k.mul(topE.div(_emissionRate.mul(bottomE)));
    }
    // console2.log("result: ", result.unwrap());
    return result;
  }

  /// See https://www.paradigm.xyz/2022/04/gda
  /// @notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchaseAmount(
    SD59x18 _price,
    SD59x18 _emissionRate,
    SD59x18 _k,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (SD59x18) {
    // console2.log("purchaseAmount _price", _price.unwrap());
    // console2.log("purchaseAmount _emissionRate", _emissionRate.unwrap());
    // console2.log("purchaseAmount _k", _k.unwrap());
    // console2.log("purchaseAmount _decayConstant", _decayConstant.unwrap());
    // console2.log("purchaseAmount _timeSinceLastAuctionStart", _timeSinceLastAuctionStart.unwrap());

    if (_price.unwrap() == 0) {
      return SD59x18.wrap(0);
    }
    /**
      p=\frac{k}{r}\cdot\frac{\left(e^{\frac{ql}{r}}-1\right)}{e^{lt}}

      q = r * ln( (k+p*r*e^(l*t))/k ) / l

     */
    // console2.log("purchaseAmount 1");
    SD59x18 exp = _decayConstant.mul(_timeSinceLastAuctionStart).exp();
    // console2.log("purchaseAmount 2", exp.unwrap());
    SD59x18 lnParam = _k.add(_price.mul(_emissionRate).mul(exp)).div(_k);
    // console2.log("purchaseAmount 3", lnParam.unwrap());
    SD59x18 numerator = _emissionRate.mul(lnParam.ln());
    // console2.log("purchaseAmount 4", numerator.unwrap());
    SD59x18 amount = numerator.div(_decayConstant);
    // console2.log("purchaseAmount 5", amount.unwrap());
    return amount;
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
    // console2.log("multiplier: ", multiplier.unwrap());
    SD59x18 denominator = (_decayConstant.mul(_purchaseAmount).div(_emissionRate)).exp().sub(ONE);
    // console2.log("denominator: ", unwrap(denominator));
    SD59x18 result = eValue.div(denominator);
    // console2.log("result: ", result.unwrap());
    return result.mul(multiplier);
  }
}
