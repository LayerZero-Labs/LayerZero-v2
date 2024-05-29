// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { EndpointV2ViewUpgradeable } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2ViewUpgradeable.sol";
import { UlnConfig } from "../UlnBase.sol";

enum VerificationState {
    Verifying,
    Verifiable,
    Verified,
    NotInitializable
}

interface IReceiveUln302 {
    function assertHeader(bytes calldata _packetHeader, uint32 _localEid) external pure;

    function verifiable(
        UlnConfig memory _config,
        bytes32 _headerHash,
        bytes32 _payloadHash
    ) external view returns (bool);

    function getUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory rtnConfig);
}

contract ReceiveUln302View is EndpointV2ViewUpgradeable, Proxied {
    using PacketV1Codec for bytes;

    IReceiveUln302 public receiveUln302;
    uint32 internal localEid;

    function initialize(address _endpoint, address _receiveUln302) external proxied initializer {
        __EndpointV2View_init(_endpoint);
        receiveUln302 = IReceiveUln302(_receiveUln302);
        localEid = endpoint.eid();
    }

    /// @dev a ULN verifiable requires it to be endpoint verifiable and committable
    function verifiable(bytes calldata _packetHeader, bytes32 _payloadHash) external view returns (VerificationState) {
        receiveUln302.assertHeader(_packetHeader, localEid);

        address receiver = _packetHeader.receiverB20();

        Origin memory origin = Origin(_packetHeader.srcEid(), _packetHeader.sender(), _packetHeader.nonce());

        // check endpoint initializable
        if (!initializable(origin, receiver)) {
            return VerificationState.NotInitializable;
        }

        // check endpoint verifiable
        if (!_endpointVerifiable(origin, receiver, _payloadHash)) {
            return VerificationState.Verified;
        }

        // check uln verifiable
        if (
            receiveUln302.verifiable(
                receiveUln302.getUlnConfig(receiver, origin.srcEid),
                keccak256(_packetHeader),
                _payloadHash
            )
        ) {
            return VerificationState.Verifiable;
        }
        return VerificationState.Verifying;
    }

    /// @dev checks for endpoint verifiable and endpoint has payload hash
    function _endpointVerifiable(
        Origin memory origin,
        address _receiver,
        bytes32 _payloadHash
    ) internal view returns (bool) {
        // check endpoint verifiable
        if (!verifiable(origin, _receiver, address(receiveUln302), _payloadHash)) return false;

        // if endpoint.verifiable, also check if the payload hash matches
        // endpoint allows re-verify, check if this payload has already been verified
        if (endpoint.inboundPayloadHash(_receiver, origin.srcEid, origin.sender, origin.nonce) == _payloadHash)
            return false;

        return true;
    }
}
