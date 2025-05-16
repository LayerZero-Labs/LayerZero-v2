// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ONFT721Upgradeable } from "../oapp/onft721/ONFT721Upgradeable.sol";

contract MyONFT721 is Initializable, ONFT721Upgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) public initializer {
        __ONFT721_init(_name, _symbol, _lzEndpoint, _delegate);
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
