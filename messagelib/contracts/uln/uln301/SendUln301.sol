// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { ExecutorConfig, WorkerOptions } from "../../SendLibBase.sol";
import { SendLibBaseE1 } from "./SendLibBaseE1.sol";
import { SendUlnBase } from "../SendUlnBase.sol";
import { UlnConfig } from "../UlnBase.sol";

/// @dev ULN301 will be deployed on EndpointV1 and is for backward compatibility with ULN302 on EndpointV2. 301 can talk to both 301 and 302
/// @dev This is a gluing contract. It simply parses the requests and forward to the super.impl() accordingly.
/// @dev In this case, it combines the logic of SendUlnBase and SendLibBaseE1
contract SendUln301 is SendUlnBase, SendLibBaseE1 {
    uint256 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint256 internal constant CONFIG_TYPE_ULN = 2;

    error LZ_ULN_InvalidConfigType(uint256 configType);

    constructor(
        address _endpoint,
        uint256 _treasuryGasLimit,
        uint256 _treasuryGasForFeeCap,
        address _nonceContract,
        uint32 _localEid,
        address _treasuryFeeHandler
    )
        SendLibBaseE1(
            _endpoint,
            _treasuryGasLimit,
            _treasuryGasForFeeCap,
            _nonceContract,
            _localEid,
            _treasuryFeeHandler
        )
    {}

    // ============================ OnlyEndpoint ===================================

    function setConfig(
        uint16 _eid,
        address _oapp,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyEndpoint {
        _assertSupportedEid(_eid);
        if (_configType == CONFIG_TYPE_EXECUTOR) {
            _setExecutorConfig(_eid, _oapp, abi.decode(_config, (ExecutorConfig)));
        } else if (_configType == CONFIG_TYPE_ULN) {
            _setUlnConfig(_eid, _oapp, abi.decode(_config, (UlnConfig)));
        } else {
            revert LZ_ULN_InvalidConfigType(_configType);
        }
    }

    // ============================ View ===================================

    function getConfig(uint16 _eid, address _oapp, uint256 _configType) external view override returns (bytes memory) {
        if (_configType == CONFIG_TYPE_EXECUTOR) {
            return abi.encode(getExecutorConfig(_oapp, _eid));
        } else if (_configType == CONFIG_TYPE_ULN) {
            return abi.encode(getUlnConfig(_oapp, _eid));
        } else {
            revert LZ_ULN_InvalidConfigType(_configType);
        }
    }

    function version() external pure override returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (3, 0, 1);
    }

    function isSupportedEid(uint32 _eid) external view returns (bool) {
        return _isSupportedEid(_eid);
    }

    // ============================ Internal ===================================

    function _quoteVerifier(
        address _sender,
        uint32 _dstEid,
        WorkerOptions[] memory _options
    ) internal view override returns (uint256) {
        return _quoteDVNs(_sender, _dstEid, _options);
    }

    function _payVerifier(
        Packet memory _packet,
        WorkerOptions[] memory _options
    ) internal virtual override returns (uint256 otherWorkerFees, bytes memory encodedPacket) {
        (otherWorkerFees, encodedPacket) = _payDVNs(fees, _packet, _options);
    }

    function _splitOptions(
        bytes calldata _options
    ) internal pure override returns (bytes memory, WorkerOptions[] memory) {
        return _splitUlnOptions(_options);
    }
}
