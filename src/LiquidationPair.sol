// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";
import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { SD59x18, uEXP_MAX_INPUT, wrap, convert, unwrap } from "prb-math/SD59x18.sol";

import { ContinuousGDA } from "./libraries/ContinuousGDA.sol";

error AmountInZero();
error AmountOutZero();
error TargetFirstSaleTimeLtPeriodLength(uint256 passedTargetSaleTime, uint256 periodLength);
error SwapExceedsAvailable(uint256 amountOut, uint256 available);
error SwapExceedsMax(uint256 amountInMax, uint256 amountIn);
error DecayConstantTooLarge(SD59x18 maxDecayConstant, SD59x18 decayConstant);
error PurchasePriceIsZero(uint256 amountOut);
error LiquidationSourceZeroAddress();
error TokenInZeroAddress();
error TokenOutZeroAddress();

uint256 constant UINT192_MAX = type(uint192).max;

/***
 * @title LiquidationPair
 * @author G9 Software Inc.
 * @notice Auctions one token for another in a periodic continuous gradual dutch auction. Auctions occur over a limit period so that the price can be adjusted.
 * @dev This contract is designed to be used with the LiquidationRouter contract.
 */
contract LiquidationPair is ILiquidationPair {

  /* ============ Events ============ */

  /// @notice Emitted when a new auction is started
  /// @param lastNonZeroAmountIn The total tokens in for the previous non-zero auction
  /// @param lastNonZeroAmountOut The total tokens out for the previous non-zero auction
  /// @param lastAuctionTime The timestamp at which the auction starts
  /// @param period The current auction period
  /// @param emissionRate The rate of token emissions for the current auction
  /// @param initialPrice The initial price for the current auction
  event StartedAuction(
    uint104 lastNonZeroAmountIn,
    uint104 lastNonZeroAmountOut,
    uint48 lastAuctionTime,
    uint48 period,
    SD59x18 emissionRate,
    SD59x18 initialPrice
  );

  /// @notice Emitted when a swap is made
  /// @param sender The sender of the swap
  /// @param receiver The receiver of the swap
  /// @param amountOut The amount of tokens out
  /// @param amountInMax The maximum amount of tokens in
  /// @param amountIn The actual amount of tokens in
  event SwappedExactAmountOut(
    address sender,
    address receiver,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 amountIn
  );

  /* ============ Variables ============ */

  /// @notice The liquidation source that the pair is using.  The source executes the actual token swap, while the pair handles the pricing.
  ILiquidationSource public immutable source;

  /// @notice The token that is used to pay for auctions
  address public immutable tokenIn;

  /// @notice The token that is being auctioned.
  address public immutable tokenOut;

  /// @notice The rate at which the price decays
  SD59x18 public immutable decayConstant;

  /// @notice The duration of each auction.
  uint256 public immutable periodLength;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the periodOffset is in the past.
  uint256 public immutable periodOffset;

  /// @notice The time within an auction at which the price of available tokens matches the previous non-zero exchange rate.
  uint32 public immutable targetFirstSaleTime;

  /// @notice Require a minimum number of tokens before an auction is triggered.
  /// @dev This is important, because the gas cost ultimately determines the efficiency of the swap.
  /// If gas cost to auction is 10 cents and the auction is for 11 cents, then the auction price will be driven to zero to make up for the difference.
  /// If gas cost is 10 cents and we're seeking an efficiency of at least 90%, then the minimum auction amount should be $1 worth of tokens.
  uint256 public immutable minimumAuctionAmount;

  /// @notice The last non-zero total tokens in for an auction. This is used to configure the target price for the next auction.
  uint104 internal _lastNonZeroAmountIn;

  /// @notice The last non-zero total tokens out for an auction.  This is used to configure the target price for the next auction.
  uint104 internal _lastNonZeroAmountOut;

  /// @notice The current auction period. Note that this number can wrap.
  uint48 internal _period;

  /// @notice The total tokens in for the current auction.
  uint104 internal _amountInForPeriod;

  /// @notice The total tokens out for the current auction.
  uint104 internal _amountOutForPeriod;

  /// @notice The timestamp at which emissions have been consumed to for the current auction
  uint48 internal _lastAuctionTime;

  /// @notice The rate of token emissions for the current auction
  SD59x18 internal _emissionRate;

  /// @notice The initial price for the current auction
  SD59x18 internal _initialPrice;

  /* ============ Constructor ============ */

  /// @notice Construct a new pair
  /// @param _source The liquidation source to use for the pair
  /// @param _tokenIn The token that is used to pay for auctions
  /// @param _tokenOut The token that is being auctioned
  /// @param _periodLength The duration of each auction.
  /// @param _periodOffset Sets the beginning timestamp for the first period
  /// @param _targetFirstSaleTime The time within an auction at which the price of available tokens matches the previous non-zero exchange rate
  /// @param _decayConstant The rate at which the price decays
  /// @param _initialAmountIn The initial amount of tokens in for the first auction (used for the initial exchange rate)
  /// @param _initialAmountOut The initial amount of tokens out for the first auction (used for the initial exchange rate)
  /// @param _minimumAuctionAmount Require a minimum number of tokens before an auction is triggered.
  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _periodOffset,
    uint32 _targetFirstSaleTime,
    SD59x18 _decayConstant,
    uint104 _initialAmountIn,
    uint104 _initialAmountOut,
    uint256 _minimumAuctionAmount
  ) {
    if (address(0) == address(_source)) revert LiquidationSourceZeroAddress();
    if (address(0) == address(_tokenIn)) revert TokenInZeroAddress();
    if (address(0) == address(_tokenOut)) revert TokenOutZeroAddress();
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    decayConstant = _decayConstant;
    periodLength = _periodLength;
    periodOffset = _periodOffset;
    targetFirstSaleTime = _targetFirstSaleTime;

    SD59x18 period59 = convert(SafeCast.toInt256(uint256(_periodLength)));
    if (_decayConstant.mul(period59).unwrap() > uEXP_MAX_INPUT) {
      revert DecayConstantTooLarge(wrap(uEXP_MAX_INPUT).div(period59), _decayConstant);
    }

    if (targetFirstSaleTime >= periodLength) {
      revert TargetFirstSaleTimeLtPeriodLength(targetFirstSaleTime, periodLength);
    }

    if (_initialAmountIn == 0) {
      revert AmountInZero();
    }

    if (_initialAmountOut == 0) {
      revert AmountOutZero();
    }

    _lastNonZeroAmountIn = _initialAmountIn;
    _lastNonZeroAmountOut = _initialAmountOut;
    minimumAuctionAmount = _minimumAuctionAmount;

    _updateAuction(0);
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

  /// @notice Returns the maximum amount of tokens in
  /// @return The max number of tokens in
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
    return uint256(convert(ContinuousGDA.purchaseAmount(
      convert(SafeCast.toInt256(__amountIn)),
      _emissionRate,
      _initialPrice,
      decayConstant,
      _getElapsedTime()
    )));
  }

  /// @notice Returns the total input tokens for the current auction.
  /// @return Total tokens in
  function amountInForPeriod() external returns (uint104) {
    _checkUpdateAuction();
    return _amountInForPeriod;
  }

  /// @notice Returns the total output tokens for the current auction.
  /// @return Total tokens out
  function amountOutForPeriod() external returns (uint104) {
    _checkUpdateAuction();
    return _amountOutForPeriod;
  }

  /// @notice Returns the timestamp to which emissions have been consumed.
  /// @return The timestamp to which emissions have been consumed.
  function lastAuctionTime() external returns (uint48) {
    _checkUpdateAuction();
    return _lastAuctionTime;
  }

  /// @notice Returns the emission rate in tokens per second for current auction
  /// @return The emission rate
  function emissionRate() external returns (SD59x18) {
    _checkUpdateAuction();
    return _emissionRate;
  }

  /// @notice Returns the initial price for the current auction
  /// @return The initial price
  function initialPrice() external returns (SD59x18) {
    _checkUpdateAuction();
    return _initialPrice;
  }

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _receiver,
    uint256 _amountOut,
    uint256 _amountInMax,
    bytes memory _flashSwapData
  ) external returns (uint256) {
    _checkUpdateAuction();
    uint256 swapAmountIn = _computeExactAmountIn(_amountOut);
    if (swapAmountIn == 0) {
      revert PurchasePriceIsZero(_amountOut);
    }
    if (swapAmountIn > _amountInMax) {
      revert SwapExceedsMax(_amountInMax, swapAmountIn);
    }
    _amountInForPeriod = _amountInForPeriod + SafeCast.toUint104(swapAmountIn);
    _amountOutForPeriod = _amountOutForPeriod + SafeCast.toUint104(_amountOut);
    _lastAuctionTime = _lastAuctionTime + SafeCast.toUint48(SafeCast.toUint256(convert(convert(SafeCast.toInt256(_amountOut)).div(_emissionRate))));
    source.liquidate(msg.sender, _receiver, tokenIn, swapAmountIn, tokenOut, _amountOut, _flashSwapData);

    emit SwappedExactAmountOut(msg.sender, _receiver, _amountOut, _amountInMax, swapAmountIn);

    return swapAmountIn;
  }

  /// @notice Computes the elapsed time within the auction
  function getElapsedTime() external returns (uint256) {
    _checkUpdateAuction();
    return uint256(convert(_getElapsedTime()));
  }

  /// @notice Returns the current auction start time
  /// @return The start timestamp
  function getPeriodStart() external returns (uint256) {
    _checkUpdateAuction();
    return _getPeriodStart(_computePeriod());
  }

  /// @notice Returns the current auction end time
  /// @return The end timestamp
  function getPeriodEnd() external returns (uint256) {
    _checkUpdateAuction();
    return _getPeriodStart(_computePeriod()) + periodLength;
  }

  /// @notice Returns the last non-zero auction total input tokens
  /// @return Total input tokens
  function lastNonZeroAmountIn() external returns (uint112) {
    _checkUpdateAuction();
    return _lastNonZeroAmountIn;
  }

  /// @notice Returns the last non-zero auction total output tokens
  /// @return Total output tokens
  function lastNonZeroAmountOut() external returns (uint112) {
    _checkUpdateAuction();
    return _lastNonZeroAmountOut;
  }

  /* ============ Internal Functions ============ */

  /// @notice Computes the maximum amount of output tokens that can be purchased
  /// @return Maximum amount of output tokens
  function _maxAmountOut() internal returns (uint256) {
    uint256 emissions = SafeCast.toUint256(convert(_emissionRate.mul(_getElapsedTime())));
    uint256 liquidatable = source.liquidatableBalanceOf(tokenOut);
    return emissions > liquidatable ? liquidatable : emissions;
  }

  /// @notice Computes the elapsed time within the current auction
  /// @return The elapsed time
  function _getElapsedTime() internal view returns (SD59x18) {
    uint256 cachedTimestamp = block.timestamp;
    uint48 cachedLastAuctionTime = _lastAuctionTime;
    if (cachedTimestamp < cachedLastAuctionTime) {
      return wrap(0);
    }
    return convert(SafeCast.toInt256(cachedTimestamp)).sub(convert(SafeCast.toInt256(cachedLastAuctionTime)));
  }

  /// @notice Computes the exact amount of input tokens required to purchase the given amount of output tokens
  /// @param _amountOut The number of output tokens desired
  /// @return The number of input tokens needed
  function _computeExactAmountIn(uint256 _amountOut) internal returns (uint256) {
    if (_amountOut == 0) {
      return 0;
    }
    uint256 maxOut = _maxAmountOut();
    if (_amountOut > maxOut) {
      revert SwapExceedsAvailable(_amountOut, maxOut);
    }
    SD59x18 elapsed = _getElapsedTime();
    uint256 purchasePrice = SafeCast.toUint256(convert(ContinuousGDA.purchasePrice(
        convert(SafeCast.toInt256(_amountOut)),
        _emissionRate,
        _initialPrice,
        decayConstant,
        elapsed
      ).ceil()));

    return purchasePrice;
  }

  /// @notice Checks to see if a new auction has started, and updates the state if so
  function _checkUpdateAuction() internal {
    uint256 currentPeriod = _computePeriod();
    if (currentPeriod != _period) {
      _updateAuction(currentPeriod);
    }
  }

  /// @notice Updates the current auction to the given period
  /// @param __period The period that the auction should be updated to
  function _updateAuction(uint256 __period) internal {
    uint104 cachedLastNonZeroAmountIn;
    uint104 cachedLastNonZeroAmountOut;
    if (_amountInForPeriod > 0 && _amountOutForPeriod > 0) {
      // if we sold something, then update the previous non-zero amount
      _lastNonZeroAmountIn = _amountInForPeriod;
      _lastNonZeroAmountOut = _amountOutForPeriod;
      cachedLastNonZeroAmountIn = _amountInForPeriod;
      cachedLastNonZeroAmountOut = _amountOutForPeriod;
    } else {
      cachedLastNonZeroAmountIn = _lastNonZeroAmountIn;
      cachedLastNonZeroAmountOut = _lastNonZeroAmountOut;
    }
    
    _period = uint48(__period);
    delete _amountInForPeriod;
    delete _amountOutForPeriod;
    _lastAuctionTime = SafeCast.toUint48(periodOffset + periodLength * __period);
    uint256 auctionAmount = source.liquidatableBalanceOf(tokenOut);
    if (auctionAmount < minimumAuctionAmount) {
      // do not release funds if the minimum is not met
      auctionAmount = 0;
    } else if (auctionAmount > UINT192_MAX) {
      auctionAmount = UINT192_MAX;
    }
    SD59x18 emissionRate_ = convert(SafeCast.toInt256(auctionAmount)).div(convert(SafeCast.toInt32(SafeCast.toInt256(periodLength))));
    _emissionRate = emissionRate_;
    if (emissionRate_.unwrap() != 0) {
      // compute k
      SD59x18 timeSinceLastAuctionStart = convert(SafeCast.toInt256(uint256(targetFirstSaleTime)));
      SD59x18 purchaseAmount = timeSinceLastAuctionStart.mul(emissionRate_);
      SD59x18 exchangeRateAmountInToAmountOut = convert(SafeCast.toInt256(uint256(cachedLastNonZeroAmountIn))).div(convert(SafeCast.toInt256(uint256(cachedLastNonZeroAmountOut))));
      SD59x18 price = exchangeRateAmountInToAmountOut.mul(purchaseAmount);
      _initialPrice = ContinuousGDA.computeK(
        emissionRate_,
        decayConstant,
        timeSinceLastAuctionStart,
        purchaseAmount,
        price
      );
    } else {
      _initialPrice = wrap(0);
    }

    emit StartedAuction(
      cachedLastNonZeroAmountIn,
      cachedLastNonZeroAmountOut,
      _lastAuctionTime,
      uint48(__period),
      emissionRate_,
      _initialPrice
    );
  }

  /// @notice Computes the start time of the given auction period
  /// @param __period The auction period, in terms of number of periods since periodOffset
  /// @return The start timestamp of the given period
  function _getPeriodStart(uint256 __period) internal view returns (uint256) {
    return periodOffset + __period * periodLength;
  }

  /// @notice Computes the current auction period
  /// @return the current period
  function _computePeriod() internal view returns (uint256) {
    uint256 _timestamp = block.timestamp;
    if (_timestamp < periodOffset) {
      return 0;
    }
    return (_timestamp - periodOffset) / periodLength;
  }
}
