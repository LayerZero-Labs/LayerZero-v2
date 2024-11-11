// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test, console } from "forge-std/Test.sol";

import { ReadCmdCodecV1 } from "../../contracts/uln/libs/ReadCmdCodecV1.sol";
import { SupportedCmdTypes, SupportedCmdTypesLib, BitMap256 } from "../../contracts/uln/libs/SupportedCmdTypes.sol";

contract ReadCmdCodecV1Test is Test {
    uint32 internal supportedEid = 666;
    ReadCodecV1Wrapper internal cmdCodec;

    uint16 internal constant CMD_VERSION = 1;
    uint16 internal constant APP_LABEL = 0;
    uint16 internal constant REQUEST_COUNT_1 = 1;
    uint16 internal constant REQUEST_COUNT_2 = 2;

    uint8 internal constant REQUEST_VERSION = 1;
    uint16 internal constant REQUEST_LABEL = 0;
    uint16 internal constant REQUEST_RESOLVER_TYPE_EVM_CALL = 1;
    bytes internal requestData = abi.encodePacked(uint8(1), uint64(100), "other request data"); // isBlockNum, blockNumOrTimestamp, other data
    uint16 internal requestSize = uint16(requestData.length) + 4; // 4 bytes for targetEid
    // request data

    uint8 internal constant COMPUTE_VERSION = 1;
    uint16 internal constant COMPUTE_TYPE_EVM_CALL = 1;
    uint8 internal constant COMPUTE_SETTING_MAP_ONLY = 0;
    uint8 internal constant COMPUTE_SETTING_REDUCE_ONLY = 1;
    uint8 internal constant COMPUTE_SETTING_MAP_AND_REDUCE = 2;
    bytes internal computeData = new bytes(31);
    // compute data

    function setUp() public {
        cmdCodec = new ReadCodecV1Wrapper(supportedEid, 3);
    }

    function test_revert_less_than_2_bytes() public {
        bytes memory cmd = hex"00";
        vm.expectRevert();
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_cmd_version() public {
        bytes memory cmd = hex"dead";
        vm.expectRevert(ReadCmdCodecV1.InvalidVersion.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_req_type() public {
        uint16 wrongRequestType = 666;
        bytes memory cmd = abi.encodePacked(CMD_VERSION, APP_LABEL, REQUEST_COUNT_1, wrongRequestType);
        vm.expectRevert(ReadCmdCodecV1.InvalidVersion.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_zero_request_count() public {
        bytes memory cmd = abi.encodePacked(CMD_VERSION, APP_LABEL, uint16(0));
        vm.expectRevert(ReadCmdCodecV1.InvalidCmd.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_req_resolver_type() public {
        uint16 wrongResolverType = 666;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            wrongResolverType
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidType.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_unsupported_eid() public {
        uint32 unsupportedEid = 2;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            unsupportedEid,
            requestData
        );
        vm.expectRevert(SupportedCmdTypesLib.UnsupportedTargetEid.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_req_size() public {
        uint16 exceedReqSize = requestSize + 1;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            exceedReqSize,
            supportedEid,
            requestData
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidCmd.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_compute_version() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION + 666
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidVersion.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_unsupported_compute_type() public {
        uint16 wrongComputeType = 666;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            wrongComputeType
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidType.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_unsupported_compute_setting() public {
        uint8 wrongComputeSetting = 222;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            wrongComputeSetting
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidType.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_unsupported_compute_target_eid() public {
        uint32 unsupportedEid = 2;
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_ONLY,
            unsupportedEid,
            computeData
        );
        vm.expectRevert(SupportedCmdTypesLib.UnsupportedTargetEid.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_invalid_compute_data_size() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_ONLY,
            supportedEid,
            new bytes(32) // more than 31
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidCmd.selector);
        cmdCodec.decode(cmd);

        cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_ONLY,
            supportedEid,
            new bytes(30) // less than 31
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidCmd.selector);
        cmdCodec.decode(cmd);
    }

    function test_revert_unused_bytes_in_end() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_ONLY,
            supportedEid,
            computeData,
            hex"deadbeef"
        );
        vm.expectRevert(ReadCmdCodecV1.InvalidCmd.selector);
        cmdCodec.decode(cmd);
    }

    function test_success_1_req_map_only() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_ONLY,
            supportedEid,
            computeData
        );
        ReadCmdCodecV1.Cmd memory ret = cmdCodec.decode(cmd);
        assertEq(ret.numEvmCallRequestV1, 1);
        assertEq(ret.evmCallComputeV1Map, true);
        assertEq(ret.evmCallComputeV1Reduce, false);
    }

    function test_success_1_req_reduce_only() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_REDUCE_ONLY,
            supportedEid,
            computeData
        );
        ReadCmdCodecV1.Cmd memory ret = cmdCodec.decode(cmd);
        assertEq(ret.numEvmCallRequestV1, 1);
        assertEq(ret.evmCallComputeV1Map, false);
        assertEq(ret.evmCallComputeV1Reduce, true);
    }

    function test_success_1_req_map_and_reduce() public {
        bytes memory cmd = abi.encodePacked(
            CMD_VERSION,
            APP_LABEL,
            REQUEST_COUNT_1,
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData,
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_AND_REDUCE,
            supportedEid,
            computeData
        );
        ReadCmdCodecV1.Cmd memory ret = cmdCodec.decode(cmd);
        assertEq(ret.numEvmCallRequestV1, 1);
        assertEq(ret.evmCallComputeV1Map, true);
        assertEq(ret.evmCallComputeV1Reduce, true);
    }

    function test_success_2_req_map_reduce() public {
        bytes memory cmd = abi.encodePacked(CMD_VERSION, APP_LABEL, REQUEST_COUNT_2);
        cmd = abi.encodePacked(
            cmd,
            // request 1
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData
        );
        cmd = abi.encodePacked(
            cmd,
            // request 2
            REQUEST_VERSION,
            REQUEST_LABEL,
            REQUEST_RESOLVER_TYPE_EVM_CALL,
            requestSize,
            supportedEid,
            requestData
        );
        cmd = abi.encodePacked(
            cmd,
            // compute
            COMPUTE_VERSION,
            COMPUTE_TYPE_EVM_CALL,
            COMPUTE_SETTING_MAP_AND_REDUCE,
            supportedEid,
            computeData
        );
        ReadCmdCodecV1.Cmd memory ret = cmdCodec.decode(cmd);
        assertEq(ret.numEvmCallRequestV1, 2);
        assertEq(ret.evmCallComputeV1Map, true);
        assertEq(ret.evmCallComputeV1Reduce, true);
    }
}

// Wrap the library functions inorder to get calldata bytes
contract ReadCodecV1Wrapper {
    SupportedCmdTypes internal supportedCmdTypes;

    constructor(uint32 dstEid, uint256 bm) {
        supportedCmdTypes.cmdTypes[dstEid] = BitMap256.wrap(bm);
    }

    function decode(bytes calldata _cmd) external view returns (ReadCmdCodecV1.Cmd memory cmd) {
        return ReadCmdCodecV1.decode(_cmd, _assertCmdTypeSupported);
    }

    function _assertCmdTypeSupported(
        uint32 _targetEid,
        bool /*_isBlockNum*/,
        uint64 /*_blockNumOrTimestamp*/,
        uint8 _cmdType
    ) internal view {
        supportedCmdTypes.assertSupported(_targetEid, _cmdType);
    }
}
