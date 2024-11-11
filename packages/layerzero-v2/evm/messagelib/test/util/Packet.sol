// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

library PacketUtil {
    function newPacket(
        uint64 _nonce,
        uint32 _srcEid,
        address _sender,
        uint32 _dstEid,
        address _receiver,
        bytes memory _message
    ) internal pure returns (Packet memory) {
        bytes32 guid = keccak256(
            abi.encodePacked(
                _nonce,
                _srcEid,
                bytes32(uint256(uint160(_sender))),
                uint32(_dstEid),
                bytes32(uint256(uint160(_receiver)))
            )
        );
        return Packet(_nonce, _srcEid, _sender, _dstEid, bytes32(uint256(uint160(_receiver))), guid, _message);
    }

    function getOrigin(Packet memory packet) internal pure returns (Origin memory origin) {
        return Origin(packet.srcEid, bytes32(uint256(uint160(packet.sender))), packet.nonce);
    }
}
