// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { ILayerZeroComposer } from "../../../protocol/interfaces/ILayerZeroComposer.sol";

/**
 * @title IOAppComposer
 * @dev This interface defines the OApp Composer, allowing developers to inherit only the OApp package without the protocol.
 */
// solhint-disable-next-line no-empty-blocks
interface IOAppComposer is ILayerZeroComposer {}
