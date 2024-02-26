// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IMessagingContext } from "./interfaces/IMessagingContext.sol";
import { Errors } from "./libs/Errors.sol";

/**
 * @title MessagingContext
 * @dev This contract acts as a non-reentrancy guard and a source of messaging context.
 *      The context includes the remote eid and the sender address.
 *      It separates the send and receive context to allow messaging receipts (send back on receive()).
 */
abstract contract MessagingContext is IMessagingContext {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private _sendContext = NOT_ENTERED;

    /**
     * @dev Modifier to set the send context, which includes the destination eid and sender address.
     * @param _dstEid The destination eid.
     * @param _sender The sender address.
     */
    modifier sendContext(uint32 _dstEid, address _sender) {
        if (_sendContext != NOT_ENTERED) revert Errors.LZ_SendReentrancy();
        _sendContext = (uint256(_dstEid) << 160) | uint160(_sender);
        _;
        _sendContext = NOT_ENTERED;
    }

    /**
     * @dev Returns true if currently sending a message.
     * @return A boolean indicating whether sending a message.
     */
    function isSendingMessage() public view returns (bool) {
        return _sendContext != NOT_ENTERED;
    }

    /**
     * @dev Returns the messaging context (eid, sender) if sending a message, (0, 0) otherwise.
     * @return The messaging context as a tuple of (eid, sender).
     */
    function getSendContext() external view returns (uint32, address) {
        return isSendingMessage() ? _getSendContext(_sendContext) : (0, address(0));
    }

    /**
     * @dev Internal function to extract the messaging context from the given context value.
     * @param _context The context value.
     * @return The messaging context as a tuple of (eid, sender).
     */
    function _getSendContext(uint256 _context) internal pure returns (uint32, address) {
        return (uint32(_context >> 160), address(uint160(_context)));
    }
}
