// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { MultiSig } from "../contracts/uln/dvn/MultiSig.sol";

contract MultiSigTest is MultiSig, Test {
    constructor() MultiSig(_getSigners(), 2) {}

    function _getSigners() internal pure returns (address[] memory) {
        address[] memory signers = new address[](2);
        signers[0] = vm.addr(2); //0x2B5AD5c4795c026514f8317c7a215E218DcCD6cF
        signers[1] = vm.addr(3); //0x6813Eb9362372EEF6200f3b1dbC3f819671cBA69
        return signers;
    }

    function test_getSigners() public {
        address[] memory signers = this.getSigners();
        assertEq(signers[0], vm.addr(2));
        assertEq(signers[1], vm.addr(3));
        assertEq(signers.length, 2);
    }

    function test_isSigner() public {
        assertEq(isSigner(vm.addr(2)), true);
        assertEq(isSigner(vm.addr(3)), true);
        assertEq(isSigner(vm.addr(4)), false);
    }

    function test_setSigner() public {
        // only two signers
        assertEq(signers(vm.addr(2)), true);
        assertEq(signers(vm.addr(3)), true);
        assertEq(signers(vm.addr(4)), false);
        assertEq(signerSize(), 2);

        // add a new signer
        address newSigner = vm.addr(4);
        bool active = true;
        _setSigner(newSigner, active);
        assertEq(signerSize(), 3);

        // cant add address(0) as a signer
        vm.expectRevert(abi.encodeWithSelector(MultiSig_InvalidSigner.selector));
        _setSigner(address(0), active);

        // cant add a signer twice
        vm.expectRevert(abi.encodeWithSelector(MultiSig_StateAlreadySet.selector, newSigner, active));
        _setSigner(newSigner, active);

        // remove a signer
        _setSigner(newSigner, !active);
        assertEq(signerSize(), 2);

        // signer size must be >= quorum after removing a signer
        vm.expectRevert(abi.encodeWithSelector(MultiSig_SignersSizeIsLessThanQuorum.selector, uint64(1), uint64(2)));
        _setSigner(vm.addr(3), false);
    }

    function test_setQuorum() public {
        assertEq(quorum, 2);

        // cant set quorum to 0
        vm.expectRevert(MultiSig_QuorumIsZero.selector);
        _setQuorum(0);

        // cant set quorum to more than signer size
        vm.expectRevert(abi.encodeWithSelector(MultiSig_SignersSizeIsLessThanQuorum.selector, uint64(2), uint64(3)));
        _setQuorum(3);

        // set quorum to 1
        _setQuorum(1);
        assertEq(quorum, 1);

        // set quorum to 2
        _setQuorum(2);
        assertEq(quorum, 2);
    }

    function test_verifySignatures() public {
        bytes32 hash = keccak256(bytes("message"));

        bytes memory sig1 = _generateSignature(2, hash); // sign with private key 2
        bytes memory sig2 = _generateSignature(3, hash); // sign with private key 3
        bytes memory sigNotInCommittee = _generateSignature(4, hash); // sign with private key 4

        // if only one signature is provided, it should fail for invalid size
        (bool verified, MultiSig.Errors error) = this.verifySignatures(hash, sig1);
        assertEq(verified, false);
        assertTrue(error == MultiSig.Errors.SignatureError);

        // if duplicate signatures are provided, it should fail
        bytes memory duplicateSignatures = bytes.concat(sig1, sig1);
        (verified, error) = this.verifySignatures(hash, duplicateSignatures);
        assertEq(verified, false);
        assertTrue(error == MultiSig.Errors.DuplicatedSigner);

        // if signatures are not in ascending order, it should fail
        bytes memory signaturesNotInOrder = bytes.concat(sig2, sig1);
        (verified, error) = this.verifySignatures(hash, signaturesNotInOrder);
        assertEq(verified, false);
        assertTrue(error == MultiSig.Errors.DuplicatedSigner);

        // if signatures are not from signers, it should fail
        bytes memory signaturesNotFromSigners = bytes.concat(sigNotInCommittee, sig1);
        (verified, error) = this.verifySignatures(hash, signaturesNotFromSigners);
        assertEq(verified, false);
        assertTrue(error == MultiSig.Errors.SignerNotInCommittee);

        // passes
        bytes memory signatures = bytes.concat(sig1, sig2);
        (verified, error) = this.verifySignatures(hash, signatures);
        assertEq(verified, true);
        assertTrue(error == MultiSig.Errors.NoError);
    }

    function _generateSignature(uint256 _privateKey, bytes32 _hash) internal pure returns (bytes memory signature) {
        bytes32 ethSignedMessageHash = _getEthSignedMessageHash(_hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, ethSignedMessageHash);
        signature = abi.encodePacked(r, s, v);
    }
}
