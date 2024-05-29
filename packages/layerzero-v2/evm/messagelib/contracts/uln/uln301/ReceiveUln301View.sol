// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { ExecutionState, EndpointV2View } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2View.sol";

import { UlnConfig } from "../UlnBase.sol";

enum VerificationState {
    Verifying,
    Verifiable,
    Verified
}

interface IReceiveUln301 {
    function assertHeader(bytes calldata _packetHeader, uint32 _localEid) external pure;

    function addressSizes(uint32 _dstEid) external view returns (uint256);

    function endpoint() external view returns (address);

    function verifiable(
        UlnConfig memory _config,
        bytes32 _headerHash,
        bytes32 _payloadHash
    ) external view returns (bool);

    function getUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory rtnConfig);
}

contract ReceiveUln301View is Initializable, Proxied {
    using PacketV1Codec for bytes;
    using AddressCast for bytes32;
    using SafeCast for uint32;

    ILayerZeroEndpoint public endpoint;
    IReceiveUln301 public receiveUln301;
    uint32 internal localEid;

    function initialize(address _endpoint, uint32 _localEid, address _receiveUln301) external proxied initializer {
        receiveUln301 = IReceiveUln301(_receiveUln301);
        endpoint = ILayerZeroEndpoint(_endpoint);
        localEid = _localEid;
    }

    function executable(bytes calldata _packetHeader, bytes32 _payloadHash) public view returns (ExecutionState) {
        receiveUln301.assertHeader(_packetHeader, localEid);

        address receiver = _packetHeader.receiverB20();
        uint16 srcEid = _packetHeader.srcEid().toUint16();
        uint64 nonce = _packetHeader.nonce();

        // executed if nonce less than or equal to inboundNonce
        bytes memory path = abi.encodePacked(
            _packetHeader.sender().toBytes(receiveUln301.addressSizes(srcEid)),
            receiver
        );
        if (nonce <= endpoint.getInboundNonce(srcEid, path)) return ExecutionState.Executed;

        // executable if not executed and _verified
        if (
            receiveUln301.verifiable(
                receiveUln301.getUlnConfig(receiver, srcEid),
                keccak256(_packetHeader),
                _payloadHash
            )
        ) {
            return ExecutionState.Executable;
        }

        return ExecutionState.NotExecutable;
    }

    /// @dev keeping the same interface as 302
    /// @dev a verifiable message requires it to be ULN verifiable only, excluding the endpoint verifiable check
    function verifiable(bytes calldata _packetHeader, bytes32 _payloadHash) external view returns (VerificationState) {
        if (executable(_packetHeader, _payloadHash) == ExecutionState.NotExecutable) {
            return VerificationState.Verifying;
        }
        return VerificationState.Verified;
    }
}
