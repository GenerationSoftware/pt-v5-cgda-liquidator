// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";
import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {
  ///@notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) public pure returns (uint256) {
    // console2.log("_numTokens", _numTokens);
    // console2.log("_emissionRate", unwrap(_emissionRate));
    // console2.log("_initialPrice", unwrap(_initialPrice));
    // console2.log("_decayConstant", unwrap(_decayConstant));
    // console2.log("_timeSinceLastAuctionStart", unwrap(_timeSinceLastAuctionStart));

    SD59x18 quantity = convert(int256(_numTokens));
    console2.log("quantity", unwrap(quantity));

    SD59x18 num1 = _initialPrice.div(_decayConstant);
    console2.log("num1", unwrap(num1));

    SD59x18 num2 = _decayConstant.mul(quantity).div(_emissionRate).exp().sub(convert(1));
    console2.log("num2", unwrap(num2));

    console2.log("den-ish", unwrap(_decayConstant.mul(_timeSinceLastAuctionStart)));
    SD59x18 den = _decayConstant.mul(_timeSinceLastAuctionStart).exp();
    console2.log("den", unwrap(den));

    console2.log("total", uint256(convert(num1.mul(num2.div(den)))));
    return uint256(convert(num1.mul(num2.div(den))));
  }
}
