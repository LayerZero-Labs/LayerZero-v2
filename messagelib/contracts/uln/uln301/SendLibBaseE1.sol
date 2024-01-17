// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";
import { GUID } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/GUID.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { IMessageLibE1 } from "./interfaces/IMessageLibE1.sol";
import { ITreasuryFeeHandler } from "./interfaces/ITreasuryFeeHandler.sol";
import { INonceContract } from "./interfaces/INonceContract.sol";
import { SendLibBase, WorkerOptions, ExecutorConfig } from "../../SendLibBase.sol";
import { AddressSizeConfig } from "./AddressSizeConfig.sol";

/// @dev send-side message library base contract on endpoint v1.
/// design:
/// 1/ it enforces the path definition on V1 and interacts with the nonce contract
/// 2/ quote: first executor, then verifier (e.g. DVNs), then treasury
/// 3/ send: first executor, then verifier (e.g. DVNs), then treasury. the treasury pay much be DoS-proof
abstract contract SendLibBaseE1 is SendLibBase, AddressSizeConfig, IMessageLibE1 {
    INonceContract public immutable nonceContract;
    ITreasuryFeeHandler public immutable treasuryFeeHandler;

    // config
    address internal lzToken;

    // this event should be identical to the one on Endpoint V2
    event PacketSent(bytes encodedPayload, bytes options, uint256 nativeFee, uint256 lzTokenFee);
    event NativeFeeWithdrawn(address user, address receiver, uint256 amount);
    event LzTokenSet(address token);

    constructor(
        address _endpoint,
        uint256 _treasuryGasLimit,
        uint256 _treasuryNativeFeeCap,
        address _nonceContract,
        uint32 _localEid,
        address _treasuryFeeHandler
    ) SendLibBase(_endpoint, _localEid, _treasuryGasLimit, _treasuryNativeFeeCap) {
        nonceContract = INonceContract(_nonceContract);
        treasuryFeeHandler = ITreasuryFeeHandler(_treasuryFeeHandler);
    }

    // ======================= OnlyEndpoint =======================
    /// @dev the abstract process for send() is:
    /// 1/ pay workers, which includes the executor and the validation workers
    /// 2/ pay treasury
    /// 3/ in EndpointV1, here we handle the fees and refunds
    function send(
        address _sender,
        uint64, // _nonce
        uint16 _dstEid,
        bytes calldata _path, // remoteAddress + localAddress
        bytes calldata _message,
        address payable _refundAddress,
        address _lzTokenPaymentAddress,
        bytes calldata _options
    ) external payable onlyEndpoint {
        (bytes memory encodedPacket, uint256 totalNativeFee) = _payWorkers(_sender, _dstEid, _path, _message, _options);

        // quote treasury fee
        uint32 dstEid = _dstEid; // stack too deep
        address sender = _sender; // stack too deep
        bool payInLzToken = _lzTokenPaymentAddress != address(0x0) && address(lzToken) != address(0x0);
        (uint256 treasuryNativeFee, uint256 lzTokenFee) = _payTreasury(sender, dstEid, totalNativeFee, payInLzToken);
        totalNativeFee += treasuryNativeFee;

        // pay native fee
        // assert the user has attached enough native token for this address
        if (msg.value < totalNativeFee) revert InsufficientMsgValue();
        // refund if they send too much
        uint256 refundAmt = msg.value - totalNativeFee;
        if (refundAmt > 0) {
            Transfer.native(_refundAddress, refundAmt);
        }

        // pay lz token fee if needed
        if (lzTokenFee > 0) {
            // in v2, we let user pass a payInLzToken boolean but always charging the sender
            // likewise in v1, if _lzTokenPaymentAddress is passed, it must be the sender
            if (_lzTokenPaymentAddress != sender) revert LzTokenPaymentAddressMustBeSender();
            _payLzTokenFee(sender, lzTokenFee);
        }

        emit PacketSent(encodedPacket, _options, totalNativeFee, lzTokenFee);
    }

    // ======================= OnlyOwner =======================
    function setLzToken(address _lzToken) external onlyOwner {
        lzToken = _lzToken;
        emit LzTokenSet(_lzToken);
    }

    function setTreasury(address _treasury) external onlyOwner {
        _setTreasury(_treasury);
    }

    // ======================= External =======================
    function withdrawFee(address _to, uint256 _amount) external {
        _debitFee(_amount);
        Transfer.native(_to, _amount);
        emit NativeFeeWithdrawn(msg.sender, _to, _amount);
    }

    // ======================= View =======================
    function estimateFees(
        uint16 _dstEid,
        address _sender,
        bytes calldata _message,
        bool _payInLzToken,
        bytes calldata _options
    ) external view returns (uint256 nativeFee, uint256 lzTokenFee) {
        return _quote(_sender, _dstEid, _message.length, _payInLzToken, _options);
    }

    // ======================= Internal =======================
    /// @dev path = remoteAddress + localAddress.
    function _assertPath(address _sender, bytes calldata _path, uint256 remoteAddressSize) internal pure {
        if (_path.length != 20 + remoteAddressSize) revert InvalidPath();
        address srcInPath = AddressCast.toAddress(_path[remoteAddressSize:]);
        if (_sender != srcInPath) revert InvalidSender();
    }

    function _payLzTokenFee(address _sender, uint256 _lzTokenFee) internal {
        treasuryFeeHandler.payFee(
            lzToken,
            _sender,
            _lzTokenFee, // the supplied fee is always equal to the required fee
            _lzTokenFee,
            treasury
        );
    }

    /// @dev outbound does three things
    /// @dev 1) asserts path
    /// @dev 2) increments the nonce
    /// @dev 3) assemble packet
    /// @return packet to be sent to workers
    function _outbound(
        address _sender,
        uint16 _dstEid,
        bytes calldata _path,
        bytes calldata _message
    ) internal returns (Packet memory packet) {
        // assert toAddress size
        uint256 remoteAddressSize = addressSizes[_dstEid];
        if (remoteAddressSize == 0) revert InvalidPath();
        _assertPath(_sender, _path, remoteAddressSize);

        // increment nonce
        uint64 nonce = nonceContract.increment(_dstEid, _sender, _path);

        bytes32 receiver = AddressCast.toBytes32(_path[0:remoteAddressSize]);

        bytes32 guid = GUID.generate(nonce, localEid, _sender, _dstEid, receiver);

        // assemble packet
        packet = Packet(nonce, localEid, _sender, _dstEid, receiver, guid, _message);
    }

    /// 1/ handle executor
    /// 2/ handle other workers
    function _payWorkers(
        address _sender,
        uint16 _dstEid,
        bytes calldata _path,
        bytes calldata _message,
        bytes calldata _options
    ) internal returns (bytes memory encodedPacket, uint256 totalNativeFee) {
        Packet memory packet = _outbound(_sender, _dstEid, _path, _message);

        // split workers options
        (bytes memory executorOptions, WorkerOptions[] memory verificationOptions) = _splitOptions(_options);

        // handle executor
        ExecutorConfig memory config = getExecutorConfig(_sender, _dstEid);
        uint256 msgSize = packet.message.length;
        _assertMessageSize(msgSize, config.maxMessageSize);
        totalNativeFee += _payExecutor(config.executor, packet.dstEid, packet.sender, msgSize, executorOptions);

        // handle other workers
        (uint256 verifierFee, bytes memory packetBytes) = _payVerifier(packet, verificationOptions);
        totalNativeFee += verifierFee;

        encodedPacket = packetBytes;
    }

    // ======================= Virtual =======================
    function _payVerifier(
        Packet memory _packet, // packet is assembled in memory for endpoint-v1. so the location can not be calldata
        WorkerOptions[] memory _options
    ) internal virtual returns (uint256 otherWorkerFees, bytes memory encodedPacket);
}
