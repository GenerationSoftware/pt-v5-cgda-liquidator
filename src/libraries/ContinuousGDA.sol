// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";
import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

int256 constant MAX_EXP = 133_084258667509499441;

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {

  ///@notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (uint256) {
    SD59x18 quantity = convert(int256(_numTokens));
    SD59x18 num1 = _initialPrice.div(_decayConstant);
    SD59x18 num2 = _decayConstant.mul(quantity).div(_emissionRate);

    // console2.log("MAX_EXP", MAX_EXP);
    // console2.log("num2", num2.unwrap());

    if (num2.unwrap() > MAX_EXP) {
      // console2.log("GOT HERE");
      return type(uint256).max;
    }

    num2 = num2.exp().sub(convert(1));
    SD59x18 den = _decayConstant.mul(_timeSinceLastAuctionStart);
    
    if (den.unwrap() > MAX_EXP) {
      // console2.log("ALSO GOT HERE");
      return type(uint256).max;
    }

    den = den.exp();
    return uint256(convert(num1.mul(num2.div(den))));
  }
}
