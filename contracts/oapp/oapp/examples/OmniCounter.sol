// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// @dev Oz5 implementation
// import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OmniCounterAbstract, MsgCodec } from "./OmniCounterAbstract.sol";

contract OmniCounter is OmniCounterAbstract {
    // @dev Oz4 implementation
    constructor(address _endpoint, address _delegate) OmniCounterAbstract(_endpoint, _delegate) {}

    // @dev Oz5 implementation
    //    constructor(address _endpoint, address _delegate) OmniCounterAbstract(_endpoint, _delegate) Ownable(_delegate) {}
}
