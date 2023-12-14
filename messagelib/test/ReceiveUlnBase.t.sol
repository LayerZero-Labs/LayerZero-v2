// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UlnConfig } from "../contracts/uln/UlnBase.sol";
import { ReceiveUlnBase, Verification } from "../contracts/uln/ReceiveUlnBase.sol";

contract ReceiveUlnBaseTest is Test, ReceiveUlnBase {
    bytes32 internal headerHash = bytes32(uint256(0x1234));
    bytes32 internal payloadHash = bytes32(uint256(0x5678));
    address internal dvn1 = address(0x11);
    address internal dvn2 = address(0x22);
    address internal optionalDVN1 = address(0x33);
    address internal optionalDVN2 = address(0x44);
    address internal oapp = address(0x55);

    function test_verified(uint64 _confirmations) public {
        vm.assume(_confirmations > 0 && _confirmations < type(uint64).max);

        // mock the hashLookup state
        hashLookup[headerHash][payloadHash][dvn1] = Verification(true, _confirmations);
        assertEq(_verified(dvn1, headerHash, payloadHash, _confirmations - 1), true);

        hashLookup[headerHash][payloadHash][dvn1] = Verification(true, _confirmations);
        assertEq(_verified(dvn1, headerHash, payloadHash, _confirmations), true);

        hashLookup[headerHash][payloadHash][dvn1] = Verification(true, _confirmations);
        assertEq(_verified(dvn1, headerHash, payloadHash, _confirmations + 1), false);
    }

    function test_verifyConditionMet_onlyMustHaveDVNs() public {
        // 2 must-have dvns, 0 optional dvns
        uint64 confirmations = 10;
        UlnConfig memory config = UlnConfig(confirmations, 2, 0, 0, _newAddressArray(dvn1, dvn2), new address[](0));

        // only dvn1 submitted the hash, so the condition is not met
        hashLookup[headerHash][payloadHash][dvn1] = Verification(true, confirmations);
        assertFalse(_checkVerifiable(config, headerHash, payloadHash));

        // both dvns submitted the hash, so the condition is met
        hashLookup[headerHash][payloadHash][dvn2] = Verification(true, confirmations);
        assertTrue(_checkVerifiable(config, headerHash, payloadHash));
    }

    function test_verifyConditionMet_onlyOptionalDVNs() public {
        // 0 must-have dvns, 2 optional dvns, threshold is 1
        uint64 confirmations = 10;
        UlnConfig memory config = UlnConfig(
            confirmations,
            0,
            2,
            1,
            new address[](0),
            _newAddressArray(optionalDVN1, optionalDVN2)
        );

        // no optional dvn submitted the hash, so the condition is not met
        assertFalse(_checkVerifiable(config, headerHash, payloadHash));

        config = UlnConfig(confirmations, 0, 2, 1, new address[](0), _newAddressArray(optionalDVN1, optionalDVN2));

        // optionalDVN1 submitted the hash, so the condition is met
        hashLookup[headerHash][payloadHash][optionalDVN1] = Verification(true, confirmations);
        assertTrue(_checkVerifiable(config, headerHash, payloadHash));

        config = UlnConfig(confirmations, 0, 2, 1, new address[](0), _newAddressArray(optionalDVN1, optionalDVN2));

        // both optional dvns submitted the hash, so the condition is still met
        hashLookup[headerHash][payloadHash][optionalDVN1] = Verification(true, confirmations);
        hashLookup[headerHash][payloadHash][optionalDVN2] = Verification(true, confirmations);
        assertTrue(_checkVerifiable(config, headerHash, payloadHash));
    }

    function test_verifyConditionMet_mustHaveAndOptionalDVNs() public {
        // 2 must-have dvns, 2 optional dvns, threshold is 1
        uint64 confirmations = 10;
        UlnConfig memory config = UlnConfig(
            confirmations,
            2,
            2,
            1,
            _newAddressArray(dvn1, dvn2),
            _newAddressArray(optionalDVN1, optionalDVN2)
        );

        // only two dvns submitted the hash, so the condition is not met
        hashLookup[headerHash][payloadHash][dvn1] = Verification(true, confirmations);
        hashLookup[headerHash][payloadHash][dvn2] = Verification(true, confirmations);
        assertFalse(_checkVerifiable(config, headerHash, payloadHash));

        // optionalDVN1 submitted the hash, so the condition is met
        hashLookup[headerHash][payloadHash][optionalDVN1] = Verification(true, confirmations);
        assertTrue(_checkVerifiable(config, headerHash, payloadHash));
    }

    function _newAddressArray(address _addr1, address _addr2) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](2);
        addrs[0] = _addr1;
        addrs[1] = _addr2;
        return addrs;
    }
}
