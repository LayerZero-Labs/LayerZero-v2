// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

/// @dev simply a container of endpoint address and local eid
abstract contract MessageLibBase {
    address internal immutable endpoint;
    uint32 internal immutable localEid;

    error LZ_MessageLib_OnlyEndpoint();

    modifier onlyEndpoint() {
        if (endpoint != msg.sender) revert LZ_MessageLib_OnlyEndpoint();
        _;
    }

    constructor(address _endpoint, uint32 _localEid) {
        endpoint = _endpoint;
        localEid = _localEid;
    }
}
