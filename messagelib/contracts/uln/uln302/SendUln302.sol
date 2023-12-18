// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import { ExecutorConfig } from "../../SendLibBase.sol";
import { SendLibBaseE2, WorkerOptions } from "../../SendLibBaseE2.sol";
import { UlnConfig } from "../UlnBase.sol";
import { SendUlnBase } from "../SendUlnBase.sol";

/// @dev This is a gluing contract. It simply parses the requests and forward to the super.impl() accordingly.
/// @dev In this case, it combines the logic of SendUlnBase and SendLibBaseE2
contract SendUln302 is SendUlnBase, SendLibBaseE2 {
    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;

    error InvalidConfigType(uint32 configType);

    constructor(
        address _endpoint,
        uint256 _treasuryGasLimit,
        uint256 _treasuryGasForFeeCap
    ) SendLibBaseE2(_endpoint, _treasuryGasLimit, _treasuryGasForFeeCap) {}

    // ============================ OnlyEndpoint ===================================

    // on the send side the user can config both the executor and the ULN
    function setConfig(address _oapp, SetConfigParam[] calldata _params) external override onlyEndpoint {
        for (uint256 i = 0; i < _params.length; i++) {
            SetConfigParam calldata param = _params[i];
            _assertSupportedEid(param.eid);
            if (param.configType == CONFIG_TYPE_EXECUTOR) {
                _setExecutorConfig(param.eid, _oapp, abi.decode(param.config, (ExecutorConfig)));
            } else if (param.configType == CONFIG_TYPE_ULN) {
                _setUlnConfig(param.eid, _oapp, abi.decode(param.config, (UlnConfig)));
            } else {
                revert InvalidConfigType(param.configType);
            }
        }
    }

    // ============================ View ===================================

    function getConfig(uint32 _eid, address _oapp, uint32 _configType) external view override returns (bytes memory) {
        if (_configType == CONFIG_TYPE_EXECUTOR) {
            return abi.encode(getExecutorConfig(_oapp, _eid));
        } else if (_configType == CONFIG_TYPE_ULN) {
            return abi.encode(getUlnConfig(_oapp, _eid));
        } else {
            revert InvalidConfigType(_configType);
        }
    }

    function version() external pure override returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (3, 0, 2);
    }

    function isSupportedEid(uint32 _eid) external view override returns (bool) {
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
        Packet calldata _packet,
        WorkerOptions[] memory _options
    ) internal override returns (uint256 otherWorkerFees, bytes memory encodedPacket) {
        (otherWorkerFees, encodedPacket) = _payDVNs(fees, _packet, _options);
    }

    function _splitOptions(
        bytes calldata _options
    ) internal pure override returns (bytes memory, WorkerOptions[] memory) {
        return _splitUlnOptions(_options);
    }
}
