// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/ILayerZeroEndpointV2.sol";

enum ExecutionState {
    NotExecutable, // executor: waits for PayloadVerified event and starts polling for executable
    VerifiedButNotExecutable, // executor: starts active polling for executable
    Executable,
    Executed
}

contract EndpointV2ViewUpgradeable is Initializable {
    bytes32 public constant EMPTY_PAYLOAD_HASH = bytes32(0);
    bytes32 public constant NIL_PAYLOAD_HASH = bytes32(type(uint256).max);

    ILayerZeroEndpointV2 public endpoint;

    function __EndpointV2View_init(address _endpoint) internal onlyInitializing {
        __EndpointV2View_init_unchained(_endpoint);
    }

    function __EndpointV2View_init_unchained(address _endpoint) internal onlyInitializing {
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    function initializable(Origin memory _origin, address _receiver) public view returns (bool) {
        return endpoint.initializable(_origin, _receiver);
    }

    /// @dev check if a message is verifiable.
    function verifiable(
        Origin memory _origin,
        address _receiver,
        address _receiveLib,
        bytes32 _payloadHash
    ) public view returns (bool) {
        if (!endpoint.isValidReceiveLibrary(_receiver, _origin.srcEid, _receiveLib)) return false;

        if (!endpoint.verifiable(_origin, _receiver)) return false;

        // checked in _inbound for verify
        if (_payloadHash == EMPTY_PAYLOAD_HASH) return false;

        return true;
    }

    /// @dev check if a message is executable.
    /// @return ExecutionState of Executed, Executable, or NotExecutable
    function executable(Origin memory _origin, address _receiver) public view returns (ExecutionState) {
        bytes32 payloadHash = endpoint.inboundPayloadHash(_receiver, _origin.srcEid, _origin.sender, _origin.nonce);

        // executed if the payload hash has been cleared and the nonce is less than or equal to lazyInboundNonce
        if (
            payloadHash == EMPTY_PAYLOAD_HASH &&
            _origin.nonce <= endpoint.lazyInboundNonce(_receiver, _origin.srcEid, _origin.sender)
        ) {
            return ExecutionState.Executed;
        }

        // executable if nonce has not been executed and has not been nilified and nonce is less than or equal to inboundNonce
        if (
            payloadHash != NIL_PAYLOAD_HASH &&
            _origin.nonce <= endpoint.inboundNonce(_receiver, _origin.srcEid, _origin.sender)
        ) {
            return ExecutionState.Executable;
        }

        // only start active executable polling if payload hash is not empty nor nil
        if (payloadHash != EMPTY_PAYLOAD_HASH && payloadHash != NIL_PAYLOAD_HASH) {
            return ExecutionState.VerifiedButNotExecutable;
        }

        // return NotExecutable as a catch-all
        return ExecutionState.NotExecutable;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
