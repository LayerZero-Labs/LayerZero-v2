// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library Transfer {
    using SafeERC20 for IERC20;

    address internal constant ADDRESS_ZERO = address(0);

    error TransferNativeFailed(address _to, uint256 _value);
    error ToAddressIsZero();

    function native(address _to, uint256 _value) internal {
        if (_to == ADDRESS_ZERO) revert ToAddressIsZero();
        (bool success, ) = _to.call{ value: _value }("");
        if (!success) revert TransferNativeFailed(_to, _value);
    }

    function token(address _token, address _to, uint256 _value) internal {
        if (_to == ADDRESS_ZERO) revert ToAddressIsZero();
        IERC20(_token).safeTransfer(_to, _value);
    }

    function nativeOrToken(address _token, address _to, uint256 _value) internal {
        if (_token == ADDRESS_ZERO) {
            native(_to, _value);
        } else {
            token(_token, _to, _value);
        }
    }
}
