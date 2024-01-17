// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { OFTCore } from "./OFTCore.sol";

/**
 * @title OFTAdapter Contract
 * @dev OFTAdapter is a contract that adapts an ERC-20 token to the OFT functionality.
 *
 * @dev For existing ERC20 tokens, this can be used to convert the token to crosschain compatibility.
 * @dev WARNING: ONLY 1 of these should exist for a given global mesh,
 * unless you make a NON-default implementation of OFT and needs to be done very carefully
 */
contract OFTAdapter is OFTCore {
    using SafeERC20 for IERC20;

    IERC20 internal immutable innerToken;

    // @dev The amount of tokens locked inside this contract.
    // @dev This SHOULD equal the total amount of OFTs in circulation on all the NON OFTAdapter chains
    uint256 public outboundAmount;

    /**
     * @dev Constructor for the OFTAdapter contract.
     * @param _token The address of the ERC-20 token to be adapted.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _owner The owner of the contract.
     */
    constructor(
        address _token,
        address _lzEndpoint,
        address _owner
    ) OFTCore(IERC20Metadata(_token).decimals(), _lzEndpoint, _owner) {
        innerToken = IERC20(_token);
    }

    /**
     * @dev Retrieves the OFTAdapter contract version.
     * @return major The major version.
     * @return minor The minor version.
     *
     * @dev major version: Indicates a cross-chain compatible msg encoding with other OFTs.
     * @dev minor version: Indicates a version within the local chains context. eg. OFTAdapter vs. OFT
     * @dev For example, if a new feature is added to the OFT contract, the minor version will be incremented.
     * @dev If a new feature is added to the OFT cross-chain msg encoding, the major version will be incremented.
     * ie. localOFT version(1,1) CAN send messages to remoteOFT version(1,2)
     */
    function oftVersion() external pure returns (uint64 major, uint64 minor) {
        return (1, 2);
    }

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the adapted ERC-20 token.
     *
     * @dev In the case of OFTAdapter, address(this) and erc20 are NOT the same contract.
     */
    function token() public view virtual returns (address) {
        return address(innerToken);
    }

    /**
     * @dev Burns tokens from the sender's specified balance, ie. pull method.
     * @param _amountToSendLD The amount of tokens to send in local decimals.
     * @param _minAmountToCreditLD The minimum amount to credit in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountDebitedLD The amount of tokens ACTUALLY debited in local decimals.
     * @return amountToCreditLD The amount of tokens to credit in local decimals.
     */
    function _debitSender(
        uint256 _amountToSendLD,
        uint256 _minAmountToCreditLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountDebitedLD, uint256 amountToCreditLD) {
        (amountDebitedLD, amountToCreditLD) = _debitView(_amountToSendLD, _minAmountToCreditLD, _dstEid);
        // @dev msg.sender will need to approve this amountLD of tokens to be locked inside of the contract.
        // @dev Move all of the debited tokens into this contract.
        innerToken.safeTransferFrom(msg.sender, address(this), amountDebitedLD);

        // @dev In NON-default OFTAdapter, amountDebited could be 100, with a 10% fee, the credited amount is 90,
        // so technically the amountToCredit would be locked as outboundAmount. Therefore amountDebited CAN differ from amountToCredit.
        // @dev Due to OFTs containing both push/pull methods, the reserved amount needs to be tracked so _debitThis() cant spend it.
        outboundAmount += amountToCreditLD;
    }

    /**
     * @dev Allows a sender to send tokens that are inside the contract but are NOT accounted for in outboundAmount, ie. push method.
     * @param _minAmountToCreditLD The minimum amount to credit in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountDebitedLD The amount of tokens ACTUALLY debited in local decimals.
     * @return amountToCreditLD The amount of tokens to credit in local decimals.
     */
    function _debitThis(
        uint256 _minAmountToCreditLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountDebitedLD, uint256 amountToCreditLD) {
        // @dev This is the push method, where at any point in the transaction, the OFT receives tokens and they can be sent by the caller.
        // @dev This SHOULD be done atomically, otherwise any caller can spend tokens that are owned by the contract.
        uint256 availableToSend = innerToken.balanceOf(address(this)) - outboundAmount;
        (amountDebitedLD, amountToCreditLD) = _debitView(availableToSend, _minAmountToCreditLD, _dstEid);

        // @dev Due to OFTs containing both push/pull methods, the reserved amount needs to be tracked so _debitThis() cant spend it.
        outboundAmount += amountToCreditLD;

        // @dev When sending tokens direct to the OFTAdapter contract,
        // there is NOT a default mechanism to capture the dust that MIGHT get left in the contract.
        // If you want to refund this dust, will need to add another function to return it.
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountToCreditLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(
        address _to,
        uint256 _amountToCreditLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        outboundAmount -= _amountToCreditLD;
        // @dev Unlock the tokens and transfer to the recipient.
        innerToken.safeTransfer(_to, _amountToCreditLD);
        // @dev In the case of NON-default OFTAdapter, the amountToCreditLD MIGHT not == amountReceivedLD.
        return _amountToCreditLD;
    }
}
