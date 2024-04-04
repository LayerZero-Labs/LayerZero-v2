// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {OAppPreCrimeSimulatorUpgradeable} from "../../contracts/precrime/OAppPreCrimeSimulatorUpgradeable.sol";

contract PreCrimeV2SimulatorUpgradeableMock is OAppPreCrimeSimulatorUpgradeable {
    uint256 public count;

    error InvalidEid();

    function initialize(address _delegate) external initializer {
        __Ownable_init();
        _transferOwnership(_delegate);
    }

    function _lzReceiveSimulate(
        Origin calldata _origin,
        bytes32, /*_guid*/
        bytes calldata, /*_message*/
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) internal override {
        if (_origin.srcEid == 0) revert InvalidEid();
        count++;
    }

    function isPeer(uint32 _eid, bytes32 _peer) public pure override returns (bool) {
        return bytes32(uint256(_eid)) == _peer;
    }
}
