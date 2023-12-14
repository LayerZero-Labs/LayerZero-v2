// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { IMessagingChannel } from "./interfaces/IMessagingChannel.sol";
import { Errors } from "./libs/Errors.sol";
import { GUID } from "./libs/GUID.sol";

abstract contract MessagingChannel is IMessagingChannel {
    bytes32 public constant EMPTY_PAYLOAD_HASH = bytes32(0);
    bytes32 public constant NIL_PAYLOAD_HASH = bytes32(type(uint256).max);

    // The universally unique id (UUID) of this deployed Endpoint
    uint32 public immutable eid;

    mapping(address receiver => mapping(uint32 srcEid => mapping(bytes32 sender => uint64 nonce)))
        public lazyInboundNonce;
    mapping(address receiver => mapping(uint32 srcEid => mapping(bytes32 sender => mapping(uint64 inboundNonce => bytes32 payloadHash))))
        public inboundPayloadHash;
    mapping(address sender => mapping(uint32 dstEid => mapping(bytes32 receiver => uint64 nonce))) public outboundNonce;

    /// @param _eid is the universally unique id (UUID) of this deployed Endpoint
    constructor(uint32 _eid) {
        eid = _eid;
    }

    /// @dev increase and return the next outbound nonce
    function _outbound(address _sender, uint32 _dstEid, bytes32 _receiver) internal returns (uint64 nonce) {
        unchecked {
            nonce = ++outboundNonce[_sender][_dstEid][_receiver];
        }
    }

    /// @dev inbound won't update the nonce eagerly to allow unordered verification
    /// @dev instead, it will update the nonce lazily when the message is received
    /// @dev messages can only be cleared in order to preserve censorship-resistance
    function _inbound(
        address _receiver,
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        bytes32 _payloadHash
    ) internal {
        if (_payloadHash == EMPTY_PAYLOAD_HASH) revert Errors.InvalidPayloadHash();
        inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] = _payloadHash;
    }

    /// @dev returns the max index of the longest gapless sequence of verified msg nonces.
    /// @dev the uninitialized value is 0. the first nonce is always 1
    /// @dev it starts from the lazyInboundNonce (last checkpoint) and iteratively check if the next nonce has been verified
    /// @dev this function can OOG if too many backlogs, but it can be trivially fixed by just clearing some prior messages
    /// @dev NOTE: Oapp explicitly skipped nonces count as "verified" for these purposes
    /// @dev eg. [1,2,3,4,6,7] => 4, [1,2,6,8,10] => 2, [1,3,4,5,6] => 1
    function inboundNonce(address _receiver, uint32 _srcEid, bytes32 _sender) public view returns (uint64) {
        uint64 nonceCursor = lazyInboundNonce[_receiver][_srcEid][_sender];

        // find the effective inbound currentNonce
        unchecked {
            while (_hasPayloadHash(_receiver, _srcEid, _sender, nonceCursor + 1)) {
                ++nonceCursor;
            }
        }
        return nonceCursor;
    }

    /// @dev checks if the storage slot is not initialized. Assumes computationally infeasible that payload can hash to 0
    function _hasPayloadHash(
        address _receiver,
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce
    ) internal view returns (bool) {
        return inboundPayloadHash[_receiver][_srcEid][_sender][_nonce] != EMPTY_PAYLOAD_HASH;
    }

    /// @dev the caller must provide _nonce to prevent skipping the unintended nonce
    /// @dev it could happen in some race conditions, e.g. to skip nonce 3, but nonce 3 was consumed first
    /// @dev usage: skipping the next nonce to prevent message verification, e.g. skip a message when Precrime throws alerts
    /// @dev if the Oapp wants to skip a verified message, it should call the clear() function instead
    /// @dev after skipping, the lazyInboundNonce is set to the provided nonce, which makes the inboundNonce also the provided nonce
    /// @dev ie. allows the Oapp to increment the lazyInboundNonce without having had that corresponding msg be verified
    function skip(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce) external {
        _assertAuthorized(_oapp);

        if (_nonce != inboundNonce(_oapp, _srcEid, _sender) + 1) revert Errors.InvalidNonce(_nonce);
        lazyInboundNonce[_oapp][_srcEid][_sender] = _nonce;
        emit InboundNonceSkipped(_srcEid, _sender, _oapp, _nonce);
    }

    /// @dev Marks a packet as verified, but disallows execution until it is re-verified.
    /// @dev Reverts if the provided _payloadHash does not match the currently verified payload hash.
    /// @dev A non-verified nonce can be nilified by passing EMPTY_PAYLOAD_HASH for _payloadHash.
    /// @dev Assumes the computational intractability of finding a payload that hashes to bytes32.max.
    /// @dev Authenticated by the caller
    function nilify(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce, bytes32 _payloadHash) external {
        _assertAuthorized(_oapp);

        bytes32 curPayloadHash = inboundPayloadHash[_oapp][_srcEid][_sender][_nonce];
        if (curPayloadHash != _payloadHash) revert Errors.PayloadHashNotFound(curPayloadHash, _payloadHash);
        if (_nonce <= lazyInboundNonce[_oapp][_srcEid][_sender] && curPayloadHash == EMPTY_PAYLOAD_HASH)
            revert Errors.InvalidNonce(_nonce);
        // set it to nil
        inboundPayloadHash[_oapp][_srcEid][_sender][_nonce] = NIL_PAYLOAD_HASH;
        emit PacketNilified(_srcEid, _sender, _oapp, _nonce, _payloadHash);
    }

    /// @dev Marks a nonce as unexecutable and un-verifiable. The nonce can never be re-verified or executed.
    /// @dev Reverts if the provided _payloadHash does not match the currently verified payload hash.
    /// @dev Only packets with nonces less than or equal to the lazy inbound nonce can be burned.
    /// @dev Reverts if the nonce has already been executed.
    /// @dev Authenticated by the caller
    function burn(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce, bytes32 _payloadHash) external {
        _assertAuthorized(_oapp);

        bytes32 curPayloadHash = inboundPayloadHash[_oapp][_srcEid][_sender][_nonce];
        if (curPayloadHash != _payloadHash) revert Errors.PayloadHashNotFound(curPayloadHash, _payloadHash);
        if (curPayloadHash == EMPTY_PAYLOAD_HASH || _nonce > lazyInboundNonce[_oapp][_srcEid][_sender])
            revert Errors.InvalidNonce(_nonce);
        delete inboundPayloadHash[_oapp][_srcEid][_sender][_nonce];
        emit PacketBurnt(_srcEid, _sender, _oapp, _nonce, _payloadHash);
    }

    /// @dev calling this function will clear the stored message and increment the lazyInboundNonce to the provided nonce
    /// @dev if a lot of messages are queued, the messages can be cleared with a smaller step size to prevent OOG
    /// @dev NOTE: this function does not change inboundNonce, it only changes the lazyInboundNonce up to the provided nonce
    function _clearPayload(
        address _receiver,
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce,
        bytes memory _payload
    ) internal returns (bytes32 actualHash) {
        uint64 currentNonce = lazyInboundNonce[_receiver][_srcEid][_sender];
        if (_nonce > currentNonce) {
            unchecked {
                // try to lazily update the inboundNonce till the _nonce
                for (uint64 i = currentNonce + 1; i <= _nonce; ++i) {
                    if (!_hasPayloadHash(_receiver, _srcEid, _sender, i)) revert Errors.InvalidNonce(i);
                }
                lazyInboundNonce[_receiver][_srcEid][_sender] = _nonce;
            }
        }

        // check the hash of the payload to verify the executor has given the proper payload that has been verified
        actualHash = keccak256(_payload);
        bytes32 expectedHash = inboundPayloadHash[_receiver][_srcEid][_sender][_nonce];
        if (expectedHash != actualHash) revert Errors.PayloadHashNotFound(expectedHash, actualHash);

        // remove it from the storage
        delete inboundPayloadHash[_receiver][_srcEid][_sender][_nonce];
    }

    /// @dev returns the GUID for the next message given the path
    /// @dev the Oapp might want to include the GUID into the message in some cases
    function nextGuid(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (bytes32) {
        uint64 nextNonce = outboundNonce[_sender][_dstEid][_receiver] + 1;
        return GUID.generate(nextNonce, eid, _sender, _dstEid, _receiver);
    }

    function _assertAuthorized(address _oapp) internal virtual;
}
