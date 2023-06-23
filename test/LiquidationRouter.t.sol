// // SPDX-License-Identifier: GPL-3.0
// pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
// import { SafeERC20 } from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

// import { LiquidationPairFactory } from "src/LiquidationPairFactory.sol";
// import { LiquidationPair } from "src/LiquidationPair.sol";
// import { LiquidationRouter } from "src/LiquidationRouter.sol";

// import { ILiquidationSource } from "src/interfaces/ILiquidationSource.sol";

// import { BaseSetup } from "./utils/BaseSetup.sol";

// contract LiquidationRouterTest is BaseSetup {
//   using SafeERC20 for IERC20;

//   /* ============ Events ============ */

//   event LiquidationRouterCreated(LiquidationPairFactory indexed liquidationPairFactory);

//   /* ============ Variables ============ */

//   address public defaultReceiver;
//   address public defaultTarget;

//   UFixed32x4 public defaultSwapMultiplier;
//   UFixed32x4 public defaultLiquidityFraction;
//   uint128 public defaultVirtualReserveIn;
//   uint128 public defaultVirtualReserveOut;
//   uint256 public defaultMinK;

//   LiquidationPairFactory public factory;
//   address public source;
//   LiquidationRouter public liquidationRouter;

//   address public tokenIn;
//   address public tokenOut;

//   /* ============ Set up ============ */

//   function setUp() public virtual override {
//     super.setUp();

//     defaultReceiver = bob;
//     defaultTarget = carol;
//     defaultSwapMultiplier = UFixed32x4.wrap(0.3e4);
//     defaultLiquidityFraction = UFixed32x4.wrap(0.02e4);
//     defaultVirtualReserveIn = 100e18;
//     defaultVirtualReserveOut = 100e18;
//     defaultMinK = 1e8;

//     tokenIn = utils.generateAddress("tokenIn");
//     tokenOut = utils.generateAddress("tokenOut");

//     source = utils.generateAddress("source");

//     factory = new LiquidationPairFactory();
//     liquidationRouter = new LiquidationRouter(factory);
//   }

//   /* ============ Constructor ============ */

//   function testConstructor() public {
//     vm.expectEmit(true, false, false, true);
//     emit LiquidationRouterCreated(factory);

//     new LiquidationRouter(factory);
//   }

//   /* ============ swapExactAmountIn ============ */

//   function testSwapExactAmountIn_HappyPath() public {
//     LiquidationPair liquidationPair = new LiquidationPair(
//       ILiquidationSource(source),
//       address(tokenIn),
//       address(tokenOut),
//       defaultSwapMultiplier,
//       defaultLiquidityFraction,
//       defaultVirtualReserveIn,
//       defaultVirtualReserveOut,
//       defaultMinK
//     );

//     mockSwapIn(
//       address(factory),
//       address(liquidationPair),
//       tokenIn,
//       alice,
//       defaultReceiver,
//       defaultTarget,
//       1e18,
//       1e18,
//       1e18
//     );

//     vm.prank(alice);
//     liquidationRouter.swapExactAmountIn(liquidationPair, defaultReceiver, 1e18, 1e18);
//   }

//   /* ============ swapExactAmountOut ============ */

//   function testSwapExactAmountOut_HappyPath() public {
//     LiquidationPair liquidationPair = new LiquidationPair(
//       ILiquidationSource(source),
//       address(tokenIn),
//       address(tokenOut),
//       defaultSwapMultiplier,
//       defaultLiquidityFraction,
//       defaultVirtualReserveIn,
//       defaultVirtualReserveOut,
//       defaultMinK
//     );

//     mockSwapOut(
//       address(factory),
//       address(liquidationPair),
//       tokenIn,
//       alice,
//       defaultReceiver,
//       defaultTarget,
//       1e18,
//       1e18,
//       1e18
//     );

//     vm.prank(alice);
//     liquidationRouter.swapExactAmountOut(liquidationPair, defaultReceiver, 1e18, 1e18);
//   }

//   /* ============ Mocks ============ */

//   function mockTokenIn(address _liquidationPair, address _result) internal {
//     vm.mockCall(_liquidationPair, abi.encodeWithSignature("tokenIn()"), abi.encode(_result));
//   }

//   function mockTarget(address _liquidationPair, address _result) internal {
//     vm.mockCall(
//       _liquidationPair,
//       abi.encodeWithSelector(LiquidationPair.target.selector),
//       abi.encode(_result)
//     );
//   }

//   function mockComputeExactAmountIn(
//     address _liquidationPair,
//     uint256 _amountOut,
//     uint256 _result
//   ) internal {
//     vm.mockCall(
//       _liquidationPair,
//       abi.encodeWithSelector(LiquidationPair.computeExactAmountIn.selector, _amountOut),
//       abi.encode(_result)
//     );
//   }

//   function mockComputeExactAmountOut(
//     address _liquidationPair,
//     uint256 _amountIn,
//     uint256 _result
//   ) internal {
//     vm.mockCall(
//       _liquidationPair,
//       abi.encodeWithSelector(LiquidationPair.computeExactAmountOut.selector, _amountIn),
//       abi.encode(_result)
//     );
//   }

//   function mockDeployedPairs(address _factory, address _liquidationPair, bool _result) internal {
//     vm.mockCall(
//       _factory,
//       abi.encodeWithSignature("deployedPairs(address)", _liquidationPair),
//       abi.encode(_result)
//     );
//   }

//   // NOTE: Function selector of safeTransferFrom wasn't working
//   function mockTransferFrom(address _token, address _from, address _to, uint256 _amount) internal {
//     vm.mockCall(
//       _token,
//       abi.encodeWithSignature("transferFrom(address,address,uint256)", _from, _to, _amount),
//       abi.encode()
//     );
//   }

//   function mockSwapExactAmountIn(
//     address _liquidationPair,
//     address _receiver,
//     uint256 _amountIn,
//     uint256 _amountOutMin,
//     uint256 _result
//   ) internal {
//     vm.mockCall(
//       _liquidationPair,
//       abi.encodeWithSelector(
//         LiquidationPair.swapExactAmountIn.selector,
//         _receiver,
//         _amountIn,
//         _amountOutMin
//       ),
//       abi.encode(_result)
//     );
//   }

//   function mockSwapExactAmountOut(
//     address _liquidationPair,
//     address _receiver,
//     uint256 _amountOut,
//     uint256 _amountInMax,
//     uint256 _result
//   ) internal {
//     vm.mockCall(
//       _liquidationPair,
//       abi.encodeWithSelector(
//         LiquidationPair.swapExactAmountOut.selector,
//         _receiver,
//         _amountOut,
//         _amountInMax
//       ),
//       abi.encode(_result)
//     );
//   }

//   function mockSwapIn(
//     address _factory,
//     address _liquidationPair,
//     address _tokenIn,
//     address _sender,
//     address _receiver,
//     address _target,
//     uint256 _amountIn,
//     uint256 _amountOutMin,
//     uint256 _result
//   ) internal {
//     mockDeployedPairs(_factory, _liquidationPair, true);
//     mockTokenIn(_liquidationPair, _tokenIn);
//     mockTarget(_liquidationPair, _target);
//     mockTransferFrom(_tokenIn, _sender, _target, _amountIn);
//     mockSwapExactAmountIn(_liquidationPair, _receiver, _amountIn, _amountOutMin, _result);
//   }

//   function mockSwapOut(
//     address _factory,
//     address _liquidationPair,
//     address _tokenIn,
//     address _sender,
//     address _receiver,
//     address _target,
//     uint256 _amountOut,
//     uint256 _amountInMax,
//     uint256 _result
//   ) internal {
//     mockDeployedPairs(_factory, _liquidationPair, true);
//     mockTokenIn(_liquidationPair, _tokenIn);
//     mockTarget(_liquidationPair, _target);
//     mockComputeExactAmountIn(_liquidationPair, _amountOut, _result);
//     mockTransferFrom(_tokenIn, _sender, _target, _result);
//     mockSwapExactAmountOut(_liquidationPair, _receiver, _amountOut, _amountInMax, _result);
//   }
// }
