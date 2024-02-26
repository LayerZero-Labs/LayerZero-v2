// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EndpointV2 } from "./EndpointV2.sol";
import { Errors } from "./libs/Errors.sol";

/// @notice This is the endpoint contract for LayerZero v2 deployed on chains using ERC20 as native tokens.
contract EndpointV2Alt is EndpointV2 {
    error LZ_OnlyAltToken();

    /// @dev The altFeeToken is used for fees when the native token has no value.
    /// @dev It is immutable for gas saving. Only 1 endpoint for such chains.
    address internal immutable nativeErc20;

    constructor(uint32 _eid, address _owner, address _altToken) EndpointV2(_eid, _owner) {
        nativeErc20 = _altToken;
    }

    /// @dev Handles native token payments on the endpoint.
    /// @dev Internal function.
    /// @param _required The amount required.
    /// @param _supplied The amount supplied.
    /// @param _receiver The receiver of the native token.
    /// @param _refundAddress The address to refund the excess to.
    function _payNative(
        uint256 _required,
        uint256 _supplied,
        address _receiver,
        address _refundAddress
    ) internal override {
        if (msg.value > 0) revert LZ_OnlyAltToken();
        _payToken(nativeErc20, _required, _supplied, _receiver, _refundAddress);
    }

    /// @dev Returns the balance of the native token.
    function _suppliedNative() internal view override returns (uint256) {
        return IERC20(nativeErc20).balanceOf(address(this));
    }

    /// @dev Checks if lzToken is set to the same address.
    function setLzToken(address _lzToken) public override onlyOwner {
        if (_lzToken == nativeErc20) revert Errors.LZ_InvalidArgument();
        super.setLzToken(_lzToken);
    }

    /// @dev Returns the address of the native token.
    function nativeToken() external view override returns (address) {
        return nativeErc20;
    }
}
