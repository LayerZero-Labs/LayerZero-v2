// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { MessagingFee, MessagingReceipt } from "../../oapp/OAppSenderUpgradeable.sol";

/**
 * @dev Struct representing token parameters for the ONFT send() operation.
 */
struct SendParam {
    uint32 dstEid; // Destination LayerZero EndpointV2 ID.
    bytes32 to; // Recipient address.
    uint256 tokenId;
    bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
    bytes composeMsg; // The composed message for the send() operation.
    bytes onftCmd; // The ONFT command to be executed, unused in default ONFT implementations.
}

/**
 * @title IONFT
 * @dev Interface for the ONFT721 token.
 * @dev Does not inherit ERC721 to accommodate usage by OFT721Adapter.
 */
interface IONFT721Upgradeable {
    // Custom error messages
    error InvalidReceiver();
    error OnlyNFTOwner(address caller, address owner);

    // Events
    event ONFTSent(
        bytes32 indexed guid, // GUID of the ONFT message.
        uint32 dstEid, // Destination Endpoint ID.
        address indexed fromAddress, // Address of the sender on the src chain.
        uint256 tokenId // ONFT ID sent.
    );

    event ONFTReceived(
        bytes32 indexed guid, // GUID of the ONFT message.
        uint32 srcEid, // Source Endpoint ID.
        address indexed toAddress, // Address of the recipient on the dst chain.
        uint256 tokenId // ONFT ID received.
    );

    /**
     * @notice Retrieves interfaceID and the version of the ONFT.
     * @return interfaceId The interface ID.
     * @return version The version.
     * @dev interfaceId: This specific interface ID is '0x94642228'.
     * @dev version: Indicates a cross-chain compatible msg encoding with other ONFTs.
     * @dev If a new feature is added to the ONFT cross-chain msg encoding, the version will be incremented.
     * ie. localONFT version(x,1) CAN send messages to remoteONFT version(x,1)
     */
    function onftVersion() external view returns (bytes4 interfaceId, uint64 version);

    /**
     * @notice Retrieves the address of the token associated with the ONFT.
     * @return token The address of the ERC721 token implementation.
     */
    function token() external view returns (address);

    /**
     * @notice Indicates whether the ONFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     * @dev Allows things like wallet implementers to determine integration requirements,
     * without understanding the underlying token implementation.
     */
    function approvalRequired() external view returns (bool);

    /**
     * @notice Provides a quote for the send() operation.
     * @param _sendParam The parameters for the send() operation.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     * @dev MessagingFee: LayerZero msg fee
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     */
    function quoteSend(SendParam calldata _sendParam, bool _payInLzToken) external view returns (MessagingFee memory);

    /**
     * @notice Executes the send() operation.
     * @param _sendParam The parameters for the send operation.
     * @param _fee The fee information supplied by the caller.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds from fees etc. on the src.
     * @return receipt The LayerZero messaging receipt from the send() operation.
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory);
}
