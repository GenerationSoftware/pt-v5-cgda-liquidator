// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { SafeSD59x18, SD59x18, wrap } from "../../src/libraries/SafeSD59x18.sol";
import { SafeSD59x18Wrapper } from "./wrapper/SafeSD59x18Wrapper.sol";

contract SafeSD59x18Test is Test {
  SafeSD59x18Wrapper wrapper;

  function setUp() public {
    wrapper = new SafeSD59x18Wrapper();
  }

  function testUnsafeNum() public {
    assertEq(wrapper.safeExp(wrap(-41.45e18)).unwrap(), 0);
    assertEq(wrapper.safeExp(wrap(-100e18)).unwrap(), 0);
  }

  function testSafeNum() public {
    assertEq(wrapper.safeExp(wrap(0)).unwrap(), 1e18);
  }
}
