// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";

import { ILayerZeroEndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroPriceFeed } from "./interfaces/ILayerZeroPriceFeed.sol";

// PriceFeed is updated based on v1 eids
// v2 eids will fall to the convention of v1 eid + 30,000
contract PriceFeed is ILayerZeroPriceFeed, OwnableUpgradeable, Proxied {
    uint128 internal PRICE_RATIO_DENOMINATOR;

    // sets pricing
    mapping(address updater => bool active) public priceUpdater;

    mapping(uint32 dstEid => Price) internal _defaultModelPrice;
    ArbitrumPriceExt internal _arbitrumPriceExt;

    uint128 internal _nativePriceUSD; // uses PRICE_RATIO_DENOMINATOR

    // upgrade: arbitrum compression - percentage of callDataSize after brotli compression
    uint128 public ARBITRUM_COMPRESSION_PERCENT;

    ILayerZeroEndpointV2 public endpoint;

    // ============================ Constructor ===================================

    function initialize(address _priceUpdater) public proxied initializer {
        __Ownable_init();
        priceUpdater[_priceUpdater] = true;
        PRICE_RATIO_DENOMINATOR = 1e20;
        ARBITRUM_COMPRESSION_PERCENT = 47;
    }

    // ============================ Modifier ======================================

    // owner is always approved
    modifier onlyPriceUpdater() {
        if (owner() != msg.sender) {
            if (!priceUpdater[msg.sender]) {
                revert LZ_PriceFeed_OnlyPriceUpdater();
            }
        }
        _;
    }

    // ============================ OnlyOwner =====================================

    function setPriceUpdater(address _addr, bool _active) external onlyOwner {
        priceUpdater[_addr] = _active;
    }

    function setPriceRatioDenominator(uint128 _denominator) external onlyOwner {
        PRICE_RATIO_DENOMINATOR = _denominator;
    }

    function setArbitrumCompressionPercent(uint128 _compressionPercent) external onlyOwner {
        ARBITRUM_COMPRESSION_PERCENT = _compressionPercent;
    }

    function setEndpoint(address _endpoint) external onlyOwner {
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function withdrawFee(address _to, uint256 _amount) external onlyOwner {
        Transfer.native(_to, _amount);
    }

    // ============================ OnlyPriceUpdater =====================================

    function setPrice(UpdatePrice[] calldata _price) external onlyPriceUpdater {
        for (uint256 i = 0; i < _price.length; i++) {
            UpdatePrice calldata _update = _price[i];
            _setPrice(_update.eid, _update.price);
        }
    }

    function setPriceForArbitrum(UpdatePriceExt calldata _update) external onlyPriceUpdater {
        _setPrice(_update.eid, _update.price);

        uint64 gasPerL2Tx = _update.extend.gasPerL2Tx;
        uint32 gasPerL1CalldataByte = _update.extend.gasPerL1CallDataByte;

        _arbitrumPriceExt.gasPerL2Tx = gasPerL2Tx;
        _arbitrumPriceExt.gasPerL1CallDataByte = gasPerL1CalldataByte;
    }

    function setNativeTokenPriceUSD(uint128 _nativeTokenPriceUSD) external onlyPriceUpdater {
        _nativePriceUSD = _nativeTokenPriceUSD;
    }

    // ============================ External =====================================

    function estimateFeeOnSend(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) external payable returns (uint256, uint128, uint128, uint128) {
        uint256 fee = getFee(_dstEid, _callDataSize, _gas);
        if (msg.value < fee) revert LZ_PriceFeed_InsufficientFee(msg.value, fee);
        return _estimateFeeByEid(_dstEid, _callDataSize, _gas);
    }

    // ============================ View ==========================================

    // get fee for calling estimateFeeOnSend
    function getFee(uint32 /*_dstEid*/, uint256 /*_callDataSize*/, uint256 /*_gas*/) public pure returns (uint256) {
        return 0;
    }

    function getPriceRatioDenominator() external view returns (uint128) {
        return PRICE_RATIO_DENOMINATOR;
    }

    // NOTE: to be reverted when endpoint is in sendContext
    function nativeTokenPriceUSD() external view returns (uint128) {
        return _nativePriceUSD;
    }

    // NOTE: to be reverted when endpoint is in sendContext
    function arbitrumPriceExt() external view returns (ArbitrumPriceExt memory) {
        return _arbitrumPriceExt;
    }

    // NOTE: to be reverted when endpoint is in sendContext
    function getPrice(uint32 _dstEid) external view returns (Price memory price) {
        price = _defaultModelPrice[_dstEid];
    }

    // NOTE: to be reverted when endpoint is in sendContext
    function estimateFeeByEid(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) external view returns (uint256, uint128, uint128, uint128) {
        return _estimateFeeByEid(_dstEid, _callDataSize, _gas);
    }

    // NOTE: to be reverted when endpoint is in sendContext
    // NOTE: to support legacy
    function getPrice(uint16 _dstEid) external view returns (Price memory price) {
        price = _defaultModelPrice[_dstEid];
    }

    // NOTE: to be reverted when endpoint is in sendContext
    // NOTE: to support legacy
    function estimateFeeByChain(
        uint16 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) external view returns (uint256 fee, uint128 priceRatio) {
        if (_dstEid == 110 || _dstEid == 10143 || _dstEid == 20143) {
            return _estimateFeeWithArbitrumModel(_dstEid, _callDataSize, _gas);
        } else if (_dstEid == 111 || _dstEid == 10132 || _dstEid == 20132) {
            return _estimateFeeWithOptimismModel(_dstEid, _callDataSize, _gas);
        } else {
            return _estimateFeeWithDefaultModel(_dstEid, _callDataSize, _gas);
        }
    }

    // ============================ Internal ==========================================

    function _setPrice(uint32 _dstEid, Price memory _price) internal {
        uint128 priceRatio = _price.priceRatio;
        uint64 gasPriceInUnit = _price.gasPriceInUnit;
        uint32 gasPerByte = _price.gasPerByte;
        _defaultModelPrice[_dstEid] = Price(priceRatio, gasPriceInUnit, gasPerByte);
    }

    function _getL1LookupId(uint32 _l2Eid) internal pure returns (uint32) {
        uint32 l2Eid = _l2Eid % 30_000;
        if (l2Eid == 111) {
            return 101;
        } else if (l2Eid == 10132) {
            return 10121; // ethereum-goerli
        } else if (l2Eid == 20132) {
            return 20121; // ethereum-goerli
        }
        revert LZ_PriceFeed_UnknownL2Eid(l2Eid);
    }

    function _estimateFeeWithDefaultModel(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) internal view returns (uint256 fee, uint128 priceRatio) {
        Price storage remotePrice = _defaultModelPrice[_dstEid];

        // assuming the _gas includes (1) the 21,000 overhead and (2) not the calldata gas
        uint256 gasForCallData = _callDataSize * remotePrice.gasPerByte;
        uint256 remoteFee = (gasForCallData + _gas) * remotePrice.gasPriceInUnit;
        return ((remoteFee * remotePrice.priceRatio) / PRICE_RATIO_DENOMINATOR, remotePrice.priceRatio);
    }

    function _estimateFeeByEid(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) internal view returns (uint256 fee, uint128 priceRatio, uint128 priceRatioDenominator, uint128 priceUSD) {
        uint32 dstEid = _dstEid % 30_000;
        if (dstEid == 110 || dstEid == 10143 || dstEid == 20143) {
            (fee, priceRatio) = _estimateFeeWithArbitrumModel(dstEid, _callDataSize, _gas);
        } else if (dstEid == 111 || dstEid == 10132 || dstEid == 20132) {
            (fee, priceRatio) = _estimateFeeWithOptimismModel(dstEid, _callDataSize, _gas);
        } else {
            (fee, priceRatio) = _estimateFeeWithDefaultModel(dstEid, _callDataSize, _gas);
        }
        priceRatioDenominator = PRICE_RATIO_DENOMINATOR;
        priceUSD = _nativePriceUSD;
    }

    function _estimateFeeWithOptimismModel(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) internal view returns (uint256 fee, uint128 priceRatio) {
        uint32 ethereumId = _getL1LookupId(_dstEid);

        // L1 fee
        Price storage ethereumPrice = _defaultModelPrice[ethereumId];
        uint256 gasForL1CallData = (_callDataSize * ethereumPrice.gasPerByte) + 3188; // 2100 + 68 * 16
        uint256 l1Fee = gasForL1CallData * ethereumPrice.gasPriceInUnit;

        // L2 fee
        Price storage optimismPrice = _defaultModelPrice[_dstEid];
        uint256 gasForL2CallData = _callDataSize * optimismPrice.gasPerByte;
        uint256 l2Fee = (gasForL2CallData + _gas) * optimismPrice.gasPriceInUnit;

        uint256 l1FeeInSrcPrice = (l1Fee * ethereumPrice.priceRatio) / PRICE_RATIO_DENOMINATOR;
        uint256 l2FeeInSrcPrice = (l2Fee * optimismPrice.priceRatio) / PRICE_RATIO_DENOMINATOR;
        uint256 gasFee = l1FeeInSrcPrice + l2FeeInSrcPrice;
        return (gasFee, optimismPrice.priceRatio);
    }

    function _estimateFeeWithArbitrumModel(
        uint32 _dstEid,
        uint256 _callDataSize,
        uint256 _gas
    ) internal view returns (uint256 fee, uint128 priceRatio) {
        Price storage arbitrumPrice = _defaultModelPrice[_dstEid];

        // L1 fee
        uint256 gasForL1CallData = ((_callDataSize * ARBITRUM_COMPRESSION_PERCENT) / 100) *
            _arbitrumPriceExt.gasPerL1CallDataByte;
        // L2 Fee
        uint256 gasForL2CallData = _callDataSize * arbitrumPrice.gasPerByte;
        uint256 gasFee = (_gas + _arbitrumPriceExt.gasPerL2Tx + gasForL1CallData + gasForL2CallData) *
            arbitrumPrice.gasPriceInUnit;

        return ((gasFee * arbitrumPrice.priceRatio) / PRICE_RATIO_DENOMINATOR, arbitrumPrice.priceRatio);
    }
}
