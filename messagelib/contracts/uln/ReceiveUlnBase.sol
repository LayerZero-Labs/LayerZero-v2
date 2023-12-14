// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { UlnBase, UlnConfig } from "./UlnBase.sol";

enum VerificationState {
    Verifying,
    Verifiable,
    Verified
}

struct Verification {
    bool submitted;
    uint64 confirmations;
}

/// @dev includes the utility functions for checking ULN states and logics
abstract contract ReceiveUlnBase is UlnBase {
    using PacketV1Codec for bytes;

    mapping(bytes32 headerHash => mapping(bytes32 payloadHash => mapping(address dvn => Verification)))
        public hashLookup;

    event PayloadVerified(address dvn, bytes header, uint256 confirmations, bytes32 proofHash);

    error InvalidPacketHeader();
    error InvalidPacketVersion();
    error InvalidEid();
    error Verifying();

    // ============================ Internal ===================================
    /// @dev per DVN signing function
    function _verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) internal {
        hashLookup[keccak256(_packetHeader)][_payloadHash][msg.sender] = Verification(true, _confirmations);
        emit PayloadVerified(msg.sender, _packetHeader, _confirmations, _payloadHash);
    }

    function _verified(
        address _dvn,
        bytes32 _headerHash,
        bytes32 _payloadHash,
        uint64 _requiredConfirmation
    ) internal view returns (bool verified) {
        Verification memory verification = hashLookup[_headerHash][_payloadHash][_dvn];
        // return true if the dvn has signed enough confirmations
        verified = verification.submitted && verification.confirmations >= _requiredConfirmation;
    }

    function _verifyAndReclaimStorage(UlnConfig memory _config, bytes32 _headerHash, bytes32 _payloadHash) internal {
        if (!_checkVerifiable(_config, _headerHash, _payloadHash)) {
            revert Verifying();
        }

        // iterate the required DVNs
        if (_config.requiredDVNCount > 0) {
            for (uint8 i = 0; i < _config.requiredDVNCount; ++i) {
                delete hashLookup[_headerHash][_payloadHash][_config.requiredDVNs[i]];
            }
        }

        // iterate the optional DVNs
        if (_config.optionalDVNCount > 0) {
            for (uint8 i = 0; i < _config.optionalDVNCount; ++i) {
                delete hashLookup[_headerHash][_payloadHash][_config.optionalDVNs[i]];
            }
        }
    }

    function _assertHeader(bytes calldata _packetHeader, uint32 _localEid) internal pure {
        // assert packet header is of right size 81
        if (_packetHeader.length != 81) revert InvalidPacketHeader();
        // assert packet header version is the same as ULN
        if (_packetHeader.version() != PacketV1Codec.PACKET_VERSION) revert InvalidPacketVersion();
        // assert the packet is for this endpoint
        if (_packetHeader.dstEid() != _localEid) revert InvalidEid();
    }

    /// @dev for verifiable view function
    /// @dev checks if this verification is ready to be committed to the endpoint
    function _checkVerifiable(
        UlnConfig memory _config,
        bytes32 _headerHash,
        bytes32 _payloadHash
    ) internal view returns (bool) {
        // iterate the required DVNs
        if (_config.requiredDVNCount > 0) {
            for (uint8 i = 0; i < _config.requiredDVNCount; ++i) {
                if (!_verified(_config.requiredDVNs[i], _headerHash, _payloadHash, _config.confirmations)) {
                    // return if any of the required DVNs haven't signed
                    return false;
                }
            }
            if (_config.optionalDVNCount == 0) {
                // returns early if all required DVNs have signed and there are no optional DVNs
                return true;
            }
        }

        // then it must require optional validations
        uint8 threshold = _config.optionalDVNThreshold;
        for (uint8 i = 0; i < _config.optionalDVNCount; ++i) {
            if (_verified(_config.optionalDVNs[i], _headerHash, _payloadHash, _config.confirmations)) {
                // increment the optional count if the optional DVN has signed
                threshold--;
                if (threshold == 0) {
                    // early return if the optional threshold has hit
                    return true;
                }
            }
        }

        // return false as a catch-all
        return false;
    }
}
