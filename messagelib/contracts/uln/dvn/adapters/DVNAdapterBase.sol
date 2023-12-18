// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";
import { IMessageLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { ISendLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { ILayerZeroDVN } from "../../interfaces/ILayerZeroDVN.sol";
import { IReceiveUlnE2 } from "../../interfaces/IReceiveUlnE2.sol";
import { IDVNAdapterFeeLib } from "../../interfaces/IDVNAdapterFeeLib.sol";

/// @title DVNAdapterBase
/// @notice base contract for DVN adapters
/// @dev limitations:
///  - doesn't accept alt token
///  - doesn't respect block confirmations
///  - doesn't support multiple libraries. One deployment per library
abstract contract DVNAdapterBase is Ownable, ILayerZeroDVN {
    using BytesLib for bytes;

    struct DstMultiplierParam {
        uint32 dstEid;
        uint16 multiplierBps;
    }

    /// @dev for protocols that doesn't allow to configure outbound block confirmations per message,
    /// ignore confirmations set in the config and use the maximum possible confirmations to prevent failure
    /// in the receive library due to insufficient confirmations if the config was changed before the message is received
    uint64 internal constant MAX_CONFIRMATIONS = type(uint64).max;

    uint256 internal constant PACKET_HEADER_SIZE = 81;
    uint256 internal constant PAYLOAD_HASH_SIZE = 32;
    uint256 internal constant PAYLOAD_SIZE = PACKET_HEADER_SIZE + PAYLOAD_HASH_SIZE;

    ISendLib public immutable sendLib;
    IReceiveUlnE2 public immutable receiveLib;
    IDVNAdapterFeeLib public feeLib;

    uint16 public defaultMultiplierBps = 10_000; // no multiplier
    mapping(address admin => bool) public admins;

    error OnlySendLib();
    error Unauthorized();
    error InvalidPayloadSize();
    error VersionMismatch();

    event AdminSet(address indexed admin, bool isAdmin);
    event DefaultMultiplierSet(uint16 multiplierBps);
    event DstMultiplierSet(DstMultiplierParam[] params);
    event FeeLibSet(address indexed feeLib);
    event FeeWithdrawn(address indexed to, uint256 amount);
    event TokenWithdrawn(address indexed to, address token, uint256 amount);

    modifier onlySendLib() {
        if (msg.sender != address(sendLib)) revert OnlySendLib();
        _;
    }

    modifier onlyAdmin() {
        if (!admins[msg.sender]) revert Unauthorized();
        _;
    }

    constructor(address _sendLib, address _receiveLib, address[] memory _admins) {
        (uint64 sendMajor, uint8 sendMinor, uint8 sendEndpoint) = IMessageLib(_sendLib).version();
        (uint64 receiveMajor, uint8 receiveMinor, uint8 receiveEndpoint) = IMessageLib(_receiveLib).version();

        if (sendMajor != receiveMajor || sendMinor != receiveMinor || sendEndpoint != receiveEndpoint) {
            revert VersionMismatch();
        }

        sendLib = ISendLib(_sendLib);
        receiveLib = IReceiveUlnE2(_receiveLib);

        for (uint256 i = 0; i < _admins.length; i++) {
            admins[_admins[i]] = true;
            emit AdminSet(_admins[i], true);
        }
    }

    function setAdmin(address _admin, bool _isAdmin) external onlyOwner {
        admins[_admin] = _isAdmin;
        emit AdminSet(_admin, _isAdmin);
    }

    // -------------------- Only Admin --------------------

    /// @notice sets the default fee multiplier in basis points
    /// @param _defaultMultiplierBps default fee multiplier
    function setDefaultMultiplier(uint16 _defaultMultiplierBps) external onlyAdmin {
        defaultMultiplierBps = _defaultMultiplierBps;
        emit DefaultMultiplierSet(_defaultMultiplierBps);
    }

    function setFeeLib(address _feeLib) external onlyAdmin {
        feeLib = IDVNAdapterFeeLib(_feeLib);
        emit FeeLibSet(_feeLib);
    }

    /// @dev supports withdrawing fee from ULN301, ULN302 and more
    /// @param _to address to withdraw fee to
    /// @param _amount amount to withdraw
    function withdrawFee(address _to, uint256 _amount) external onlyAdmin {
        _withdrawFee(_to, _amount);
    }

    /// @dev supports withdrawing token from the contract
    /// @param _token token address
    /// @param _to address to withdraw token to
    /// @param _amount amount to withdraw
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyAdmin {
        // transfers native if _token is address(0x0)
        Transfer.nativeOrToken(_token, _to, _amount);
        emit TokenWithdrawn(_to, _token, _amount);
    }

    // -------------------- Internal Functions --------------------

    function _assertBalanceAndWithdrawFee(uint256 _messageFee) internal {
        uint256 balance = address(this).balance;

        if (balance < _messageFee) {
            // withdraw fees from the sendLib if balance is insufficient
            // sendLib will revert if not enough fees were accumulated
            _withdrawFee(address(this), _messageFee - balance); // todo: why not withdraw all fees from sendLib? so that dont need to withdraw every time
        }
    }

    function _withdrawFee(address _to, uint256 _amount) internal {
        sendLib.withdrawFee(_to, _amount);
        emit FeeWithdrawn(_to, _amount);
    }

    function _encodePayload(
        bytes memory _packetHeader,
        bytes32 _payloadHash
    ) internal pure returns (bytes memory payload) {
        return abi.encodePacked(_packetHeader, _payloadHash);
    }

    function _decodePayload(
        bytes memory _payload
    ) internal pure returns (bytes memory packetHeader, bytes32 payloadHash) {
        if (_payload.length != PAYLOAD_SIZE) revert InvalidPayloadSize();
        uint256 start = 0;
        packetHeader = _payload.slice(start, PACKET_HEADER_SIZE);

        start += PACKET_HEADER_SIZE;
        payloadHash = _payload.toBytes32(start);
    }

    function _verify(bytes memory _payload) internal {
        (bytes memory packetHeader, bytes32 payloadHash) = _decodePayload(_payload);
        receiveLib.verify(packetHeader, payloadHash, MAX_CONFIRMATIONS);
    }

    receive() external payable {}
}
