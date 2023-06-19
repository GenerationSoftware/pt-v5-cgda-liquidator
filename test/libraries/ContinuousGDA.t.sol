// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { ContinuousGDA, SD59x18, toSD59x18, sd } from "src/libraries/ContinuousGDA.sol";

contract ContinuousGDATest is Test {

    function testPurchasePrice() public {

        // 1 per 10 seconds
        uint256 purchaseAmount = 10e18;
        SD59x18 emissionRate = toSD59x18(1e18); // 1 per second
        SD59x18 initialPrice = toSD59x18(10e18);
        SD59x18 decayConstant = sd(0.9e18);
        SD59x18 elapsedTime = toSD59x18(10);

        console2.log(
            "purchase price",
            ContinuousGDA.purchasePrice(
                purchaseAmount,
                emissionRate,
                initialPrice,
                decayConstant,
                elapsedTime
            ) / 1e18
        );

    }

}
