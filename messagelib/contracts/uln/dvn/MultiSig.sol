// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract MultiSig {
    enum Errors {
        NoError,
        SignatureError,
        DuplicatedSigner,
        SignerNotInCommittee
    }

    mapping(address signer => bool active) public signers;
    uint64 public signerSize;
    uint64 public quorum;

    error MultiSig_OnlySigner();
    error MultiSig_QuorumIsZero();
    error MultiSig_SignersSizeIsLessThanQuorum(uint64 signersSize, uint64 quorum);
    error MultiSig_UnorderedSigners();
    error MultiSig_StateAlreadySet(address signer, bool active);

    event UpdateSigner(address _signer, bool _active);
    event UpdateQuorum(uint64 _quorum);

    modifier onlySigner() {
        if (!signers[msg.sender]) {
            revert MultiSig_OnlySigner();
        }
        _;
    }

    constructor(address[] memory _signers, uint64 _quorum) {
        if (_quorum == 0) {
            revert MultiSig_QuorumIsZero();
        }
        if (_signers.length < _quorum) {
            revert MultiSig_SignersSizeIsLessThanQuorum(uint64(_signers.length), _quorum);
        }
        address lastSigner = address(0);
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer <= lastSigner) {
                revert MultiSig_UnorderedSigners();
            }
            signers[signer] = true;
            lastSigner = signer;
        }
        signerSize = uint64(_signers.length);
        quorum = _quorum;
    }

    function _setSigner(address _signer, bool _active) internal {
        if (signers[_signer] == _active) {
            revert MultiSig_StateAlreadySet(_signer, _active);
        }
        signers[_signer] = _active;
        uint64 _signerSize = _active ? signerSize + 1 : signerSize - 1;
        uint64 _quorum = quorum;
        if (_signerSize < _quorum) {
            revert MultiSig_SignersSizeIsLessThanQuorum(_signerSize, _quorum);
        }
        signerSize = _signerSize;
        emit UpdateSigner(_signer, _active);
    }

    function _setQuorum(uint64 _quorum) internal {
        if (_quorum == 0) {
            revert MultiSig_QuorumIsZero();
        }
        uint64 _signerSize = signerSize;
        if (_signerSize < _quorum) {
            revert MultiSig_SignersSizeIsLessThanQuorum(_signerSize, _quorum);
        }
        quorum = _quorum;
        emit UpdateQuorum(_quorum);
    }

    function verifySignatures(bytes32 _hash, bytes calldata _signatures) public view returns (bool, Errors) {
        if (_signatures.length != uint256(quorum) * 65) {
            return (false, Errors.SignatureError);
        }

        bytes32 messageDigest = _getEthSignedMessageHash(_hash);

        address lastSigner = address(0); // There cannot be a signer with address 0.
        for (uint256 i = 0; i < quorum; i++) {
            bytes calldata signature = _signatures[i * 65:(i + 1) * 65];
            (address currentSigner, ECDSA.RecoverError error) = ECDSA.tryRecover(messageDigest, signature);

            if (error != ECDSA.RecoverError.NoError) return (false, Errors.SignatureError);
            if (currentSigner <= lastSigner) return (false, Errors.DuplicatedSigner); // prevent duplicate signatures
            if (!signers[currentSigner]) return (false, Errors.SignerNotInCommittee); // signature is not in committee
            lastSigner = currentSigner;
        }
        return (true, Errors.NoError);
    }

    function _getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }
}
