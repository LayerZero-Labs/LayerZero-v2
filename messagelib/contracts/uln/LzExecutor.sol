// SPDX-License-Identifier: LZBL-1.2

pragma solidity 0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IReceiveUlnE2 } from "./interfaces/IReceiveUlnE2.sol";
import { ILayerZeroEndpointV2, ExecutionState, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { VerificationState } from "./ReceiveUlnBase.sol";

struct LzReceiveParam {
    Origin origin;
    address receiver;
    bytes32 guid;
    bytes message;
    bytes extraData;
    uint256 gas;
    uint256 value;
}

struct NativeDropParam {
    address _receiver;
    uint256 _amount;
}

contract LzExecutor is Ownable {
    address public immutable receiveUln302;
    ILayerZeroEndpointV2 public immutable endpoint;
    uint32 public immutable localEid;

    error Executed();
    error Verifying();

    constructor(address _receiveUln302, address _endpoint) {
        receiveUln302 = _receiveUln302;
        endpoint = ILayerZeroEndpointV2(_endpoint);
        localEid = endpoint.eid();
    }

    /// @notice process for commit and execute
    /// 1. check if executable, revert if executed, execute if executable
    /// 2. check if verifiable, revert if verifying, commit if verifiable
    /// 3. native drop
    /// 4. try execute, will revert if not executable
    function commitAndExecute(
        address _receiveLib,
        LzReceiveParam calldata _lzReceiveParam,
        NativeDropParam calldata _nativeDropParam
    ) external payable {
        /// 1. check if executable, revert if executed
        ExecutionState executionState = endpoint.executable(_lzReceiveParam.origin, _lzReceiveParam.receiver);
        if (executionState == ExecutionState.Executed) revert Executed();

        /// 2. if not executable, check if verifiable, revert if verifying, commit if verifiable
        if (executionState != ExecutionState.Executable) {
            address receiveLib = receiveUln302 == address(0x0) ? _receiveLib : address(receiveUln302);
            bytes memory packetHeader = abi.encodePacked(
                uint8(1), // packet version 1
                _lzReceiveParam.origin.nonce,
                _lzReceiveParam.origin.srcEid,
                _lzReceiveParam.origin.sender,
                localEid,
                bytes32(uint256(uint160(_lzReceiveParam.receiver)))
            );
            bytes32 payloadHash = keccak256(abi.encodePacked(_lzReceiveParam.guid, _lzReceiveParam.message));

            VerificationState verificationState = IReceiveUlnE2(receiveLib).verifiable(packetHeader, payloadHash);
            if (verificationState == VerificationState.Verifiable) {
                // verification required
                IReceiveUlnE2(receiveLib).commitVerification(packetHeader, payloadHash);
            } else if (verificationState == VerificationState.Verifying) {
                revert Verifying();
            }
        }

        /// 3. native drop
        if (_nativeDropParam._amount > 0 && _nativeDropParam._receiver != address(0x0)) {
            Transfer.native(_nativeDropParam._receiver, _nativeDropParam._amount);
        }

        /// 4. try execute, will revert if not executable
        endpoint.lzReceive{ gas: _lzReceiveParam.gas, value: _lzReceiveParam.value }(
            _lzReceiveParam.origin,
            _lzReceiveParam.receiver,
            _lzReceiveParam.guid,
            _lzReceiveParam.message,
            _lzReceiveParam.extraData
        );
    }

    function withdrawNative(address _to, uint256 _amount) external onlyOwner {
        Transfer.native(_to, _amount);
    }
}
