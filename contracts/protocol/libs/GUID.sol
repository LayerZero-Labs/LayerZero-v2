// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { AddressCast } from "./AddressCast.sol";

library GUID {
    using AddressCast for address;

    function generate(
        uint64 _nonce,
        uint32 _srcEid,
        address _sender,
        uint32 _dstEid,
        bytes32 _receiver
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_nonce, _srcEid, _sender.toBytes32(), _dstEid, _receiver));
    }
}
