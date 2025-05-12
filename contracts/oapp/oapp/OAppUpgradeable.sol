// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// @dev Import the 'MessagingFee' and 'MessagingReceipt' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { OAppSenderUpgradeable, MessagingFee, MessagingReceipt } from "./OAppSenderUpgradeable.sol";
// @dev Import the 'Origin' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { OAppReceiverUpgradeable, Origin } from "./OAppReceiverUpgradeable.sol";
import { OAppCoreUpgradeable } from "./OAppCoreUpgradeable.sol";

/**
 * @title OApp
 * @dev Abstract contract serving as the base for OApp implementation, combining OAppSender and OAppReceiver functionality.
 */
abstract contract OAppUpgradeable is OAppSenderUpgradeable, OAppReceiverUpgradeable {
    /**
     * @dev Constructor to initialize the OApp with the provided endpoint and owner.
     * @param _endpoint The address of the LOCAL LayerZero endpoint.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    function __OApp_init(address _endpoint, address _delegate) internal onlyInitializing {
        __OAppCore_init(_endpoint, _delegate);
    }

    /**
     * @notice Retrieves the OApp version information.
     * @return senderVersion The version of the OAppSender.sol implementation.
     * @return receiverVersion The version of the OAppReceiver.sol implementation.
     */
    function oAppVersion()
        public
        pure
        virtual
        override(OAppSenderUpgradeable, OAppReceiverUpgradeable)
        returns (uint64 senderVersion, uint64 receiverVersion)
    {
        return (SENDER_VERSION, RECEIVER_VERSION);
    }
}
