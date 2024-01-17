// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract AddressSizeConfig is Ownable {
    // EndpointV1 is using bytes as address. this map is for address length assertion
    mapping(uint32 dstEid => uint256 size) public addressSizes;

    event AddressSizeSet(uint16 eid, uint256 size);

    error InvalidAddressSize();
    error AddressSizeAlreadySet();

    function setAddressSize(uint16 _eid, uint256 _size) external onlyOwner {
        if (_size > 32) revert InvalidAddressSize();
        if (addressSizes[_eid] != 0) revert AddressSizeAlreadySet();
        addressSizes[_eid] = _size;
        emit AddressSizeSet(_eid, _size);
    }
}
