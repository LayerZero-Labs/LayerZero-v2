// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { IMessageLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { IMessagingChannel } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import { SendLibBaseE2 } from "../contracts/SendLibBaseE2.sol";
import { WorkerOptions } from "../contracts/SendLibBase.sol";

import { TokenMock } from "./mocks/TokenMock.sol";

contract SendLibBaseE2Test is Test {
    uint32 internal eid = 1;
    address internal endpoint = address(0x1234);
    SendLibBaseE2Mock internal msglib;
    SendLibBaseE2Mock internal msglibAlt;

    address internal treasury = address(0x5678);
    TokenMock internal lzToken = new TokenMock();
    TokenMock internal altToken = new TokenMock();
    address internal alice = address(0x1111);

    function setUp() public {
        // mock endpoint
        vm.mockCall(endpoint, abi.encodeWithSelector(IMessagingChannel.eid.selector), abi.encode(eid));
        vm.mockCall(
            endpoint,
            abi.encodeWithSelector(ILayerZeroEndpointV2.nativeToken.selector),
            abi.encode(address(0))
        );
        msglib = new SendLibBaseE2Mock(endpoint);
        msglib.setTreasury(treasury);

        vm.mockCall(
            endpoint,
            abi.encodeWithSelector(ILayerZeroEndpointV2.nativeToken.selector),
            abi.encode(address(altToken))
        );
        msglibAlt = new SendLibBaseE2Mock(endpoint);
        msglibAlt.setTreasury(treasury);

        // mock alice has 1000 altToken fee and 1000 native coin fee
        vm.deal(address(msglib), 1000); // 1000 native coin
        msglib.mockFee(alice, 1000); // 1000 altToken

        altToken.transfer(address(msglibAlt), 1000);
        msglibAlt.mockFee(alice, 1000); // 1000 altToken

        // treasury fee 1000
        lzToken.transfer(address(msglib), 1000);
    }

    function test_supportsInterface() public {
        assertEq(msglib.supportsInterface(type(IMessageLib).interfaceId), true);
        assertEq(msglib.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(msglib.supportsInterface(type(IMessagingChannel).interfaceId), false);
    }

    function test_withdrawFee_nativeFee() public {
        address receiver = address(0x2222);

        // withdraw 100 native coin to receiver
        vm.prank(alice);

        // mock endpoint
        vm.mockCall(
            endpoint,
            abi.encodeWithSelector(ILayerZeroEndpointV2.nativeToken.selector),
            abi.encode(address(0))
        );
        msglib.withdrawFee(receiver, 100);
        assertEq(address(msglib).balance, 900);
        assertEq(receiver.balance, 100);
        assertEq(msglib.fees(alice), 900);
    }

    function test_withdrawFee_altTokenFee() public {
        address receiver = address(0x2222);

        // withdraw 100 native coin to receiver
        vm.prank(alice);
        msglibAlt.withdrawFee(receiver, 100);
        assertEq(msglibAlt.fees(alice), 900);
        assertEq(altToken.balanceOf(address(msglibAlt)), 900);
        assertEq(altToken.balanceOf(receiver), 100);
    }

    function test_withdrawLzTokenFee() public {
        address receiver = address(0x2222);

        // mock endpoint has altToken
        vm.mockCall(
            endpoint,
            abi.encodeWithSelector(ILayerZeroEndpointV2.nativeToken.selector),
            abi.encode(address(altToken))
        );

        // treasury cannot withdraw altToken
        vm.startPrank(treasury);
        vm.expectRevert(SendLibBaseE2.CannotWithdrawAltToken.selector);
        msglib.withdrawLzTokenFee(address(altToken), receiver, 100);

        // treasury can withdraw lzToken
        msglib.withdrawLzTokenFee(address(lzToken), receiver, 100);
        assertEq(lzToken.balanceOf(address(msglib)), 900);
        assertEq(lzToken.balanceOf(receiver), 100);
    }
}

contract SendLibBaseE2Mock is SendLibBaseE2 {
    constructor(address _endpoint) SendLibBaseE2(_endpoint, type(uint256).max, 0) {}

    function setConfig(address, SetConfigParam[] calldata) external {}

    function getConfig(uint32, address, uint32) external view returns (bytes memory) {}

    function getDefaultConfig(uint32 _eid, uint32 _configType) external view returns (bytes memory) {}

    function isSupportedEid(uint32 _eid) external view returns (bool) {}

    function _quoteVerifier(address, uint32, WorkerOptions[] memory) internal view override returns (uint256) {}

    function version() external view returns (uint64, uint8, uint8) {}

    function _splitOptions(bytes calldata) internal view override returns (bytes memory, WorkerOptions[] memory) {}

    function _payVerifier(Packet calldata, WorkerOptions[] memory) internal override returns (uint256, bytes memory) {}

    function mockFee(address _owner, uint256 _fee) external {
        fees[_owner] = _fee;
    }
}
