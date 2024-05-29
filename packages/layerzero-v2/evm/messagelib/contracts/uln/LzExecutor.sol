// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";

import { IReceiveUlnE2 } from "./interfaces/IReceiveUlnE2.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ExecutionState, EndpointV2ViewUpgradeable } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2ViewUpgradeable.sol";

import { VerificationState } from "./uln302/ReceiveUln302View.sol";

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

interface IReceiveUlnView {
    function verifiable(bytes calldata _packetHeader, bytes32 _payloadHash) external view returns (VerificationState);
}

contract LzExecutor is OwnableUpgradeable, EndpointV2ViewUpgradeable, Proxied {
    error LzExecutor_Executed();
    error LzExecutor_Verifying();
    error LzExecutor_ReceiveLibViewNotSet();

    event NativeWithdrawn(address _to, uint256 _amount);
    event ReceiveLibViewSet(address _receiveLib, address _receiveLibView);

    address public receiveUln302;
    uint32 public localEid;

    mapping(address receiveLib => address receiveLibView) public receiveLibToView;

    function initialize(
        address _receiveUln302,
        address _receiveUln302View,
        address _endpoint
    ) external proxied initializer {
        __Ownable_init();
        __EndpointV2View_init(_endpoint);

        receiveUln302 = _receiveUln302;
        localEid = endpoint.eid();
        receiveLibToView[_receiveUln302] = _receiveUln302View;
    }

    // ============================ OnlyOwner ===================================

    function withdrawNative(address _to, uint256 _amount) external onlyOwner {
        Transfer.native(_to, _amount);
        emit NativeWithdrawn(_to, _amount);
    }

    function setReceiveLibView(address _receiveLib, address _receiveLibView) external onlyOwner {
        receiveLibToView[_receiveLib] = _receiveLibView;
        emit ReceiveLibViewSet(_receiveLib, _receiveLibView);
    }

    // ============================ External ===================================

    /// @notice process for commit and execute
    /// 1. check if executable, revert if executed, execute if executable
    /// 2. check if verifiable, revert if verifying, commit if verifiable
    /// 3. native drop
    /// 4. try execute, will revert if not executable
    function commitAndExecute(
        address _receiveLib,
        LzReceiveParam calldata _lzReceiveParam,
        NativeDropParam[] calldata _nativeDropParams
    ) external payable {
        /// 1. check if executable, revert if executed
        ExecutionState executionState = executable(_lzReceiveParam.origin, _lzReceiveParam.receiver);
        if (executionState == ExecutionState.Executed) revert LzExecutor_Executed();

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

            address receiveLibView = receiveLibToView[receiveLib];
            if (receiveLibView == address(0x0)) revert LzExecutor_ReceiveLibViewNotSet();

            VerificationState verificationState = IReceiveUlnView(receiveLibView).verifiable(packetHeader, payloadHash);
            if (verificationState == VerificationState.Verifiable) {
                // verification required
                IReceiveUlnE2(receiveLib).commitVerification(packetHeader, payloadHash);
            } else if (verificationState == VerificationState.Verifying) {
                revert LzExecutor_Verifying();
            }
        }

        /// 3. native drop
        for (uint256 i = 0; i < _nativeDropParams.length; i++) {
            NativeDropParam calldata param = _nativeDropParams[i];
            Transfer.native(param._receiver, param._amount);
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
}
