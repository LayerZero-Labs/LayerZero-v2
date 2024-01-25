// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IMessagingComposer } from "./interfaces/IMessagingComposer.sol";
import { ILayerZeroComposer } from "./interfaces/ILayerZeroComposer.sol";
import { Errors } from "./libs/Errors.sol";

abstract contract MessagingComposer is IMessagingComposer {
    bytes32 private constant NO_MESSAGE_HASH = bytes32(0);
    bytes32 private constant RECEIVED_MESSAGE_HASH = bytes32(uint256(1));

    mapping(address from => mapping(address to => mapping(bytes32 guid => mapping(uint16 index => bytes32 messageHash))))
        public composeQueue;

    /// @dev the Oapp sends the lzCompose message to the endpoint
    /// @dev the composer MUST assert the sender because anyone can send compose msg with this function
    /// @dev with the same GUID, the Oapp can send compose to multiple _composer at the same time
    /// @dev authenticated by the msg.sender
    /// @param _to the address which will receive the composed message
    /// @param _guid the message guid
    /// @param _message the message
    function sendCompose(address _to, bytes32 _guid, uint16 _index, bytes calldata _message) external {
        // must have not been sent before
        if (composeQueue[msg.sender][_to][_guid][_index] != NO_MESSAGE_HASH) revert Errors.LZ_ComposeExists();
        composeQueue[msg.sender][_to][_guid][_index] = keccak256(_message);
        emit ComposeSent(msg.sender, _to, _guid, _index, _message);
    }

    /// @dev execute a composed messages from the sender to the composer (receiver)
    /// @dev the execution provides the execution context (caller, extraData) to the receiver.
    ///      the receiver can optionally assert the caller and validate the untrusted extraData
    /// @dev can not re-entrant
    /// @param _from the address which sends the composed message. in most cases, it is the Oapp's address.
    /// @param _to the address which receives the composed message
    /// @param _guid the message guid
    /// @param _message the message
    /// @param _extraData the extra data provided by the executor. this data is untrusted and should be validated.
    function lzCompose(
        address _from,
        address _to,
        bytes32 _guid,
        uint16 _index,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable {
        // assert the validity
        bytes32 expectedHash = composeQueue[_from][_to][_guid][_index];
        bytes32 actualHash = keccak256(_message);
        if (expectedHash != actualHash) revert Errors.LZ_ComposeNotFound(expectedHash, actualHash);

        // marks the message as received to prevent reentrancy
        // cannot just delete the value, otherwise the message can be sent again and could result in some undefined behaviour
        // even though the sender(composing Oapp) is implicitly fully trusted by the composer.
        // eg. sender may not even realize it has such a bug
        composeQueue[_from][_to][_guid][_index] = RECEIVED_MESSAGE_HASH;
        ILayerZeroComposer(_to).lzCompose{ value: msg.value }(_from, _guid, _message, msg.sender, _extraData);
        emit ComposeDelivered(_from, _to, _guid, _index);
    }

    /// @param _from the address which sends the composed message
    /// @param _to the address which receives the composed message
    /// @param _guid the message guid
    /// @param _message the message
    /// @param _extraData the extra data provided by the executor
    /// @param _reason the reason why the message is not received
    function lzComposeAlert(
        address _from,
        address _to,
        bytes32 _guid,
        uint16 _index,
        uint256 _gas,
        uint256 _value,
        bytes calldata _message,
        bytes calldata _extraData,
        bytes calldata _reason
    ) external {
        emit LzComposeAlert(_from, _to, msg.sender, _guid, _index, _gas, _value, _message, _extraData, _reason);
    }
}
