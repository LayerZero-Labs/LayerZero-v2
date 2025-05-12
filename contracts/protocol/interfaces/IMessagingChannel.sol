// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IMessagingChannel {
    event InboundNonceSkipped(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce);
    event PacketNilified(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce, bytes32 payloadHash);
    event PacketBurnt(uint32 srcEid, bytes32 sender, address receiver, uint64 nonce, bytes32 payloadHash);

    function eid() external view returns (uint32);

    // this is an emergency function if a message cannot be verified for some reasons
    // required to provide _nextNonce to avoid race condition
    function skip(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce) external;

    function nilify(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce, bytes32 _payloadHash) external;

    function burn(address _oapp, uint32 _srcEid, bytes32 _sender, uint64 _nonce, bytes32 _payloadHash) external;

    function nextGuid(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (bytes32);

    function inboundNonce(address _receiver, uint32 _srcEid, bytes32 _sender) external view returns (uint64);

    function outboundNonce(address _sender, uint32 _dstEid, bytes32 _receiver) external view returns (uint64);

    function inboundPayloadHash(
        address _receiver,
        uint32 _srcEid,
        bytes32 _sender,
        uint64 _nonce
    ) external view returns (bytes32);

    function lazyInboundNonce(address _receiver, uint32 _srcEid, bytes32 _sender) external view returns (uint64);
}
