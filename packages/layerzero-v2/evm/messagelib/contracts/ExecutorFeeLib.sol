// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

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
        if (_dstConfig.lzReceiveBaseGas == 0) revert Executor_EidNotSupported(_params.dstEid);

        (uint256 totalDstAmount, uint256 totalGas) = _decodeExecutorOptions(
            _isV1Eid(_params.dstEid),
            _dstConfig.lzReceiveBaseGas,
            _dstConfig.lzComposeBaseGas,
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

        uint16 multiplierBps = _dstConfig.multiplierBps == 0 ? _params.defaultMultiplierBps : _dstConfig.multiplierBps;

        fee = _applyPremiumToGas(totalGasFee, multiplierBps, _dstConfig.floorMarginUSD, nativePriceUSD);
        fee += _convertAndApplyPremiumToValue(totalDstAmount, priceRatio, priceRatioDenominator, multiplierBps);
    }

    // ================================ View ================================
    function getFee(
        FeeParams calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 fee) {
        if (_dstConfig.lzReceiveBaseGas == 0) revert Executor_EidNotSupported(_params.dstEid);

        (uint256 totalDstAmount, uint256 totalGas) = _decodeExecutorOptions(
            _isV1Eid(_params.dstEid),
            _dstConfig.lzReceiveBaseGas,
            _dstConfig.lzComposeBaseGas,
            _dstConfig.nativeCap,
            _options
        );

        (
            uint256 totalGasFee,
            uint128 priceRatio,
            uint128 priceRatioDenominator,
            uint128 nativePriceUSD
        ) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeByEid(_params.dstEid, _params.calldataSize, totalGas);

        uint16 multiplierBps = _dstConfig.multiplierBps == 0 ? _params.defaultMultiplierBps : _dstConfig.multiplierBps;

        fee = _applyPremiumToGas(totalGasFee, multiplierBps, _dstConfig.floorMarginUSD, nativePriceUSD);
        fee += _convertAndApplyPremiumToValue(totalDstAmount, priceRatio, priceRatioDenominator, multiplierBps);
    }

    // ================================ Internal ================================
    // @dev decode executor options into dstAmount and totalGas
    function _decodeExecutorOptions(
        bool _v1Eid,
        uint64 _lzReceiveBaseGas,
        uint64 _lzComposeBaseGas,
        uint128 _nativeCap,
        bytes calldata _options
    ) internal pure returns (uint256 dstAmount, uint256 totalGas) {
        if (_options.length == 0) {
            revert Executor_NoOptions();
        }

        uint256 cursor = 0;
        bool ordered = false;
        totalGas = _lzReceiveBaseGas; // lz receive only called once

        bool v1Eid = _v1Eid; // stack too deep
        uint256 lzReceiveGas;
        while (cursor < _options.length) {
            (uint8 optionType, bytes calldata option, uint256 newCursor) = _options.nextExecutorOption(cursor);
            cursor = newCursor;

            if (optionType == ExecutorOptions.OPTION_TYPE_LZRECEIVE) {
                (uint128 gas, uint128 value) = ExecutorOptions.decodeLzReceiveOption(option);

                // endpoint v1 does not support lzReceive with value
                if (v1Eid && value > 0) revert Executor_UnsupportedOptionType(optionType);

                dstAmount += value;
                lzReceiveGas += gas;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_NATIVE_DROP) {
                (uint128 nativeDropAmount, ) = ExecutorOptions.decodeNativeDropOption(option);
                dstAmount += nativeDropAmount;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_LZCOMPOSE) {
                // endpoint v1 does not support lzCompose
                if (v1Eid) revert Executor_UnsupportedOptionType(optionType);

                (, uint128 gas, uint128 value) = ExecutorOptions.decodeLzComposeOption(option);
                if (gas == 0) revert Executor_ZeroLzComposeGasProvided();

                dstAmount += value;
                // lz compose can be called multiple times, based on unique index
                // to simplify the quoting, we add lzComposeBaseGas for each lzComposeOption received
                // if the same index has multiple compose options, the gas will be added multiple times
                totalGas += gas + _lzComposeBaseGas;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_ORDERED_EXECUTION) {
                ordered = true;
            } else {
                revert Executor_UnsupportedOptionType(optionType);
            }
        }
        if (cursor != _options.length) revert Executor_InvalidExecutorOptions(cursor);
        if (dstAmount > _nativeCap) revert Executor_NativeAmountExceedsCap(dstAmount, _nativeCap);
        if (lzReceiveGas == 0) revert Executor_ZeroLzReceiveGasProvided();
        totalGas += lzReceiveGas;

        if (ordered) {
            totalGas = (totalGas * 102) / 100;
        }
    }

    function _applyPremiumToGas(
        uint256 _fee,
        uint16 _multiplierBps,
        uint128 _marginUSD,
        uint128 _nativePriceUSD
    ) internal view returns (uint256) {
        uint256 feeWithMultiplier = (_fee * _multiplierBps) / 10000;

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
        uint16 _multiplierBps
    ) internal pure returns (uint256 fee) {
        if (_value > 0) {
            fee = (((_value * _ratio) / _denom) * _multiplierBps) / 10000;
        }
    }

    function _isV1Eid(uint32 _eid) internal pure virtual returns (bool) {
        // v1 eid is < 30000
        return _eid < 30000;
    }

    // send funds here to pay for price feed directly
    receive() external payable {}
}
