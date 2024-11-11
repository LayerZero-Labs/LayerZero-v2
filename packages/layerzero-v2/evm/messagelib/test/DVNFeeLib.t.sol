// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test, console } from "forge-std/Test.sol";

import { IDVN } from "../contracts/uln/interfaces/IDVN.sol";
import { IDVNFeeLib } from "../contracts/uln/interfaces/IDVNFeeLib.sol";
import { DVNFeeLib } from "../contracts/uln/dvn/DVNFeeLib.sol";
import { DVN, ExecuteParam } from "../contracts/uln/dvn/DVN.sol";
import { SupportedCmdTypes, BitMap256 } from "../contracts/uln/libs/SupportedCmdTypes.sol";
import { ReadLib1002 } from "../contracts/uln/readlib/ReadLib1002.sol";
import { ReceiveUln302 } from "../contracts/uln/uln302/ReceiveUln302.sol";

import { PriceFeedMock } from "./mocks/PriceFeedMock.sol";
import { CmdUtil } from "./util/CmdUtil.sol";

contract DVNFeeLibTest is Test, DVNFeeLib {
    DVNFeeLib dvnFeeLib;
    PriceFeedMock priceFeed;
    IDVN.DstConfig config;
    uint16 defaultMultiplierBps = 12000;
    uint32 localEid = 100;
    uint32 dstEid = 101;
    uint256 gasFee = 100;
    uint128 priceRatio = 1e10;
    uint128 nativePriceUSD = 2000e10;
    uint64 gas = 1;
    uint16 multiplierBps = 10000;
    uint128 floorMarginUSD = 3e10;
    uint64 quorum = 3;
    address oapp = address(0);
    uint64 confirmations = 15;

    uint120 internal OneUSD = 1e10;
    uint120 internal REQUEST_PER_JOB = OneUSD;
    uint120 internal REDUCE_PER_JOB = OneUSD;
    uint16 internal MAP_PER_REQ_JOB = 1000; // 10%

    constructor() DVNFeeLib(100, 1e18) {}

    function setUp() public {
        priceFeed = new PriceFeedMock();

        dvnFeeLib = new DVNFeeLib(localEid, 1e18);
        dvnFeeLib.setCmdFees(REQUEST_PER_JOB, REDUCE_PER_JOB, MAP_PER_REQ_JOB); // 1u, 1u, 1000
        setDVNFeeLibSupportedCmdTypes(dstEid, 3);

        priceFeed.setup(gasFee, priceRatio, nativePriceUSD);
    }

    // quorum * signatureRawBytes == 0
    function test_getFee_notPadded_defaultMultiplier() public {
        quorum = 32;
        config = IDVN.DstConfig(gas, 0, 0);

        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    // quorum * signatureRawBytes != 0
    function test_getFee_padded_defaultMultiplier() public {
        config = IDVN.DstConfig(gas, 0, 0);

        uint256 expected = (gasFee * defaultMultiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_specificMultiplier() public {
        config = IDVN.DstConfig(gas, multiplierBps, 0);

        uint256 expected = (gasFee * multiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_floorMargin() public {
        config = IDVN.DstConfig(gas, multiplierBps, floorMarginUSD);

        uint256 expected = gasFee + (floorMarginUSD * 1e18) / nativePriceUSD;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_nativeTokenPriceZero_specificMultiplier() public {
        config = IDVN.DstConfig(gas, multiplierBps, floorMarginUSD);
        priceFeed.setup(gasFee, priceRatio, 0);

        uint256 expected = (gasFee * multiplierBps) / 10000;
        IDVNFeeLib.FeeParams memory params = IDVNFeeLib.FeeParams(
            address(priceFeed),
            dstEid,
            confirmations,
            oapp,
            quorum,
            defaultMultiplierBps
        );
        uint256 actual = dvnFeeLib.getFee(params, config, "");

        assertEq(actual, expected);
    }

    function test_getFee_read_defaultMultiplier() public {
        config = IDVN.DstConfig(gas, 0, 0);

        uint8 requestNum = 5;
        uint256 expected = (((requestNum * REQUEST_PER_JOB * 1e18) / nativePriceUSD + gasFee) * defaultMultiplierBps) /
            10000;
        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );
        bytes memory cmd = buildCmd(requestNum, false, 0);
        uint256 actual = dvnFeeLib.getFee(params, config, cmd, "");
        assertEq(actual, expected);

        // with map only, request_fee * (1+MAP_PER_REQ_JOB)
        expected =
            (((((requestNum * REQUEST_PER_JOB * 1e18) / nativePriceUSD) * (10000 + MAP_PER_REQ_JOB)) / 10000 + gasFee) *
                defaultMultiplierBps) /
            10000;
        cmd = buildCmd(requestNum, true, 0);
        actual = dvnFeeLib.getFee(params, config, cmd, "");
        assertEq(actual, expected);

        // with reduce only, request_fee + REDUCE_PER_JOB
        expected =
            ((((((requestNum * REQUEST_PER_JOB + REDUCE_PER_JOB) * 1e18) / nativePriceUSD)) + gasFee) *
                defaultMultiplierBps) /
            10000;
        cmd = buildCmd(requestNum, true, 1);
        actual = dvnFeeLib.getFee(params, config, cmd, "");
        assertEq(actual, expected);

        // with map and reduce, request_fee * (1+MAP_PER_REQ_JOB) + REDUCE_PER_JOB
        expected =
            ((((((requestNum * REQUEST_PER_JOB * (10000 + MAP_PER_REQ_JOB)) / 10000 + REDUCE_PER_JOB) * 1e18) /
                nativePriceUSD) + gasFee) * defaultMultiplierBps) /
            10000;
        cmd = buildCmd(requestNum, true, 2);
        actual = dvnFeeLib.getFee(params, config, cmd, "");
        assertEq(actual, expected);
    }

    function test_getFee_read_specificMultiplier() public {
        config = IDVN.DstConfig(gas, multiplierBps, 0);

        uint8 requestNum = 5;
        uint256 expected = (((requestNum * REQUEST_PER_JOB * 1e18) / nativePriceUSD + gasFee) * multiplierBps) / 10000;
        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );
        bytes memory cmd = buildCmd(requestNum, false, 0);
        uint256 actual = dvnFeeLib.getFee(params, config, cmd, "");
        assertEq(actual, expected);
    }

    function test_setSupportedCmdTypes() public {
        DVNFeeLib.SetSupportedCmdTypesParam[] memory params = new DVNFeeLib.SetSupportedCmdTypesParam[](1);
        params[0] = DVNFeeLib.SetSupportedCmdTypesParam(1, BitMap256.wrap(1));
        dvnFeeLib.setSupportedCmdTypes(params);

        uint256 bm = BitMap256.unwrap(dvnFeeLib.getSupportedCmdTypes(1));
        assertEq(bm, 1);
    }

    function test_getReadCallDataSize() public {
        uint256[] memory quorums = new uint256[](4);
        quorums[0] = 1;
        quorums[1] = 64;
        quorums[2] = 128;
        quorums[3] = 200;

        for (uint256 i = 0; i < quorums.length; i++) {
            uint256 qum = quorums[i];
            bytes memory header = new bytes(81);
            bytes memory callData = abi.encodeWithSelector(ReadLib1002.verify.selector, header, bytes32(0), bytes32(0)); // verify(bytes calldata _packetHeader, bytes32 _cmdHash, bytes32 _payloadHash)
            bytes memory signatures = new bytes(65 * qum);
            ExecuteParam[] memory params = new ExecuteParam[](1);
            params[0] = ExecuteParam(0, address(0), callData, 0, signatures);
            uint256 expected = abi.encodeWithSelector(DVN.execute.selector, params).length; // dvn.execute(params)
            uint256 actual = _getReadCallDataSize(qum);
            assertEq(actual, expected);
        }
    }

    function test_getCallDataSize() public {
        uint256[] memory quorums = new uint256[](4);
        quorums[0] = 1;
        quorums[1] = 64;
        quorums[2] = 128;
        quorums[3] = 200;

        for (uint256 i = 0; i < quorums.length; i++) {
            uint256 qum = quorums[i];
            bytes memory header = new bytes(81);
            bytes memory callData = abi.encodeWithSelector(
                ReceiveUln302.verify.selector,
                header,
                bytes32(0),
                uint64(0)
            ); // verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations)
            bytes memory signatures = new bytes(65 * qum);
            ExecuteParam[] memory params = new ExecuteParam[](1);
            params[0] = ExecuteParam(0, address(0), callData, 0, signatures);
            uint256 expected = abi.encodeWithSelector(DVN.execute.selector, params).length; // dvn.execute(params)
            uint256 actual = _getCallDataSize(qum);
            assertEq(actual, expected);
        }
    }

    function test_revert_request_TimestampOutOfReach() public {
        setBlock(1000, 1000);
        setDVNFeeLibSupportedCmdTypes(dstEid, 7); // 1 + 2 + 4
        config = IDVN.DstConfig(gas, 0, 0);

        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );

        setFeeLibBlockConfig(dstEid, 500, 500, 90);

        // request timestamp out of reach
        uint64 pinTimestamp = uint64(block.timestamp) - 100; // set it out of reach
        bytes memory cmd = buildCmd(1, false, 0, false, pinTimestamp, false, uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinTimestamp));
        dvnFeeLib.getFee(params, config, cmd, "");

        pinTimestamp = uint64(block.timestamp) + 100; // set it out of reach
        cmd = buildCmd(1, false, 0, false, pinTimestamp, false, uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinTimestamp));
        dvnFeeLib.getFee(params, config, cmd, "");
    }

    function test_revert_compute_TimestampOutOfReach() public {
        setBlock(1000, 1000);
        setDVNFeeLibSupportedCmdTypes(dstEid, 7); // 1 + 2 + 4
        config = IDVN.DstConfig(gas, 0, 0);

        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );

        setFeeLibBlockConfig(dstEid, 500, 500, 90);

        // request timestamp out of reach
        uint64 pinTimestamp = uint64(block.timestamp) - 100; // set it out of reach
        bytes memory cmd = buildCmd(1, true, 2, false, uint64(block.timestamp), false, pinTimestamp);
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinTimestamp));
        dvnFeeLib.getFee(params, config, cmd, "");

        pinTimestamp = uint64(block.timestamp) + 100; // set it out of reach
        cmd = buildCmd(1, true, 2, false, uint64(block.timestamp), false, pinTimestamp);
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinTimestamp));
        dvnFeeLib.getFee(params, config, cmd, "");
    }

    function test_revert_request_BlockOutOfReach() public {
        setBlock(1000, 1000);
        setDVNFeeLibSupportedCmdTypes(dstEid, 7); // 1 + 2 + 4
        config = IDVN.DstConfig(gas, 0, 0);

        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );

        setFeeLibBlockConfig(dstEid, 500, 500, 90); // 90 sec retention

        // request block number out of reach
        uint64 pinBlockNum = uint64(block.number) - 99; // set it out of reach
        bytes memory cmd = buildCmd(1, false, 0, true, pinBlockNum, true, uint64(block.number));
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinBlockNum));
        dvnFeeLib.getFee(params, config, cmd, "");

        pinBlockNum = uint64(block.number) + 99; // set it out of reach
        cmd = buildCmd(1, false, 0, true, pinBlockNum, true, uint64(block.number));
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinBlockNum));
        dvnFeeLib.getFee(params, config, cmd, "");
    }

    function test_revert_compute_BlockOutOfReach() public {
        setBlock(1000, 1000);
        setDVNFeeLibSupportedCmdTypes(dstEid, 7); // 1 + 2 + 4
        config = IDVN.DstConfig(gas, 0, 0);

        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );

        setFeeLibBlockConfig(dstEid, 500, 500, 90); // 90 sec retention

        // request block number out of reach
        uint64 pinBlockNum = uint64(block.number) - 99; // set it out of reach
        bytes memory cmd = buildCmd(1, true, 2, true, uint64(block.number), true, pinBlockNum);
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinBlockNum));
        dvnFeeLib.getFee(params, config, cmd, "");

        pinBlockNum = uint64(block.number) + 99; // set it out of reach
        cmd = buildCmd(1, true, 2, true, uint64(block.number), true, pinBlockNum);
        vm.expectRevert(abi.encodeWithSelector(DVN_TimestampOutOfRange.selector, dstEid, pinBlockNum));
        dvnFeeLib.getFee(params, config, cmd, "");
    }

    function test_success_with_valid_blockNum() public {
        setBlock(1000, 1000);
        setDVNFeeLibSupportedCmdTypes(dstEid, 7); // 1 + 2 + 4
        config = IDVN.DstConfig(gas, 0, 0);

        IDVNFeeLib.FeeParamsForRead memory params = IDVNFeeLib.FeeParamsForRead(
            address(priceFeed),
            oapp,
            quorum,
            defaultMultiplierBps
        );

        setFeeLibBlockConfig(dstEid, 500, 500, 90); // 90 sec retention

        // request block number out of reach
        uint64 pinBlockNum = uint64(block.number) - 10; // set it within reach
        bytes memory cmd = buildCmd(1, true, 2, true, pinBlockNum, true, pinBlockNum);
        uint256 fee = dvnFeeLib.getFee(params, config, cmd, "");
        assertGt(fee, 0);
    }

    // ---------------------------- Test Helpers ----------------------------
    function buildCmd(
        uint256 requestNum,
        bool hasComputeSetting,
        uint8 computeSetting
    ) internal view returns (bytes memory) {
        return buildCmd(requestNum, hasComputeSetting, computeSetting, false, 0, false, 0);
    }

    function buildCmd(
        uint256 requestNum,
        bool hasComputeSetting,
        uint8 computeSetting,
        bool requestIsBlockNum,
        uint64 requestBlockNumOrTimestamp,
        bool computeIsBlockNum,
        uint64 computeBlockNumOrTimestamp
    ) internal view returns (bytes memory) {
        CmdUtil.EVMCallRequestV1[] memory requests = new CmdUtil.EVMCallRequestV1[](requestNum);
        for (uint256 i = 0; i < requestNum; i++) {
            CmdUtil.EVMCallRequestV1 memory request = CmdUtil.EVMCallRequestV1({
                targetEid: dstEid,
                appRequestLabel: 0,
                isBlockNum: requestIsBlockNum,
                blockNumOrTimestamp: requestBlockNumOrTimestamp,
                callData: new bytes(10),
                confirmations: 0,
                to: oapp
            });
            requests[i] = request;
        }
        CmdUtil.EVMCallComputeV1 memory compute = CmdUtil.EVMCallComputeV1({
            computeSetting: computeSetting,
            to: oapp,
            isBlockNum: computeIsBlockNum,
            blockNumOrTimestamp: computeBlockNumOrTimestamp,
            confirmations: 0,
            targetEid: hasComputeSetting ? dstEid : 0
        });
        return CmdUtil.encode(0, requests, compute);
    }

    function setDVNFeeLibSupportedCmdTypes(uint32 _targetEid, uint256 _cmdTypes) public {
        SetSupportedCmdTypesParam[] memory params = new SetSupportedCmdTypesParam[](1);
        params[0] = SetSupportedCmdTypesParam(_targetEid, BitMap256.wrap(_cmdTypes));
        dvnFeeLib.setSupportedCmdTypes(params);
    }

    function setBlock(uint64 _blockNum, uint64 _timestamp) public {
        vm.roll(_blockNum);
        vm.warp(_timestamp);
    }

    function setFeeLibBlockConfig(uint32 _dstEid, uint64 _blockNum, uint64 _timestamp, uint32 _maxRetention) public {
        uint32[] memory _dstEids = new uint32[](1);
        _dstEids[0] = _dstEid;
        DVNFeeLib.BlockTimeConfig[] memory _snapshots = new DVNFeeLib.BlockTimeConfig[](1);
        _snapshots[0] = DVNFeeLib.BlockTimeConfig(1000, _blockNum, _timestamp, _maxRetention, _maxRetention); // 1 sec per block
        dvnFeeLib.setDstBlockTimeConfigs(_dstEids, _snapshots);
    }
}
