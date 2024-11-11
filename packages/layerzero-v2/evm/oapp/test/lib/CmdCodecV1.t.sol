// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test, console } from "forge-std/Test.sol";
import { EVMCallRequestV1, EVMCallComputeV1, ReadCmdCodecV1 } from "../../contracts/oapp/libs/ReadCmdCodecV1.sol";
import { CmdCodecV1Mock } from "../../contracts/oapp/examples/CmdCodecV1Mock.sol";

contract CmdCodecV1Test is Test {
    CmdCodecV1Mock internal codec = new CmdCodecV1Mock();

    function test_codec() public {
        // requests
        EVMCallRequestV1 memory evmCallRequest1 = EVMCallRequestV1({
            appRequestLabel: 1,
            targetEid: 2,
            isBlockNum: true,
            blockNumOrTimestamp: 3,
            confirmations: 4,
            to: address(5),
            callData: hex"1234"
        });
        EVMCallRequestV1 memory evmCallRequest2 = EVMCallRequestV1({
            appRequestLabel: 2,
            targetEid: 2,
            isBlockNum: true,
            blockNumOrTimestamp: 3,
            confirmations: 4,
            to: address(5),
            callData: hex"5678"
        });
        EVMCallRequestV1[] memory evmCallRequests = new EVMCallRequestV1[](2);
        evmCallRequests[0] = evmCallRequest1;
        evmCallRequests[1] = evmCallRequest2;

        // compute
        EVMCallComputeV1 memory compute = EVMCallComputeV1({
            computeSetting: 1,
            targetEid: 8,
            isBlockNum: false,
            blockNumOrTimestamp: 9,
            confirmations: 10,
            to: address(11)
        });

        uint16 appCmdLabel = 1;
        bytes memory cmd = codec.encode(appCmdLabel, evmCallRequests, compute);

        (
            uint16 actualAppCmdLabel,
            EVMCallRequestV1[] memory actualEvmCallRequests,
            EVMCallComputeV1 memory actualCompute
        ) = codec.decode(cmd);

        assertEq(actualAppCmdLabel, appCmdLabel, "AppCmdLabel should match");
        assertEVMCallRequestV1Eq(actualEvmCallRequests[0], evmCallRequest1);
        assertEVMCallRequestV1Eq(actualEvmCallRequests[1], evmCallRequest2);
        assertEVMCallComputeV1Eq(actualCompute, compute);

        // test no compute encode/decode
        cmd = codec.encode(appCmdLabel, evmCallRequests);

        (actualAppCmdLabel, actualEvmCallRequests, actualCompute) = codec.decode(cmd);
        assertEq(actualAppCmdLabel, appCmdLabel, "AppCmdLabel should match");
        assertEVMCallRequestV1Eq(actualEvmCallRequests[0], evmCallRequest1);
        assertEVMCallRequestV1Eq(actualEvmCallRequests[1], evmCallRequest2);

        EVMCallComputeV1 memory emptyCompute;
        assertEVMCallComputeV1Eq(actualCompute, emptyCompute);
    }

    // ------------------------------- utils -------------------------------

    function assertEVMCallRequestV1Eq(EVMCallRequestV1 memory a, EVMCallRequestV1 memory b) internal {
        assertEq(a.appRequestLabel, b.appRequestLabel, "AppRequestLabel should match");
        assertEq(a.targetEid, b.targetEid, "TargetEid should match");
        assertEq(a.isBlockNum, b.isBlockNum, "IsBlockNum should match");
        assertEq(a.blockNumOrTimestamp, b.blockNumOrTimestamp, "BlockNumOrTimestamp should match");
        assertEq(a.confirmations, b.confirmations, "Confirmations should match");
        assertEq(a.to, b.to, "To should match");
        assertEq(a.callData, b.callData, "CallData should match");
    }

    function assertEVMCallComputeV1Eq(EVMCallComputeV1 memory a, EVMCallComputeV1 memory b) internal {
        assertEq(a.computeSetting, b.computeSetting, "ComputeSetting should match");
        assertEq(a.targetEid, b.targetEid, "TargetEid should match");
        assertEq(a.isBlockNum, b.isBlockNum, "IsBlockNum should match");
        assertEq(a.blockNumOrTimestamp, b.blockNumOrTimestamp, "BlockNumOrTimestamp should match");
        assertEq(a.confirmations, b.confirmations, "Confirmations should match");
        assertEq(a.to, b.to, "To should match");
    }
}
