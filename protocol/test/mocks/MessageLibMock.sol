// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { MessageLibType } from "../../contracts/interfaces/IMessageLib.sol";

contract MessageLibMock is ERC165 {
    bool internal isSupported;

    constructor(bool _isSupported) {
        isSupported = _isSupported;
    }

    function supportsInterface(bytes4) public view override returns (bool) {
        return isSupported;
    }

    function isSupportedEid(uint32 _eid) external pure returns (bool) {
        return _eid != type(uint32).max;
    }

    function messageLibType() external pure returns (MessageLibType) {
        return MessageLibType.SendAndReceive;
    }
}
