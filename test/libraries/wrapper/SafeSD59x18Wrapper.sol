// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SafeSD59x18, SD59x18 } from "../../../src/libraries/SafeSD59x18.sol";

contract SafeSD59x18Wrapper {

    function safeExp(SD59x18 x) external pure returns (SD59x18) {
        SD59x18 result = SafeSD59x18.safeExp(x);
        return result;
    }

}
