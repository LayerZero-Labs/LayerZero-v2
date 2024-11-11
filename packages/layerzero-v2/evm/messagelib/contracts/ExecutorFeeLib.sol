// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroPriceFeed } from "./interfaces/ILayerZeroPriceFeed.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { IExecutorFeeLib } from "./interfaces/IExecutorFeeLib.sol";
import { ExecutorOptions } from "./libs/ExecutorOptions.sol";

contract ExecutorFeeLib is Ownable, IExecutorFeeLib {
    using ExecutorOptions for bytes;

    uint256 private immutable nativeDecimalsRate;
    uint32 private immutable localEidV2; // endpoint-v2 only, for read call

    constructor(uint32 _localEidV2, uint256 _nativeDecimalsRate) {
        localEidV2 = _localEidV2;
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
    ) external view returns (uint256 fee) {
        fee = getFee(_params, _dstConfig, _options);
    }

    function getFeeOnSend(
        FeeParamsForRead calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 fee) {
        fee = getFee(_params, _dstConfig, _options);
    }

    // ================================ View ================================
    function getFee(
        FeeParams calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) public view returns (uint256 fee) {
        if (_dstConfig.lzReceiveBaseGas == 0) revert Executor_EidNotSupported(_params.dstEid);

        (uint256 totalValue, uint256 totalGas, ) = _decodeExecutorOptions(
            false,
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
        fee += _convertAndApplyPremiumToValue(totalValue, priceRatio, priceRatioDenominator, multiplierBps);
    }

    function getFee(
        FeeParamsForRead calldata _params,
        IExecutor.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) public view returns (uint256 fee) {
        if (_dstConfig.lzReceiveBaseGas == 0) revert Executor_EidNotSupported(localEidV2);

        (uint256 totalValue, uint256 totalGas, uint32 calldataSize) = _decodeExecutorOptions(
            true,
            false, // endpoint v2 only
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
        ) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeByEid(localEidV2, calldataSize, totalGas);

        uint16 multiplierBps = _dstConfig.multiplierBps == 0 ? _params.defaultMultiplierBps : _dstConfig.multiplierBps;

        fee = _applyPremiumToGas(totalGasFee, multiplierBps, _dstConfig.floorMarginUSD, nativePriceUSD);
        fee += _convertAndApplyPremiumToValue(totalValue, priceRatio, priceRatioDenominator, multiplierBps);
    }

    // ================================ Internal ================================
    // @dev decode executor options into dstAmount and totalGas
    function _decodeExecutorOptions(
        bool _isRead,
        bool _v1Eid,
        uint64 _lzReceiveBaseGas,
        uint64 _lzComposeBaseGas,
        uint128 _nativeCap,
        bytes calldata _options
    ) internal pure returns (uint256 totalValue, uint256 totalGas, uint32 calldataSize) {
        ExecutorOptionsAgg memory aggOptions = _parseExecutorOptions(_options, _isRead, _v1Eid, _nativeCap);
        totalValue = aggOptions.totalValue;
        calldataSize = aggOptions.calldataSize;

        // lz receive only called once
        // lz compose can be called multiple times, based on unique index
        // to simplify the quoting, we add lzComposeBaseGas for each lzComposeOption received
        // if the same index has multiple compose options, the gas will be added multiple times
        totalGas = _lzReceiveBaseGas + aggOptions.totalGas + _lzComposeBaseGas * aggOptions.numLzCompose;
        if (aggOptions.ordered) {
            totalGas = (totalGas * 102) / 100;
        }
    }

    struct ExecutorOptionsAgg {
        uint256 totalValue;
        uint256 totalGas;
        bool ordered;
        uint32 calldataSize;
        uint256 numLzCompose;
    }

    function _parseExecutorOptions(
        bytes calldata _options,
        bool _isRead,
        bool _v1Eid,
        uint128 _nativeCap
    ) internal pure returns (ExecutorOptionsAgg memory options) {
        if (_options.length == 0) {
            revert Executor_NoOptions();
        }

        uint256 cursor = 0;
        uint256 lzReceiveGas;
        uint32 calldataSize;
        while (cursor < _options.length) {
            (uint8 optionType, bytes calldata option, uint256 newCursor) = _options.nextExecutorOption(cursor);
            cursor = newCursor;

            if (optionType == ExecutorOptions.OPTION_TYPE_LZRECEIVE) {
                // lzRead does not support lzReceive option
                if (_isRead) revert Executor_UnsupportedOptionType(optionType);
                (uint128 gas, uint128 value) = ExecutorOptions.decodeLzReceiveOption(option);

                // endpoint v1 does not support lzReceive with value
                if (_v1Eid && value > 0) revert Executor_UnsupportedOptionType(optionType);

                options.totalValue += value;
                lzReceiveGas += gas;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_NATIVE_DROP) {
                // lzRead does not support nativeDrop option
                if (_isRead) revert Executor_UnsupportedOptionType(optionType);

                (uint128 nativeDropAmount, ) = ExecutorOptions.decodeNativeDropOption(option);
                options.totalValue += nativeDropAmount;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_LZCOMPOSE) {
                // endpoint v1 does not support lzCompose
                if (_v1Eid) revert Executor_UnsupportedOptionType(optionType);

                (, uint128 gas, uint128 value) = ExecutorOptions.decodeLzComposeOption(option);
                if (gas == 0) revert Executor_ZeroLzComposeGasProvided();

                options.totalValue += value;
                options.totalGas += gas;
                options.numLzCompose++;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_ORDERED_EXECUTION) {
                options.ordered = true;
            } else if (optionType == ExecutorOptions.OPTION_TYPE_LZREAD) {
                if (!_isRead) revert Executor_UnsupportedOptionType(optionType);

                (uint128 gas, uint32 size, uint128 value) = ExecutorOptions.decodeLzReadOption(option);
                options.totalValue += value;
                lzReceiveGas += gas;
                calldataSize += size;
            } else {
                revert Executor_UnsupportedOptionType(optionType);
            }
        }
        if (cursor != _options.length) revert Executor_InvalidExecutorOptions(cursor);
        if (options.totalValue > _nativeCap) revert Executor_NativeAmountExceedsCap(options.totalValue, _nativeCap);
        if (lzReceiveGas == 0) revert Executor_ZeroLzReceiveGasProvided();
        if (_isRead && calldataSize == 0) revert Executor_ZeroCalldataSizeProvided();
        options.totalGas += lzReceiveGas;
        options.calldataSize = calldataSize;
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

    function version() external pure returns (uint64 major, uint8 minor) {
        return (1, 1);
    }

    // send funds here to pay for price feed directly
    receive() external payable {}
}
