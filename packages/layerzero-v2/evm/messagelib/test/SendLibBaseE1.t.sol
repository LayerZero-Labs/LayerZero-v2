// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";
import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { WorkerOptions, ExecutorConfig } from "../contracts/SendLibBase.sol";
import { SendLibBaseE1 } from "../contracts/uln/uln301/SendLibBaseE1.sol";
import { INonceContract } from "../contracts/uln/uln301/interfaces/INonceContract.sol";
import { ILayerZeroExecutor } from "../contracts/interfaces/ILayerZeroExecutor.sol";

contract SendLibBaseE1Test is SendLibBaseE1, Test {
    uint32 internal constant EID = 1;
    address internal constant ENDPOINT = address(0x11);
    address internal constant NONCE_CONTRACT = address(0x22);
    address internal constant TREASURY_FEE_HANDLER = address(0x33);
    address internal constant EXECUTOR = address(0x44);

    constructor() SendLibBaseE1(ENDPOINT, type(uint256).max, 0, NONCE_CONTRACT, EID, TREASURY_FEE_HANDLER) {}

    function test_withdrawFee() public {
        // mock alice has 1000 native fee
        address alice = address(0xabcd);
        fees[alice] = 1000;
        vm.deal(address(this), 1000);

        // withdraw 100 native fee
        vm.prank(alice);
        address receiver = address(0x1234);
        this.withdrawFee(receiver, 100);
        assertEq(fees[alice], 900);
        assertEq(receiver.balance, 100);
    }

    function test_assertPath(address _sender, bytes calldata _receiver) public {
        bytes memory path = abi.encodePacked(_receiver, _sender);
        this.assertPath(_sender, path, _receiver.length);

        // revert if address is wrong
        vm.expectRevert(LZ_MessageLib_InvalidPath.selector);
        this.assertPath(_sender, path, _receiver.length + 1);
    }

    function test_send() public {
        address sender = address(0xaa);
        uint16 dstEid = 2;
        address receiver = address(0xbb);
        bytes memory path = abi.encodePacked(receiver, sender);
        bytes memory message = "message";
        addressSizes[dstEid] = 20;
        executorConfigs[address(0x0)][dstEid] = ExecutorConfig(20, EXECUTOR);

        // mock calls
        vm.startPrank(ENDPOINT);
        vm.mockCall(NONCE_CONTRACT, abi.encodeWithSelector(INonceContract.increment.selector), abi.encode(uint64(1)));
        vm.mockCall(EXECUTOR, abi.encodeWithSelector(ILayerZeroExecutor.assignJob.selector), abi.encode(200));

        // the message fee is 300 (100 + 200)
        vm.deal(ENDPOINT, 300);
        vm.expectEmit(false, false, false, true, address(this));
        emit PacketSent("packet", "", 300, 0);
        this.send{ value: 300 }(sender, 0, dstEid, path, message, payable(sender), sender, "");

        // if send with 400 fee, 100 will be refunded to sender
        vm.deal(ENDPOINT, 400);
        this.send{ value: 400 }(sender, 0, dstEid, path, message, payable(sender), sender, "");
        assertEq(sender.balance, 100);
    }

    function _payVerifier(
        Packet memory,
        WorkerOptions[] memory
    ) internal pure override returns (uint256, bytes memory) {
        return (100, "packet");
    }

    function _quoteVerifier(address, uint32, WorkerOptions[] memory) internal view override returns (uint256) {}

    function version() external view returns (uint64, uint8, uint8) {}

    function _splitOptions(bytes calldata) internal view override returns (bytes memory, WorkerOptions[] memory) {}

    function setConfig(uint16, address, uint256, bytes calldata) external {}

    function getConfig(uint16, address, uint256) external view returns (bytes memory) {}

    function getDefaultConfig(uint32 _eid, uint32 _configType) external view returns (bytes memory) {}

    function assertPath(address _sender, bytes calldata _path, uint256 remoteAddressSize) external pure {
        _assertPath(_sender, _path, remoteAddressSize);
    }
}
