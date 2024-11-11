// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { EndpointV2ViewUpgradeable } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2ViewUpgradeable.sol";

import { ReadLibConfig } from "./ReadLibBase.sol";
import { ReadLib1002 } from "./ReadLib1002.sol";

enum VerificationState {
    Verifying,
    Verifiable,
    Verified,
    NotInitializable,
    Reorged
}

contract ReadLib1002View is EndpointV2ViewUpgradeable, Proxied {
    using PacketV1Codec for bytes;

    ReadLib1002 public readLib;
    uint32 internal localEid;

    function initialize(address _endpoint, address payable _readLib) external proxied initializer {
        __EndpointV2View_init(_endpoint);
        readLib = ReadLib1002(_readLib);
        localEid = endpoint.eid();
    }

    /// @dev get a verifiable payload hash based on the payloadHashLookup from the DVNs
    function getVerifiablePayloadHash(
        address _receiver,
        uint32 _srcEid,
        bytes32 _headerHash,
        bytes32 _cmdHash
    ) public view returns (bytes32) {
        ReadLibConfig memory config = readLib.getReadLibConfig(_receiver, _srcEid);
        uint8 dvnsLength = config.requiredDVNCount + config.optionalDVNCount;
        for (uint8 i = 0; i < dvnsLength; ++i) {
            address dvn = i < config.requiredDVNCount
                ? config.requiredDVNs[i]
                : config.optionalDVNs[i - config.requiredDVNCount];

            bytes32 payloadHash = readLib.hashLookup(_headerHash, _cmdHash, dvn);
            if (readLib.verifiable(config, _headerHash, _cmdHash, payloadHash)) {
                return payloadHash;
            }
        }
        return EMPTY_PAYLOAD_HASH; // not found
    }

    /// @dev a verifiable requires it to be endpoint verifiable and committable
    function verifiable(bytes calldata _packetHeader, bytes32 _cmdHash) external view returns (VerificationState) {
        address receiver = _packetHeader.receiverB20();
        uint32 srcEid = _packetHeader.srcEid();

        Origin memory origin = Origin(srcEid, _packetHeader.sender(), _packetHeader.nonce());

        // check endpoint initializable
        if (!initializable(origin, receiver)) {
            return VerificationState.NotInitializable;
        }

        // check endpoint verifiable. if false, that means it is executed and can not be verified
        if (!endpoint.verifiable(origin, receiver)) {
            return VerificationState.Verified;
        }

        // get the verifiable payload hash
        bytes32 payloadHash = getVerifiablePayloadHash(receiver, srcEid, keccak256(_packetHeader), _cmdHash);

        if (payloadHash == EMPTY_PAYLOAD_HASH) {
            // if payload hash is not empty, it is verified
            if (endpoint.inboundPayloadHash(receiver, srcEid, origin.sender, origin.nonce) != EMPTY_PAYLOAD_HASH) {
                return VerificationState.Verified;
            }

            // otherwise, it is verifying
            return VerificationState.Verifying;
        }

        // check if the cmdHash matches
        if (readLib.cmdHashLookup(receiver, srcEid, origin.nonce) != _cmdHash) {
            return VerificationState.Reorged;
        }

        // check if the payload hash matches
        // endpoint allows re-verify, check if this payload has already been verified
        if (endpoint.inboundPayloadHash(receiver, origin.srcEid, origin.sender, origin.nonce) == payloadHash) {
            return VerificationState.Verified;
        }

        return VerificationState.Verifiable;
    }
}
