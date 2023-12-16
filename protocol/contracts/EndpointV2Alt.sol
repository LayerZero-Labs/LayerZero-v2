// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EndpointV2 } from "./EndpointV2.sol";
import { Errors } from "./libs/Errors.sol";

/// @notice this is the endpoint contract for layerzero v2 deployed on chains using ERC20 as native tokens
contract EndpointV2Alt is EndpointV2 {
    /// @dev the altFeeToken is used for fees when the native token has no value
    /// @dev it is immutable for gas saving. only 1 endpoint for such chains
    address internal immutable nativeErc20;

    constructor(uint32 _eid, address _owner, address _altToken) EndpointV2(_eid, _owner) {
        nativeErc20 = _altToken;
    }

    /// @dev handling native token payments on endpoint
    /// @dev internal function
    /// @param _required the amount required
    /// @param _supplied the amount supplied
    /// @param _receiver the receiver of the native token
    /// @param _refundAddress the address to refund the excess to
    function _payNative(
        uint256 _required,
        uint256 _supplied,
        address _receiver,
        address _refundAddress
    ) internal override {
        if (msg.value > 0) revert Errors.OnlyAltToken();
        _payToken(nativeErc20, _required, _supplied, _receiver, _refundAddress);
    }

    /// @dev return the balance of the native token
    function _suppliedNative() internal view override returns (uint256) {
        return IERC20(nativeErc20).balanceOf(address(this));
    }

    /// @dev check if lzToken is set to the same address
    function setLzToken(address _lzToken) public override onlyOwner {
        if (_lzToken == nativeErc20) revert Errors.InvalidArgument();
        super.setLzToken(_lzToken);
    }

    function nativeToken() external view override returns (address) {
        return nativeErc20;
    }
}
