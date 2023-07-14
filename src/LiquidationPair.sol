// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { RingBufferLib } from "ring-buffer-lib/RingBufferLib.sol";
import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "v5-liquidator-interfaces/ILiquidationPair.sol";

import { ContinuousGDA } from "./libraries/ContinuousGDA.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";

error AmountInZero();
error AmountOutZero();
error TargetFirstSaleTimeLtPeriodLength(uint passedTargetSaleTime, uint periodLength);

contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;

  SD59x18 public immutable decayConstant;

  /// @notice Sets the minimum period length for auctions. When a period elapses a new auction begins.
  uint32 public immutable PERIOD_LENGTH;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the PERIOD_OFFSET is in the past.
  uint32 public immutable PERIOD_OFFSET;

  uint32 public immutable targetFirstSaleTime;

  uint112 public lastNonZeroAmountIn;
  uint112 public lastNonZeroAmountOut;

  /* ============ Structs ============ */

  uint112 amountIn;
  uint112 amountOut;
  uint32 lastAuctionTime;
  uint16 period;
  SD59x18 emissionRate;
  SD59x18 initialPrice;

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _periodOffset,
    uint32 _targetFirstSaleTime,
    SD59x18 _decayConstant,
    uint112 _initialAmountIn,
    uint112 _initialAmountOut
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    decayConstant = _decayConstant;
    PERIOD_LENGTH = _periodLength;
    PERIOD_OFFSET = _periodOffset;
    targetFirstSaleTime = _targetFirstSaleTime;

    // convert to event
    if (targetFirstSaleTime >= PERIOD_LENGTH) {
      revert TargetFirstSaleTimeLtPeriodLength(targetFirstSaleTime, PERIOD_LENGTH);
    }

    if (_initialAmountIn == 0) {
      revert AmountInZero();
    }
    if (_initialAmountOut == 0) {
      revert AmountOutZero();
    }

    lastNonZeroAmountIn = _initialAmountIn;
    lastNonZeroAmountOut = _initialAmountOut;

    _updateAuction(0);
  }

  /* ============ External Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external returns (uint256) {
    _checkUpdateAuction();
    return _maxAmountOut();
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountIn() external view returns (uint256) {
    console2.log("TODO: maxAmountIn");
    return 0;
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    if (_amountOut == 0) {
      return 0;
    }
    return _computeExactAmountIn(_amountOut);
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountOut(uint256 _amountIn) external returns (uint256) {
    console2.log("TODO: computeExactAmountOut");
    return 0;
  }

  /* ============ External Write Methods ============ */

  /// @inheritdoc ILiquidationPair
  function swapExactAmountIn(
    address _receiver,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) external returns (uint256) {
    console2.log("TODO: swapExactAmountIn");
    return 0;
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    uint swapAmountIn = _computeExactAmountIn(_amountOut);
    require(swapAmountIn <= _amountInMax, "exceeds max amount in");
    amountIn += uint112(swapAmountIn);
    amountOut += uint112(_amountOut);
    lastAuctionTime += uint32(uint256(convert(convert(int256(_amountOut)).div(emissionRate))));
    _swap(_account, _amountOut, swapAmountIn);
    return swapAmountIn;
  }

  function computePurchasePrice(
    uint256 _amountOut,
    SD59x18 _initialPrice,
    SD59x18 _emissionRate,
    SD59x18 _elapsed
  ) public view returns (uint256) {
    return
      ContinuousGDA.purchasePrice(
        _amountOut,
        _emissionRate,
        _initialPrice,
        decayConstant,
        _elapsed
      );
  }

  function getElapsedTime() external returns (int256) {
    _checkUpdateAuction();
    return convert(_getElapsedTime(lastAuctionTime));
  }

  function getPeriodStart() external returns (uint32) {
    _checkUpdateAuction();
    return _getPeriodStart(_getPeriod(uint32(block.timestamp)));
  }

  function getPeriodEnd() external returns (uint32) {
    _checkUpdateAuction();
    return _getPeriodEnd(_getPeriod(uint32(block.timestamp)));
  }

  /* ============ Internal Functions ============ */

  function _maxAmountOut() internal view returns (uint256) {
    // console2.log("_maxAmountOut lastAuctionTime", lastAuctionTime);
    uint emissions = uint(convert(emissionRate.mul(_getElapsedTime(lastAuctionTime))));
    // console2.log("_maxAmountOut emissions", emissions);
    uint liquidatable = source.liquidatableBalanceOf(tokenOut);
    return emissions > liquidatable ? liquidatable : emissions;
  }

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  function _computeEmissionRate() internal view returns (SD59x18) {
    return
      convert(int256(source.liquidatableBalanceOf(tokenOut))).div(convert(int32(PERIOD_LENGTH)));
  }

  function _getElapsedTime(uint256 _lastAuctionTime) internal view returns (SD59x18) {
    return convert(int256(block.timestamp)).sub(convert(int256(_lastAuctionTime)));
  }

  function _computeExactAmountIn(uint256 _amountOut) internal returns (uint256) {
    _checkUpdateAuction();
    require(_amountOut <= _maxAmountOut(), "exceeds available");
    SD59x18 elapsed = _getElapsedTime(lastAuctionTime);
    uint purchasePrice;

    (bool success, bytes memory returnData) = address(this).delegatecall(
      abi.encodeWithSelector(
        this.computePurchasePrice.selector,
        _amountOut,
        initialPrice,
        emissionRate,
        elapsed
      )
    );

    if (success) {
      purchasePrice = abi.decode(returnData, (uint256));
    } else {
      purchasePrice = type(uint256).max;
    }
    return purchasePrice;
  }

  function _checkUpdateAuction() internal {
    uint32 _timestamp = uint32(block.timestamp);
    uint16 currentPeriod = _getPeriod(_timestamp);
    if (currentPeriod != period) {
      _updateAuction(currentPeriod);
    }
  }

  function _updateAuction(uint16 _period) internal {
    if (amountIn > 0 && amountOut > 0) {
      // if we sold something, then update the previous non-zero amount
      lastNonZeroAmountIn = amountIn;
      lastNonZeroAmountOut = amountOut;
    }
    amountIn = 0;
    amountOut = 0;
    lastAuctionTime = PERIOD_OFFSET + PERIOD_LENGTH * _period;
    period = _period;
    emissionRate = _computeEmissionRate();
    if (emissionRate.unwrap() != 0) {
      initialPrice = _computeK(
        emissionRate,
        uint112(lastNonZeroAmountIn),
        uint112(lastNonZeroAmountOut)
      );
    } else {
      initialPrice = wrap(0);
    }
  }

  function _getPeriodStart(uint32 _period) internal view returns (uint32) {
    return PERIOD_OFFSET + _period * PERIOD_LENGTH;
  }

  function _getPeriodEnd(uint32 _period) internal view returns (uint32) {
    return _getPeriodStart(_period) + PERIOD_LENGTH;
  }

  function _getPeriod(uint256 _timestamp) internal view returns (uint16) {
    if (_timestamp < PERIOD_OFFSET) {
      return 0;
    }
    return uint16((_timestamp - PERIOD_OFFSET) / PERIOD_LENGTH);
  }

  function _computeK(
    SD59x18 _emissionRate,
    uint112 _amountIn,
    uint112 _amountOut
  ) internal view returns (SD59x18) {
    // console2.log("_computingK _emissionRate", _emissionRate.unwrap());
    // console2.log("_computingK _amountIn", _amountIn);
    // console2.log("_computingK _amountOut", _amountOut);
    // console2.log("_computingK targetFirstSaleTime", targetFirstSaleTime);
    SD59x18 timeSinceLastAuctionStart = convert(int(uint(targetFirstSaleTime)));
    // console2.log("_computingK timeSinceLastAuctionStart", timeSinceLastAuctionStart.unwrap());
    SD59x18 purchaseAmount = timeSinceLastAuctionStart.mul(_emissionRate);
    SD59x18 exchangeRateAmountInToAmountOut = _amountOut > 0
      ? convert(int(uint(_amountIn))).div(convert(int(uint(_amountOut))))
      : wrap(0);
    SD59x18 price = exchangeRateAmountInToAmountOut.mul(purchaseAmount);
    // console2.log("_got here");
    SD59x18 result = ContinuousGDA.computeK(
      _emissionRate,
      decayConstant,
      timeSinceLastAuctionStart,
      purchaseAmount,
      price
    );
    // console2.log("????? result: ", result.unwrap());
    return result;
  }
}
