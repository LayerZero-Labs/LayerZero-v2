// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { AddressSizeConfig } from "./AddressSizeConfig.sol";
import { MessageLibBase } from "../../MessageLibBase.sol";

// only receiver function from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroMessagingLibrary.sol"
// because we are separating the send and receive libraries
interface ILayerZeroReceiveLibrary {
    // setConfig / getConfig are User Application (UA) functions to specify Oracle, Relayer, blockConfirmations, libraryVersion
    function setConfig(uint16 _chainId, address _userApplication, uint256 _configType, bytes calldata _config) external;

    function getConfig(
        uint16 _chainId,
        address _userApplication,
        uint256 _configType
    ) external view returns (bytes memory);
}

struct SetDefaultExecutorParam {
    uint32 eid;
    address executor;
}

/// @dev receive-side message library base contract on endpoint v1.
/// design:
/// 1/ it provides an internal execute function that calls the endpoint. It enforces the path definition on V1.
/// 2/ it provides interfaces to configure executors that is whitelisted to execute the msg to prevent grieving
abstract contract ReceiveLibBaseE1 is MessageLibBase, AddressSizeConfig, ILayerZeroReceiveLibrary {
    using AddressCast for bytes32;

    mapping(address oapp => mapping(uint32 eid => address executor)) public executors;
    mapping(uint32 eid => address executor) public defaultExecutors;

    // this event is the same as the PacketDelivered event on EndpointV2
    event PacketDelivered(Origin origin, address receiver);
    event InvalidDst(
        uint16 indexed srcChainId,
        bytes32 srcAddress,
        address indexed dstAddress,
        uint64 nonce,
        bytes32 payloadHash
    );
    event DefaultExecutorsSet(SetDefaultExecutorParam[] params);
    event ExecutorSet(address oapp, uint32 eid, address executor);

    error InvalidExecutor();
    error OnlyExecutor();

    constructor(address _endpoint, uint32 _localEid) MessageLibBase(_endpoint, _localEid) {}

    function setDefaultExecutors(SetDefaultExecutorParam[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; ++i) {
            SetDefaultExecutorParam calldata param = _params[i];
            if (param.executor == address(0x0)) revert InvalidExecutor();
            defaultExecutors[param.eid] = param.executor;
        }
        emit DefaultExecutorsSet(_params);
    }

    function getExecutor(address _oapp, uint32 _remoteEid) public view returns (address) {
        address executor = executors[_oapp][_remoteEid];
        return executor != address(0x0) ? executor : defaultExecutors[_remoteEid];
    }

    function _setExecutor(uint32 _remoteEid, address _oapp, address _executor) internal {
        executors[_oapp][_remoteEid] = _executor;
        emit ExecutorSet(_oapp, _remoteEid, _executor);
    }

    /// @dev this function change pack the path as required for EndpointV1
    function _execute(
        uint16 _srcEid,
        bytes32 _sender,
        address _receiver,
        uint64 _nonce,
        bytes memory _message,
        uint256 _gasLimit
    ) internal {
        // if the executor is malicious, it can make the msg as a storedPayload or fail in the nonBlockingApp
        // which might result in unintended behaviour and risks, like grieving.
        // to err on the safe side, we should assert the executor here.
        if (msg.sender != getExecutor(_receiver, _srcEid)) revert OnlyExecutor();

        if (_receiver.code.length == 0) {
            /// on chains where EOA has no codes, it will early return and emit InvalidDst event
            // on chains where all address have codes, this will be skipped
            emit InvalidDst(_srcEid, _sender, _receiver, _nonce, keccak256(_message));
            return;
        }

        bytes memory pathData = abi.encodePacked(_sender.toBytes(addressSizes[_srcEid]), _receiver);
        ILayerZeroEndpoint(endpoint).receivePayload(_srcEid, pathData, _receiver, _nonce, _gasLimit, _message);

        Origin memory origin = Origin(_srcEid, _sender, _nonce);
        emit PacketDelivered(origin, _receiver);
    }
}
