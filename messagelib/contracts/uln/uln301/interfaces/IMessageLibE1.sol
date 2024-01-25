// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import { ILayerZeroMessagingLibrary } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroMessagingLibrary.sol";

/// extends ILayerZeroMessagingLibrary instead of ILayerZeroMessagingLibraryV2 for reducing the contract size
interface IMessageLibE1 is ILayerZeroMessagingLibrary {
    error LZ_MessageLib_InvalidPath();
    error LZ_MessageLib_InvalidSender();
    error LZ_MessageLib_InsufficientMsgValue();
    error LZ_MessageLib_LzTokenPaymentAddressMustBeSender();

    function setLzToken(address _lzToken) external;

    function setTreasury(address _treasury) external;

    function withdrawFee(address _to, uint256 _amount) external;

    // message libs of same major version are compatible
    function version() external view returns (uint64 major, uint8 minor, uint8 endpointVersion);
}
