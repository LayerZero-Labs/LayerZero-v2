// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IMessageLib, MessageLibType } from "../interfaces/IMessageLib.sol";
import { Errors } from "../libs/Errors.sol";

contract BlockedMessageLib is ERC165 {
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IMessageLib).interfaceId || super.supportsInterface(interfaceId);
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (type(uint64).max, type(uint8).max, 2);
    }

    function messageLibType() external pure returns (MessageLibType) {
        return MessageLibType.SendAndReceive;
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        return true;
    }

    fallback() external {
        revert Errors.NotImplemented();
    }
}
