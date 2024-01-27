// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Proxied } from "hardhat-deploy/solc_0.8/proxy/Proxied.sol";
import "./EndpointV2ViewUpgradeable.sol";

contract EndpointV2View is EndpointV2ViewUpgradeable, Proxied {
    function initialize(address _endpoint) external proxied initializer {
        __EndpointV2View_init(_endpoint);
    }
}
