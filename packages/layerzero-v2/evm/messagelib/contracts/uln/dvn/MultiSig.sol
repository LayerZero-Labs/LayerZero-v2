// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract MultiSig {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum Errors {
        NoError,
        SignatureError,
        DuplicatedSigner,
        SignerNotInCommittee
    }

    EnumerableSet.AddressSet internal signerSet;
    uint64 public quorum;

    error MultiSig_OnlySigner();
    error MultiSig_QuorumIsZero();
    error MultiSig_SignersSizeIsLessThanQuorum(uint64 signersSize, uint64 quorum);
    error MultiSig_UnorderedSigners();
    error MultiSig_StateAlreadySet(address signer, bool active);
    error MultiSig_StateNotSet(address signer, bool active);
    error MultiSig_InvalidSigner();

    event UpdateSigner(address _signer, bool _active);
    event UpdateQuorum(uint64 _quorum);

    modifier onlySigner() {
        if (!isSigner(msg.sender)) {
            revert MultiSig_OnlySigner();
        }
        _;
    }

    constructor(address[] memory _signers, uint64 _quorum) {
        if (_quorum == 0) {
            revert MultiSig_QuorumIsZero();
        }
        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            if (signer == address(0)) {
                revert MultiSig_InvalidSigner();
            }
            signerSet.add(signer);
        }

        uint64 _signerSize = uint64(signerSet.length());
        if (_signerSize < _quorum) {
            revert MultiSig_SignersSizeIsLessThanQuorum(_signerSize, _quorum);
        }

        quorum = _quorum;
    }

    function _setSigner(address _signer, bool _active) internal {
        if (_active) {
            if (_signer == address(0)) {
                revert MultiSig_InvalidSigner();
            }
            if (!signerSet.add(_signer)) {
                revert MultiSig_StateAlreadySet(_signer, _active);
            }
        } else {
            if (!signerSet.remove(_signer)) {
                revert MultiSig_StateNotSet(_signer, _active);
            }
        }

        uint64 _signerSize = uint64(signerSet.length());
        uint64 _quorum = quorum;
        if (_signerSize < _quorum) {
            revert MultiSig_SignersSizeIsLessThanQuorum(_signerSize, _quorum);
        }
        emit UpdateSigner(_signer, _active);
    }

    function _setQuorum(uint64 _quorum) internal {
        if (_quorum == 0) {
            revert MultiSig_QuorumIsZero();
        }
        uint64 _signerSize = uint64(signerSet.length());
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
            // the quorum is guaranteed not to be zero in the constructor and setter
            bytes calldata signature = _signatures[i * 65:(i + 1) * 65];
            (address currentSigner, ECDSA.RecoverError error) = ECDSA.tryRecover(messageDigest, signature);

            if (error != ECDSA.RecoverError.NoError) return (false, Errors.SignatureError);
            if (currentSigner <= lastSigner) return (false, Errors.DuplicatedSigner); // prevent duplicate signatures, the signers must be ordered to sign the digest
            if (!isSigner(currentSigner)) return (false, Errors.SignerNotInCommittee); // signature is not in committee
            lastSigner = currentSigner;
        }
        return (true, Errors.NoError);
    }

    function _getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    // ============================================== View ==============================================
    function getSigners() public view returns (address[] memory) {
        return signerSet.values();
    }

    // compatibility with the previous version
    function signers(address _signer) public view returns (bool) {
        return isSigner(_signer);
    }

    function isSigner(address _signer) public view returns (bool) {
        return signerSet.contains(_signer);
    }

    function signerSize() public view returns (uint256) {
        return signerSet.length();
    }
}
