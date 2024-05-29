// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ILayerZeroPriceFeed {
    /**
     * @dev
     * priceRatio: (USD price of 1 unit of remote native token in unit of local native token) * PRICE_RATIO_DENOMINATOR
     */

    struct Price {
        uint128 priceRatio; // float value * 10 ^ 20, decimal awared. for aptos to evm, the basis would be (10^18 / 10^8) * 10 ^20 = 10 ^ 30.
        uint64 gasPriceInUnit; // for evm, it is in wei, for aptos, it is in octas.
        uint32 gasPerByte;
    }

    struct UpdatePrice {
        uint32 eid;
        Price price;
    }

    /**
     * @dev
     *    ArbGasInfo.go:GetPricesInArbGas
     *
     */
    struct ArbitrumPriceExt {
        uint64 gasPerL2Tx; // L2 overhead
        uint32 gasPerL1CallDataByte;
    }

    struct UpdatePriceExt {
        uint32 eid;
        Price price;
        ArbitrumPriceExt extend;
    }

    error LZ_PriceFeed_OnlyPriceUpdater();
    error LZ_PriceFeed_InsufficientFee(uint256 provided, uint256 required);
    error LZ_PriceFeed_UnknownL2Eid(uint32 l2Eid);

    function nativeTokenPriceUSD() external view returns (uint128);

    function getFee(uint32 _dstEid, uint256 _callDataSize, uint256 _gas) external view returns (uint256);

    function getPrice(uint32 _dstEid) external view returns (Price memory);

    function getPriceRatioDenominator() external view returns (uint128);

    function estimateFeeByEid(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) external view returns (uint256 fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD);

    function estimateFeeOnSend(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) external payable returns (uint256 fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 nativePriceUSD);
}
