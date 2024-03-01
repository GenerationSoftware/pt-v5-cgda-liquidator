// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { ContinuousGDA, SD59x18 } from "../../../src/libraries/ContinuousGDA.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
contract ContinuousGDAWrapper {
  ///@notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    SD59x18 _amount,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) external pure returns (SD59x18) {
    SD59x18 result = ContinuousGDA.purchasePrice(
      _amount,
      _emissionRate,
      _initialPrice,
      _decayConstant,
      _timeSinceLastAuctionStart
    );
    return result;
  }

  function computeK(
    SD59x18 _emissionRate,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart,
    SD59x18 _purchaseAmount,
    SD59x18 _price
  ) external pure returns (SD59x18) {
    SD59x18 result = ContinuousGDA.computeK(
      _emissionRate,
      _decayConstant,
      _timeSinceLastAuctionStart,
      _purchaseAmount,
      _price
    );
    return result;
  }
}
