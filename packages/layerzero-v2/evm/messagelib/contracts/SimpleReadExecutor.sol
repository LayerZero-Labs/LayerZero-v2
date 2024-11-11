// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { ILayerZeroReadExecutor } from "./interfaces/ILayerZeroReadExecutor.sol";
import { ExecutorOptions } from "./libs/ExecutorOptions.sol";

struct ExecutionParams {
    address receiver;
    Origin origin;
    bytes32 guid;
    bytes message;
    bytes extraData;
    uint256 gasLimit;
}

interface ILayerZeroEndpointV2 {
    function eid() external view returns (uint32);

    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;

    function lzReceiveAlert(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        uint256 _gas,
        uint256 _value,
        bytes calldata _message,
        bytes calldata _extraData,
        bytes calldata _reason
    ) external;
}

contract SimpleReadExecutor is ILayerZeroReadExecutor {
    using ExecutorOptions for bytes;

    address public immutable endpoint;

    uint128 public gasPerByte;
    uint128 public gasPrice;

    constructor(address _endpoint) {
        endpoint = _endpoint;
    }

    function configGas(uint128 _gasPerByte, uint128 _gasPrice) external {
        gasPerByte = _gasPerByte;
        gasPrice = _gasPrice;
    }

    function assignJob(address _sender, bytes calldata _options) external returns (uint256) {
        return getFee(_sender, _options);
    }

    function execute(ExecutionParams calldata _executionParams) external payable {
        try
            ILayerZeroEndpointV2(endpoint).lzReceive{ value: msg.value, gas: _executionParams.gasLimit }(
                _executionParams.origin,
                _executionParams.receiver,
                _executionParams.guid,
                _executionParams.message,
                _executionParams.extraData
            )
        {
            // do nothing
        } catch (bytes memory reason) {
            ILayerZeroEndpointV2(endpoint).lzReceiveAlert(
                _executionParams.origin,
                _executionParams.receiver,
                _executionParams.guid,
                _executionParams.gasLimit,
                msg.value,
                _executionParams.message,
                _executionParams.extraData,
                reason
            );
        }
    }

    function mustExecute(ExecutionParams calldata _executionParams) external payable {
        ILayerZeroEndpointV2(endpoint).lzReceive{ value: msg.value, gas: _executionParams.gasLimit }(
            _executionParams.origin,
            _executionParams.receiver,
            _executionParams.guid,
            _executionParams.message,
            _executionParams.extraData
        );
    }

    // ========================= View =========================

    function getFee(address /*_sender*/, bytes calldata _options) public view returns (uint256) {
        // For simplify, we only support one execute option, and must be LZREAD type
        (uint8 optionType, bytes calldata option, ) = _options.nextExecutorOption(0);
        require(optionType == ExecutorOptions.OPTION_TYPE_LZREAD, "SimpleReadExecutor: not LZREAD option");
        (uint128 gas, uint32 calldataSize, uint128 value) = option.decodeLzReadOption();
        // calculate fee
        return (gas + calldataSize * gasPerByte) * gasPrice + value;
    }

    receive() external payable virtual {}
}
