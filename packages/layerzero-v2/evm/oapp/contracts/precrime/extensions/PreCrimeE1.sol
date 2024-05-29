// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";

import { PreCrime } from "../PreCrime.sol";

abstract contract PreCrimeE1 is PreCrime {
    using SafeCast for uint32;

    uint32 internal immutable localEid;

    constructor(uint32 _localEid, address _endpoint, address _simulator) PreCrime(_endpoint, _simulator) {
        localEid = _localEid;
    }

    function _getLocalEid() internal view override returns (uint32) {
        return localEid;
    }

    function _getInboundNonce(uint32 _srcEid, bytes32 _sender) internal view override returns (uint64) {
        bytes memory path = _getPath(_srcEid, _sender);
        return ILayerZeroEndpoint(lzEndpoint).getInboundNonce(_srcEid.toUint16(), path);
    }

    function _getPath(uint32 _srcEid, bytes32 _sender) internal view virtual returns (bytes memory);
}
