// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

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

  SD59x18 public immutable decayConstant;

  /// @notice Sets the minimum period length for auctions. When a period elapses a new auction begins.
  uint32 public immutable PERIOD_LENGTH;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the PERIOD_OFFSET is in the past.
  uint32 public immutable PERIOD_OFFSET;

  /// @notice Storage for the auction.
  Auction internal _auction;

  /* ============ Structs ============ */

  struct Auction {
    uint104 amountAccrued;
    uint104 amountClaimed;
    uint16 period;
    uint32 lastAuctionTime;
    SD59x18 targetPrice;
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
    decayConstant = _decayConstant;
    PERIOD_LENGTH = _periodLength;
    PERIOD_OFFSET = _periodOffset;

    _setAuction(
      Auction({
        lastAuctionTime: PERIOD_OFFSET,
        amountAccrued: uint104(source.liquidatableBalanceOf(tokenOut)),
        amountClaimed: 0,
        period: 0,
        targetPrice: _initialPrice
      })
    );
  }

  /* ============ External Read Methods ============ */

  /// @inheritdoc ILiquidationPair
  function target() external view returns (address) {
    return source.targetOf(tokenIn);
  }

  /// @inheritdoc ILiquidationPair
  function maxAmountOut() external returns (uint256) {
    return _maxAmountOut(_getAuction(uint32(block.timestamp)));
  }

  function _maxAmountOut(Auction memory auction) internal returns (uint256) {
    return uint256(auction.amountAccrued) - auction.amountClaimed;
  }

  /// @inheritdoc ILiquidationPair
  function computeExactAmountIn(uint256 _amountOut) external returns (uint256) {
    if (_amountOut == 0) {
      return 0;
    }
    return _computeExactAmountIn(_amountOut, uint32(block.timestamp));
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
    Auction memory auction = _getAuction(uint32(block.timestamp));
    require(_amountOut <= _maxAmountOut(auction), "exceeds available");
    SD59x18 emissionRate = _getEmissionRate(auction.amountAccrued);
    SD59x18 elapsed = _getElapsedTime(auction.lastAuctionTime);
    uint amountIn = ContinuousGDA.purchasePrice(
      _amountOut,
      emissionRate,
      auction.targetPrice,
      decayConstant,
      elapsed
    );
    require(amountIn <= _amountInMax, "exceeds max amount in");

    // increase lastAvailableAuctionStartTime with elapsed time (based on quantity)
    auction.lastAuctionTime += uint32(
      uint256(convert(convert(int256(_amountOut)).div(emissionRate)))
    );
    // Remove from current auctions allocation
    auction.amountClaimed = uint104(auction.amountClaimed + _amountOut);
    _setAuction(auction);

    _swap(_account, _amountOut, amountIn);

    return amountIn;
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  function _getEmissionRate(uint256 amountAccrued) internal view returns (SD59x18) {
    // a^2/t
    // return convert(int256(amountAccrued)).pow(convert(2)).div(convert(int32(PERIOD_LENGTH)));
    // a/t
    return convert(int256(amountAccrued)).div(convert(int32(PERIOD_LENGTH)));
  }

  function _getElapsedTime(uint256 _lastAuctionTime) internal view returns (SD59x18) {
    return convert(int256(block.timestamp)).sub(convert(int256(_lastAuctionTime)));
  }

  function _computeExactAmountIn(
    uint256 _amountOut,
    uint32 _timestamp
  ) internal returns (uint256) {
    Auction memory auction = _getAuction(_timestamp);
    require(_amountOut <= _maxAmountOut(auction), "exceeds available");
    SD59x18 emissionRate = _getEmissionRate(auction.amountAccrued);
    SD59x18 elapsed = _getElapsedTime(auction.lastAuctionTime);
    uint purchasePrice;

    (bool success, bytes memory returnData) =
      address(this).delegatecall(
        abi.encodeWithSelector(
          this.computePurchasePrice.selector,
          _amountOut,
          auction.targetPrice,
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

  function computePurchasePrice(uint256 _amountOut, SD59x18 _targetPrice, SD59x18 _emissionRate, SD59x18 _elapsed) public view returns (uint256) {
    return ContinuousGDA.purchasePrice(
      _amountOut,
      _emissionRate,
      _targetPrice,
      decayConstant,
      _elapsed
    );
  }

  function getAuction() external returns (Auction memory) {
    return _getAuction(uint32(block.timestamp));
  }

  function getElapsedTime() external returns (int256) {
    return convert(_getElapsedTime(_auction.lastAuctionTime));
  }

  function _getAuction(uint32 _timestamp) internal returns (Auction memory) {
    Auction memory auction = _auction;

    uint16 currentPeriod = _getPeriod(_timestamp);
    if (currentPeriod != auction.period) {
      auction = Auction({
        lastAuctionTime: PERIOD_OFFSET + PERIOD_LENGTH * currentPeriod,
        amountAccrued: uint104(source.liquidatableBalanceOf(tokenOut)),
        amountClaimed: 0,
        period: currentPeriod,
        targetPrice: auction.targetPrice
      });
    }

    return auction;
  }

  function _setAuction(Auction memory auction) internal {
    _auction = auction;
  }

  function _getPeriodStart(uint32 _period) internal view returns (uint32) {
    return PERIOD_OFFSET + _period * PERIOD_LENGTH;
  }

  function _getPeriodEnd(uint32 _period) internal view returns (uint32) {
    return _getPeriodStart(_period) + PERIOD_LENGTH;
  }

  function _getPeriod(uint32 _timestamp) internal view returns (uint16) {
    if (_timestamp < PERIOD_OFFSET) {
      return 0;
    }
    return uint16((_timestamp - PERIOD_OFFSET) / PERIOD_LENGTH);
  }
}
