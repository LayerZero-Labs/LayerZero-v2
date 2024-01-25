// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

import { ICCIPDVNAdapter } from "../../../interfaces/adapters/ICCIPDVNAdapter.sol";
import { ICCIPDVNAdapterFeeLib } from "../../../interfaces/adapters/ICCIPDVNAdapterFeeLib.sol";

contract CCIPDVNAdapterFeeLib is OwnableUpgradeable, Proxied, ICCIPDVNAdapterFeeLib {
    uint16 internal constant BPS_DENOMINATOR = 10000;

    mapping(uint32 dstEid => DstConfig) public dstConfig;

    function initialize() external proxied initializer {
        __Ownable_init();
    }

    // ================================ OnlyOwner ===============================
    function setDstConfig(DstConfigParam[] calldata _param) external onlyOwner {
        for (uint256 i = 0; i < _param.length; i++) {
            DstConfigParam calldata param = _param[i];

            dstConfig[param.dstEid] = DstConfig({ floorMarginUSD: param.floorMarginUSD });
        }

        emit DstConfigSet(_param);
    }

    // ================================ External ================================
    function getFeeOnSend(
        Param calldata _params,
        ICCIPDVNAdapter.DstConfig calldata _dstConfig,
        Client.EVM2AnyMessage calldata _message,
        bytes calldata _options,
        IRouterClient _router
    ) external payable returns (uint256 ccipFee, uint256 totalFee) {
        if (_dstConfig.gas == 0) revert CCIPDVNAdapter_EidNotSupported(_params.dstEid);
        if (_options.length > 0) revert CCIPDVNAdapter_OptionsUnsupported();

        ccipFee = _router.getFee(_dstConfig.chainSelector, _message);
        totalFee = _applyPremium(_dstConfig.multiplierBps, _params.defaultMultiplierBps, ccipFee);
    }

    function getFee(
        Param calldata _params,
        ICCIPDVNAdapter.DstConfig calldata _dstConfig,
        Client.EVM2AnyMessage calldata _message,
        bytes calldata _options,
        IRouterClient _router
    ) external view returns (uint256 totalFee) {
        if (_dstConfig.gas == 0) revert CCIPDVNAdapter_EidNotSupported(_params.dstEid);
        if (_options.length > 0) revert CCIPDVNAdapter_OptionsUnsupported();

        totalFee = _router.getFee(_dstConfig.chainSelector, _message);
        totalFee = _applyPremium(_dstConfig.multiplierBps, _params.defaultMultiplierBps, totalFee);
    }

    // ================================ Internal ================================
    function _applyPremium(
        uint16 _multiplierBps,
        uint16 _defaultMultiplierBps,
        uint256 _fee
    ) internal pure returns (uint256 fee) {
        uint256 multiplier = _multiplierBps == 0 ? _defaultMultiplierBps : _multiplierBps;
        fee = (_fee * multiplier) / BPS_DENOMINATOR;
    }
}
