// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

// @dev Import the 'MessagingFee' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { OAppSenderUpgradeable, MessagingFee } from "./OAppSenderUpgradeable.sol";
// @dev Import the 'Origin' so it's exposed to OApp implementers
// solhint-disable-next-line no-unused-import
import { OAppReceiverUpgradeable, Origin } from "./OAppReceiverUpgradeable.sol";
import { OAppCoreUpgradeable } from "./OAppCoreUpgradeable.sol";

/**
 * @title OAppUpgradeable
 * @dev Abstract contract serving as the base for OAppUpgradeable implementation, combining OAppSenderUpgradeable and
 * OAppReceiverUpgradeable functionality.
 */
abstract contract OAppUpgradeable is OAppSenderUpgradeable, OAppReceiverUpgradeable {
    /**
     * @dev Initializer for the upgradeable OApp with the provided endpoint and owner.
     * @param _endpoint The address of the LOCAL LayerZero endpoint.
     * @param _owner The address of the owner of the OApp.
     */
    function initialize(address _endpoint, address _owner) public virtual initializer {
        _initializeOAppCore(_endpoint, _owner);
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
