// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { SD59x18, convert, unwrap } from "prb-math/SD59x18.sol";

// NOTE: taken from https://github.com/FrankieIsLost/gradual-dutch-auction/blob/master/src/ContinuousGDA.sol
library ContinuousGDA {

  /// See https://www.paradigm.xyz/2022/04/gda
  /// @notice calculate price to purchased _numTokens using exponential continuous GDA formula
  function purchasePrice(
    uint256 _numTokens,
    SD59x18 _emissionRate,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant,
    SD59x18 _timeSinceLastAuctionStart
  ) internal pure returns (uint256) {
    SD59x18 quantity = convert(int256(_numTokens));

    SD59x18 topE = _decayConstant.mul(quantity).div(_emissionRate);
    topE = topE.exp().sub(convert(1));

    SD59x18 bottomE = _decayConstant.mul(_timeSinceLastAuctionStart);
    bottomE = bottomE.exp();
    bottomE = _decayConstant.mul(bottomE);

    return uint256(convert(_initialPrice.mul(topE.div(bottomE))));
  }
}
