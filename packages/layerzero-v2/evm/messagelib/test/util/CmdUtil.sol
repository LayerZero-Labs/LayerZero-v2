// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

library CmdUtil {
    struct EVMCallRequestV1 {
        uint16 appRequestLabel; // Label identifying the application or type of request (can be use in lzCompute)
        uint32 targetEid; // Target endpoint ID (representing a target blockchain)
        bool isBlockNum; // True if the request = block number, false if timestamp
        uint64 blockNumOrTimestamp; // Block number or timestamp to use in the request
        uint16 confirmations; // Number of block confirmations on top of the requested block number or timestamp before the view function can be called
        address to; // Address of the target contract on the target chain
        bytes callData; // Calldata for the contract call
    }

    struct EVMCallComputeV1 {
        uint8 computeSetting; // Compute setting (0 = map only, 1 = reduce only, 2 = map reduce)
        uint32 targetEid; // Target endpoint ID (representing a target blockchain)
        bool isBlockNum; // True if the request = block number, false if timestamp
        uint64 blockNumOrTimestamp; // Block number or timestamp to use in the request
        uint16 confirmations; // Number of block confirmations on top of the requested block number or timestamp before the view function can be called
        address to; // Address of the target contract on the target chain
    }

    uint16 internal constant CMD_VERSION = 1;

    uint8 internal constant REQUEST_VERSION = 1;
    uint16 internal constant RESOLVER_TYPE_SINGLE_VIEW_EVM_CALL = 1;

    uint8 internal constant COMPUTE_VERSION = 1;
    uint16 internal constant COMPUTE_TYPE_SINGLE_VIEW_EVM_CALL = 1;

    error InvalidVersion();
    error InvalidType();

    function decode(
        bytes calldata _cmd
    )
        internal
        pure
        returns (uint16 appCmdLabel, EVMCallRequestV1[] memory evmCallRequests, EVMCallComputeV1 memory compute)
    {
        uint256 offset = 0;
        uint16 cmdVersion = uint16(bytes2(_cmd[offset:offset + 2]));
        offset += 2;
        if (cmdVersion != CMD_VERSION) revert InvalidVersion();

        appCmdLabel = uint16(bytes2(_cmd[offset:offset + 2]));
        offset += 2;

        (evmCallRequests, offset) = decodeRequestsV1(_cmd, offset);

        // decode the compute if it exists
        if (offset < _cmd.length) {
            (compute, ) = decodeEVMCallComputeV1(_cmd, offset);
        }
    }

    function decodeRequestsV1(
        bytes calldata _cmd,
        uint256 _offset
    ) internal pure returns (EVMCallRequestV1[] memory evmCallRequests, uint256 newOffset) {
        newOffset = _offset;
        uint16 requestCount = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
        newOffset += 2;

        evmCallRequests = new EVMCallRequestV1[](requestCount);
        for (uint16 i = 0; i < requestCount; i++) {
            uint8 requestVersion = uint8(_cmd[newOffset]);
            newOffset += 1;
            if (requestVersion != REQUEST_VERSION) revert InvalidVersion();

            uint16 appRequestLabel = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
            newOffset += 2;

            uint16 resolverType = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
            newOffset += 2;

            if (resolverType == RESOLVER_TYPE_SINGLE_VIEW_EVM_CALL) {
                (EVMCallRequestV1 memory request, uint256 nextOffset) = decodeEVMCallRequestV1(
                    _cmd,
                    newOffset,
                    appRequestLabel
                );
                newOffset = nextOffset;
                evmCallRequests[i] = request;
            } else {
                revert InvalidType();
            }
        }
    }

    function decodeEVMCallRequestV1(
        bytes calldata _cmd,
        uint256 _offset,
        uint16 _appRequestLabel
    ) internal pure returns (EVMCallRequestV1 memory request, uint256 newOffset) {
        newOffset = _offset;
        request.appRequestLabel = _appRequestLabel;

        uint16 requestSize = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
        newOffset += 2;
        request.targetEid = uint32(bytes4(_cmd[newOffset:newOffset + 4]));
        newOffset += 4;
        request.isBlockNum = uint8(_cmd[newOffset]) == 1;
        newOffset += 1;
        request.blockNumOrTimestamp = uint64(bytes8(_cmd[newOffset:newOffset + 8]));
        newOffset += 8;
        request.confirmations = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
        newOffset += 2;
        request.to = address(bytes20(_cmd[newOffset:newOffset + 20]));
        newOffset += 20;
        uint16 callDataSize = requestSize - 35;
        request.callData = _cmd[newOffset:newOffset + callDataSize];
        newOffset += callDataSize;
    }

    function decodeEVMCallComputeV1(
        bytes calldata _cmd,
        uint256 _offset
    ) internal pure returns (EVMCallComputeV1 memory compute, uint256 newOffset) {
        newOffset = _offset;
        uint8 computeVersion = uint8(_cmd[newOffset]);
        newOffset += 1;
        if (computeVersion != COMPUTE_VERSION) revert InvalidVersion();
        uint16 computeType = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
        newOffset += 2;
        if (computeType != COMPUTE_TYPE_SINGLE_VIEW_EVM_CALL) revert InvalidType();

        compute.computeSetting = uint8(_cmd[newOffset]);
        newOffset += 1;
        compute.targetEid = uint32(bytes4(_cmd[newOffset:newOffset + 4]));
        newOffset += 4;
        compute.isBlockNum = uint8(_cmd[newOffset]) == 1;
        newOffset += 1;
        compute.blockNumOrTimestamp = uint64(bytes8(_cmd[newOffset:newOffset + 8]));
        newOffset += 8;
        compute.confirmations = uint16(bytes2(_cmd[newOffset:newOffset + 2]));
        newOffset += 2;
        compute.to = address(bytes20(_cmd[newOffset:newOffset + 20]));
        newOffset += 20;
    }

    function decodeCmdAppLabel(bytes calldata _cmd) internal pure returns (uint16) {
        uint256 offset = 0;
        uint16 cmdVersion = uint16(bytes2(_cmd[offset:offset + 2]));
        offset += 2;
        if (cmdVersion != CMD_VERSION) revert InvalidVersion();

        return uint16(bytes2(_cmd[offset:offset + 2]));
    }

    function decodeRequestV1AppRequestLabel(bytes calldata _request) internal pure returns (uint16) {
        uint256 offset = 0;
        uint8 requestVersion = uint8(_request[offset]);
        offset += 1;
        if (requestVersion != REQUEST_VERSION) revert InvalidVersion();

        return uint16(bytes2(_request[offset:offset + 2]));
    }

    function encode(
        uint16 _appCmdLabel,
        EVMCallRequestV1[] memory _evmCallRequests,
        EVMCallComputeV1 memory _evmCallCompute
    ) internal pure returns (bytes memory) {
        bytes memory cmd = abi.encodePacked(CMD_VERSION, _appCmdLabel, uint16(_evmCallRequests.length));
        for (uint256 i = 0; i < _evmCallRequests.length; i++) {
            cmd = appendEVMCallRequestV1(cmd, _evmCallRequests[i]);
        }
        if (_evmCallCompute.targetEid != 0) {
            // if eid is 0, it means no compute
            cmd = appendEVMCallComputeV1(cmd, _evmCallCompute);
        }
        return cmd;
    }

    function appendEVMCallRequestV1(
        bytes memory _cmd,
        EVMCallRequestV1 memory _request
    ) internal pure returns (bytes memory) {
        bytes memory newCmd = abi.encodePacked(
            _cmd,
            REQUEST_VERSION,
            _request.appRequestLabel,
            RESOLVER_TYPE_SINGLE_VIEW_EVM_CALL,
            uint16(_request.callData.length + 35),
            _request.targetEid
        );
        return
            abi.encodePacked(
                newCmd,
                _request.isBlockNum,
                _request.blockNumOrTimestamp,
                _request.confirmations,
                _request.to,
                _request.callData
            );
    }

    function appendEVMCallComputeV1(
        bytes memory _cmd,
        EVMCallComputeV1 memory _compute
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _cmd,
                COMPUTE_VERSION,
                COMPUTE_TYPE_SINGLE_VIEW_EVM_CALL,
                _compute.computeSetting,
                _compute.targetEid,
                _compute.isBlockNum,
                _compute.blockNumOrTimestamp,
                _compute.confirmations,
                _compute.to
            );
    }
}
