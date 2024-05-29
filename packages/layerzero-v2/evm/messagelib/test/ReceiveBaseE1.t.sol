// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";

import { ReceiveLibBaseE1 } from "../contracts/uln/uln301/ReceiveLibBaseE1.sol";

import { TokenMock } from "./mocks/TokenMock.sol";

contract ReceiveLibBaseE1Test is ReceiveLibBaseE1, Test {
    uint32 internal constant EID = 1;
    address internal constant ENDPOINT = address(0x11);

    constructor() ReceiveLibBaseE1(ENDPOINT, EID) {}

    function test_execute() public {
        // if the receiver is not the contract, just emit the event instead of calling the endpoint
        executors[address(0x22)][2] = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        vm.expectEmit(false, false, false, true, address(this));
        emit InvalidDst(2, bytes32(uint256(0x11)), address(0x22), 1, keccak256("message"));
        _execute(2, bytes32(uint256(0x11)), address(0x22), 1, "message", 0);

        // if the receiver is the contract, call the endpoint
        address receiver = address(new TokenMock()); // mock receiver is a contract
        executors[receiver][2] = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        addressSizes[2] = 20;
        vm.mockCall(ENDPOINT, abi.encodeWithSelector(ILayerZeroEndpoint.receivePayload.selector), "");
        _execute(2, bytes32(uint256(0x11)), receiver, 1, "message", 0);
    }

    function setConfig(uint16, address, uint256, bytes calldata) external {}

    function getConfig(uint16, address, uint256) external view returns (bytes memory) {}
}
