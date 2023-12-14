// SPDX-License-Identifier: LZBL-1.2

pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";
import { ExecutorOptions } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/ExecutorOptions.sol";

import { ILayerZeroPriceFeed } from "./interfaces/ILayerZeroPriceFeed.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { IExecutorFeeLib } from "./interfaces/IExecutorFeeLib.sol";

contract ExecutorFeeLib is Ownable, IExecutorFeeLib {
    using ExecutorOptions for bytes;

    uint256 private immutable nativeDecimalsRate;

    constructor(uint256 _nativeDecimalsRate) {
        nativeDecimalsRate = _nativeDecimalsRate;
    }

    // ================================ OnlyOwner ================================
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
    }

    // ================================ External ================================
    function getFeeOnSend(
        FeeParams calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external returns (uint256 fee) {
        (uint256 totalDstAmount, uint256 totalGas) = _decodeExecutorOptions(
            _isV1Eid(_params.dstEid),
            _dstConfig.baseGas,
            _dstConfig.nativeCap,
            _options
        );

        // for future versions where priceFeed charges a fee
        (
            uint256 totalGasFee,
            uint128 priceRatio,
            uint128 priceRatioDenominator,
            uint128 nativePriceUSD
        ) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeOnSend(_params.dstEid, _params.calldataSize, totalGas);

        fee = _applyPremiumToGas(
            totalGasFee,
            _dstConfig.multiplierBps,
            _params.defaultMultiplierBps,
            _dstConfig.floorMarginUSD,
            nativePriceUSD
        );
        fee += _convertAndApplyPremiumToValue(
            totalDstAmount,
            priceRatio,
            priceRatioDenominator,
            _params.defaultMultiplierBps
        );
    }

    // ================================ View ================================
    function getFee(
        FeeParams calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 fee) {
        (uint256 totalDstAmount, uint256 totalGas) = _decodeExecutorOptions(
            _isV1Eid(_params.dstEid),
            _dstConfig.baseGas,
            _dstConfig.nativeCap,
            _options
        );

        (
            uint256 totalGasFee,
            uint128 priceRatio,
            uint128 priceRatioDenominator,
            uint128 nativePriceUSD
        ) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeByEid(_params.dstEid, _params.calldataSize, totalGas);

        fee = _applyPremiumToGas(
            totalGasFee,
            _dstConfig.multiplierBps,
            _params.defaultMultiplierBps,
            _dstConfig.floorMarginUSD,
            nativePriceUSD
        );
        fee += _convertAndApplyPremiumToValue(
            totalDstAmount,
            priceRatio,
            priceRatioDenominator,
            _params.defaultMultiplierBps
        );
    }

    // ================================ Internal ================================
    // @dev decode executor options into dstAmount and totalGas
    function _decodeExecutorOptions(
        bool _v1Eid,
        uint64 _baseGas,
        uint128 _nativeCap,
        bytes calldata _options
    ) internal pure returns (uint256 dstAmount, uint256 totalGas) {
        if (_options.length == 0) {
            revert NoOptions();
        }

        uint256 cursor = 0;
        bool ordered = false;
        totalGas = _baseGas;

        while (cursor < _options.length) {
            (uint8 optionType, bytes calldata option, uint256 newCursor) = _options.nextExecutorOption(cursor);
            cursor = newCursor;

            if (optionType == ExecutorOptions.OPTION_TYPE_LZRECEIVE) {
                (uint128 gas, uint128 value) = ExecutorOptions.decodeLzReceiveOption(option);

                // endpoint v1 does not support lzReceive with value
                if (_v1Eid && value > 0) revert UnsupportedOptionType(optionType);

                dstAmount += value;
                totalGas += gas;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_NATIVE_DROP) {
                (uint128 nativeDropAmount, ) = ExecutorOptions.decodeNativeDropOption(option);
                dstAmount += nativeDropAmount;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_LZCOMPOSE) {
                // endpoint v1 does not support lzCompose
                if (_v1Eid) revert UnsupportedOptionType(optionType);

                (, uint128 gas, uint128 value) = ExecutorOptions.decodeLzComposeOption(option);
                dstAmount += value;
                totalGas += gas;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_ORDERED_EXECUTION) {
                ordered = true;
            } else {
                revert UnsupportedOptionType(optionType);
            }
        }
        if (cursor != _options.length) revert InvalidExecutorOptions(cursor);
        if (dstAmount > _nativeCap) revert NativeAmountExceedsCap(dstAmount, _nativeCap);

        if (ordered) {
            // todo: finalize the premium for ordered
            totalGas = (totalGas * 102) / 100;
        }
    }

    function _applyPremiumToGas(
        uint256 _fee,
        uint16 _bps,
        uint16 _defaultBps,
        uint128 _marginUSD,
        uint128 _nativePriceUSD
    ) internal view returns (uint256) {
        uint16 multiplierBps = _bps == 0 ? _defaultBps : _bps;

        uint256 feeWithMultiplier = (_fee * multiplierBps) / 10000;

        if (_nativePriceUSD == 0 || _marginUSD == 0) {
            return feeWithMultiplier;
        }
        uint256 feeWithMargin = (_marginUSD * nativeDecimalsRate) / _nativePriceUSD + _fee;
        return feeWithMargin > feeWithMultiplier ? feeWithMargin : feeWithMultiplier;
    }

    // includes value and nativeDrop
    function _convertAndApplyPremiumToValue(
        uint256 _value,
        uint128 _ratio,
        uint128 _denom,
        uint16 _defaultBps
    ) internal pure returns (uint256 fee) {
        if (_value > 0) {
            fee = (((_value * _ratio) / _denom) * _defaultBps) / 10000;
        }
    }

    function _isV1Eid(uint32 _eid) internal pure virtual returns (bool) {
        // v1 eid is < 30000
        return _eid < 30000;
    }

    // send funds here to pay for price feed directly
    receive() external payable {}
}
