// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { IMessagingContext } from "./interfaces/IMessagingContext.sol";
import { Errors } from "./libs/Errors.sol";

/// this contract acts as a non-reentrancy guard and a source of messaging context
/// the context includes the remote eid and the sender address
/// it separates the send and receive context to allow messaging receipts (send back on receive())
abstract contract MessagingContext is IMessagingContext {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private _sendContext = NOT_ENTERED;

    /// @dev the sendContext is set to 8 bytes 0s + 4 bytes eid + 20 bytes sender
    modifier sendContext(uint32 _dstEid, address _sender) {
        if (_sendContext != NOT_ENTERED) revert Errors.SendReentrancy();
        _sendContext = (uint256(_dstEid) << 160) | uint160(_sender);
        _;
        _sendContext = NOT_ENTERED;
    }

    /// @dev returns true if sending message
    function isSendingMessage() public view returns (bool) {
        return _sendContext != NOT_ENTERED;
    }

    /// @dev returns (eid, sender) if sending message, (0, 0) otherwise
    function getSendContext() external view returns (uint32, address) {
        return isSendingMessage() ? _getSendContext(_sendContext) : (0, address(0));
    }

    function _getSendContext(uint256 _context) internal pure returns (uint32, address) {
        return (uint32(_context >> 160), address(uint160(_context)));
    }
}
