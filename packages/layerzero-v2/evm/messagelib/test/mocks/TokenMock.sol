// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TokenMock is ERC20 {
    constructor() ERC20("Token", "TKN") {
        _mint(msg.sender, 1000000000 * 10 ** 18);
    }
}
