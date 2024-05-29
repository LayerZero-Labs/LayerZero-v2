// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ILayerZeroPriceFeed } from "../../contracts/interfaces/ILayerZeroPriceFeed.sol";

contract PriceFeedMock is ILayerZeroPriceFeed {
    uint128 PRICE_RATIO_DENOMINATOR = 1e10;
    uint128 public nativeTokenPriceUSD;
    uint128 tokensPriceRatio;
    uint256 gasFee;

    function setup(uint256 _fee, uint128 _priceRatio, uint128 _nativeTokenPriceUSD) external {
        gasFee = _fee;
        tokensPriceRatio = _priceRatio;
        nativeTokenPriceUSD = _nativeTokenPriceUSD;
    }

    function getFee(uint32, uint256, uint256) public pure returns (uint256) {
        return 0;
    }

    function getPrice(uint32) external view override returns (Price memory price) {
        price = Price(tokensPriceRatio, 0, 0);
    }

    function getPriceRatioDenominator() external view override returns (uint128) {
        return PRICE_RATIO_DENOMINATOR;
    }

    function estimateFeeByEid(
        uint32,
        uint256,
        uint256
    )
        external
        view
        override
        returns (uint256 fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD)
    {
        return (gasFee, tokensPriceRatio, PRICE_RATIO_DENOMINATOR, nativeTokenPriceUSD);
    }

    function estimateFeeOnSend(
        uint32,
        uint256,
        uint256
    )
        external
        payable
        override
        returns (uint256 fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD)
    {
        return (gasFee, tokensPriceRatio, PRICE_RATIO_DENOMINATOR, nativeTokenPriceUSD);
    }
}
