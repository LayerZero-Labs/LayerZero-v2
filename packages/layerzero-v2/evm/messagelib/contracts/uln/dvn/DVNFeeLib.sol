// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroPriceFeed } from "../../interfaces/ILayerZeroPriceFeed.sol";
import { IDVN } from "../interfaces/IDVN.sol";
import { IDVNFeeLib } from "../interfaces/IDVNFeeLib.sol";
import { DVNOptions } from "../libs/DVNOptions.sol";
import { ReadCmdCodecV1 } from "../libs/ReadCmdCodecV1.sol";
import { SupportedCmdTypesLib, SupportedCmdTypes, BitMap256 } from "../libs/SupportedCmdTypes.sol";

contract DVNFeeLib is Ownable, IDVNFeeLib {
    using DVNOptions for bytes;

    struct SetSupportedCmdTypesParam {
        uint32 targetEid;
        BitMap256 types;
    }

    struct BlockTimeConfig {
        uint32 avgBlockTime; // milliseconds
        uint64 blockNum; // the block number of the reference timestamp
        uint64 timestamp; // second, the reference timestamp of the block number
        uint32 maxPastRetention; // second, the max retention time the DVN will accept read requests/compute from the past time
        uint32 maxFutureRetention; // second, the max retention time the DVN will accept read requests/compute from the future time
    }

    uint16 internal constant BPS_BASE = 10000;

    // encoded( execute(ExecuteParam[]) ): funcSigHash + params -> 4  + 32(Offset of the array) + 32(array size) + 32(first element start offset)\
    // + 32(vid) + 32(target) + 32(calldata-offset) + 32(expiration) + 32(signatures-offset) = 260
    uint16 internal constant EXECUTE_FIXED_BYTES = 260;
    uint16 internal constant SIGNATURE_RAW_BYTES = 65; // not encoded
    // verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations)\
    // 4 + 32(header offset) + 32(payloadHash) + 32(confirmations, 8 -> 32 padded) + 32(header-size) + 96(81 -> header-padded) = 228,
    // padded to multiples of 32 = 256, encoded as bytes with an 32 byte for the bytes size = 288
    uint16 internal constant VERIFY_BYTES_ULN = 288;
    // verify(bytes calldata _packetHeader, bytes32 _cmdHash, bytes32 _payloadHash)\
    // 4 + 32(header offset) + 32(cmdHash) + 32(payloadHash) + 32(header-size) + 96(81 -> header-padded) = 228,
    // padded to multiples of 32 = 256, encoded as bytes with an 32 byte for the bytes size = 288
    uint16 internal constant VERIFY_BYTES_CMD_LIB = 288;

    uint256 internal immutable nativeDecimalsRate;
    uint32 internal immutable localEidV2; // endpoint-v2 only, for read call

    SupportedCmdTypes internal supportedCmdTypes;

    uint120 internal evmCallRequestV1FeeUSD;
    uint120 internal evmCallComputeV1ReduceFeeUSD;
    uint16 internal evmCallComputeV1MapBps;

    mapping(uint32 dstEid => BlockTimeConfig) public dstBlockTimeConfigs;

    constructor(uint32 _localEidV2, uint256 _nativeDecimalsRate) {
        localEidV2 = _localEidV2;
        nativeDecimalsRate = _nativeDecimalsRate;
    }

    // ================================ OnlyOwner ================================
    function setSupportedCmdTypes(SetSupportedCmdTypesParam[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; i++) {
            supportedCmdTypes.cmdTypes[_params[i].targetEid] = _params[i].types;
        }
    }

    function getSupportedCmdTypes(uint32 _targetEid) external view returns (BitMap256) {
        return supportedCmdTypes.cmdTypes[_targetEid];
    }

    function setDstBlockTimeConfigs(
        uint32[] calldata dstEids,
        BlockTimeConfig[] calldata _blockConfigs
    ) external onlyOwner {
        if (dstEids.length != _blockConfigs.length) revert DVN_INVALID_INPUT_LENGTH();
        for (uint256 i = 0; i < dstEids.length; i++) {
            dstBlockTimeConfigs[dstEids[i]] = _blockConfigs[i];
        }
    }

    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
    }

    function setCmdFees(
        uint120 _evmCallRequestV1FeeUSD,
        uint120 _evmCallComputeV1ReduceFeeUSD,
        uint16 _evmCallComputeV1MapBps
    ) external onlyOwner {
        evmCallRequestV1FeeUSD = _evmCallRequestV1FeeUSD;
        evmCallComputeV1ReduceFeeUSD = _evmCallComputeV1ReduceFeeUSD;
        evmCallComputeV1MapBps = _evmCallComputeV1MapBps;
    }

    function getCmdFees() external view returns (uint120, uint120, uint16) {
        return (evmCallRequestV1FeeUSD, evmCallComputeV1ReduceFeeUSD, evmCallComputeV1MapBps);
    }

    // ========================= External =========================
    /// @dev get fee function that can change state. e.g. paying priceFeed
    /// @param _params fee params
    /// @param _dstConfig dst config
    /// @param //_options options
    function getFeeOnSend(
        FeeParams calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external payable returns (uint256) {
        return getFee(_params, _dstConfig, _options);
    }

    function getFeeOnSend(
        FeeParamsForRead calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _cmd,
        bytes calldata _options
    ) external payable returns (uint256 fee) {
        fee = getFee(_params, _dstConfig, _cmd, _options);
    }

    // ========================= View =========================
    /// @dev get fee view function
    /// @param _params fee params
    /// @param _dstConfig dst config
    /// @param //_options options
    function getFee(
        FeeParams calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) public view returns (uint256) {
        if (_dstConfig.gas == 0) revert DVN_EidNotSupported(_params.dstEid);

        _decodeDVNOptions(_options); // validate options

        uint256 callDataSize = _getCallDataSize(_params.quorum);
        (uint256 fee, , , uint128 nativePriceUSD) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeByEid(
            _params.dstEid,
            callDataSize,
            _dstConfig.gas
        );
        return
            _applyPremium(
                fee,
                _dstConfig.multiplierBps,
                _params.defaultMultiplierBps,
                _dstConfig.floorMarginUSD,
                nativePriceUSD
            );
    }

    function getFee(
        FeeParamsForRead calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _cmd,
        bytes calldata _options
    ) public view returns (uint256) {
        if (_dstConfig.gas == 0) revert DVN_EidNotSupported(localEidV2);

        _decodeDVNOptions(_options); // validate options

        uint256 callDataSize = _getReadCallDataSize(_params.quorum);
        (uint256 fee, , , uint128 nativePriceUSD) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeByEid(
            localEidV2,
            callDataSize,
            _dstConfig.gas
        );

        // cmdFeeUSD -> cmdFee native final
        uint256 cmdFeeUSD = _estimateCmdFee(_cmd);
        uint256 cmdFee = (cmdFeeUSD * nativeDecimalsRate) / nativePriceUSD;

        return
            _applyPremium(
                fee + cmdFee,
                _dstConfig.multiplierBps,
                _params.defaultMultiplierBps,
                _dstConfig.floorMarginUSD,
                nativePriceUSD
            );
    }

    // ========================= Internal =========================
    function _getCallDataSize(uint256 _quorum) internal pure returns (uint256) {
        return _getCallDataSizeByQuorumAndVerifyBytes(_quorum, VERIFY_BYTES_ULN);
    }

    function _getReadCallDataSize(uint256 _quorum) internal pure returns (uint256) {
        return _getCallDataSizeByQuorumAndVerifyBytes(_quorum, VERIFY_BYTES_CMD_LIB);
    }

    function _getCallDataSizeByQuorumAndVerifyBytes(
        uint256 _quorum,
        uint256 verifyBytes
    ) internal pure returns (uint256) {
        uint256 totalSignatureBytes = _quorum * SIGNATURE_RAW_BYTES;
        if (totalSignatureBytes % 32 != 0) {
            totalSignatureBytes = totalSignatureBytes - (totalSignatureBytes % 32) + 32;
        }
        // getFee should charge on execute(updateHash)
        // totalSignatureBytesPadded also has 32 as size of the bytes
        return uint256(EXECUTE_FIXED_BYTES) + verifyBytes + totalSignatureBytes + 32;
    }

    function _applyPremium(
        uint256 _fee,
        uint16 _bps,
        uint16 _defaultBps,
        uint128 _marginUSD,
        uint128 _nativePriceUSD
    ) internal view returns (uint256) {
        uint16 multiplierBps = _bps == 0 ? _defaultBps : _bps;

        uint256 feeWithMultiplier = (_fee * multiplierBps) / 10000;
        if (_nativePriceUSD == 0 || _marginUSD == 0) {
            return feeWithMultiplier;
        }

        uint256 feeWithFloorMargin = _fee + (_marginUSD * nativeDecimalsRate) / _nativePriceUSD;

        return feeWithFloorMargin > feeWithMultiplier ? feeWithFloorMargin : feeWithMultiplier;
    }

    function _decodeDVNOptions(bytes calldata _options) internal pure returns (uint256) {
        uint256 cursor;
        while (cursor < _options.length) {
            (uint8 optionType, , uint256 newCursor) = _options.nextDVNOption(cursor);
            cursor = newCursor;
            revert DVN_UnsupportedOptionType(optionType);
        }
        if (cursor != _options.length) revert DVNOptions.DVN_InvalidDVNOptions(cursor);

        return 0; // todo: precrime fee model
    }

    function _estimateCmdFee(bytes calldata _cmd) internal view returns (uint256 fee) {
        ReadCmdCodecV1.Cmd memory cmd = ReadCmdCodecV1.decode(_cmd, _assertCmdTypeSupported);
        fee = cmd.numEvmCallRequestV1 * evmCallRequestV1FeeUSD;
        if (cmd.evmCallComputeV1Map) {
            fee += (fee * evmCallComputeV1MapBps) / BPS_BASE;
        }
        if (cmd.evmCallComputeV1Reduce) {
            fee += evmCallComputeV1ReduceFeeUSD;
        }
    }

    function _assertCmdTypeSupported(
        uint32 _targetEid,
        bool _isBlockNum,
        uint64 _blockNumOrTimestamp,
        uint8 _cmdType
    ) internal view {
        supportedCmdTypes.assertSupported(_targetEid, _cmdType);
        if (supportedCmdTypes.isSupported(_targetEid, SupportedCmdTypesLib.CMD_V1__TIMESTAMP_VALIDATE)) {
            BlockTimeConfig memory blockCnf = dstBlockTimeConfigs[_targetEid];
            uint64 timestamp = _blockNumOrTimestamp;
            if (_isBlockNum) {
                // convert the blockNum to the timestamp
                if (_blockNumOrTimestamp > blockCnf.blockNum) {
                    timestamp =
                        blockCnf.timestamp +
                        ((_blockNumOrTimestamp - blockCnf.blockNum) * blockCnf.avgBlockTime) /
                        1000;
                } else {
                    timestamp =
                        blockCnf.timestamp -
                        ((blockCnf.blockNum - _blockNumOrTimestamp) * blockCnf.avgBlockTime) /
                        1000;
                }
            }
            if (
                timestamp + blockCnf.maxPastRetention < block.timestamp ||
                timestamp > block.timestamp + blockCnf.maxFutureRetention
            ) {
                revert DVN_TimestampOutOfRange(_targetEid, timestamp);
            }
        }
    }

    function version() external pure returns (uint64 major, uint8 minor) {
        return (1, 1);
    }

    // send funds here to pay for price feed directly
    receive() external payable {}
}
