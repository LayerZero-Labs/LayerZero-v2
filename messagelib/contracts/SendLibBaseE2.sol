// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { ILayerZeroEndpointV2, MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IMessageLib, MessageLibType } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { ISendLib, Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { SendLibBase, WorkerOptions, ExecutorConfig } from "./SendLibBase.sol";

/// @dev send-side message library base contract on endpoint v2.
/// design: the high level logic is the same as SendLibBaseE1
/// 1/ with added interfaces
/// 2/ adapt the functions to the new types, like uint32 for eid, address for sender.
abstract contract SendLibBaseE2 is SendLibBase, ERC165, ISendLib {
    event NativeFeeWithdrawn(address worker, address receiver, uint256 amount);
    event LzTokenFeeWithdrawn(address lzToken, address receiver, uint256 amount);

    error NotTreasury();
    error CannotWithdrawAltToken();

    constructor(
        address _endpoint,
        uint256 _treasuryGasLimit,
        uint256 _treasuryNativeFeeCap
    ) SendLibBase(_endpoint, ILayerZeroEndpointV2(_endpoint).eid(), _treasuryGasLimit, _treasuryNativeFeeCap) {}

    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            _interfaceId == type(IMessageLib).interfaceId ||
            _interfaceId == type(ISendLib).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    // ========================= OnlyEndpoint =========================
    // @dev this function is marked as virtual and public for testing purpose
    function send(
        Packet calldata _packet,
        bytes calldata _options,
        bool _payInLzToken
    ) public virtual onlyEndpoint returns (MessagingFee memory, bytes memory) {
        (bytes memory encodedPacket, uint256 totalNativeFee) = _payWorkers(_packet, _options);

        (uint256 treasuryNativeFee, uint256 lzTokenFee) = _payTreasury(
            _packet.sender,
            _packet.dstEid,
            totalNativeFee,
            _payInLzToken
        );
        totalNativeFee += treasuryNativeFee;

        return (MessagingFee(totalNativeFee, lzTokenFee), encodedPacket);
    }

    // ========================= OnlyOwner =========================
    function setTreasury(address _treasury) external onlyOwner {
        _setTreasury(_treasury);
    }

    // ========================= External =========================
    /// @dev E2 only
    function withdrawFee(address _to, uint256 _amount) external {
        _debitFee(_amount);
        address nativeToken = ILayerZeroEndpointV2(endpoint).nativeToken();
        // transfers native if nativeToken == address(0x0)
        Transfer.nativeOrToken(nativeToken, _to, _amount);
        emit NativeFeeWithdrawn(msg.sender, _to, _amount);
    }

    /// @dev _lzToken is a user-supplied value because lzToken might change in the endpoint before all lzToken can be taken out
    /// @dev E2 only
    /// @dev treasury only function
    function withdrawLzTokenFee(address _lzToken, address _to, uint256 _amount) external {
        if (msg.sender != treasury) revert NotTreasury();

        // lz token cannot be the same as the native token
        if (ILayerZeroEndpointV2(endpoint).nativeToken() == _lzToken) revert CannotWithdrawAltToken();

        Transfer.token(_lzToken, _to, _amount);

        emit LzTokenFeeWithdrawn(_lzToken, _to, _amount);
    }

    // ========================= View =========================
    function quote(
        Packet calldata _packet,
        bytes calldata _options,
        bool _payInLzToken
    ) external view returns (MessagingFee memory) {
        (uint256 nativeFee, uint256 lzTokenFee) = _quote(
            _packet.sender,
            _packet.dstEid,
            _packet.message.length,
            _payInLzToken,
            _options
        );
        return MessagingFee(nativeFee, lzTokenFee);
    }

    function messageLibType() external pure virtual override returns (MessageLibType) {
        return MessageLibType.Send;
    }

    // ========================= Internal =========================
    /// 1/ handle executor
    /// 2/ handle other workers
    function _payWorkers(
        Packet calldata _packet,
        bytes calldata _options
    ) internal returns (bytes memory encodedPacket, uint256 totalNativeFee) {
        // split workers options
        (bytes memory executorOptions, WorkerOptions[] memory validationOptions) = _splitOptions(_options);

        // handle executor
        ExecutorConfig memory config = getExecutorConfig(_packet.sender, _packet.dstEid);
        uint256 msgSize = _packet.message.length;
        _assertMessageSize(msgSize, config.maxMessageSize);
        totalNativeFee += _payExecutor(config.executor, _packet.dstEid, _packet.sender, msgSize, executorOptions);

        // handle other workers
        (uint256 verifierFee, bytes memory packetBytes) = _payVerifier(_packet, validationOptions); //for ULN, it will be dvns
        totalNativeFee += verifierFee;

        encodedPacket = packetBytes;
    }

    // ======================= Virtual =======================
    // For implementation to override
    function _payVerifier(
        Packet calldata _packet,
        WorkerOptions[] memory _options
    ) internal virtual returns (uint256 otherWorkerFees, bytes memory encodedPacket);

    // receive native token from endpoint
    receive() external payable virtual {}
}
