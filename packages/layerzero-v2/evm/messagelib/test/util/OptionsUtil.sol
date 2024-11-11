// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { ExecutorOptions } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/ExecutorOptions.sol";

import { DVNOptions } from "../../contracts/uln/libs/DVNOptions.sol";

library OptionsUtil {
    using SafeCast for uint256;
    using BytesLib for bytes;

    uint16 internal constant TYPE_1 = 1; // legacy options type 1
    uint16 internal constant TYPE_2 = 2; // legacy options type 2
    uint16 internal constant TYPE_3 = 3;

    uint8 internal constant OPTION_TYPE_LZ_READ = 5;

    function newOptions() internal pure returns (bytes memory) {
        return abi.encodePacked(TYPE_3);
    }

    function addExecutorLzReceiveOption(
        bytes memory _options,
        uint128 _gas,
        uint128 _value
    ) internal pure returns (bytes memory) {
        bytes memory option = ExecutorOptions.encodeLzReceiveOption(_gas, _value);
        return addExecutorOption(_options, ExecutorOptions.OPTION_TYPE_LZRECEIVE, option);
    }

    function addExecutorLzReadOption(
        bytes memory _options,
        uint128 _gas,
        uint32 _size,
        uint128 _value
    ) internal pure returns (bytes memory) {
        bytes memory option = encodeLzReadOption(_gas, _size, _value);
        return addExecutorOption(_options, OPTION_TYPE_LZ_READ, option);
    }

    function addExecutorNativeDropOption(
        bytes memory _options,
        uint128 _amount,
        bytes32 _receiver
    ) internal pure returns (bytes memory) {
        bytes memory option = ExecutorOptions.encodeNativeDropOption(_amount, _receiver);
        return addExecutorOption(_options, ExecutorOptions.OPTION_TYPE_NATIVE_DROP, option);
    }

    function addExecutorLzComposeOption(
        bytes memory _options,
        uint128 _gas,
        uint128 _value
    ) internal pure returns (bytes memory) {
        bytes memory option = ExecutorOptions.encodeLzComposeOption(0, _gas, _value);
        return addExecutorOption(_options, ExecutorOptions.OPTION_TYPE_LZCOMPOSE, option);
    }

    function addExecutorOrderedExecutionOption(bytes memory _options) internal pure returns (bytes memory) {
        return addExecutorOption(_options, ExecutorOptions.OPTION_TYPE_ORDERED_EXECUTION, bytes(""));
    }

    function addDVNPreCrimeOption(bytes memory _options, uint8 _dvnIdx) internal pure returns (bytes memory) {
        return addDVNOption(_options, _dvnIdx, DVNOptions.OPTION_TYPE_PRECRIME, bytes(""));
    }

    function addExecutorOption(
        bytes memory _options,
        uint8 _optionType,
        bytes memory _option
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _options,
                ExecutorOptions.WORKER_ID,
                _option.length.toUint16() + 1, // +1 for optionType
                _optionType,
                _option
            );
    }

    function addDVNOption(
        bytes memory _options,
        uint8 _dvnIdx,
        uint8 _optionType,
        bytes memory _option
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _options,
                DVNOptions.WORKER_ID,
                _option.length.toUint16() + 2, // +2 for optionType and dvnIdx
                _dvnIdx,
                _optionType,
                _option
            );
    }

    function addOption(
        bytes memory _options,
        uint8 _workerId,
        uint8 _optionType,
        bytes memory _option
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _options,
                _workerId,
                _option.length.toUint16() + 1, // +1 for optionType
                _optionType,
                _option
            );
    }

    function encodeLegacyOptionsType1(uint256 _executionGas) internal pure returns (bytes memory) {
        return abi.encodePacked(TYPE_1, _executionGas);
    }

    function encodeLegacyOptionsType2(
        uint256 _executionGas,
        uint256 _amount,
        bytes memory _receiver // use bytes instead of bytes32 in legacy type 2
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(TYPE_2, _executionGas, _amount, _receiver);
    }

    function trimType(bytes memory _options) internal pure returns (bytes memory) {
        return _options.slice(2, _options.length - 2);
    }

    function encodeLzReadOption(uint128 _gas, uint32 _size, uint128 _value) internal pure returns (bytes memory) {
        return _value == 0 ? abi.encodePacked(_gas, _size) : abi.encodePacked(_gas, _size, _value);
    }
}
