// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { UlnBase, UlnConfig, SetDefaultUlnConfigParam } from "../contracts/uln/UlnBase.sol";
import { Constant } from "./util/Constant.sol";

contract UlnBaseTest is Test, UlnBase {
    address private constant DEFAULT_CONFIG = address(0x0);

    function test_setInvalidDefaultUlnConfig() public {
        vm.startPrank(owner());
        SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);

        // nil dvns count
        params[0] = SetDefaultUlnConfigParam(
            1,
            UlnConfig(1, Constant.NIL_DVN_COUNT, 0, 0, new address[](Constant.NIL_DVN_COUNT), new address[](0))
        );
        vm.expectRevert(LZ_ULN_InvalidRequiredDVNCount.selector);
        this.setDefaultUlnConfigs(params);

        // nil optional dvns count
        params[0] = SetDefaultUlnConfigParam(
            1,
            UlnConfig(1, 0, Constant.NIL_DVN_COUNT, 1, new address[](0), new address[](Constant.NIL_DVN_COUNT))
        );
        vm.expectRevert(LZ_ULN_InvalidOptionalDVNCount.selector);
        this.setDefaultUlnConfigs(params);

        // nil confirmations
        params[0] = SetDefaultUlnConfigParam(
            1,
            UlnConfig(Constant.NIL_CONFIRMATIONS, 1, 0, 0, new address[](1), new address[](0))
        );
        vm.expectRevert(LZ_ULN_InvalidConfirmations.selector);
        this.setDefaultUlnConfigs(params);

        // no dvn
        params[0] = SetDefaultUlnConfigParam(1, UlnConfig(1, 0, 0, 0, new address[](0), new address[](0)));
        vm.expectRevert(LZ_ULN_AtLeastOneDVN.selector);
        this.setDefaultUlnConfigs(params);
    }

    function test_setDefaultUlnConfig() public {
        vm.startPrank(owner());
        UlnConfig memory param = _newUlnConfig(10, 1, address(0x11), 1, address(0x22));
        SetDefaultUlnConfigParam[] memory params = new SetDefaultUlnConfigParam[](1);
        params[0] = SetDefaultUlnConfigParam(1, param);
        this.setDefaultUlnConfigs(params);

        // check default config
        UlnConfig memory defaultConfig = ulnConfigs[DEFAULT_CONFIG][1];
        assertEq(defaultConfig.confirmations, 10);
        assertEq(defaultConfig.requiredDVNCount, 1);
        assertEq(defaultConfig.optionalDVNCount, 1);
        assertEq(defaultConfig.optionalDVNThreshold, 1);
        assertEq(defaultConfig.requiredDVNs[0], address(0x11));
        assertEq(defaultConfig.optionalDVNs[0], address(0x22));
    }

    function test_setInvalidUlnConfig() public {
        // dvns.length > 0 but count == default(0)
        UlnConfig memory param = UlnConfig(1, 0, 0, 0, new address[](1), new address[](0));
        vm.expectRevert(LZ_ULN_InvalidRequiredDVNCount.selector);
        _setUlnConfig(1, address(2), param);

        // count != dvns.length
        param = UlnConfig(1, 1, 0, 0, new address[](2), new address[](0));
        vm.expectRevert(LZ_ULN_InvalidRequiredDVNCount.selector);
        _setUlnConfig(1, address(2), param);

        // dvns.length > MAX(127)
        param = UlnConfig(1, 128, 0, 0, new address[](128), new address[](0));
        vm.expectRevert(LZ_ULN_InvalidRequiredDVNCount.selector);
        _setUlnConfig(1, address(2), param);

        // duplicated dvns
        param = UlnConfig(1, 2, 0, 0, new address[](2), new address[](0));
        vm.expectRevert(LZ_ULN_Unsorted.selector);
        _setUlnConfig(1, address(2), param);

        // optionalDVNs.length > 0 but count == default(0)
        param = UlnConfig(1, 0, 0, 0, new address[](0), new address[](1));
        vm.expectRevert(LZ_ULN_InvalidOptionalDVNCount.selector);
        _setUlnConfig(1, address(2), param);

        // optionalDVNs.length > MAX(127)
        param = UlnConfig(1, 0, 128, 1, new address[](0), new address[](128));
        vm.expectRevert(LZ_ULN_InvalidOptionalDVNCount.selector);
        _setUlnConfig(1, address(2), param);

        // optionalDVNs.length < threshold
        param = UlnConfig(1, 0, 1, 2, new address[](0), new address[](1));
        vm.expectRevert(LZ_ULN_InvalidOptionalDVNThreshold.selector);
        _setUlnConfig(1, address(2), param);

        // optionalDVNs.length > 0 but threshold is 0
        param = UlnConfig(1, 0, 1, 0, new address[](0), new address[](1));
        vm.expectRevert(LZ_ULN_AtLeastOneDVN.selector);
        _setUlnConfig(1, address(2), param);
    }

    function test_setUlnConfig() public {
        UlnConfig memory param = _newUlnConfig(10, 1, address(0x11), 1, address(0x22));
        _setUlnConfig(1, address(2), param);

        // check custom config
        UlnConfig memory customConfig = ulnConfigs[address(2)][1];
        assertEq(customConfig.confirmations, 10);
        assertEq(customConfig.requiredDVNCount, 1);
        assertEq(customConfig.optionalDVNCount, 1);
        assertEq(customConfig.optionalDVNThreshold, 1);
        assertEq(customConfig.requiredDVNs[0], address(0x11));
        assertEq(customConfig.optionalDVNs[0], address(0x22));
    }

    function test_getUlnConfig() public {
        // no available dvn
        vm.expectRevert(LZ_ULN_AtLeastOneDVN.selector);
        getUlnConfig(address(1), 1);

        // set default config
        ulnConfigs[DEFAULT_CONFIG][1] = _newUlnConfig(10, 1, address(0x11), 1, address(0x22));

        // use default uln config
        UlnConfig memory config = getUlnConfig(address(1), 1);
        assertEq(config.confirmations, 10);
        assertEq(config.requiredDVNCount, 1);
        assertEq(config.optionalDVNCount, 1);
        assertEq(config.optionalDVNThreshold, 1);
        assertEq(config.requiredDVNs[0], address(0x11));
        assertEq(config.optionalDVNs[0], address(0x22));

        // set custom confirmations
        ulnConfigs[address(1)][1].confirmations = 2;
        config = getUlnConfig(address(1), 1);
        assertEq(config.confirmations, 2);

        // set custom confirmations to nil
        ulnConfigs[address(1)][1].confirmations = Constant.NIL_CONFIRMATIONS;
        config = getUlnConfig(address(1), 1);
        assertEq(config.confirmations, 0);

        // set custom required dvns
        ulnConfigs[address(1)][1].requiredDVNCount = 1;
        ulnConfigs[address(1)][1].requiredDVNs[0] = address(0x33);
        config = getUlnConfig(address(1), 1);
        assertEq(config.requiredDVNCount, 1);
        assertEq(config.requiredDVNs[0], address(0x33));

        // set custom dvns to nil
        ulnConfigs[address(1)][1].requiredDVNCount = Constant.NIL_DVN_COUNT;
        config = getUlnConfig(address(1), 1);
        assertEq(config.requiredDVNCount, 0);
        assertEq(config.requiredDVNs.length, 0);

        // set custom optional dvns
        ulnConfigs[address(1)][1].optionalDVNCount = 1;
        ulnConfigs[address(1)][1].optionalDVNs[0] = address(0x44);
        config = getUlnConfig(address(1), 1);
        assertEq(config.optionalDVNCount, 1);
        assertEq(config.optionalDVNs[0], address(0x44));

        // set custom optional dvns to nil
        ulnConfigs[address(1)][1].optionalDVNCount = Constant.NIL_DVN_COUNT;
        config = getUlnConfig(address(1), 1);
        assertEq(config.optionalDVNCount, 0);
        assertEq(config.optionalDVNs.length, 0);
        assertEq(config.optionalDVNThreshold, 0);
    }

    function _newSingletonAddressArray(address _addr) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](1);
        addrs[0] = _addr;
        return addrs;
    }

    function _newUlnConfig(
        uint64 _confirmations,
        uint8 _requiredCount,
        address _dvn,
        uint8 _optionalCount,
        address _optionalDVN
    ) internal pure returns (UlnConfig memory) {
        address[] memory dvns = _dvn == address(0) ? new address[](0) : _newSingletonAddressArray(_dvn);
        address[] memory optionalDVNs = _optionalDVN == address(0)
            ? new address[](0)
            : _newSingletonAddressArray(_optionalDVN);
        uint8 optionalDVNThreshold = _optionalDVN == address(0) ? 0 : 1;
        return UlnConfig(_confirmations, _requiredCount, _optionalCount, optionalDVNThreshold, dvns, optionalDVNs);
    }
}
