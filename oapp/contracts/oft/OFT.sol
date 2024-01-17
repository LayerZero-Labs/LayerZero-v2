// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { OFTCore } from "./OFTCore.sol";

/**
 * @title OFT Contract
 * @dev OFT is an ERC-20 token that extends the functionality of the OFTCore contract.
 */
contract OFT is OFTCore, ERC20 {
    /**
     * @dev Constructor for the OFT contract.
     * @param _name The name of the OFT.
     * @param _symbol The symbol of the OFT.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _owner The owner of the contract.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _owner
    ) ERC20(_name, _symbol) OFTCore(decimals(), _lzEndpoint, _owner) {}

    /**
     * @dev Retrieves the OFT contract version.
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
        return (1, 1);
    }

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the OFT token.
     *
     * @dev In the case of OFT, address(this) and erc20 are the same contract.
     */
    function token() external view returns (address) {
        return address(this);
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
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

        // @dev In NON-default OFT, amountDebited could be 100, with a 10% fee, the credited amount is 90,
        // therefore amountDebited CAN differ from amountToCredit.

        // @dev Default OFT burns on src.
        _burn(msg.sender, amountDebitedLD);
    }

    /**
     * @dev Burns tokens that have been sent into this contract.
     * @param _minAmountToReceiveLD The minimum amount to receive in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountDebitedLD The amount of tokens ACTUALLY debited in local decimals.
     * @return amountToCreditLD The amount of tokens to credit in local decimals.
     */
    function _debitThis(
        uint256 _minAmountToReceiveLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountDebitedLD, uint256 amountToCreditLD) {
        // @dev This is the push method, where at any point in the transaction, the OFT receives tokens and they can be sent by the caller.
        // @dev This SHOULD be done atomically, otherwise any caller can spend tokens that are owned by the contract.
        // @dev In the NON-default case where fees are stored in the contract, there should be a value reserved via a global state.
        // eg. balanceOf(address(this)) - accruedFees;
        (amountDebitedLD, amountToCreditLD) = _debitView(balanceOf(address(this)), _minAmountToReceiveLD, _dstEid);

        // @dev Default OFT burns on src.
        _burn(address(this), amountDebitedLD);

        // @dev When sending tokens direct to the OFT contract,
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
        // @dev Default OFT mints on dst.
        _mint(_to, _amountToCreditLD);
        // @dev In the case of NON-default OFT, the amountToCreditLD MIGHT not == amountReceivedLD.
        return _amountToCreditLD;
    }
}
