// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ReadLibBase, ReadLibConfig, SetDefaultReadLibConfigParam } from "../../contracts/uln/readlib/ReadLibBase.sol";
import { Constant } from "../util/Constant.sol";

contract ReadLibBaseTest is Test, ReadLibBase {
    address private constant EXECUTOR = address(0x1);
    uint32 private constant DST_EID = 1;

    function test_setInvalidDefaultReadLibConfig() public {
        vm.startPrank(owner());
        SetDefaultReadLibConfigParam[] memory params = new SetDefaultReadLibConfigParam[](1);

        // nil dvns count
        params[0] = SetDefaultReadLibConfigParam(
            DST_EID,
            ReadLibConfig(
                EXECUTOR,
                Constant.NIL_DVN_COUNT,
                0,
                0,
                new address[](Constant.NIL_DVN_COUNT),
                new address[](0)
            )
        );
        vm.expectRevert(LZ_RL_InvalidRequiredDVNCount.selector);
        this.setDefaultReadLibConfigs(params);

        // nil optional dvns count
        params[0] = SetDefaultReadLibConfigParam(
            DST_EID,
            ReadLibConfig(
                EXECUTOR,
                0,
                Constant.NIL_DVN_COUNT,
                1,
                new address[](0),
                new address[](Constant.NIL_DVN_COUNT)
            )
        );
        vm.expectRevert(LZ_RL_InvalidOptionalDVNCount.selector);
        this.setDefaultReadLibConfigs(params);

        // no executor
        params[0] = SetDefaultReadLibConfigParam(
            DST_EID,
            ReadLibConfig(address(0), 1, 0, 0, new address[](1), new address[](0))
        );
        vm.expectRevert(LZ_RL_InvalidExecutor.selector);
        this.setDefaultReadLibConfigs(params);

        // no dvn
        params[0] = SetDefaultReadLibConfigParam(
            DST_EID,
            ReadLibConfig(EXECUTOR, 0, 0, 0, new address[](0), new address[](0))
        );
        vm.expectRevert(LZ_RL_AtLeastOneDVN.selector);
        this.setDefaultReadLibConfigs(params);
    }

    function test_setDefaultReadLibConfig() public {
        vm.startPrank(owner());
        ReadLibConfig memory param = _newReadLibConfig(EXECUTOR, 1, address(0x11), 1, address(0x22));
        SetDefaultReadLibConfigParam[] memory params = new SetDefaultReadLibConfigParam[](1);
        params[0] = SetDefaultReadLibConfigParam(DST_EID, param);
        this.setDefaultReadLibConfigs(params);

        // check default config
        ReadLibConfig memory defaultConfig = readLibConfigs[DEFAULT_CONFIG][1];
        assertEq(defaultConfig.executor, EXECUTOR);
        assertEq(defaultConfig.requiredDVNCount, 1);
        assertEq(defaultConfig.optionalDVNCount, 1);
        assertEq(defaultConfig.optionalDVNThreshold, 1);
        assertEq(defaultConfig.requiredDVNs[0], address(0x11));
        assertEq(defaultConfig.optionalDVNs[0], address(0x22));
    }

    function test_setInvalidReadLibConfig() public {
        // dvns.length > 0 but count == default(0)
        ReadLibConfig memory param = ReadLibConfig(EXECUTOR, 0, 0, 0, new address[](1), new address[](0));
        vm.expectRevert(LZ_RL_InvalidRequiredDVNCount.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // count != dvns.length
        param = ReadLibConfig(EXECUTOR, 1, 0, 0, new address[](2), new address[](0));
        vm.expectRevert(LZ_RL_InvalidRequiredDVNCount.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // dvns.length > MAX(127)
        param = ReadLibConfig(EXECUTOR, 128, 0, 0, new address[](128), new address[](0));
        vm.expectRevert(LZ_RL_InvalidRequiredDVNCount.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // duplicated dvns
        param = ReadLibConfig(EXECUTOR, 2, 0, 0, new address[](2), new address[](0));
        vm.expectRevert(LZ_RL_Unsorted.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // optionalDVNs.length > 0 but count == default(0)
        param = ReadLibConfig(EXECUTOR, 0, 0, 0, new address[](0), new address[](1));
        vm.expectRevert(LZ_RL_InvalidOptionalDVNCount.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // optionalDVNs.length > MAX(127)
        param = ReadLibConfig(EXECUTOR, 0, 128, 1, new address[](0), new address[](128));
        vm.expectRevert(LZ_RL_InvalidOptionalDVNCount.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // optionalDVNs.length < threshold
        param = ReadLibConfig(EXECUTOR, 0, 1, 2, new address[](0), new address[](1));
        vm.expectRevert(LZ_RL_InvalidOptionalDVNThreshold.selector);
        _setReadLibConfig(DST_EID, address(2), param);

        // optionalDVNs.length > 0 but threshold is 0
        param = ReadLibConfig(EXECUTOR, 0, 1, 0, new address[](0), new address[](1));
        vm.expectRevert(LZ_RL_AtLeastOneDVN.selector);
        _setReadLibConfig(DST_EID, address(2), param);
    }

    function test_setReadLibConfig() public {
        ReadLibConfig memory param = _newReadLibConfig(EXECUTOR, 1, address(0x11), 1, address(0x22));
        _setReadLibConfig(DST_EID, address(2), param);

        // check custom config
        ReadLibConfig memory customConfig = readLibConfigs[address(2)][1];
        assertEq(customConfig.executor, EXECUTOR);
        assertEq(customConfig.requiredDVNCount, 1);
        assertEq(customConfig.optionalDVNCount, 1);
        assertEq(customConfig.optionalDVNThreshold, 1);
        assertEq(customConfig.requiredDVNs[0], address(0x11));
        assertEq(customConfig.optionalDVNs[0], address(0x22));
    }

    function test_getReadLibConfig() public {
        // no available dvn
        vm.expectRevert(LZ_RL_AtLeastOneDVN.selector);
        getReadLibConfig(address(1), 1);

        // set default config
        readLibConfigs[DEFAULT_CONFIG][1] = _newReadLibConfig(EXECUTOR, 1, address(0x11), 1, address(0x22));

        // use default uln config
        ReadLibConfig memory config = getReadLibConfig(address(1), 1);
        assertEq(config.executor, EXECUTOR);
        assertEq(config.requiredDVNCount, 1);
        assertEq(config.optionalDVNCount, 1);
        assertEq(config.optionalDVNThreshold, 1);
        assertEq(config.requiredDVNs[0], address(0x11));
        assertEq(config.optionalDVNs[0], address(0x22));

        // set custom executor
        readLibConfigs[address(1)][1].executor = address(0xabcd);
        config = getReadLibConfig(address(1), 1);
        assertEq(config.executor, address(0xabcd));

        // set custom executor to nil
        readLibConfigs[address(1)][1].executor = address(0);
        config = getReadLibConfig(address(1), 1);
        assertEq(config.executor, EXECUTOR);

        // set custom required dvns
        readLibConfigs[address(1)][1].requiredDVNCount = 1;
        readLibConfigs[address(1)][1].requiredDVNs[0] = address(0x33);
        config = getReadLibConfig(address(1), 1);
        assertEq(config.requiredDVNCount, 1);
        assertEq(config.requiredDVNs[0], address(0x33));

        // set custom dvns to nil
        readLibConfigs[address(1)][1].requiredDVNCount = Constant.NIL_DVN_COUNT;
        config = getReadLibConfig(address(1), 1);
        assertEq(config.requiredDVNCount, 0);
        assertEq(config.requiredDVNs.length, 0);

        // set custom optional dvns
        readLibConfigs[address(1)][1].optionalDVNCount = 1;
        readLibConfigs[address(1)][1].optionalDVNs[0] = address(0x44);
        config = getReadLibConfig(address(1), 1);
        assertEq(config.optionalDVNCount, 1);
        assertEq(config.optionalDVNs[0], address(0x44));

        // set custom optional dvns to nil
        readLibConfigs[address(1)][1].optionalDVNCount = Constant.NIL_DVN_COUNT;
        config = getReadLibConfig(address(1), 1);
        assertEq(config.optionalDVNCount, 0);
        assertEq(config.optionalDVNs.length, 0);
        assertEq(config.optionalDVNThreshold, 0);
    }

    function _newSingletonAddressArray(address _addr) internal pure returns (address[] memory) {
        address[] memory addrs = new address[](1);
        addrs[0] = _addr;
        return addrs;
    }

    function _newReadLibConfig(
        address _executor,
        uint8 _requiredCount,
        address _dvn,
        uint8 _optionalCount,
        address _optionalDVN
    ) internal pure returns (ReadLibConfig memory) {
        address[] memory dvns = _dvn == address(0) ? new address[](0) : _newSingletonAddressArray(_dvn);
        address[] memory optionalDVNs = _optionalDVN == address(0)
            ? new address[](0)
            : _newSingletonAddressArray(_optionalDVN);
        uint8 optionalDVNThreshold = _optionalDVN == address(0) ? 0 : 1;
        return ReadLibConfig(_executor, _requiredCount, _optionalCount, optionalDVNThreshold, dvns, optionalDVNs);
    }
}
