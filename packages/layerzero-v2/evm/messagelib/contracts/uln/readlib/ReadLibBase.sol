// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

struct ReadLibConfig {
    address executor;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}

struct SetDefaultReadLibConfigParam {
    uint32 eid;
    ReadLibConfig config;
}

/// @dev includes the utility functions for checking ReadLib states and logics
abstract contract ReadLibBase is Ownable {
    address internal constant DEFAULT_CONFIG = address(0);
    // reserved values for
    uint8 internal constant DEFAULT = 0;
    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
    // 127 to prevent total number of DVNs (127 * 2) exceeding uint8.max (255)
    // by limiting the total size, it would help constraint the design of DVNOptions
    uint8 private constant MAX_COUNT = (type(uint8).max - 1) / 2;

    mapping(address oapp => mapping(uint32 eid => ReadLibConfig config)) internal readLibConfigs;

    error LZ_RL_Unsorted();
    error LZ_RL_InvalidRequiredDVNCount();
    error LZ_RL_InvalidOptionalDVNCount();
    error LZ_RL_AtLeastOneDVN();
    error LZ_RL_InvalidOptionalDVNThreshold();
    error LZ_RL_UnsupportedEid(uint32 eid);
    error LZ_RL_InvalidExecutor();

    event DefaultReadLibConfigsSet(SetDefaultReadLibConfigParam[] params);
    event ReadLibConfigSet(address oapp, uint32 eid, ReadLibConfig config);

    // ============================ OnlyOwner ===================================

    /// @dev about the DEFAULT ReadLib config
    /// 1) its values are all LITERAL (e.g. 0 is 0). whereas in the oapp ReadLib config, 0 (default value) points to the default ReadLib config
    ///     this design enables the oapp to point to DEFAULT config without explicitly setting the config
    /// 2) its configuration is more restrictive than the oapp ReadLib config that
    ///     a) it must not use NIL value, where NIL is used only by oapps to indicate the LITERAL 0
    ///     b) it must have at least one DVN and executor
    function setDefaultReadLibConfigs(SetDefaultReadLibConfigParam[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; ++i) {
            SetDefaultReadLibConfigParam calldata param = _params[i];

            // 2.a must not use NIL
            if (param.config.requiredDVNCount == NIL_DVN_COUNT) revert LZ_RL_InvalidRequiredDVNCount();
            if (param.config.optionalDVNCount == NIL_DVN_COUNT) revert LZ_RL_InvalidOptionalDVNCount();

            // 2.b must have at least one dvn and executor
            _assertAtLeastOneDVN(param.config);
            if (param.config.executor == address(0x0)) revert LZ_RL_InvalidExecutor();

            _setConfig(DEFAULT_CONFIG, param.eid, param.config);
        }
        emit DefaultReadLibConfigsSet(_params);
    }

    // ============================ View ===================================
    // @dev assuming most oapps use default, we get default as memory and custom as storage to save gas
    function getReadLibConfig(address _oapp, uint32 _remoteEid) public view returns (ReadLibConfig memory rtnConfig) {
        ReadLibConfig storage defaultConfig = readLibConfigs[DEFAULT_CONFIG][_remoteEid];
        ReadLibConfig storage customConfig = readLibConfigs[_oapp][_remoteEid];

        address executor = customConfig.executor;
        rtnConfig.executor = executor != address(0x0) ? executor : defaultConfig.executor;

        if (customConfig.requiredDVNCount == DEFAULT) {
            if (defaultConfig.requiredDVNCount > 0) {
                // copy only if count > 0. save gas
                rtnConfig.requiredDVNs = defaultConfig.requiredDVNs;
                rtnConfig.requiredDVNCount = defaultConfig.requiredDVNCount;
            } // else, do nothing
        } else {
            if (customConfig.requiredDVNCount != NIL_DVN_COUNT) {
                rtnConfig.requiredDVNs = customConfig.requiredDVNs;
                rtnConfig.requiredDVNCount = customConfig.requiredDVNCount;
            } // else, do nothing
        }

        if (customConfig.optionalDVNCount == DEFAULT) {
            if (defaultConfig.optionalDVNCount > 0) {
                // copy only if count > 0. save gas
                rtnConfig.optionalDVNs = defaultConfig.optionalDVNs;
                rtnConfig.optionalDVNCount = defaultConfig.optionalDVNCount;
                rtnConfig.optionalDVNThreshold = defaultConfig.optionalDVNThreshold;
            }
        } else {
            if (customConfig.optionalDVNCount != NIL_DVN_COUNT) {
                rtnConfig.optionalDVNs = customConfig.optionalDVNs;
                rtnConfig.optionalDVNCount = customConfig.optionalDVNCount;
                rtnConfig.optionalDVNThreshold = customConfig.optionalDVNThreshold;
            }
        }

        // the final value must have at least one dvn
        // it is possible that some default config result into 0 dvns
        _assertAtLeastOneDVN(rtnConfig);
    }

    /// @dev Get the readLib config without the default config for the given remoteEid.
    function getAppReadLibConfig(address _oapp, uint32 _remoteEid) external view returns (ReadLibConfig memory) {
        return readLibConfigs[_oapp][_remoteEid];
    }

    // ============================ Internal ===================================
    function _setReadLibConfig(uint32 _remoteEid, address _oapp, ReadLibConfig memory _param) internal {
        _setConfig(_oapp, _remoteEid, _param);

        // get ReadLib config again as a catch all to ensure the config is valid
        getReadLibConfig(_oapp, _remoteEid);
        emit ReadLibConfigSet(_oapp, _remoteEid, _param);
    }

    /// @dev a supported Eid must have a valid default readLib config, which has at least one dvn
    function _isSupportedEid(uint32 _remoteEid) internal view returns (bool) {
        ReadLibConfig storage defaultConfig = readLibConfigs[DEFAULT_CONFIG][_remoteEid];
        return defaultConfig.requiredDVNCount > 0 || defaultConfig.optionalDVNThreshold > 0;
    }

    function _assertSupportedEid(uint32 _remoteEid) internal view {
        if (!_isSupportedEid(_remoteEid)) revert LZ_RL_UnsupportedEid(_remoteEid);
    }

    // ============================ Private ===================================

    function _assertAtLeastOneDVN(ReadLibConfig memory _config) private pure {
        if (_config.requiredDVNCount == 0 && _config.optionalDVNThreshold == 0) revert LZ_RL_AtLeastOneDVN();
    }

    /// @dev this private function is used in both setDefaultReadLibConfigs and setReadLibConfig
    function _setConfig(address _oapp, uint32 _eid, ReadLibConfig memory _param) private {
        // @dev required dvns
        // if dvnCount == NONE, dvns list must be empty
        // if dvnCount == DEFAULT, dvn list must be empty
        // otherwise, dvnList.length == dvnCount and assert the list is valid
        if (_param.requiredDVNCount == NIL_DVN_COUNT || _param.requiredDVNCount == DEFAULT) {
            if (_param.requiredDVNs.length != 0) revert LZ_RL_InvalidRequiredDVNCount();
        } else {
            if (_param.requiredDVNs.length != _param.requiredDVNCount || _param.requiredDVNCount > MAX_COUNT)
                revert LZ_RL_InvalidRequiredDVNCount();
            _assertNoDuplicates(_param.requiredDVNs);
        }

        // @dev optional dvns
        // if optionalDVNCount == NONE, optionalDVNs list must be empty and threshold must be 0
        // if optionalDVNCount == DEFAULT, optionalDVNs list must be empty and threshold must be 0
        // otherwise, optionalDVNs.length == optionalDVNCount, threshold > 0 && threshold <= optionalDVNCount and assert the list is valid

        // example use case: an oapp uses the DEFAULT 'required' but
        //     a) use a custom 1/1 dvn (practically a required dvn), or
        //     b) use a custom 2/3 dvn
        if (_param.optionalDVNCount == NIL_DVN_COUNT || _param.optionalDVNCount == DEFAULT) {
            if (_param.optionalDVNs.length != 0) revert LZ_RL_InvalidOptionalDVNCount();
            if (_param.optionalDVNThreshold != 0) revert LZ_RL_InvalidOptionalDVNThreshold();
        } else {
            if (_param.optionalDVNs.length != _param.optionalDVNCount || _param.optionalDVNCount > MAX_COUNT)
                revert LZ_RL_InvalidOptionalDVNCount();
            if (_param.optionalDVNThreshold == 0 || _param.optionalDVNThreshold > _param.optionalDVNCount)
                revert LZ_RL_InvalidOptionalDVNThreshold();
            _assertNoDuplicates(_param.optionalDVNs);
        }
        // don't assert valid count here, as it needs to be validated along side default config

        readLibConfigs[_oapp][_eid] = _param;
    }

    function _assertNoDuplicates(address[] memory _dvns) private pure {
        address lastDVN = address(0);
        for (uint256 i = 0; i < _dvns.length; i++) {
            address dvn = _dvns[i];
            if (dvn <= lastDVN) revert LZ_RL_Unsorted(); // to ensure no duplicates
            lastDVN = dvn;
        }
    }
}
