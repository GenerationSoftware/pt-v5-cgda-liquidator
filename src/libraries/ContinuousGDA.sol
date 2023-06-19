// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {
    ///@notice calculate purchase price using exponential continuous GDA formula
    function purchasePrice(uint256 _numTokens, SD59x18 _emissionRate, SD59x18 _initialPrice, SD59x18 _decayConstant, SD59x18 _timeSinceLastAuctionStart) public pure returns (uint256) {
        SD59x18 quantity = toSD59x18(int256(_numTokens));
        SD59x18 num1 = _initialPrice.div(_decayConstant);
        SD59x18 num2 = _decayConstant.mul(quantity).div(_emissionRate).exp().sub(toSD59x18(1));
        SD59x18 den = _decayConstant.mul(_timeSinceLastAuctionStart).exp();
        return uint256(fromSD59x18(num1.mul(num2).div(den)));
    }
}
