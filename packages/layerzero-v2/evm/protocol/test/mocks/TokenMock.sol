// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenMock is ERC20 {
    constructor(uint256 amount) ERC20("token", "tkn") {
        _mint(msg.sender, amount);
    }
}
