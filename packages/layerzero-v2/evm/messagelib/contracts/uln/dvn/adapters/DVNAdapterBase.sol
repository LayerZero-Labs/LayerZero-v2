// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";
import { ISendLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { ILayerZeroDVN } from "../../interfaces/ILayerZeroDVN.sol";
import { Worker } from "../../../Worker.sol";
import { DVNAdapterMessageCodec } from "./libs/DVNAdapterMessageCodec.sol";

interface ISendLibBase {
    function fees(address _worker) external view returns (uint256);
}

interface IReceiveUln {
    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external;
}

struct ReceiveLibParam {
    address sendLib;
    uint32 dstEid;
    bytes32 receiveLib;
}

/// @title SendDVNAdapterBase
/// @notice base contract for DVN adapters
/// @dev limitations:
///  - doesn't accept alt token
///  - doesn't respect block confirmations
abstract contract DVNAdapterBase is Worker, ILayerZeroDVN {
    // --- Errors ---
    error DVNAdapter_InsufficientBalance(uint256 actual, uint256 requested);
    error DVNAdapter_NotImplemented();
    error DVNAdapter_MissingRecieveLib(address sendLib, uint32 dstEid);

    event ReceiveLibsSet(ReceiveLibParam[] params);

    /// @dev on change of application config, dvn adapters will not perform any additional verification
    /// @dev to avoid messages from being stuck, all verifications from adapters will be done with the maximum possible confirmations
    uint64 internal constant MAX_CONFIRMATIONS = type(uint64).max;

    /// @dev receive lib to call verify() on at destination
    mapping(address sendLib => mapping(uint32 dstEid => bytes32 receiveLib)) public receiveLibs;

    constructor(
        address _roleAdmin,
        address[] memory _admins,
        uint16 _defaultMultiplierBps
    ) Worker(new address[](0), address(0x0), _defaultMultiplierBps, _roleAdmin, _admins) {}

    // ========================= OnlyAdmin =========================
    /// @notice sets receive lib for destination chains
    /// @dev DEFAULT_ADMIN_ROLE can set MESSAGE_LIB_ROLE for sendLibs and use below function to set receiveLibs
    function setReceiveLibs(ReceiveLibParam[] calldata _params) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _params.length; i++) {
            ReceiveLibParam calldata param = _params[i];
            receiveLibs[param.sendLib][param.dstEid] = param.receiveLib;
        }

        emit ReceiveLibsSet(_params);
    }

    // ========================= Internal =========================
    function _getAndAssertReceiveLib(address _sendLib, uint32 _dstEid) internal view returns (bytes32 lib) {
        lib = receiveLibs[_sendLib][_dstEid];
        if (lib == bytes32(0)) revert DVNAdapter_MissingRecieveLib(_sendLib, _dstEid);
    }

    function _encode(
        bytes32 _receiveLib,
        bytes memory _packetHeader,
        bytes32 _payloadHash
    ) internal pure returns (bytes memory) {
        return DVNAdapterMessageCodec.encode(_receiveLib, _packetHeader, _payloadHash);
    }

    function _encodeEmpty() internal pure returns (bytes memory) {
        return
            DVNAdapterMessageCodec.encode(bytes32(0), new bytes(DVNAdapterMessageCodec.PACKET_HEADER_SIZE), bytes32(0));
    }

    function _decodeAndVerify(uint32 _srcEid, bytes calldata _payload) internal {
        require((DVNAdapterMessageCodec.srcEid(_payload) % 30000) == _srcEid, "DVNAdapterBase: invalid srcEid");

        (address receiveLib, bytes memory packetHeader, bytes32 payloadHash) = DVNAdapterMessageCodec.decode(_payload);

        IReceiveUln(receiveLib).verify(packetHeader, payloadHash, MAX_CONFIRMATIONS);
    }

    function _withdrawFeeFromSendLib(address _sendLib, address _to) internal {
        uint256 fee = ISendLibBase(_sendLib).fees(address(this));
        if (fee > 0) {
            ISendLib(_sendLib).withdrawFee(_to, fee);
            emit Withdraw(_sendLib, _to, fee);
        }
    }

    function _assertBalanceAndWithdrawFee(address _sendLib, uint256 _messageFee) internal {
        uint256 balance = address(this).balance;
        if (balance < _messageFee) {
            // withdraw all fees from the sendLib if balance is insufficient
            _withdrawFeeFromSendLib(_sendLib, address(this));

            // check balance again
            balance = address(this).balance;
            // revert if balance is still insufficient, need to transfer more funds manually to the adapter
            if (balance < _messageFee) revert DVNAdapter_InsufficientBalance(balance, _messageFee);
        }
    }

    /// @dev to receive refund
    receive() external payable {}
}
