// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IMessageLib, MessageLibType } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { MessageLibBase } from "./MessageLibBase.sol";

/// @dev receive-side message library base contract on endpoint v2.
/// it does not have the complication as the one of endpoint v1, such as nonce, executor whitelist, etc.
abstract contract ReceiveLibBaseE2 is MessageLibBase, ERC165, IMessageLib {
    using PacketV1Codec for bytes;

    constructor(address _endpoint) MessageLibBase(_endpoint, ILayerZeroEndpointV2(_endpoint).eid()) {}

    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return _interfaceId == type(IMessageLib).interfaceId || super.supportsInterface(_interfaceId);
    }

    function messageLibType() external pure virtual override returns (MessageLibType) {
        return MessageLibType.Receive;
    }
}
