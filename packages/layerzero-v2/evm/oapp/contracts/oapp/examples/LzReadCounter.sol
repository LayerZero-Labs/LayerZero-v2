// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ILayerZeroEndpointV2, MessagingFee, MessagingReceipt, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { ReadCmdCodecV1, EVMCallComputeV1, EVMCallRequestV1 } from "../libs/ReadCmdCodecV1.sol";
import { IOAppComputer } from "../interfaces/IOAppComputer.sol";

import { OAppRead } from "../OAppRead.sol";

contract LzReadCounter is OAppRead, IOAppComputer {
    struct EvmReadRequest {
        uint16 appRequestLabel;
        uint32 targetEid;
        bool isBlockNum;
        uint64 blockNumOrTimestamp;
        uint16 confirmations;
        address to;
        uint256 countAddition; // addition to add to the count when reading
    }

    struct ComputeSetting {
        uint8 computeSetting;
        uint16 computeConfirmations;
        uint64 blockNumOrTimestamp;
        bool isBlockNum;
    }

    uint8 internal constant COMPUTE_SETTING_MAP_ONLY = 0;
    uint8 internal constant COMPUTE_SETTING_REDUCE_ONLY = 1;
    uint8 internal constant COMPUTE_SETTING_MAP_REDUCE = 2;
    uint8 internal constant COMPUTE_SETTING_NONE = 3;

    uint32 public immutable eid;
    uint256 public count;

    constructor(address _endpoint) OAppRead(_endpoint, msg.sender) {
        eid = ILayerZeroEndpointV2(_endpoint).eid();
    }

    // -------------------------------
    // Trigger Read
    function triggerRead(
        uint32 _channelId, // The read channel id
        uint16 _appLabel, // The cmd app label
        EvmReadRequest[] memory _requests,
        ComputeSetting memory _computeSetting,
        bytes calldata _options
    ) external payable returns (MessagingReceipt memory receipt) {
        bytes memory cmd = buildCmd(_appLabel, _requests, _computeSetting);
        count += 1; // increase the count, for pin block testing
        return _lzSend(_channelId, cmd, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function clearCount() external {
        count = 0;
    }

    // -------------------------------
    // View
    function quote(
        uint32 _channelId,
        uint16 _appLabel,
        EvmReadRequest[] memory _requests,
        ComputeSetting memory _computeSetting,
        bytes calldata _options
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        bytes memory cmd = buildCmd(_appLabel, _requests, _computeSetting);
        MessagingFee memory fee = _quote(_channelId, cmd, _options, false);
        return (fee.nativeFee, fee.lzTokenFee);
    }

    function buildCmd(
        uint16 appLabel,
        EvmReadRequest[] memory _readRequests,
        ComputeSetting memory _computeSetting
    ) public view returns (bytes memory) {
        require(_readRequests.length > 0, "LzReadCounter: empty requests");
        // build read requests
        EVMCallRequestV1[] memory readRequests = new EVMCallRequestV1[](_readRequests.length);
        for (uint256 i = 0; i < _readRequests.length; i++) {
            EvmReadRequest memory req = _readRequests[i];
            readRequests[i] = EVMCallRequestV1({
                appRequestLabel: req.appRequestLabel,
                targetEid: req.targetEid,
                isBlockNum: req.isBlockNum,
                blockNumOrTimestamp: req.blockNumOrTimestamp,
                confirmations: req.confirmations,
                to: req.to,
                callData: abi.encodeWithSelector(this.readCount.selector, req.countAddition)
            });
        }
        // build compute, on current contract
        require(_computeSetting.computeSetting <= COMPUTE_SETTING_NONE, "LzReadCounter: invalid compute type");
        EVMCallComputeV1 memory evmCompute = EVMCallComputeV1({
            computeSetting: _computeSetting.computeSetting,
            targetEid: _computeSetting.computeSetting == COMPUTE_SETTING_NONE ? 0 : eid, // 0(means no compute) for none, else use local eid
            isBlockNum: _computeSetting.isBlockNum,
            blockNumOrTimestamp: _computeSetting.blockNumOrTimestamp,
            confirmations: _computeSetting.computeConfirmations,
            to: address(this)
        });
        bytes memory cmd = ReadCmdCodecV1.encode(appLabel, readRequests, evmCompute);

        return cmd;
    }

    function readCount(uint256 countAddition) external view returns (uint256) {
        require(countAddition != 9, "LzReadCounter: invalid count addition"); // This is only for testing
        return count + countAddition;
    }

    function lzMap(bytes calldata _request, bytes calldata _response) external pure returns (bytes memory) {
        require(_response.length == 32, "LzReadCounter: invalid response length");
        uint16 requestId = ReadCmdCodecV1.decodeRequestV1AppRequestLabel(_request);
        uint256 countNum = abi.decode(_response, (uint256));
        return abi.encode(countNum + 100 + requestId * 1000); // map behavior
    }

    function lzReduce(bytes calldata _cmd, bytes[] calldata _responses) external pure returns (bytes memory) {
        uint256 total = 0;
        for (uint256 i = 0; i < _responses.length; i++) {
            require(_responses[i].length == 32, "LzReadCounter: invalid response length");
            uint256 countNum = abi.decode(_responses[i], (uint256));
            total += countNum;
        }
        total += 10000; // reduce behavior

        uint16 cmdAppLabel = ReadCmdCodecV1.decodeCmdAppLabel(_cmd);
        total += uint256(cmdAppLabel) * 100000; // cmdAppLabel behavior

        return abi.encode(total);
    }

    // -------------------------------
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        require(_message.length % 32 == 0, "LzReadCounter: invalid message length");
        uint256 total = 0;
        // loop read bytes32 of the message and decode it to uint256 then add it to the total
        for (uint256 i = 0; i < _message.length; i += 32) {
            total += abi.decode(_message[i:i + 32], (uint256));
        }
        // reset count if it's too large
        if (count >= 2 ** 128) {
            count = 0;
        }
        count += total;
    }

    // be able to receive ether
    receive() external payable virtual {}

    fallback() external payable {}
}
