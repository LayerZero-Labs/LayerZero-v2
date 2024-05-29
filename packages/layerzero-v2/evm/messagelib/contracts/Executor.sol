// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";

import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { IUltraLightNode301 } from "./uln/uln301/interfaces/IUltraLightNode301.sol";
import { IExecutor } from "./interfaces/IExecutor.sol";
import { IExecutorFeeLib } from "./interfaces/IExecutorFeeLib.sol";
import { WorkerUpgradeable } from "./upgradeable/WorkerUpgradeable.sol";

contract Executor is WorkerUpgradeable, ReentrancyGuardUpgradeable, Proxied, IExecutor {
    using PacketV1Codec for bytes;

    mapping(uint32 dstEid => DstConfig) public dstConfig;

    // endpoint v2
    address public endpoint;
    uint32 public localEid;

    // endpoint v1
    address public receiveUln301;

    function initialize(
        address _endpoint,
        address _receiveUln301,
        address[] memory _messageLibs,
        address _priceFeed,
        address _roleAdmin,
        address[] memory _admins
    ) external proxied initializer {
        __ReentrancyGuard_init();
        __Worker_init(_messageLibs, _priceFeed, 12000, _roleAdmin, _admins);
        endpoint = _endpoint;
        localEid = ILayerZeroEndpointV2(_endpoint).eid();
        receiveUln301 = _receiveUln301;
    }

    function onUpgrade(address _receiveUln301) external proxied {
        receiveUln301 = _receiveUln301;
    }

    // --- Admin ---
    function setDstConfig(DstConfigParam[] memory _params) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam memory param = _params[i];
            dstConfig[param.dstEid] = DstConfig(
                param.baseGas,
                param.multiplierBps,
                param.floorMarginUSD,
                param.nativeCap
            );
        }
        emit DstConfigSet(_params);
    }

    function nativeDrop(
        Origin calldata _origin,
        uint32 _dstEid,
        address _oapp,
        NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit
    ) external payable onlyRole(ADMIN_ROLE) nonReentrant {
        _nativeDrop(_origin, _dstEid, _oapp, _nativeDropParams, _nativeDropGasLimit);
    }

    function nativeDropAndExecute301(
        Origin calldata _origin,
        NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit,
        bytes calldata _packet,
        uint256 _gasLimit
    ) external payable onlyRole(ADMIN_ROLE) nonReentrant {
        _nativeDrop(_origin, _packet.dstEid(), _packet.receiverB20(), _nativeDropParams, _nativeDropGasLimit);
        IUltraLightNode301(receiveUln301).commitVerification(_packet, _gasLimit);
    }

    function execute301(bytes calldata _packet, uint256 _gasLimit) external onlyRole(ADMIN_ROLE) nonReentrant {
        IUltraLightNode301(receiveUln301).commitVerification(_packet, _gasLimit);
    }

    function nativeDropAndExecute302(
        NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit,
        ExecutionParams calldata _executionParams
    ) external payable onlyRole(ADMIN_ROLE) nonReentrant {
        uint256 spent = _nativeDrop(
            _executionParams.origin,
            localEid,
            _executionParams.receiver,
            _nativeDropParams,
            _nativeDropGasLimit
        );

        uint256 value = msg.value - spent;
        // ignore the execution result
        ILayerZeroEndpointV2(endpoint).lzReceive{ value: value, gas: _executionParams.gasLimit }(
            _executionParams.origin,
            _executionParams.receiver,
            _executionParams.guid,
            _executionParams.message,
            _executionParams.extraData
        );
    }

    // --- Message Lib ---
    function assignJob(
        uint32 _dstEid,
        address _sender,
        uint256 _calldataSize,
        bytes calldata _options
    ) external onlyRole(MESSAGE_LIB_ROLE) onlyAcl(_sender) returns (uint256 fee) {
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            priceFeed,
            _dstEid,
            _sender,
            _calldataSize,
            defaultMultiplierBps
        );
        fee = IExecutorFeeLib(workerFeeLib).getFeeOnSend(params, dstConfig[_dstEid], _options);
    }

    // --- Only ACL ---
    function getFee(
        uint32 _dstEid,
        address _sender,
        uint256 _calldataSize,
        bytes calldata _options
    ) external view onlyAcl(_sender) whenNotPaused returns (uint256 fee) {
        IExecutorFeeLib.FeeParams memory params = IExecutorFeeLib.FeeParams(
            priceFeed,
            _dstEid,
            _sender,
            _calldataSize,
            defaultMultiplierBps
        );
        fee = IExecutorFeeLib(workerFeeLib).getFee(params, dstConfig[_dstEid], _options);
    }

    function _nativeDrop(
        Origin calldata _origin,
        uint32 _dstEid,
        address _oapp,
        NativeDropParams[] calldata _nativeDropParams,
        uint256 _nativeDropGasLimit
    ) internal returns (uint256 spent) {
        bool[] memory success = new bool[](_nativeDropParams.length);
        for (uint256 i = 0; i < _nativeDropParams.length; i++) {
            NativeDropParams memory param = _nativeDropParams[i];

            (bool sent, ) = param.receiver.call{ value: param.amount, gas: _nativeDropGasLimit }("");

            success[i] = sent;
            spent += param.amount;
        }
        emit NativeDropApplied(_origin, _dstEid, _oapp, _nativeDropParams, success);
    }
}
