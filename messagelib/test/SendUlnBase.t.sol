// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UlnConfig } from "../contracts/uln/UlnBase.sol";
import { SendUlnBase } from "../contracts/uln/SendUlnBase.sol";
import { ILayerZeroDVN } from "../contracts/uln/interfaces/ILayerZeroDVN.sol";

import { OptionsUtil } from "./util/OptionsUtil.sol";

contract SendUlnBaseTest is Test, SendUlnBase {
    using OptionsUtil for bytes;

    bytes32 internal headerHash = bytes32(uint256(0x1234));
    bytes32 internal payloadHash = bytes32(uint256(0x5678));
    address internal dvn1 = address(0x11);
    address internal dvn2 = address(0x22);
    address internal optionalDVN1 = address(0x33);
    address internal optionalDVN2 = address(0x44);
    address internal oapp = address(0x55);

    mapping(address => uint256) internal fees;

    function test_getFees() public {
        // 2 must-have dvns, 2 optional dvns
        uint64 confirmations = 10;
        UlnConfig memory config = UlnConfig(
            confirmations,
            2,
            2,
            1,
            _newAddressArray(dvn1, dvn2),
            _newAddressArray(optionalDVN1, optionalDVN2)
        );

        // mock the dvn fees, when the dvn has options, its fee is 200, otherwise 100
        // only dvn2 and optionalDVN1 have options
        bytes memory options = bytes("options");
        uint256 fee = 100;
        vm.mockCall(
            dvn1,
            abi.encodeWithSelector(ILayerZeroDVN.getFee.selector, 1, confirmations, address(this), ""),
            abi.encode(fee)
        );
        vm.mockCall(
            dvn2,
            abi.encodeWithSelector(ILayerZeroDVN.getFee.selector, 1, confirmations, address(this), options),
            abi.encode(fee * 2)
        );
        vm.mockCall(
            optionalDVN1,
            abi.encodeWithSelector(ILayerZeroDVN.getFee.selector, 1, confirmations, address(this), options),
            abi.encode(fee * 2)
        );
        vm.mockCall(
            optionalDVN2,
            abi.encodeWithSelector(ILayerZeroDVN.getFee.selector, 1, confirmations, address(this), ""),
            abi.encode(fee)
        );

        // mock the options array and dvn ids array
        bytes[] memory optionsArray = new bytes[](2);
        optionsArray[0] = options;
        optionsArray[1] = options;
        uint8[] memory dvnIds = new uint8[](2);
        dvnIds[0] = 1;
        dvnIds[1] = 2;

        uint256 totalFee = _getFees(config, 1, address(this), optionsArray, dvnIds);
        assertEq(totalFee, fee * 6); // 100 + 200 + 200 + 100
    }

    function test_assignJobToDVNs() public {
        // 2 must-have dvns, 2 optional dvns
        uint64 confirmations = 10;
        UlnConfig memory config = UlnConfig(
            confirmations,
            2,
            2,
            1,
            _newAddressArray(dvn1, dvn2),
            _newAddressArray(optionalDVN1, optionalDVN2)
        );

        ILayerZeroDVN.AssignJobParam memory param = ILayerZeroDVN.AssignJobParam(
            1,
            bytes("packetHeader"),
            payloadHash,
            confirmations,
            address(this)
        );

        // mock the dvn fees, dvn1's fee is 100, dvn2's fee is 200,
        // optionalDVN1's fee is 300, optionalDVN2's fee is 400
        // only dvn2 and optionalDVN1 have options
        vm.mockCall(dvn1, abi.encodeWithSelector(ILayerZeroDVN.assignJob.selector), abi.encode(100));
        vm.mockCall(
            dvn2,
            abi.encodeWithSelector(ILayerZeroDVN.assignJob.selector, param, OptionsUtil.addDVNPreCrimeOption("", 1)),
            abi.encode(200)
        );
        vm.mockCall(
            optionalDVN1,
            abi.encodeWithSelector(ILayerZeroDVN.assignJob.selector, param, OptionsUtil.addDVNPreCrimeOption("", 2)),
            abi.encode(300)
        );
        vm.mockCall(optionalDVN2, abi.encodeWithSelector(ILayerZeroDVN.assignJob.selector), abi.encode(400));

        bytes memory options = "";
        options = options.addDVNPreCrimeOption(1); // dvn2
        options = options.addDVNPreCrimeOption(2); // optionalDVN1
        (uint256 totalFee, uint256[] memory dvnFees) = _assignJobs(fees, config, param, options);
        assertEq(totalFee, 1000); // 100 + 200 + 300 + 400
        assertEq(dvnFees[0], 100);
        assertEq(dvnFees[1], 200);
        assertEq(dvnFees[2], 300);
        assertEq(dvnFees[3], 400);
        assertEq(fees[dvn1], 100);
        assertEq(fees[dvn2], 200);
        assertEq(fees[optionalDVN1], 300);
        assertEq(fees[optionalDVN2], 400);
    }

    function _newAddressArray(address _addr1, address _addr2) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](2);
        addrs[0] = _addr1;
        addrs[1] = _addr2;
        return addrs;
    }
}
