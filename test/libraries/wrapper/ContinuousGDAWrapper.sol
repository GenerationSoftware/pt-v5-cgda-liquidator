// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ContinuousGDA, SD59x18 } from "src/libraries/ContinuousGDA.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
contract ContinuousGDAWrapper {

  ///@notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) external pure returns (uint256) {
    uint256 result = ContinuousGDA.purchasePrice(
      _numTokens,
      _emissionRate,
      _initialPrice,
      _decayConstant,
      _timeSinceLastAuctionStart);
    return result;
  }
}
