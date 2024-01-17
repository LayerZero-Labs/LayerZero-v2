// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ILayerZeroEndpoint } from "@layerzerolabs/lz-evm-v1-0.7/contracts/interfaces/ILayerZeroEndpoint.sol";

import { ITreasuryFeeHandler } from "./interfaces/ITreasuryFeeHandler.sol";

contract TreasuryFeeHandler is ITreasuryFeeHandler {
    using SafeERC20 for IERC20;

    ILayerZeroEndpoint public immutable endpoint;

    error OnlySendLibrary();
    error OnlyOnSending();
    error InvalidAmount(uint256 required, uint256 supplied);

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
    }

    // @dev payer of layerzero token must be sender
    function payFee(
        address _lzToken,
        address _sender,
        uint256 _required,
        uint256 _supplied,
        address _treasury
    ) external {
        // only sender's message library can call this function and only when sending a payload
        if (endpoint.getSendLibraryAddress(_sender) != msg.sender) revert OnlySendLibrary();
        if (!endpoint.isSendingPayload()) revert OnlyOnSending();
        if (_required > _supplied) revert InvalidAmount(_required, _supplied);

        // send lz token fee to the treasury directly
        IERC20(_lzToken).safeTransferFrom(_sender, _treasury, _required);
    }
}
