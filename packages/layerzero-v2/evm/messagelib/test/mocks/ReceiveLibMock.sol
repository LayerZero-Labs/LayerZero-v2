// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { IMessageLib, MessageLibType } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { IReceiveUlnE2 } from "../../contracts/uln/interfaces/IReceiveUlnE2.sol";
import { Verification } from "../../contracts/uln/ReceiveUlnBase.sol";

contract ReceiveLibMock is IReceiveUlnE2, IMessageLib {
    error NotImplemented();

    mapping(bytes32 headerHash => mapping(bytes32 payloadHash => mapping(address dvn => Verification)))
        public hashLookup;

    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external {
        hashLookup[keccak256(_packetHeader)][_payloadHash][msg.sender] = Verification(true, _confirmations);
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (3, 0, 2);
    }

    function commitVerification(bytes calldata, bytes32) external pure {
        revert NotImplemented();
    }

    function setConfig(address, SetConfigParam[] calldata) external pure {
        revert NotImplemented();
    }

    function getConfig(uint32, address, uint32) external pure returns (bytes memory) {
        revert NotImplemented();
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        revert NotImplemented();
    }

    function messageLibType() external pure returns (MessageLibType) {
        revert NotImplemented();
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        revert NotImplemented();
    }
}
