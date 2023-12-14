// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ILayerZeroDVN } from "../contracts/uln/interfaces/ILayerZeroDVN.sol";
import { DVNAdapterBase } from "../contracts/uln/dvn/adapters/DVNAdapterBase.sol";
import { DVNAdapterFeeLibBase } from "../contracts/uln/dvn/adapters/DVNAdapterFeeLibBase.sol";
import { SendLibMock } from "./mocks/SendLibMock.sol";
import { ReceiveLibMock } from "./mocks/ReceiveLibMock.sol";

contract DVNAdapterBaseHarness is DVNAdapterBase {
    constructor(
        address _sendLib,
        address _receiveLib,
        address[] memory _admins
    ) DVNAdapterBase(_sendLib, _receiveLib, _admins) {}

    function exposed_PACKET_HEADER_SIZE() external pure returns (uint256) {
        return PACKET_HEADER_SIZE;
    }

    function exposed_PAYLOAD_SIZE() external pure returns (uint256) {
        return PAYLOAD_SIZE;
    }

    function exposed_assertBalanceAndWithdrawFee(uint256 _messageFee) external {
        _assertBalanceAndWithdrawFee(_messageFee);
    }

    function exposed_encodePayload(
        bytes memory _packetHeader,
        bytes32 _payloadHash
    ) external pure returns (bytes memory payload) {
        return _encodePayload(_packetHeader, _payloadHash);
    }

    function exposed_decodePayload(bytes memory _payload) external pure returns (bytes memory, bytes32) {
        return _decodePayload(_payload);
    }

    function assignJob(AssignJobParam calldata, bytes calldata) external payable returns (uint256) {
        return 0;
    }

    function getFee(uint32, uint64, address, bytes calldata) external pure returns (uint256) {
        return 0;
    }
}

contract DVNAdapterFeeLib is DVNAdapterFeeLibBase {}

contract DVNAdapterBaseTest is Test {
    DVNAdapterBaseHarness dvnAdapter;
    SendLibMock sendLib;
    ReceiveLibMock receiveLib;

    address admin = address(0x01);

    function setUp() public {
        address[] memory admins = new address[](1);
        admins[0] = admin;
        sendLib = new SendLibMock();
        receiveLib = new ReceiveLibMock();
        dvnAdapter = new DVNAdapterBaseHarness(address(sendLib), address(receiveLib), admins);
    }

    function testFuzz_setAdmin(address newAdmin) public {
        dvnAdapter.setAdmin(newAdmin, true);
        assertEq(dvnAdapter.admins(newAdmin), true);

        dvnAdapter.setAdmin(newAdmin, false);
        assertEq(dvnAdapter.admins(newAdmin), false);
    }

    function test_setAdmin_notOwner_revert() public {
        address newAdmin = vm.addr(1);

        vm.prank(admin);
        vm.expectRevert();
        dvnAdapter.setAdmin(newAdmin, true);
    }

    function testFuzz_setDefaultMultiplier(uint16 defaultMultiplierBps) public {
        vm.prank(admin);
        dvnAdapter.setDefaultMultiplier(defaultMultiplierBps);

        assertEq(dvnAdapter.defaultMultiplierBps(), defaultMultiplierBps);
    }

    function testFuzz_setAdmin_notAdmin_revert(address caller, uint16 defaultMultiplierBps) public {
        vm.assume(caller != admin);

        vm.prank(caller);
        vm.expectRevert(DVNAdapterBase.Unauthorized.selector);
        dvnAdapter.setDefaultMultiplier(defaultMultiplierBps);
    }

    function test_setFeeLib() public {
        DVNAdapterFeeLib feeLib = new DVNAdapterFeeLib();

        vm.prank(admin);
        dvnAdapter.setFeeLib(address(feeLib));

        assertEq(address(dvnAdapter.feeLib()), address(feeLib));
    }

    function testFuzz_setFeeLib_notAdmin_revert(address caller) public {
        vm.assume(caller != admin);

        DVNAdapterFeeLib feeLib = new DVNAdapterFeeLib();

        vm.prank(caller);
        vm.expectRevert(DVNAdapterBase.Unauthorized.selector);
        dvnAdapter.setFeeLib(address(feeLib));
    }

    function testFuzz_withdrawFee(uint256 fee) public {
        assertEq(address(dvnAdapter).balance, 0);

        vm.deal(admin, fee);
        vm.prank(admin);
        sendLib.setFee{ value: fee }(address(dvnAdapter));

        vm.prank(admin);
        dvnAdapter.withdrawFee(address(dvnAdapter), fee);

        assertEq(address(dvnAdapter).balance, fee);
    }

    function testFuzz_assertBalanceAndWithdrawFee_sufficientBalance_noWithdraw(uint256 fee) public {
        vm.deal(address(dvnAdapter), fee);
        assertEq(address(dvnAdapter).balance, fee);

        dvnAdapter.exposed_assertBalanceAndWithdrawFee(fee);
        assertEq(address(dvnAdapter).balance, fee);
    }

    function testFuzz_assertBalanceAndWithdrawFee_insufficientBalance_withdraw(uint256 fee) public {
        vm.deal(admin, fee);
        vm.prank(admin);
        sendLib.setFee{ value: fee }(address(dvnAdapter));
        assertEq(sendLib.fees(address(dvnAdapter)), fee);
        assertEq(address(dvnAdapter).balance, 0);

        dvnAdapter.exposed_assertBalanceAndWithdrawFee(fee);
        assertEq(address(dvnAdapter).balance, fee);
        assertEq(sendLib.fees(address(dvnAdapter)), 0);
    }

    function testFuzz_encodePayload(bytes memory packetHeader, bytes32 payloadHash) public {
        vm.assume(packetHeader.length == dvnAdapter.exposed_PACKET_HEADER_SIZE());

        bytes memory expected = abi.encodePacked(packetHeader, payloadHash);
        bytes memory actual = dvnAdapter.exposed_encodePayload(packetHeader, payloadHash);

        assertEq(actual, expected);
    }

    function testFuzz_decodePayload(bytes memory packetHeader, bytes32 payloadHash) public {
        vm.assume(packetHeader.length == dvnAdapter.exposed_PACKET_HEADER_SIZE());

        bytes memory payload = abi.encodePacked(packetHeader, payloadHash);
        (bytes memory actualPacketHeader, bytes32 actualPayloadHash) = dvnAdapter.exposed_decodePayload(payload);

        assertEq(actualPacketHeader, packetHeader);
        assertEq(actualPayloadHash, payloadHash);
    }

    function testFuzz_decodePayload_invalidPayloadSize_revert(bytes memory payload) public {
        vm.assume(payload.length != dvnAdapter.exposed_PAYLOAD_SIZE());

        vm.expectRevert(DVNAdapterBase.InvalidPayloadSize.selector);
        dvnAdapter.exposed_decodePayload(payload);
    }
}
