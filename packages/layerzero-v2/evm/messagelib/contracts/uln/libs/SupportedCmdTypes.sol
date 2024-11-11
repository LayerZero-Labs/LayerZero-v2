// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { BitMap256 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/BitMaps.sol";

struct SupportedCmdTypes {
    mapping(uint32 => BitMap256) cmdTypes; // support options
}

using SupportedCmdTypesLib for SupportedCmdTypes global;

library SupportedCmdTypesLib {
    // the max number of supported command types is 256
    uint8 internal constant CMD_V1__REQUEST_V1__EVM_CALL = 0;
    uint8 internal constant CMD_V1__COMPUTE_V1__EVM_CALL = 1;
    uint8 internal constant CMD_V1__TIMESTAMP_VALIDATE = 2; // validate timestamp, to check if the timestamp is out of range
    // more types can be added here in the future

    error UnsupportedTargetEid();

    function assertSupported(SupportedCmdTypes storage _self, uint32 _targetEid, uint8 _type) internal view {
        if (!isSupported(_self, _targetEid, _type)) revert UnsupportedTargetEid();
    }

    function isSupported(SupportedCmdTypes storage _self, uint32 _targetEid, uint8 _type) internal view returns (bool) {
        return _self.cmdTypes[_targetEid].get(_type);
    }
}
