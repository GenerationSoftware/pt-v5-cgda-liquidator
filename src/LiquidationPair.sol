// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { SD59x18, uEXP_MAX_INPUT, wrap, convert, unwrap } from "prb-math/SD59x18.sol";

import { ContinuousGDA } from "./libraries/ContinuousGDA.sol";

error AmountInZero();
error AmountOutZero();
error TargetFirstSaleTimeLtPeriodLength(uint passedTargetSaleTime, uint periodLength);
error SwapExceedsAvailable(uint256 amountOut, uint256 available);
error SwapExceedsMax(uint256 amountInMax, uint256 amountIn);
error DecayConstantTooLarge(SD59x18 maxDecayConstant, SD59x18 decayConstant);
error PurchasePriceIsZero(uint256 amountOut);

contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;

  SD59x18 public immutable decayConstant;

  /// @notice Sets the minimum period length for auctions. When a period elapses a new auction begins.
  uint256 public immutable periodLength;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the periodOffset is in the past.
  uint256 public immutable periodOffset;

  uint32 public immutable targetFirstSaleTime;

  /// @notice Require a minimum number of tokens before an auction is triggered.
  /// @dev This is important, because the gas cost ultimately determines the efficiency of the swap.
  /// If gas cost to auction is 10 cents and the auction is for 11 cents, then the auction price will be driven to zero to make up for the difference.
  /// If gas cost is 10 cents and we're seeking an efficiency of at least 90%, then the minimum auction amount should be $1 worth of tokens.
  uint256 public immutable minimumAuctionAmount;

  uint112 _lastNonZeroAmountIn;
  uint112 _lastNonZeroAmountOut;
  uint96 _amountInForPeriod;
  uint96 _amountOutForPeriod;
  uint16 _period;
  uint48 _lastAuctionTime;
  SD59x18 _emissionRate;
  SD59x18 _initialPrice;

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
    uint112 _initialAmountOut,
    uint256 _minimumAuctionAmount
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    decayConstant = _decayConstant;
    periodLength = _periodLength;
    periodOffset = _periodOffset;
    targetFirstSaleTime = _targetFirstSaleTime;

    SD59x18 period59 = convert(int256(uint256(_periodLength)));
    if (_decayConstant.mul(period59).unwrap() > uEXP_MAX_INPUT) {
      revert DecayConstantTooLarge(wrap(uEXP_MAX_INPUT).div(period59), _decayConstant);
    }

    // console2.log("GOT here?");

    // convert to event
    if (targetFirstSaleTime >= periodLength) {
      revert TargetFirstSaleTimeLtPeriodLength(targetFirstSaleTime, periodLength);
    }

    // console2.log("GOT here? 2");

    if (_initialAmountIn == 0) {
      revert AmountInZero();
    }


    // console2.log("GOT here?3 ");

    if (_initialAmountOut == 0) {
      revert AmountOutZero();
    }

    // console2.log("GOT here? 4");

    _lastNonZeroAmountIn = _initialAmountIn;
    _lastNonZeroAmountOut = _initialAmountOut;
    minimumAuctionAmount = _minimumAuctionAmount;

    _updateAuction(0);

    // console2.log("GOT here? 5");
  }

  /* ============ External Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external returns (uint256) {
    _checkUpdateAuction();
    return _maxAmountOut();
  }

  function maxAmountIn() external returns (uint256) {
    _checkUpdateAuction();
    return _computeExactAmountIn(_maxAmountOut());
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    _checkUpdateAuction();
    return _computeExactAmountIn(_amountOut);
  }

  /// @inheritdoc ILiquidationPair
  function estimateAmountOut(uint256 __amountIn) external returns (uint256) {
    _checkUpdateAuction();
    return uint(convert(ContinuousGDA.purchaseAmount(
      convert(int(__amountIn)),
      _emissionRate,
      _initialPrice,
      decayConstant,
      _getElapsedTime()
    )));
  }

  function amountInForPeriod() external returns (uint96) {
    _checkUpdateAuction();
    return _amountInForPeriod;
  }

  function amountOutForPeriod() external returns (uint96) {
    _checkUpdateAuction();
    return _amountOutForPeriod;
  }

  function lastAuctionTime() external returns (uint48) {
    _checkUpdateAuction();
    return _lastAuctionTime;
  }

  function emissionRate() external returns (SD59x18) {
    _checkUpdateAuction();
    return _emissionRate;
  }

  function initialPrice() external returns (SD59x18) {
    _checkUpdateAuction();
    return _initialPrice;
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    _checkUpdateAuction();
    uint swapAmountIn = _computeExactAmountIn(_amountOut);
    if (swapAmountIn > _amountInMax) {
      revert SwapExceedsMax(_amountInMax, swapAmountIn);
    }
    _amountInForPeriod += uint96(swapAmountIn);
    _amountOutForPeriod += uint96(_amountOut);
    _lastAuctionTime += uint48(uint256(convert(convert(int256(_amountOut)).div(_emissionRate))));
    _swap(_account, _amountOut, swapAmountIn);
    return swapAmountIn;
  }

  // function computeMinPrice() external returns (SD59x18) {
  //   _checkUpdateAuction();
  //   // amount for 1 second
  //   uint amount = uint(convert(convert(1).mul(_emissionRate).ceil()));
  //   // console2.log("amount", amount);
  //   return ContinuousGDA.purchasePrice(
  //     amount,
  //     _emissionRate,
  //     _initialPrice,
  //     decayConstant,
  //     convert(int256(periodLength-20 hours))
  //   );
  // }

  function getElapsedTime() external returns (uint256) {
    _checkUpdateAuction();
    return uint256(convert(_getElapsedTime()));
  }

  function getPeriodStart() external returns (uint256) {
    _checkUpdateAuction();
    return _getPeriodStart(_getPeriod());
  }

  function getPeriodEnd() external returns (uint256) {
    _checkUpdateAuction();
    return _getPeriodEnd(_getPeriod());
  }

  function lastNonZeroAmountIn() external returns (uint112) {
    _checkUpdateAuction();
    return _lastNonZeroAmountIn;
  }

  function lastNonZeroAmountOut() external returns (uint112) {
    _checkUpdateAuction();
    return _lastNonZeroAmountOut;
  }

  /* ============ Internal Functions ============ */

  function _maxAmountOut() internal returns (uint256) {
    // console2.log("_maxAmountOut _emissionRate", _emissionRate.unwrap());
    // console2.log("_maxAmountOut _getElapsedTime", _getElapsedTime().unwrap());
    uint emissions = uint(convert(_emissionRate.mul(_getElapsedTime())));
    // console2.log("max amount ooouuuutt 2", emissions);
    uint liquidatable = source.liquidatableBalanceOf(tokenOut);
    // console2.log("max amount ooouuuutt 3");
    // console2.log("_maxAmountOut emissions liquidatable", emissions, liquidatable);
    return emissions > liquidatable ? liquidatable : emissions;
  }

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  function _computeEmissionRate() internal returns (SD59x18) {
    uint256 amount = source.liquidatableBalanceOf(tokenOut);
    // console2.log("_computeEmissionRate amount", amount);
    if (amount < minimumAuctionAmount) {
      // do not release funds if the minimum is not met
      amount = 0;
      // console2.log("AMOUNT IS ZERO");
    }
    return convert(int256(amount)).div(convert(int32(int(periodLength))));
  }

  function _getElapsedTime() internal view returns (SD59x18) {
    if (block.timestamp < _lastAuctionTime) {
      return wrap(0);
    }
    return convert(int256(block.timestamp)).sub(convert(int256(uint256(_lastAuctionTime))));
  }

  function _computeExactAmountIn(uint256 _amountOut) internal returns (uint256) {
    if (_amountOut == 0) {
      return 0;
    }
    uint256 maxOut = _maxAmountOut();
    if (_amountOut > maxOut) {
      revert SwapExceedsAvailable(_amountOut, maxOut);
    }
    SD59x18 elapsed = _getElapsedTime();
    uint purchasePrice = uint256(convert(ContinuousGDA.purchasePrice(
        convert(int(_amountOut)),
        _emissionRate,
        _initialPrice,
        decayConstant,
        elapsed
      ).ceil()));

    if (purchasePrice == 0) {
      revert PurchasePriceIsZero(_amountOut);
    }

    return purchasePrice;
  }

  function _checkUpdateAuction() internal {
    uint256 currentPeriod = _getPeriod();
    if (currentPeriod != _period) {
      _updateAuction(currentPeriod);
    }
  }

  function _updateAuction(uint256 __period) internal {
    if (_amountInForPeriod > 0 && _amountOutForPeriod > 0) {
      // if we sold something, then update the previous non-zero amount
      _lastNonZeroAmountIn = _amountInForPeriod;
      _lastNonZeroAmountOut = _amountOutForPeriod;
    }
    _amountInForPeriod = 0;
    _amountOutForPeriod = 0;
    _lastAuctionTime = uint48(periodOffset + periodLength * __period);
    _period = uint16(__period);
    // console2.log("_updateAuction _computeEmissionRate...");
    SD59x18 emissionRate_ = _computeEmissionRate();
    _emissionRate = emissionRate_;
    if (_emissionRate.unwrap() != 0) {
      // console2.log("_updateAuction _computeK...");
      // console2.log("_lastNonZeroAmountIn", _lastNonZeroAmountIn);
      // console2.log("_lastNonZeroAmountOut", _lastNonZeroAmountOut);
      _initialPrice = _computeK(
        emissionRate_,
        _lastNonZeroAmountIn,
        _lastNonZeroAmountOut
      );
    } else {
      _initialPrice = wrap(0);
    }
  }

  function _getPeriodStart(uint256 __period) internal view returns (uint256) {
    return periodOffset + __period * periodLength;
  }

  function _getPeriodEnd(uint256 __period) internal view returns (uint256) {
    return _getPeriodStart(__period) + periodLength;
  }

  function _getPeriod() internal view returns (uint256) {
    uint256 _timestamp = block.timestamp;
    if (_timestamp < periodOffset) {
      return 0;
    }
    return (_timestamp - periodOffset) / periodLength;
  }

  function _computeK(
    SD59x18 __emissionRate,
    uint112 _amountIn,
    uint112 _amountOut
  ) internal view returns (SD59x18) {
    SD59x18 timeSinceLastAuctionStart = convert(int(uint(targetFirstSaleTime)));
    SD59x18 purchaseAmount = timeSinceLastAuctionStart.mul(__emissionRate);
    SD59x18 exchangeRateAmountInToAmountOut = _amountOut > 0
      ? convert(int(uint(_amountIn))).div(convert(int(uint(_amountOut))))
      : wrap(0);
    SD59x18 price = exchangeRateAmountInToAmountOut.mul(purchaseAmount);
    SD59x18 result = ContinuousGDA.computeK(
      __emissionRate,
      decayConstant,
      timeSinceLastAuctionStart,
      purchaseAmount,
      price
    );
    return result;
  }
}
