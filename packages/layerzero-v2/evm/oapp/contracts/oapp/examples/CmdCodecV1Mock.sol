// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { EVMCallRequestV1, EVMCallComputeV1, ReadCmdCodecV1 } from "../libs/ReadCmdCodecV1.sol";

contract CmdCodecV1Mock {
    function decode(
        bytes calldata _cmd
    )
        external
        pure
        returns (uint16 appCmdLabel, EVMCallRequestV1[] memory evmRequests, EVMCallComputeV1 memory compute)
    {
        return ReadCmdCodecV1.decode(_cmd);
    }

    function encode(
        uint16 _appCmdLabel,
        EVMCallRequestV1[] calldata _evmRequests
    ) external pure returns (bytes memory) {
        return ReadCmdCodecV1.encode(_appCmdLabel, _evmRequests);
    }

    function encode(
        uint16 _appCmdLabel,
        EVMCallRequestV1[] calldata _evmRequests,
        EVMCallComputeV1 calldata _evmCompute
    ) external pure returns (bytes memory) {
        return ReadCmdCodecV1.encode(_appCmdLabel, _evmRequests, _evmCompute);
    }
}
