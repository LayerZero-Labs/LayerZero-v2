// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { SupportedCmdTypes, SupportedCmdTypesLib } from "./SupportedCmdTypes.sol";

library ReadCmdCodecV1 {
    uint16 internal constant CMD_VERSION = 1;
    uint8 internal constant REQUEST_VERSION = 1;
    uint16 internal constant RESOLVER_TYPE_SINGLE_VIEW_EVM_CALL = 1;
    uint8 internal constant COMPUTE_VERSION = 1;
    uint16 internal constant COMPUTE_TYPE_SINGLE_VIEW_EVM_CALL = 1;

    uint8 internal constant COMPUTE_SETTING_MAP_ONLY = 0;
    uint8 internal constant COMPUTE_SETTING_REDUCE_ONLY = 1;
    uint8 internal constant COMPUTE_SETTING_MAP_AND_REDUCE = 2;

    error InvalidCmd();
    error InvalidVersion();
    error InvalidType();

    struct Cmd {
        uint16 numEvmCallRequestV1;
        bool evmCallComputeV1Map;
        bool evmCallComputeV1Reduce;
    }

    function decode(
        bytes calldata _cmd,
        function(uint32, bool, uint64, uint8) view _assertCmdTypeSupported
    ) internal view returns (Cmd memory cmd) {
        uint256 cursor = 0;
        // decode the header in scope, depress stack too deep
        {
            uint16 cmdVersion = uint16(bytes2(_cmd[cursor:cursor + 2]));
            cursor += 2;
            if (cmdVersion != CMD_VERSION) revert InvalidVersion();

            cursor += 2; // skip appCmdLabel

            uint16 requestCount = uint16(bytes2(_cmd[cursor:cursor + 2]));
            cursor += 2;

            // there is only one request type in this version, so total request count should be the same as numEvmCallRequestV1
            if (requestCount == 0) revert InvalidCmd();
            cmd.numEvmCallRequestV1 = requestCount;
        }

        // decode the requests
        for (uint16 i = 0; i < cmd.numEvmCallRequestV1; i++) {
            uint8 requestVersion = uint8(_cmd[cursor]);
            cursor += 1;
            if (requestVersion != REQUEST_VERSION) revert InvalidVersion();

            // skip appRequestLabel
            cursor += 2;

            uint16 resolverType = uint16(bytes2(_cmd[cursor:cursor + 2]));
            cursor += 2;

            if (resolverType == RESOLVER_TYPE_SINGLE_VIEW_EVM_CALL) {
                uint16 requestSize = uint16(bytes2(_cmd[cursor:cursor + 2]));
                cursor += 2;

                // decode the request in scope, depress stack too deep
                {
                    uint256 requestCursor = cursor;
                    uint32 targetEid = uint32(bytes4(_cmd[requestCursor:requestCursor + 4]));
                    requestCursor += 4;

                    bool isBlockNum = uint8(_cmd[requestCursor]) == 1;
                    requestCursor += 1;

                    uint64 blockNumOrTimestamp = uint64(bytes8(_cmd[requestCursor:requestCursor + 8]));

                    _assertCmdTypeSupported(
                        targetEid,
                        isBlockNum,
                        blockNumOrTimestamp,
                        SupportedCmdTypesLib.CMD_V1__REQUEST_V1__EVM_CALL
                    );
                }

                if (cursor + requestSize > _cmd.length) revert InvalidCmd();
                cursor += requestSize;
            } else {
                revert InvalidType();
            }
        }

        // decode the compute if it exists
        if (cursor < _cmd.length) {
            uint8 computeVersion = uint8(_cmd[cursor]);
            cursor += 1;
            if (computeVersion != COMPUTE_VERSION) revert InvalidVersion();

            uint16 computeType = uint16(bytes2(_cmd[cursor:cursor + 2]));
            cursor += 2;
            if (computeType != COMPUTE_TYPE_SINGLE_VIEW_EVM_CALL) revert InvalidType();

            uint8 computeSetting = uint8(_cmd[cursor]);
            cursor += 1;

            if (computeSetting == COMPUTE_SETTING_MAP_ONLY) {
                cmd.evmCallComputeV1Map = true;
            } else if (computeSetting == COMPUTE_SETTING_REDUCE_ONLY) {
                cmd.evmCallComputeV1Reduce = true;
            } else if (computeSetting == COMPUTE_SETTING_MAP_AND_REDUCE) {
                cmd.evmCallComputeV1Map = true;
                cmd.evmCallComputeV1Reduce = true;
            } else {
                revert InvalidType();
            }

            uint32 targetEid = uint32(bytes4(_cmd[cursor:cursor + 4]));
            cursor += 4;

            bool isBlockNum = uint8(_cmd[cursor]) == 1;
            cursor += 1;

            uint64 blockNumOrTimestamp = uint64(bytes8(_cmd[cursor:cursor + 8]));
            cursor += 8;

            _assertCmdTypeSupported(
                targetEid,
                isBlockNum,
                blockNumOrTimestamp,
                SupportedCmdTypesLib.CMD_V1__COMPUTE_V1__EVM_CALL
            );

            // assert the remaining length: confirmations(2), to(20)
            cursor += 22;
        }
        if (cursor != _cmd.length) revert InvalidCmd();
    }
}
