// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD59x18, wrap } from "prb-math/SD59x18.sol";

library SafeSD59x18 {

    function safeExp(SD59x18 x) internal pure returns (SD59x18) {
        if (x.unwrap() < -41.45e18) {
            return wrap(0);
        }
        return x.exp();
    }

}