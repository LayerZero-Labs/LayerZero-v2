// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISendLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";

contract Treasury is Ownable, ILayerZeroTreasury {
    uint256 public nativeBP;
    uint256 public lzTokenFee;
    bool public lzTokenEnabled;

    error LzTokenNotEnabled();

    function getFee(
        address /*_sender*/,
        uint32 /*_eid*/,
        uint256 _totalFee,
        bool _payInLzToken
    ) external view override returns (uint256) {
        return _getFee(_totalFee, _payInLzToken);
    }

    function payFee(
        address /*_sender*/,
        uint32 /*_eid*/,
        uint256 _totalFee,
        bool _payInLzToken
    ) external payable override returns (uint256) {
        return _getFee(_totalFee, _payInLzToken);
    }

    function setLzTokenEnabled(bool _lzTokenEnabled) external onlyOwner {
        lzTokenEnabled = _lzTokenEnabled;
    }

    function setNativeFeeBP(uint256 _nativeBP) external onlyOwner {
        nativeBP = _nativeBP;
    }

    function setLzTokenFee(uint256 _lzTokenFee) external onlyOwner {
        lzTokenFee = _lzTokenFee;
    }

    function withdrawLzToken(address _messageLib, address _lzToken, address _to, uint256 _amount) external onlyOwner {
        ISendLib(_messageLib).withdrawLzTokenFee(_lzToken, _to, _amount);
    }

    function withdrawNativeFee(address _messageLib, address payable _to, uint256 _amount) external onlyOwner {
        ISendLib(_messageLib).withdrawFee(_to, _amount);
    }

    // this is for withdrawing lz token sent to this contract by uln301 and fee handler
    // and to withdraw any native sent over via payFee
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
    }

    // ======================= Internal =======================

    function _getFee(uint256 _totalFee, bool _payInLzToken) internal view returns (uint256) {
        if (_payInLzToken) {
            if (!lzTokenEnabled) revert LzTokenNotEnabled();
            return lzTokenFee;
        } else {
            return (_totalFee * nativeBP) / 10000;
        }
    }
}
