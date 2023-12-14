// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { MessageLibType } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { ISendLib, Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

contract SendLibMock is ISendLib {
    mapping(address worker => uint256) public fees;

    error InvalidAmount(uint256 requested, uint256 available);
    error NotImplemented();

    receive() external payable {}

    function setFee(address _worker) external payable {
        fees[_worker] = msg.value;
    }

    function _debitFee(uint256 _amount) internal {
        uint256 fee = fees[msg.sender];
        if (_amount > fee) revert InvalidAmount(_amount, fee);
        unchecked {
            fees[msg.sender] = fee - _amount;
        }
    }

    function withdrawFee(address _to, uint256 _amount) external {
        _debitFee(_amount);
        address nativeToken = address(0);
        Transfer.nativeOrToken(nativeToken, _to, _amount);
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (3, 0, 2);
    }

    function send(Packet calldata, bytes calldata, bool) external pure returns (MessagingFee memory, bytes memory) {
        revert NotImplemented();
    }

    function quote(Packet calldata, bytes calldata, bool) external pure returns (MessagingFee memory) {
        revert NotImplemented();
    }

    function setTreasury(address) external pure {
        revert NotImplemented();
    }

    function withdrawLzTokenFee(address, address, uint256) external pure {
        revert NotImplemented();
    }

    function setConfig(address, SetConfigParam[] calldata) external pure {
        revert NotImplemented();
    }

    function getConfig(uint32, address, uint32) external pure returns (bytes memory) {
        revert NotImplemented();
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        revert NotImplemented();
    }

    function messageLibType() external pure returns (MessageLibType) {
        revert NotImplemented();
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        revert NotImplemented();
    }
}
