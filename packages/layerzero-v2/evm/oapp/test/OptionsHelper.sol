// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ExecutorOptions } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/ExecutorOptions.sol";
import { UlnOptions } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/libs/UlnOptions.sol";

contract UlnOptionsMock {
    using UlnOptions for bytes;

    function decode(
        bytes calldata _options
    ) public pure returns (bytes memory executorOptions, bytes memory dvnOptions) {
        return UlnOptions.decode(_options);
    }
}

contract OptionsHelper {
    UlnOptionsMock ulnOptions = new UlnOptionsMock();

    function _parseExecutorLzReceiveOption(bytes memory _options) internal view returns (uint256 gas, uint256 value) {
        (bool exist, bytes memory option) = _getExecutorOptionByOptionType(
            _options,
            ExecutorOptions.OPTION_TYPE_LZRECEIVE
        );
        require(exist, "OptionsHelper: lzReceive option not found");
        (gas, value) = this.decodeLzReceiveOption(option);
    }

    function _parseExecutorNativeDropOption(
        bytes memory _options
    ) internal view returns (uint256 amount, bytes32 receiver) {
        (bool exist, bytes memory option) = _getExecutorOptionByOptionType(
            _options,
            ExecutorOptions.OPTION_TYPE_NATIVE_DROP
        );
        require(exist, "OptionsHelper: nativeDrop option not found");
        (amount, receiver) = this.decodeNativeDropOption(option);
    }

    function _parseExecutorLzComposeOption(
        bytes memory _options
    ) internal view returns (uint16 index, uint256 gas, uint256 value) {
        (bool exist, bytes memory option) = _getExecutorOptionByOptionType(
            _options,
            ExecutorOptions.OPTION_TYPE_LZCOMPOSE
        );
        require(exist, "OptionsHelper: lzCompose option not found");
        return this.decodeLzComposeOption(option);
    }

    function _executorOptionExists(
        bytes memory _options,
        uint8 _executorOptionType
    ) internal view returns (bool exist) {
        (exist, ) = _getExecutorOptionByOptionType(_options, _executorOptionType);
    }

    function _getExecutorOptionByOptionType(
        bytes memory _options,
        uint8 _executorOptionType
    ) internal view returns (bool exist, bytes memory option) {
        (bytes memory executorOpts, ) = ulnOptions.decode(_options);

        uint256 cursor;
        while (cursor < executorOpts.length) {
            (uint8 optionType, bytes memory op, uint256 nextCursor) = this.nextExecutorOption(executorOpts, cursor);
            if (optionType == _executorOptionType) {
                return (true, op);
            }
            cursor = nextCursor;
        }
    }

    function nextExecutorOption(
        bytes calldata _options,
        uint256 _cursor
    ) external pure returns (uint8 optionType, bytes calldata option, uint256 cursor) {
        return ExecutorOptions.nextExecutorOption(_options, _cursor);
    }

    function decodeLzReceiveOption(bytes calldata _option) external pure returns (uint128 gas, uint128 value) {
        return ExecutorOptions.decodeLzReceiveOption(_option);
    }

    function decodeNativeDropOption(bytes calldata _option) external pure returns (uint128 amount, bytes32 receiver) {
        return ExecutorOptions.decodeNativeDropOption(_option);
    }

    function decodeLzComposeOption(
        bytes calldata _option
    ) external pure returns (uint16 index, uint128 gas, uint128 value) {
        return ExecutorOptions.decodeLzComposeOption(_option);
    }
}
