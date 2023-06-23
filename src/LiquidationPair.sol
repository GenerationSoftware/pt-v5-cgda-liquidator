// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { RingBufferLib } from "ring-buffer-lib/RingBufferLib.sol";
import { ContinuousGDA } from "./libraries/ContinuousGDA.sol";
import "./interfaces/ILiquidationSource.sol";
import "./interfaces/ILiquidationPair.sol";
import { SD59x18, wrap, convert, unwrap } from "prb-math/SD59x18.sol";

contract LiquidationPair is ILiquidationPair {
  /* ============ Variables ============ */

  ILiquidationSource public immutable source;
  address public immutable tokenIn;
  address public immutable tokenOut;

  uint32 public lastAvailableAuctionStartTime;
  SD59x18 public immutable decayConstant;
  SD59x18 public immutable initialAuctionPrice;

  /// @notice Sets the minimum period length for auctions. When a period elapses a new auction begins.
  uint32 public immutable PERIOD_LENGTH;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the PERIOD_OFFSET is in the past.
  uint32 public immutable PERIOD_OFFSET;

  /// @notice Storage for the previous, current and next auctions.
  uint8 public constant MAX_CARDINALITY = 3;
  Auction[MAX_CARDINALITY] internal auctions;

  /* ============ Structs ============ */

  struct Auction {
    uint128 amountAccrued;
    uint128 amountClaimed;
    SD59x18 targetPrice;
    uint32 startTime;
  }

  /* ============ Constructor ============ */

  constructor(
    ILiquidationSource _source,
    address _tokenIn,
    address _tokenOut,
    uint32 _periodLength,
    uint32 _periodOffset,
    SD59x18 _initialPrice,
    SD59x18 _decayConstant
  ) {
    source = _source;
    tokenIn = _tokenIn;
    tokenOut = _tokenOut;
    PERIOD_LENGTH = _periodLength;
    PERIOD_OFFSET = _periodOffset;
    initialAuctionPrice = _initialPrice;
    decayConstant = _decayConstant;
    lastAvailableAuctionStartTime = uint32(block.timestamp);

    Auction memory currentAuction = _getAuctionData(uint32(block.timestamp));
    currentAuction.targetPrice = _initialPrice;
  }

  /* ============ External Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external returns (uint256) {
    Auction memory auction = _getAuctionData(uint32(block.timestamp));
    return uint256(auction.amountAccrued) - auction.amountClaimed;
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    if (_amountOut == 0) {
      return 0;
    }
    (uint256 amountIn, , , , ) = _computeExactAmountIn(_amountOut, uint32(block.timestamp));
    return amountIn;
  }

  // /// @inheritdoc ILiquidationPair
  // function computeExactAmountOut(uint256 _amountIn) external view returns (uint256) {}

  /* ============ External Write Methods ============ */

  // /// @inheritdoc ILiquidationPair
  // function swapExactAmountIn(
  //   address _account,
  //   uint256 _amountIn,
  //   uint256 _amountOutMin
  // ) external returns (uint256) {}

  /// @inheritdoc ILiquidationPair
  function swapExactAmountOut(
    address _account,
    uint256 _amountOut,
    uint256 _amountInMax
  ) external returns (uint256) {
    (
      uint256 amountIn,
      ,
      SD59x18 emissionRate,
      ,
      
    ) = _computeExactAmountIn(_amountOut, uint32(block.timestamp));
    // Ensure amount out is less than max amount available.
    require(amountIn <= _amountInMax, "LiquidationPair/exceeds-max-amount-in");

    _swap(_account, _amountOut, amountIn);

    _updateAuctionData(
      uint32(block.timestamp),
      amountIn,
      _amountOut,
      emissionRate
    );

    return amountIn;
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  // function _getPurchaseAmountOut(
  //   SD59x18 _amountIn,
  //   uint32 _timestamp
  // ) internal view returns (SD59x18) {
  //   SD59x18 price = _getPurchasePrice(_timestamp);
  //   return _amountIn.mul(price);
  // }

  function _getPurchaseAmountIn(
    uint256 _amountOut,
    uint32 _timestamp
  ) internal returns (uint256, uint256, SD59x18, SD59x18, uint256) {
    (
      uint256 amountEmitted,
      SD59x18 emissionRate,
      SD59x18 elapsed,
      uint256 amountAccrued
    ) = _getAmountEmitted(_timestamp);
    // require(_amountOut <= amountEmitted, "exceeds emitted");
    SD59x18 decayRate = _getDecayRate();

    // console2.log("purchaseAmount", _amountOut);
    // console2.log("emissionRate", unwrap(emissionRate));
    // console2.log("initialPrice", unwrap(initialAuctionPrice));
    // console2.log("decayRate", unwrap(decayRate));
    // console2.log("elapsedTime", unwrap(elapsed));

    uint256 amountIn = ContinuousGDA.purchasePrice(
      _amountOut,
      emissionRate,
      initialAuctionPrice,
      decayRate,
      elapsed
    );

    return (amountIn, amountEmitted, emissionRate, elapsed, amountAccrued);
  }

  function _getEmissionRate(uint256 amountAccrued) internal view returns (SD59x18) {
    // a^2/t
    // return convert(int256(amountAccrued)).pow(convert(2)).div(convert(int32(PERIOD_LENGTH)));
    // a/t
    return convert(int256(amountAccrued)).div(convert(int32(PERIOD_LENGTH)));
  }

  function _getDecayRate() internal view returns (SD59x18) {
    // 1.5/a
    // return wrap(1.5e18).div(convert(int256(amountAccrued)));
    // constant
    return decayConstant;
  }

  function _computeExactAmountIn(
    uint256 _amountOut,
    uint32 _timestamp
  ) internal returns (uint256, uint256, SD59x18, SD59x18, uint256) {
    uint256 amountAccrued = _getAmountAccrued(_timestamp);
    require(_amountOut <= amountAccrued, "exceeds accrued");
    return _getPurchaseAmountIn(_amountOut, _timestamp);
  }

  /**
   * @notice Returns the maximum amount of tokenOut that can be purchased during the period the timestamp falls within.
   * @param _timestamp The timestamp to query
   */
  function _getAmountAccrued(uint32 _timestamp) internal returns (uint256) {
    Auction memory auction = _getAuctionData(_timestamp);
    return uint256(auction.amountAccrued);
  }

  function _getAmountEmitted(
    uint32 _timestamp
  )
    internal
    returns (uint256 amountEmitted, SD59x18 emissionRate, SD59x18 elapsed, uint256 amountAccrued)
  {
    Auction storage currentAuction = _getAuctionData(uint32(block.timestamp));

    elapsed = convert(int32(_timestamp)).sub(convert(int32(lastAvailableAuctionStartTime)));
    emissionRate = _getEmissionRate(currentAuction.amountAccrued);
    amountEmitted = uint256(convert(emissionRate.mul(elapsed)));
    amountAccrued = currentAuction.amountAccrued;
  }

  function _getAuctionData(uint32 _timestamp) internal returns (Auction storage) {
    Auction storage auctionData = auctions[
      uint16(RingBufferLib.wrap(_getTimestampPeriod(_timestamp), MAX_CARDINALITY))
    ];
    uint32 timestampPeriod = _getTimestampPeriod(_timestamp);
    uint32 startTime = _getPeriodStart(timestampPeriod);

    // console2.log("timestampPeriod", timestampPeriod);
    // console2.log("auctionData.startTime", auctionData.startTime);
    // console2.log("startTime", startTime);

    // If it is an old auction, overwrite it.
    // NOTE: Don't overwrite the target price! That is set elsewhere.
    if (auctionData.startTime != startTime) {
      // Reset last available auction start time when draw rolls over.
      lastAvailableAuctionStartTime = startTime;
      // NOTE: Downcasting available balance to liquidate from source.
      auctionData.amountAccrued = uint128(source.liquidatableBalanceOf(tokenOut));
      auctionData.startTime = startTime;
      auctionData.amountClaimed = 0;
      auctionData.targetPrice = initialAuctionPrice;

      // If it's not the first, add rollover amount.
      if (timestampPeriod > 0) {
        Auction memory previousAuctionData = auctions[
          uint16(RingBufferLib.prevIndex(timestampPeriod, MAX_CARDINALITY))
        ];
        auctionData.amountAccrued += (previousAuctionData.amountAccrued -
          previousAuctionData.amountClaimed);
      }
    }

    return auctionData;
  }

  /**
   * @notice Calculates the period a timestamp falls into.
   * @param _timestamp The timestamp to check
   */
  function _getTimestampPeriod(uint32 _timestamp) internal view returns (uint32) {
    if (_timestamp <= PERIOD_OFFSET) {
      return 0;
    }
    // Shrink by 1 to ensure periods end on a multiple of PERIOD_LENGTH.
    // Increase by 1 to start periods at # 1.
    return ((_timestamp - PERIOD_OFFSET - 1) / PERIOD_LENGTH) + 1;
  }

  function _getPeriodStart(uint32 _period) internal view returns (uint32) {
    if (_period == 0) return PERIOD_OFFSET;
    return PERIOD_OFFSET + (_period - 1) * PERIOD_LENGTH;
  }

  function _getPeriodEnd(uint32 _period) internal view returns (uint32) {
    return _getPeriodStart(_period) + PERIOD_LENGTH;
  }

  function _updateAuctionData(
    uint32 _timestamp,
    uint256 _amountIn,
    uint256 _amountOut,
    SD59x18 emissionRate
  ) internal {
    Auction storage currentAuction = _getAuctionData(_timestamp);
    Auction storage nextAuction = auctions[
      uint16(RingBufferLib.nextIndex(_getTimestampPeriod(_timestamp), MAX_CARDINALITY))
    ];

    // increase lastAvailableAuctionStartTime with elapsed time (based on quantity)
    lastAvailableAuctionStartTime += uint32(
      uint256(convert(convert(int256(_amountOut)).div(emissionRate)))
    );

    // Remove from current auctions allocation
    currentAuction.amountClaimed = uint128(currentAuction.amountClaimed + _amountOut);

    // Update next auctions target price based on swap price
    // SD59x18 swapPrice = convert(int256(_amountIn)).div(convert(int256(_amountOut)));
    // nextAuction.targetPrice = nextAuction.targetPrice.add(swapPrice).div(convert(2));
  }
}
