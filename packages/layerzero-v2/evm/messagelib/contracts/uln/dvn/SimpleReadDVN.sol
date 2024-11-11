// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { BitMap256 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/BitMaps.sol";

import { ILayerZeroReadDVN } from "../interfaces/ILayerZeroReadDVN.sol";
import { ReadCmdCodecV1 } from "../libs/ReadCmdCodecV1.sol";
import { ReadLib1002 } from "../readlib/ReadLib1002.sol";
import { SupportedCmdTypes } from "../libs/SupportedCmdTypes.sol";

contract SimpleReadDVN is ILayerZeroReadDVN {
    struct SetSupportedCmdTypesParam {
        uint32 targetEid;
        BitMap256 types;
    }

    uint128 internal constant DENOMINATOR = 10 ** 18;
    uint128 internal constant NATIVE_DECIMALS = 10 ** 18;

    uint16 internal constant BPS_BASE = 10000;

    address payable public immutable readLib;

    // the usd fee should be usd * DENOMINATOR
    uint128 internal evmCallRequestV1FeeUSD;
    uint128 internal evmCallComputeV1MapFeeUSD;
    uint128 internal evmCallComputeV1ReduceFeeUSD;

    uint128 internal nativePriceUSD; // usd * DENOMINATOR

    SupportedCmdTypes internal supportedCmdTypes;

    constructor(address payable _readLib) {
        readLib = _readLib;
    }

    function setSupportedCmdTypes(SetSupportedCmdTypesParam[] calldata _params) external {
        for (uint256 i = 0; i < _params.length; i++) {
            supportedCmdTypes.cmdTypes[_params[i].targetEid] = _params[i].types;
        }
    }

    function assignJob(
        address /*_sender*/,
        bytes calldata /*_packetHeader*/,
        bytes calldata _cmd,
        bytes calldata /*_options*/
    ) external payable returns (uint256) {
        uint256 cmdFeeUSD = _estimateCmdFee(_cmd);
        uint256 cmdFee = (cmdFeeUSD * NATIVE_DECIMALS) / nativePriceUSD;

        return cmdFee;
    }

    function verify(bytes calldata _packetHeader, bytes32 _cmdHash, bytes32 _payloadHash) external {
        ReadLib1002(readLib).verify(_packetHeader, _cmdHash, _payloadHash);
    }

    // ========================= View =========================

    function getFee(
        address /*_sender*/,
        bytes calldata /*_packetHeader*/,
        bytes calldata _cmd,
        bytes calldata /*_options*/
    ) external view returns (uint256) {
        // cmdFeeUSD -> cmdFee native
        uint256 cmdFeeUSD = _estimateCmdFee(_cmd);
        uint256 cmdFee = (cmdFeeUSD * NATIVE_DECIMALS) / nativePriceUSD;

        return cmdFee;
    }

    function setCmdFees(
        uint128 _evmCallReqV1FeeUSD,
        uint128 _evmCallComputeV1MapFeeUSD,
        uint128 _evmCallComputeV1ReduceFeeUSD,
        uint128 _nativePriceUSD
    ) external {
        evmCallRequestV1FeeUSD = _evmCallReqV1FeeUSD;
        evmCallComputeV1MapFeeUSD = _evmCallComputeV1MapFeeUSD;
        evmCallComputeV1ReduceFeeUSD = _evmCallComputeV1ReduceFeeUSD;
        nativePriceUSD = _nativePriceUSD;
    }

    function getCmdFees() external view returns (uint128, uint128, uint128, uint128) {
        return (evmCallRequestV1FeeUSD, evmCallComputeV1MapFeeUSD, evmCallComputeV1ReduceFeeUSD, nativePriceUSD);
    }

    function _estimateCmdFee(bytes calldata _cmd) internal view returns (uint256 fee) {
        ReadCmdCodecV1.Cmd memory cmd = ReadCmdCodecV1.decode(_cmd, _assertCmdTypeSupported);
        fee = cmd.numEvmCallRequestV1 * evmCallRequestV1FeeUSD;
        if (cmd.evmCallComputeV1Map) {
            fee += evmCallComputeV1MapFeeUSD * cmd.numEvmCallRequestV1;
        }
        if (cmd.evmCallComputeV1Reduce) {
            fee += evmCallComputeV1ReduceFeeUSD;
        }
    }

    function _assertCmdTypeSupported(
        uint32 _targetEid,
        bool /*_isBlockNum*/,
        uint64 /*_blockNumOrTimestamp*/,
        uint8 _cmdType
    ) internal view {
        supportedCmdTypes.assertSupported(_targetEid, _cmdType);
    }

    receive() external payable virtual {}
}
