// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IAxelarGasService } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { IAxelarDVNAdapter } from "../../../interfaces/adapters/IAxelarDVNAdapter.sol";
import { IAxelarDVNAdapterFeeLib } from "../../../interfaces/adapters/IAxelarDVNAdapterFeeLib.sol";
import { ILayerZeroPriceFeed } from "../../../../interfaces/ILayerZeroPriceFeed.sol";

contract AxelarDVNAdapterFeeLib is OwnableUpgradeable, Proxied, IAxelarDVNAdapterFeeLib {
    uint16 internal constant BPS_DENOMINATOR = 10000;

    /// @dev to be applied to native gas fee before sending to Axelar Gas Service
    uint16 public nativeGasFeeMultiplierBps;

    IAxelarDVNAdapter public dvn;
    IAxelarGasService public gasService;
    ILayerZeroPriceFeed public priceFeed;

    mapping(uint32 dstEid => DstConfig) public dstConfig;

    function initialize(
        address _gasService,
        address _dvn,
        uint16 _nativeGasFeeMultiplierBps
    ) external proxied initializer {
        __Ownable_init();
        gasService = IAxelarGasService(_gasService);
        dvn = IAxelarDVNAdapter(_dvn);
        nativeGasFeeMultiplierBps = _nativeGasFeeMultiplierBps;
    }

    // ================================ OnlyOwner ================================
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
        emit TokenWithdrawn(_token, _to, _amount);
    }

    function setGasService(address _gasService) external onlyOwner {
        gasService = IAxelarGasService(_gasService);
        emit GasServiceSet(_gasService);
    }

    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = ILayerZeroPriceFeed(_priceFeed);
        emit PriceFeedSet(_priceFeed);
    }

    function setDstConfig(DstConfigParam[] calldata _param) external onlyOwner {
        for (uint256 i = 0; i < _param.length; i++) {
            DstConfigParam calldata param = _param[i];
            dstConfig[param.dstEid] = DstConfig({ gas: param.gas, floorMarginUSD: param.floorMarginUSD });
        }
        emit DstConfigSet(_param);
    }

    function setNativeGasFeeMultiplierBps(uint16 _multiplierBps) external onlyOwner {
        nativeGasFeeMultiplierBps = _multiplierBps;
        emit NativeGasFeeMultiplierBpsSet(_multiplierBps);
    }

    // ================================ External ================================
    function getFeeOnSend(
        Param calldata _param,
        IAxelarDVNAdapter.DstConfig calldata _dstConfig,
        bytes memory _payload,
        bytes calldata _options,
        address _sendLib
    ) external payable returns (uint256 totalFee) {
        if (_dstConfig.nativeGasFee == 0) revert AxelarDVNAdapter_EidNotSupported(_param.dstEid);
        if (_options.length > 0) revert AxelarDVNAdapter_OptionsUnsupported();

        uint256 axelarFee = _getAxelarFee(_dstConfig.nativeGasFee);
        totalFee = _applyPremium(_dstConfig.multiplierBps, _param.defaultMultiplierBps, axelarFee);

        // withdraw from uln to fee lib if not enough balance
        uint256 balance = address(this).balance;
        if (balance < axelarFee) {
            dvn.withdrawToFeeLib(_sendLib);

            // revert if still not enough
            balance = address(this).balance;
            if (balance < axelarFee) revert AxelarDVNAdapter_InsufficientBalance(balance, axelarFee);
        }

        // pay axelar gas service
        gasService.payNativeGasForContractCall{ value: axelarFee }(
            address(this), // sender
            _dstConfig.chainName, // destinationChain
            _dstConfig.peer, // destinationAddress
            _payload, // payload
            address(this) // refundAddress
        );
    }

    function getFee(
        Param calldata _param,
        IAxelarDVNAdapter.DstConfig calldata _dstConfig,
        bytes calldata _options
    ) external view returns (uint256 totalFee) {
        if (_dstConfig.nativeGasFee == 0) revert AxelarDVNAdapter_EidNotSupported(_param.dstEid);
        if (_options.length > 0) revert AxelarDVNAdapter_OptionsUnsupported();

        uint256 axelarFee = _getAxelarFee(_dstConfig.nativeGasFee);
        totalFee = _applyPremium(_dstConfig.multiplierBps, _param.defaultMultiplierBps, axelarFee);
    }

    // ================================ Internal ================================
    function _getAxelarFee(uint256 _nativeGasFee) internal view returns (uint256) {
        return (_nativeGasFee * nativeGasFeeMultiplierBps) / BPS_DENOMINATOR;
    }

    function _applyPremium(
        uint16 multiplierBps,
        uint16 defaultMultiplierBps,
        uint256 fee
    ) internal pure returns (uint256) {
        uint256 multiplier = multiplierBps == 0 ? defaultMultiplierBps : multiplierBps;
        return (fee * multiplier) / BPS_DENOMINATOR;
    }

    receive() external payable {}
}
