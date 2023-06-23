// // SPDX-License-Identifier: GPL-3.0
// pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import { ILiquidationSource } from "../src/interfaces/ILiquidationSource.sol";

// import { UFixed32x4 } from "../src/libraries/FixedMathLib.sol";

// import { LiquidationPairFactory } from "../src/LiquidationPairFactory.sol";
// import { LiquidationPair } from "../src/LiquidationPair.sol";

// import { BaseSetup } from "./utils/BaseSetup.sol";

// contract LiquidationPairFactoryTest is BaseSetup {
//   /* ============ Variables ============ */
//   LiquidationPairFactory public factory;
//   address public tokenIn;
//   address public tokenOut;
//   address public source;
//   address public target;

//   /* ============ Events ============ */

//   event PairCreated(
//     LiquidationPair indexed liquidator,
//     ILiquidationSource indexed source,
//     address indexed tokenIn,
//     address tokenOut,
//     UFixed32x4 swapMultiplier,
//     UFixed32x4 liquidityFraction,
//     uint128 virtualReserveIn,
//     uint128 virtualReserveOut,
//     uint256 minK
//   );

//   /* ============ Set up ============ */

//   function setUp() public virtual override {
//     super.setUp();
//     // Contract setup
//     factory = new LiquidationPairFactory();
//     tokenIn = utils.generateAddress("tokenIn");
//     tokenOut = utils.generateAddress("tokenOut");
//     source = utils.generateAddress("source");
//     target = utils.generateAddress("target");
//   }

//   /* ============ External functions ============ */

//   /* ============ createPair ============ */

//   function testCreatePair() public {
//     vm.expectEmit(false, true, true, true);
//     emit PairCreated(
//       LiquidationPair(0x0000000000000000000000000000000000000000),
//       ILiquidationSource(source),
//       tokenIn,
//       tokenOut,
//       UFixed32x4.wrap(.3e4),
//       UFixed32x4.wrap(.02e4),
//       100,
//       100,
//       200
//     );

//     LiquidationPair lp = factory.createPair(
//       ILiquidationSource(source),
//       tokenIn,
//       tokenOut,
//       UFixed32x4.wrap(.3e4),
//       UFixed32x4.wrap(.02e4),
//       100,
//       100,
//       200
//     );

//     mockTarget(source, target);

//     assertEq(address(lp.source()), source);
//     assertEq(lp.target(), target);
//     assertEq(address(lp.tokenIn()), tokenIn);
//     assertEq(address(lp.tokenOut()), tokenOut);
//     assertEq(UFixed32x4.unwrap(lp.swapMultiplier()), .3e4);
//     assertEq(UFixed32x4.unwrap(lp.liquidityFraction()), .02e4);
//     assertEq(lp.virtualReserveIn(), 100);
//     assertEq(lp.virtualReserveOut(), 100);
//   }

//   function testCannotCreatePair() public {
//     vm.expectRevert(bytes("LiquidationPair/liquidity-fraction-greater-than-zero"));

//     factory.createPair(
//       ILiquidationSource(source),
//       tokenIn,
//       tokenOut,
//       UFixed32x4.wrap(.3e4),
//       UFixed32x4.wrap(0),
//       100,
//       100,
//       200
//     );
//   }

//   /* ============ totalPairs ============ */

//   function testTotalPairs() public {
//     assertEq(factory.totalPairs(), 0);
//     factory.createPair(
//       ILiquidationSource(source),
//       tokenIn,
//       tokenOut,
//       UFixed32x4.wrap(.3e4),
//       UFixed32x4.wrap(.02e4),
//       100,
//       100,
//       200
//     );
//     assertEq(factory.totalPairs(), 1);
//   }

//   /* ============ Mocks ============ */

//   function mockTarget(address _source, address _result) internal {
//     vm.mockCall(
//       _source,
//       abi.encodeWithSelector(ILiquidationSource.targetOf.selector),
//       abi.encode(_result)
//     );
//   }
// }
