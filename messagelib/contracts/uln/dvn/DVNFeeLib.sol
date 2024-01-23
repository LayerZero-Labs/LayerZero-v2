// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroPriceFeed } from "../../interfaces/ILayerZeroPriceFeed.sol";
import { IDVN } from "../interfaces/IDVN.sol";
import { IDVNFeeLib } from "../interfaces/IDVNFeeLib.sol";
import { DVNOptions } from "../libs/DVNOptions.sol";

contract DVNFeeLib is Ownable, IDVNFeeLib {
    using DVNOptions for bytes;

    uint16 internal constant EXECUTE_FIXED_BYTES = 68; // encoded: funcSigHash + params -> 4  + (32 * 2)
    uint16 internal constant SIGNATURE_RAW_BYTES = 65; // not encoded
    // callData(updateHash) = 132 (4 + 32 * 4), padded to 32 = 160 and encoded as bytes with an 64 byte overhead = 224
    uint16 internal constant UPDATE_HASH_BYTES = 224;

    uint256 private immutable nativeDecimalsRate;

    constructor(uint256 _nativeDecimalsRate) {
        nativeDecimalsRate = _nativeDecimalsRate;
    }

    // ================================ OnlyOwner ================================
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
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
        _decodeDVNOptions(_options); // todo: validate options

        uint256 callDataSize = _getCallDataSize(_params.quorum);

        // for future versions where priceFeed charges a fee
        //        uint256 priceFeedFee = ILayerZeroPriceFeed(_params.priceFeed).getFee(_params.dstEid, callDataSize, _dstConfig.gas);
        //        (uint256 fee, , , uint128 nativePriceUSD) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeOnSend{
        //            value: priceFeedFee
        //        }(_params.dstEid, callDataSize, _dstConfig.gas);

        (uint256 fee, , , uint128 nativePriceUSD) = ILayerZeroPriceFeed(_params.priceFeed).estimateFeeOnSend(
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

    // ========================= View =========================
    /// @dev get fee view function
    /// @param _params fee params
    /// @param _dstConfig dst config
    /// @param //_options options
    function getFee(
        FeeParams calldata _params,
        IDVN.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256) {
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

    // ========================= Internal =========================
    function _getCallDataSize(uint256 _quorum) internal pure returns (uint256) {
        uint256 totalSignatureBytes = _quorum * SIGNATURE_RAW_BYTES;
        if (totalSignatureBytes % 32 != 0) {
            totalSignatureBytes = totalSignatureBytes - (totalSignatureBytes % 32) + 32;
        }
        // getFee should charge on execute(updateHash)
        // totalSignatureBytesPadded also has 64 overhead for bytes
        return uint256(EXECUTE_FIXED_BYTES) + UPDATE_HASH_BYTES + totalSignatureBytes + 64;
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

    // send funds here to pay for price feed directly
    receive() external payable {}
}
