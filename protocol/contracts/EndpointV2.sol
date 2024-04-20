// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MessagingFee, MessagingParams, MessagingReceipt, Origin, ILayerZeroEndpointV2 } from "./interfaces/ILayerZeroEndpointV2.sol";
import { ISendLib, Packet } from "./interfaces/ISendLib.sol";
import { ILayerZeroReceiver } from "./interfaces/ILayerZeroReceiver.sol";
import { Errors } from "./libs/Errors.sol";
import { GUID } from "./libs/GUID.sol";
import { Transfer } from "./libs/Transfer.sol";
import { MessagingChannel } from "./MessagingChannel.sol";
import { MessagingComposer } from "./MessagingComposer.sol";
import { MessageLibManager } from "./MessageLibManager.sol";
import { MessagingContext } from "./MessagingContext.sol";

/**
 * @notice LayerZero EndpointV2 is fully backward compatible with LayerZero Endpoint(V1), but it also supports additional
 *         features that Endpoint(V1) does not support now and may not in the future. We have also changed some terminology
 *         to clarify pre-existing language that might have been confusing.
 *         
 *         The following is a list of terminology changes:
 *          -chainId -> eid
 *              - Rationale: chainId was a term we initially used to describe an endpoint on a specific chain. Since
 *                       LayerZero supports non-EVMs we could not map the classic EVM chainIds to the LayerZero chainIds, 
 *                       making it confusing for developers. With the addition of EndpointV2 and its backward compatible 
 *                       nature, we would have two chainIds per chain that has Endpoint(V1), further confusing developers. 
 *                       We have decided to change the name to Endpoint Id, or eid, for simplicity and clarity.
 *          -adapterParams -> options
 *          -userApplication -> oapp. Omnichain Application
 *          -srcAddress -> sender
 *          -dstAddress -> receiver
 *              - Rationale: The sender/receiver on EVM is the address. However, on non-EVM chains, the sender/receiver could be
 *                           represented as a public key, or some other identifier. The term sender/receiver is more generic.
 *          -payload -> message.
 *              - Rationale: The term payload is used in the context of a packet, which is a combination of the message and GUID.
 */
contract EndpointV2 is ILayerZeroEndpointV2, MessagingChannel, MessageLibManager, MessagingComposer, MessagingContext {
    address public lzToken;

    mapping(address oapp => address delegate) public delegates;

    /**
     * @param _eid The unique Endpoint Id for this deploy that all other Endpoints can use to send to it.
     * @param _owner The contract owner's address.
     */
    constructor(uint32 _eid, address _owner) MessagingChannel(_eid) {
        _transferOwnership(_owner);
    }

    /**
     * @dev MESSAGING STEP 0
     * @notice This view function gives the application built on top of LayerZero the ability to requests a quote
     *         with the same parameters as they would to send their message. Since the quotes are given on chain 
     *         there is a race condition in which the prices could change between the time the user gets their 
     *         quote and the time they submit their message. If the price moves up and the user doesn't send enough 
     *         funds the transaction will revert, if the price goes down the _refundAddress provided by the app will 
     *         be refunded the difference.
     * @param _params The messaging parameters.
     * @param _sender The sender of the message.
     * @return MessagingFee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quote(
        MessagingParams calldata _params, 
        address _sender
    ) external view returns (MessagingFee memory) {
        // lzToken must be set to support payInLzToken
        if (_params.payInLzToken && lzToken == address(0x0)) revert Errors.LZ_LzTokenUnavailable();

        // get the correct outbound nonce
        uint64 nonce = outboundNonce[_sender][_params.dstEid][_params.receiver] + 1;

        // construct the packet with a GUID
        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: eid,
            sender: _sender,
            dstEid: _params.dstEid,
            receiver: _params.receiver,
            guid: GUID.generate(nonce, eid, _sender, _params.dstEid, _params.receiver),
            message: _params.message
        });

        // get the send library by sender and dst eid
        // use _ to avoid variable shadowing
        address _sendLibrary = getSendLibrary(_sender, _params.dstEid);

        return ISendLib(_sendLibrary).quote(packet, _params.options, _params.payInLzToken);
    }

    /**
     * @dev MESSAGING STEP 1 - OApp need to transfer the fees to the endpoint before sending the message
     * @param _params The messaging parameters.
     * @param _refundAddress The address to refund both the native and lzToken.
     * @return MessagingReceipt A `MessagingReceipt` struct containing details of the message sent.
     */
    function send(
        MessagingParams calldata _params,
        address _refundAddress
    ) external payable sendContext(_params.dstEid, msg.sender) returns (MessagingReceipt memory) {
        if (_params.payInLzToken && lzToken == address(0x0)) revert Errors.LZ_LzTokenUnavailable();

        // send message
        (MessagingReceipt memory receipt, address _sendLibrary) = _send(msg.sender, _params);

        // OApp can simulate with 0 native value it will fail with error including the required fee, which can be provided in the actual call
        // this trick can be used to avoid the need to write the quote() function
        // however, without the quote view function it will be hard to compose an oapp on chain
        uint256 suppliedNative = _suppliedNative();
        uint256 suppliedLzToken = _suppliedLzToken(_params.payInLzToken);
        _assertMessagingFee(receipt.fee, suppliedNative, suppliedLzToken);

        // handle lz token fees
        _payToken(lzToken, receipt.fee.lzTokenFee, suppliedLzToken, _sendLibrary, _refundAddress);

        // handle native fees
        _payNative(receipt.fee.nativeFee, suppliedNative, _sendLibrary, _refundAddress);

        return receipt;
    }

    /**
     * @dev Internal function for sending the messages used by all external send methods.
     * @param _sender The address of the application sending the message to the destination chain.
     * @param _params The messaging parameters.
     * @return MessagingReceipt A `MessagingReceipt` struct containing details of the message sent.
     * @return address The send library address from sender.
     */
    function _send(
        address _sender,
        MessagingParams calldata _params
    ) internal returns (MessagingReceipt memory, address) {
        // get the correct outbound nonce
        uint64 latestNonce = _outbound(_sender, _params.dstEid, _params.receiver);

        // construct the packet with a GUID
        Packet memory packet = Packet({
            nonce: latestNonce,
            srcEid: eid,
            sender: _sender,
            dstEid: _params.dstEid,
            receiver: _params.receiver,
            guid: GUID.generate(latestNonce, eid, _sender, _params.dstEid, _params.receiver),
            message: _params.message
        });

        // get the send library by sender and dst eid
        address _sendLibrary = getSendLibrary(_sender, _params.dstEid);

        // messageLib always returns encodedPacket with guid
        (MessagingFee memory fee, bytes memory encodedPacket) = ISendLib(_sendLibrary).send(
            packet,
            _params.options,
            _params.payInLzToken
        );

        // Emit packet information for DVNs, Executors, and any other offchain infrastructure to only listen
        // for this one event to perform their actions.
        emit PacketSent(encodedPacket, _params.options, _sendLibrary);

        return (MessagingReceipt(packet.guid, latestNonce, fee), _sendLibrary);
    }

    /**
     * @dev MESSAGING STEP 2 - on the destination chain.
     * @dev Configured receive library verifies a message.
     * @param _origin A struct holding the srcEid, nonce, and sender of the message.
     * @param _receiver The receiver of the message.
     * @param _payloadHash The payload hash of the message.
     */
    function verify(
        Origin calldata _origin, 
        address _receiver, 
        bytes32 _payloadHash
    ) external {
        if (!isValidReceiveLibrary(_receiver, _origin.srcEid, msg.sender)) revert Errors.LZ_InvalidReceiveLibrary();

        uint64 lazyNonce = lazyInboundNonce[_receiver][_origin.srcEid][_origin.sender];
        if (!_initializable(_origin, _receiver, lazyNonce)) revert Errors.LZ_PathNotInitializable();
        if (!_verifiable(_origin, _receiver, lazyNonce)) revert Errors.LZ_PathNotVerifiable();

        // insert the message into the message channel
        _inbound(_receiver, _origin.srcEid, _origin.sender, _origin.nonce, _payloadHash);
        emit PacketVerified(_origin, _receiver, _payloadHash);
    }

    /**
     * @dev MESSAGING STEP 3 - the last step.
     * @dev Execute a verified message to the designated receiver.
     * @dev The execution provides the execution context (caller, extraData) to the receiver. The receiver can 
            optionally assert the caller and validate the untrusted extraData.
     * @dev Can't reentrant because the payload is cleared before execution.
     * @param _origin The origin of the message.
     * @param _receiver The receiver of the message.
     * @param _guid The guid of the message.
     * @param _message The message.
     * @param _extraData The extra data provided by the executor. This data is untrusted and should be validated.
     */
    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable {
        // clear the payload first to prevent reentrancy, and then execute the message
        _clearPayload(_receiver, _origin.srcEid, _origin.sender, _origin.nonce, abi.encodePacked(_guid, _message));
        ILayerZeroReceiver(_receiver).lzReceive{ value: msg.value }(_origin, _guid, _message, msg.sender, _extraData);
        emit PacketDelivered(_origin, _receiver);
    }

    /**
     * @param _origin The origin of the message.
     * @param _receiver The receiver of the message.
     * @param _guid The guid of the message.
     * @param _gas The amount of gas.
     * @param _value The value in wei.
     * @param _message The message.
     * @param _extraData The extra data provided by the executor.
     * @param _reason The reason for failure.
     */
    function lzReceiveAlert(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        uint256 _gas,
        uint256 _value,
        bytes calldata _message,
        bytes calldata _extraData,
        bytes calldata _reason
    ) external {
        emit LzReceiveAlert(_receiver, msg.sender, _origin, _guid, _gas, _value, _message, _extraData, _reason);
    }

    /**
     * @dev Oapp uses this interface to clear a message.
     * @dev This is a PULL mode versus the PUSH mode of lzReceive.
     * @dev The cleared message can be ignored by the app (effectively burnt).
     * @dev Authenticated by oapp.
     * @param _oapp The oapp address.
     * @param _origin The origin of the message.
     * @param _guid The guid of the message.
     * @param _message The message.
     */
    function clear(
        address _oapp, 
        Origin calldata _origin, 
        bytes32 _guid, 
        bytes calldata _message
    ) external {
        _assertAuthorized(_oapp);

        bytes memory payload = abi.encodePacked(_guid, _message);
        _clearPayload(_oapp, _origin.srcEid, _origin.sender, _origin.nonce, payload);
        emit PacketDelivered(_origin, _oapp);
    }

    /**
     * @dev Allows reconfiguration to recover from wrong configurations.
     * @dev Users should never approve the EndpointV2 contract to spend their non-LayerZero tokens.
     * @dev Override this function if the endpoint is charging ERC20 tokens as native.
     * @dev Only owner.
     * @param _lzToken The new layer zero token address.
     */
    function setLzToken(
        address _lzToken
    ) public virtual onlyOwner {
        lzToken = _lzToken;
        emit LzTokenSet(_lzToken);
    }

    /**
     * @dev Recover the token sent to this contract by mistake.
     * @dev Only owner.
     * @param _token The token to recover. If 0x0 then it is native token.
     * @param _to The address to send the token to.
     * @param _amount The amount to send.
     */
    function recoverToken(
        address _token, 
        address _to, 
        uint256 _amount
    ) external onlyOwner {
        Transfer.nativeOrToken(_token, _to, _amount);
    }

    /**
     * @dev Handling token payments on endpoint. The sender must approve the endpoint to spend the token.
     * @dev Internal function.
     * @param _token The token to pay.
     * @param _required The amount required.
     * @param _supplied The amount supplied.
     * @param _receiver The receiver of the token.
     * @param _refundAddress The address to refund the excess to.
     */
    function _payToken(
        address _token,
        uint256 _required,
        uint256 _supplied,
        address _receiver,
        address _refundAddress
    ) internal {
        if (_required > 0) {
            Transfer.token(_token, _receiver, _required);
        }
        if (_required < _supplied) {
            unchecked {
                // refund the excess
                Transfer.token(_token, _refundAddress, _supplied - _required);
            }
        }
    }

    /**
     * @dev Handling native token payments on endpoint.
     * @dev Override this if the endpoint is charging ERC20 tokens as native.
     * @dev Internal function.
     * @param _required The amount required.
     * @param _supplied The amount supplied.
     * @param _receiver The receiver of the native token.
     * @param _refundAddress The address to refund the excess to.
     */
    function _payNative(
        uint256 _required,
        uint256 _supplied,
        address _receiver,
        address _refundAddress
    ) internal virtual {
        if (_required > 0) {
            Transfer.native(_receiver, _required);
        }
        if (_required < _supplied) {
            unchecked {
                // refund the excess
                Transfer.native(_refundAddress, _supplied - _required);
            }
        }
    }

    /**
     * @dev Get the balance of the lzToken as the supplied lzToken fee if payInLzToken is true.
     * @param _payInLzToken Whether to return fee in ZRO token.
     * @return supplied The balance of the lzToken as the supplied lzToken fee.
     */
    function _suppliedLzToken(bool _payInLzToken) internal view returns (uint256 supplied) {
        if (_payInLzToken) {
            supplied = IERC20(lzToken).balanceOf(address(this));

            // if payInLzToken is true, the supplied fee must be greater than 0 to prevent a race condition
            // in which an oapp sending a message with lz token and the lz token is set to a new token between the tx
            // being sent and the tx being mined. if the required lz token fee is 0 and the old lz token would be
            // locked in the contract instead of being refunded
            if (supplied == 0) revert Errors.LZ_ZeroLzTokenFee();
        }
    }

    /**
     * @dev Override this if the endpoint is charging ERC20 tokens as native.
     * @return uint256 The value in wei for the message.
     */
    function _suppliedNative() internal view virtual returns (uint256) {
        return msg.value;
    }

    /**
     * @dev Assert the required fees and the supplied fees are enough.
     * @param _required The `MessagingFee` struct containing the fee.
     * @param _suppliedNativeFee The supplied native fee.
     * @param _suppliedLzTokenFee The supplied fee in ZRO token.
     */
    function _assertMessagingFee(
        MessagingFee memory _required,
        uint256 _suppliedNativeFee,
        uint256 _suppliedLzTokenFee
    ) internal pure {
        if (_required.nativeFee > _suppliedNativeFee || _required.lzTokenFee > _suppliedLzTokenFee) {
            revert Errors.LZ_InsufficientFee(
                _required.nativeFee,
                _suppliedNativeFee,
                _required.lzTokenFee,
                _suppliedLzTokenFee
            );
        }
    }

    /**
     * @dev Override this if the endpoint is charging ERC20 tokens as native.
     * @return address 0x0 if using native; otherwise, the address of the native ERC20 token.
     */
    function nativeToken() external view virtual returns (address) {
        return address(0x0);
    }

    /**
     * @notice Delegate is authorized by the oapp to configure anything in LayerZero.
     * @param _delegate The address to delegate to.
     */
    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
        emit DelegateSet(msg.sender, _delegate);
    }

    // ========================= Internal =========================
    function _initializable(
        Origin calldata _origin,
        address _receiver,
        uint64 _lazyInboundNonce
    ) internal view returns (bool) {
        return
            _lazyInboundNonce > 0 || // allowInitializePath already checked
            ILayerZeroReceiver(_receiver).allowInitializePath(_origin);
    }

    /**
     * @dev Bytes(0) payloadHash can never be submitted.
     */
    function _verifiable(
        Origin calldata _origin,
        address _receiver,
        uint64 _lazyInboundNonce
    ) internal view returns (bool) {
        return
            _origin.nonce > _lazyInboundNonce || // either initializing an empty slot or reverifying
            inboundPayloadHash[_receiver][_origin.srcEid][_origin.sender][_origin.nonce] != EMPTY_PAYLOAD_HASH; // only allow reverifying if it hasn't been executed
    }

    /**
     * @dev Assert the caller to either be the oapp or the delegate.
     */
    function _assertAuthorized(address _oapp) internal view override(MessagingChannel, MessageLibManager) {
        if (msg.sender != _oapp && msg.sender != delegates[_oapp]) revert Errors.LZ_Unauthorized();
    }

    // ========================= VIEW FUNCTIONS FOR OFFCHAIN ONLY =========================
    // Not involved in any state transition function.
    // ====================================================================================
    function initializable(Origin calldata _origin, address _receiver) external view returns (bool) {
        return _initializable(_origin, _receiver, lazyInboundNonce[_receiver][_origin.srcEid][_origin.sender]);
    }

    function verifiable(Origin calldata _origin, address _receiver) external view returns (bool) {
        return _verifiable(_origin, _receiver, lazyInboundNonce[_receiver][_origin.srcEid][_origin.sender]);
    }
}
