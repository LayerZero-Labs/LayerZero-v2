// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { MessagingReceipt, MessagingFee } from "../../oapp/OAppSender.sol";

/**
 * @dev Struct representing token parameters for the OFT send() operation.
 */
struct SendParam {
    uint32 dstEid; // Destination endpoint ID.
    bytes32 to; // Recipient address.
    uint256 amountToSendLD; // Amount to send in local decimals.
    uint256 minAmountToCreditLD; // Minimum amount to credit in local decimals.
}

/**
 * @dev Struct representing OFT limit information.
 * @dev These amounts can change dynamically and are up the the specific oft implementation.
 */
struct OFTLimit {
    uint256 minAmountLD; // Minimum amount in local decimals that can be sent to the recipient.
    uint256 maxAmountLD; // Maximum amount in local decimals that can be sent to the recipient.
}

/**
 * @dev Struct representing OFT receipt information.
 */
struct OFTReceipt {
    uint256 amountDebitLD; // Amount of tokens ACTUALLY debited in local decimals.
    // @dev Does not guarantee the recipient will receive the credit amount, as remote implementations can vary depending on the OFT
    // eg. fees COULD be applied on the remote side, so the recipient may receive less than amountCreditLD
    uint256 amountCreditLD; // Amount of tokens to be credited on the remote side.
}

/**
 * @dev Struct representing OFT fee details.
 * @dev Future proof mechanism to provide a standardized way to communicate fees to things like a UI.
 */
struct OFTFeeDetail {
    uint256 feeAmountLD; // Amount of the fee in local decimals.
    string description; // Description of the fee.
}

/**
 * @title IOFT
 * @dev Interface for the OftChain (OFT) token.
 * @dev Does not inherit ERC20 to accommodate usage by OFTAdapter as well.
 */
interface IOFT {
    // Custom error messages
    error InvalidLocalDecimals();
    error SlippageExceeded(uint256 amountToCreditLD, uint256 minAmountToCreditLD);

    // Events
    event MsgInspectorSet(address inspector);
    event OFTSent(
        bytes32 indexed guid, // GUID of the OFT message.
        address indexed fromAddress, // Address of the sender on the src chain.
        uint256 amountDebitedLD, // Amount of tokens ACTUALLY debited from the sender in local decimals.
        uint256 amountToCreditLD, // Amount of tokens to be credited on the remote side in local decimals.
        bytes composeMsg // Composed message for the send() operation.
    );
    event OFTReceived(
        bytes32 indexed guid, // GUID of the OFT message.
        address indexed toAddress, // Address of the recipient on the dst chain.
        uint256 amountToCreditLD, // Amount of tokens to be credited on the remote side in local decimals.
        uint256 amountReceivedLD // Amount of tokens ACTUALLY received by the recipient in local decimals.
    );

    /**
     * @notice Retrieves the major and minor version of the OFT.
     * @return major The major version.
     * @return minor The minor version.
     *
     * @dev major version: Indicates a cross-chain compatible msg encoding with other OFTs.
     * @dev minor version: Indicates a version within the local chains context. eg. OFTAdapter vs. OFT
     * @dev For example, if a new feature is added to the OFT contract, the minor version will be incremented.
     * @dev If a new feature is added to the OFT cross-chain msg encoding, the major version will be incremented.
     * ie. localOFT version(1,1) CAN send messages to remoteOFT version(1,2)
     */
    function oftVersion() external view returns (uint64 major, uint64 minor);

    /**
     * @notice Retrieves the address of the token associated with the OFT.
     * @return token The address of the ERC20 token implementation.
     */
    function token() external view returns (address);

    /**
     * @notice Retrieves the shared decimals of the OFT.
     * @return sharedDecimals The shared decimals of the OFT.
     */
    function sharedDecimals() external view returns (uint8);

    /**
     * @notice Sets the message inspector address for the OFT.
     * @param _msgInspector The address of the message inspector.
     */
    function setMsgInspector(address _msgInspector) external;

    /**
     * @notice Retrieves the address of the message inspector.
     * @return msgInspector The address of the message inspector.
     */
    function msgInspector() external view returns (address);

    /**
     * @notice Provides a quote for OFT-related operations.
     * @param _sendParam The parameters for the send operation.
     * @param _oftCmd The OFT command to be executed.
     * @return limit The OFT limit information.
     * @return oftFeeDetails The details of OFT fees.
     * @return receipt The OFT receipt information.
     */
    function quoteOFT(
        SendParam calldata _sendParam,
        bytes calldata _oftCmd
    ) external view returns (OFTLimit memory, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory);

    /**
     * @notice Provides a quote for the send() operation.
     * @param _sendParam The parameters for the send() operation.
     * @param _extraOptions Additional options supplied by the caller to be used in the LayerZero message.
     * @param _payInLzToken Flag indicating whether the caller is paying in the LZ token.
     * @param _composeMsg The composed message for the send() operation.
     * @param _oftCmd The OFT command to be executed.
     * @return fee The calculated LayerZero messaging fee from the send() operation.
     *
     * @dev MessagingFee: LayerZero msg fee
     *  - nativeFee: The native fee.
     *  - lzTokenFee: The lzToken fee.
     */
    function quoteSend(
        SendParam calldata _sendParam,
        bytes calldata _extraOptions,
        bool _payInLzToken,
        bytes calldata _composeMsg,
        bytes calldata _oftCmd
    ) external view returns (MessagingFee memory);

    /**
     * @notice Executes the send() operation.
     * @param _sendParam The parameters for the send operation.
     * @param _extraOptions Additional options supplied by the caller to be used in the LayerZero message.
     * @param _fee The fee information supplied by the caller.
     *      - nativeFee: The native fee.
     *      - lzTokenFee: The lzToken fee.
     * @param _refundAddress The address to receive any excess funds from fees etc. on the src.
     * @param _composeMsg The composed message for the send() operation.
     * @param _oftCmd The OFT command to be executed.
     * @return receipt The LayerZero messaging receipt from the send() operation.
     * @return oftReceipt The OFT receipt information.
     *
     * @dev MessagingReceipt: LayerZero msg receipt
     *  - guid: The unique identifier for the sent message.
     *  - nonce: The nonce of the sent message.
     *  - fee: The LayerZero fee incurred for the message.
     */
    function send(
        SendParam calldata _sendParam,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress,
        bytes calldata _composeMsg,
        bytes calldata _oftCmd
    ) external payable returns (MessagingReceipt memory, OFTReceipt memory);
}
