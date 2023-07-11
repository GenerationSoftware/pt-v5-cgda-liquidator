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

  SD59x18 public immutable decayConstant;

  /// @notice Sets the minimum period length for auctions. When a period elapses a new auction begins.
  uint32 public immutable PERIOD_LENGTH;

  /// @notice Sets the beginning timestamp for the first period.
  /// @dev Ensure that the PERIOD_OFFSET is in the past.
  uint32 public immutable PERIOD_OFFSET;

  uint32 public immutable targetFirstSaleTime;

  /// @notice Storage for the auction.
  Auction internal _auction;

  /* ============ Structs ============ */

  struct Auction {
    uint112 amountIn;
    uint112 amountOut;
    uint32 lastAuctionTime;
    uint16 period;
    SD59x18 emissionRate;
    SD59x18 initialPrice;
  }

  int public auctionTimeOffset;

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
    require(targetFirstSaleTime < PERIOD_LENGTH, "targetFirstSaleTime must be less than PERIOD_LENGTH");

    // console2.log("GOT HEREEEE");

    SD59x18 emissionRate = _computeEmissionRate();
    
    // console2.log("GOT HEREEEE 22222");

    SD59x18 initialPrice = _computeK(emissionRate, _initialAmountIn, _initialAmountOut);


    // console2.log("GOT HEREEEE 3433");

    _setAuction(
      Auction({
        lastAuctionTime: PERIOD_OFFSET,
        amountIn: 0,
        amountOut: 0,
        period: 0,
        emissionRate: emissionRate,
        initialPrice: initialPrice
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
    uint emissions = uint(convert(auction.emissionRate.mul(_getElapsedTime(auction.lastAuctionTime))));
    uint liquidatable = source.liquidatableBalanceOf(tokenOut);
    return emissions > liquidatable ? liquidatable : emissions;
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
    SD59x18 elapsed = _getElapsedTime(auction.lastAuctionTime);
    uint amountIn = ContinuousGDA.purchasePrice(
      _amountOut,
      auction.emissionRate,
      auction.initialPrice,
      decayConstant,
      elapsed
    );
    require(amountIn <= _amountInMax, "exceeds max amount in");

    // console2.log("lastAuctionTime: ", auction.lastAuctionTime);
    // console2.log("period: ", auction.period);

    // increase lastAvailableAuctionStartTime with elapsed time (based on quantity)
    
    auction.amountIn += uint112(amountIn);
    auction.amountOut += uint112(_amountOut);
    auction.lastAuctionTime += uint32(
      uint256(convert(convert(int256(_amountOut)).div(auction.emissionRate)))
    );
    _setAuction(auction);
    _swap(_account, _amountOut, amountIn);



    // console2.log("auctionTimeOffset: ", auctionTimeOffset);

    // console2.log("amountOut: ", _amountOut);
    // console2.log("auction.initialPrice: ", convert(auction.initialPrice));
    // SD59x18 currentPrice = convert(int256(amountIn)).div(convert(int256(_amountOut)));
    // console2.log("currentPrice: ", currentPrice.unwrap());
    // console2.log("priceAverage: ", priceAverage.unwrap());
    // SD59x18 addition = currentPrice.mul(convert(1).sub(smoothing));
    // console2.log("addition: ", addition.unwrap());
    // SD59x18 muller = priceAverage.mul(smoothing);
    // console2.log("muller: ", muller.unwrap());
    // priceAverage = muller.add(addition);
    // console2.log("new priceAverage: ", convert(priceAverage));

    // AuctionPerSecond

    return amountIn;
  }

  /* ============ Internal Functions ============ */

  function _swap(address _account, uint256 _amountOut, uint256 _amountIn) internal {
    source.liquidate(_account, tokenIn, _amountIn, tokenOut, _amountOut);
  }

  function _computeEmissionRate() internal view returns (SD59x18) {
    return convert(int256(source.liquidatableBalanceOf(tokenOut))).div(convert(int32(PERIOD_LENGTH)));
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
    SD59x18 elapsed = _getElapsedTime(auction.lastAuctionTime);
    uint purchasePrice;

    (bool success, bytes memory returnData) =
      address(this).delegatecall(
        abi.encodeWithSelector(
          this.computePurchasePrice.selector,
          _amountOut,
          auction.initialPrice,
          auction.emissionRate,
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

  function computePurchasePrice(uint256 _amountOut, SD59x18 _initialPrice, SD59x18 _emissionRate, SD59x18 _elapsed) public view returns (uint256) {
    return ContinuousGDA.purchasePrice(
      _amountOut,
      _emissionRate,
      _initialPrice,
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
      uint startTime = PERIOD_OFFSET + PERIOD_LENGTH * currentPeriod;
      SD59x18 emissionRate = _computeEmissionRate();
      SD59x18 initialPrice = _computeK(emissionRate, auction.amountIn, auction.amountOut);
      auction = Auction({
        amountIn: 0,
        amountOut: 0,
        lastAuctionTime: uint32(startTime),
        period: currentPeriod,
        emissionRate: emissionRate,
        initialPrice: initialPrice
      });
    }

    return auction;
  }

  function _setAuction(Auction memory auction) internal {
    _auction = auction;
  }

  function getPeriodStart() external view returns (uint32) {
    return _getPeriodStart(_getPeriod(uint32(block.timestamp)));
  }

  function getPeriodEnd() external view returns (uint32) {
    return _getPeriodEnd(_getPeriod(uint32(block.timestamp)));
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
    SD59x18 exchangeRateAmountInToAmountOut = _amountOut > 0 ? convert(int(uint(_amountIn))).div(convert(int(uint(_amountOut)))) : wrap(0);
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
