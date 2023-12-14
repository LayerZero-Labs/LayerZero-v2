// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { ILayerZeroDVN } from "./interfaces/ILayerZeroDVN.sol";
import { DVNOptions } from "./libs/DVNOptions.sol";
import { UlnOptions } from "./libs/UlnOptions.sol";
import { WorkerOptions } from "../SendLibBase.sol";
import { UlnConfig, UlnBase } from "./UlnBase.sol";

/// @dev includes the utility functions for checking ULN states and logics
abstract contract SendUlnBase is UlnBase {
    event DVNFeePaid(address[] requiredDVNs, address[] optionalDVNs, uint256[] fees);

    function _splitUlnOptions(bytes calldata _options) internal pure returns (bytes memory, WorkerOptions[] memory) {
        (bytes memory executorOpts, bytes memory dvnOpts) = UlnOptions.decode(_options);

        if (dvnOpts.length == 0) {
            return (executorOpts, new WorkerOptions[](0));
        }

        WorkerOptions[] memory workerOpts = new WorkerOptions[](1);
        workerOpts[0] = WorkerOptions(DVNOptions.WORKER_ID, dvnOpts);
        return (executorOpts, workerOpts);
    }

    /// ---------- pay and assign jobs ----------

    function _payDVNs(
        mapping(address => uint256) storage _fees,
        Packet memory _packet,
        WorkerOptions[] memory _options
    ) internal returns (uint256 totalFee, bytes memory encodedPacket) {
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(_packet);
        bytes memory payload = PacketV1Codec.encodePayload(_packet);
        bytes32 payloadHash = keccak256(payload);
        uint32 dstEid = _packet.dstEid;
        address sender = _packet.sender;
        UlnConfig memory config = getUlnConfig(sender, dstEid);

        // if options is not empty, it must be dvn options
        bytes memory dvnOptions = _options.length == 0 ? bytes("") : _options[0].options;
        uint256[] memory dvnFees;
        (totalFee, dvnFees) = _assignJobs(
            _fees,
            config,
            ILayerZeroDVN.AssignJobParam(dstEid, packetHeader, payloadHash, config.confirmations, sender),
            dvnOptions
        );
        encodedPacket = abi.encodePacked(packetHeader, payload);

        emit DVNFeePaid(config.requiredDVNs, config.optionalDVNs, dvnFees);
    }

    function _assignJobs(
        mapping(address => uint256) storage _fees,
        UlnConfig memory _ulnConfig,
        ILayerZeroDVN.AssignJobParam memory _param,
        bytes memory dvnOptions
    ) internal returns (uint256 totalFee, uint256[] memory dvnFees) {
        (bytes[] memory optionsArray, uint8[] memory dvnIds) = DVNOptions.groupDVNOptionsByIdx(dvnOptions);

        uint8 dvnsLength = _ulnConfig.requiredDVNCount + _ulnConfig.optionalDVNCount;
        dvnFees = new uint256[](dvnsLength);
        for (uint8 i = 0; i < dvnsLength; ++i) {
            address dvn = i < _ulnConfig.requiredDVNCount
                ? _ulnConfig.requiredDVNs[i]
                : _ulnConfig.optionalDVNs[i - _ulnConfig.requiredDVNCount];

            bytes memory options = "";
            for (uint256 j = 0; j < dvnIds.length; ++j) {
                if (dvnIds[j] == i) {
                    options = optionsArray[j];
                    break;
                }
            }

            dvnFees[i] = ILayerZeroDVN(dvn).assignJob(_param, options);
            if (dvnFees[i] > 0) {
                _fees[dvn] += dvnFees[i];
                totalFee += dvnFees[i];
            }
        }
    }

    /// ---------- quote ----------
    function _quoteDVNs(
        address _sender,
        uint32 _dstEid,
        WorkerOptions[] memory _options
    ) internal view returns (uint256 totalFee) {
        UlnConfig memory config = getUlnConfig(_sender, _dstEid);

        // if options is not empty, it must be dvn options
        bytes memory dvnOptions = _options.length == 0 ? bytes("") : _options[0].options;
        (bytes[] memory optionsArray, uint8[] memory dvnIndices) = DVNOptions.groupDVNOptionsByIdx(dvnOptions);

        totalFee = _getFees(config, _dstEid, _sender, optionsArray, dvnIndices);
    }

    function _getFees(
        UlnConfig memory _config,
        uint32 _dstEid,
        address _sender,
        bytes[] memory _optionsArray,
        uint8[] memory _dvnIds
    ) internal view returns (uint256 totalFee) {
        // here we merge 2 list of dvns into 1 to allocate the indexed dvn options to the right dvn
        uint8 dvnsLength = _config.requiredDVNCount + _config.optionalDVNCount;
        for (uint8 i = 0; i < dvnsLength; ++i) {
            address dvn = i < _config.requiredDVNCount
                ? _config.requiredDVNs[i]
                : _config.optionalDVNs[i - _config.requiredDVNCount];

            bytes memory options = "";
            // it is a double loop here. however, if the list is short, the cost is very acceptable.
            for (uint256 j = 0; j < _dvnIds.length; ++j) {
                if (_dvnIds[j] == i) {
                    options = _optionsArray[j];
                    break;
                }
            }
            totalFee += ILayerZeroDVN(dvn).getFee(_dstEid, _config.confirmations, _sender, options);
        }
    }
}
