// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// the formal properties are documented in the setter functions
struct UlnConfig {
    uint64 confirmations;
    // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
    uint8 requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
    uint8 optionalDVNThreshold; // (0, optionalDVNCount]
    address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
    address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
}

struct SetDefaultUlnConfigParam {
    uint32 eid;
    UlnConfig config;
}

/// @dev includes the utility functions for checking ULN states and logics
abstract contract UlnBase is Ownable {
    address private constant DEFAULT_CONFIG = address(0);
    // reserved values for
    uint8 internal constant DEFAULT = 0;
    uint8 internal constant NIL_DVN_COUNT = type(uint8).max;
    uint64 internal constant NIL_CONFIRMATIONS = type(uint64).max;
    // 127 to prevent total number of DVNs (127 * 2) exceeding uint8.max (255)
    // by limiting the total size, it would help constraint the design of DVNOptions
    uint8 private constant MAX_COUNT = (type(uint8).max - 1) / 2;

    mapping(address oapp => mapping(uint32 eid => UlnConfig)) internal ulnConfigs;

    error Unsorted();
    error InvalidRequiredDVNCount();
    error InvalidOptionalDVNCount();
    error AtLeastOneDVN();
    error InvalidOptionalDVNThreshold();
    error InvalidConfirmations();
    error UnsupportedEid(uint32 eid);

    event DefaultUlnConfigsSet(SetDefaultUlnConfigParam[] params);
    event UlnConfigSet(address oapp, uint32 eid, UlnConfig config);

    // ============================ OnlyOwner ===================================

    /// @dev about the DEFAULT ULN config
    /// 1) its values are all LITERAL (e.g. 0 is 0). whereas in the oapp ULN config, 0 (default value) points to the default ULN config
    ///     this design enables the oapp to point to DEFAULT config without explicitly setting the config
    /// 2) its configuration is more restrictive than the oapp ULN config that
    ///     a) it must not use NIL value, where NIL is used only by oapps to indicate the LITERAL 0
    ///     b) it must have at least one DVN
    function setDefaultUlnConfigs(SetDefaultUlnConfigParam[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; ++i) {
            SetDefaultUlnConfigParam calldata param = _params[i];

            // 2.a must not use NIL
            if (param.config.requiredDVNCount == NIL_DVN_COUNT) revert InvalidRequiredDVNCount();
            if (param.config.optionalDVNCount == NIL_DVN_COUNT) revert InvalidOptionalDVNCount();
            if (param.config.confirmations == NIL_CONFIRMATIONS) revert InvalidConfirmations();

            // 2.b must have at least one dvn
            _assertAtLeastOneDVN(param.config);

            _setConfig(DEFAULT_CONFIG, param.eid, param.config);
        }
        emit DefaultUlnConfigsSet(_params);
    }

    // ============================ View ===================================
    // @dev assuming most oapps use default, we get default as memory and custom as storage to save gas
    function getUlnConfig(address _oapp, uint32 _remoteEid) public view returns (UlnConfig memory rtnConfig) {
        UlnConfig storage defaultConfig = ulnConfigs[DEFAULT_CONFIG][_remoteEid];
        UlnConfig storage customConfig = ulnConfigs[_oapp][_remoteEid];

        // if confirmations is 0, use default
        uint64 confirmations = customConfig.confirmations;
        if (confirmations == DEFAULT) {
            rtnConfig.confirmations = defaultConfig.confirmations;
        } else if (confirmations != NIL_CONFIRMATIONS) {
            // if confirmations is uint64.max, no block confirmations required
            rtnConfig.confirmations = confirmations;
        } // else do nothing, rtnConfig.confirmation is 0

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

    /// @dev Get the uln config without the default config for the given remoteEid.
    function getAppUlnConfig(address _oapp, uint32 _remoteEid) external view returns (UlnConfig memory) {
        return ulnConfigs[_oapp][_remoteEid];
    }

    // ============================ Internal ===================================
    function _setUlnConfig(uint32 _remoteEid, address _oapp, UlnConfig memory _param) internal {
        _setConfig(_oapp, _remoteEid, _param);

        // get ULN config again as a catch all to ensure the config is valid
        getUlnConfig(_oapp, _remoteEid);
        emit UlnConfigSet(_oapp, _remoteEid, _param);
    }

    /// @dev a supported Eid must have a valid default uln config, which has at least one dvn
    function _isSupportedEid(uint32 _remoteEid) internal view returns (bool) {
        UlnConfig storage defaultConfig = ulnConfigs[DEFAULT_CONFIG][_remoteEid];
        return defaultConfig.requiredDVNCount > 0 || defaultConfig.optionalDVNThreshold > 0;
    }

    function _assertSupportedEid(uint32 _remoteEid) internal view {
        if (!_isSupportedEid(_remoteEid)) revert UnsupportedEid(_remoteEid);
    }

    // ============================ Private ===================================

    function _assertAtLeastOneDVN(UlnConfig memory _config) private pure {
        if (_config.requiredDVNCount == 0 && _config.optionalDVNThreshold == 0) revert AtLeastOneDVN();
    }

    /// @dev this private function is used in both setDefaultUlnConfigs and setUlnConfig
    function _setConfig(address _oapp, uint32 _eid, UlnConfig memory _param) private {
        // @dev required dvns
        // if dvnCount == NONE, dvns list must be empty
        // if dvnCount == DEFAULT, dvn list must be empty
        // otherwise, dvnList.length == dvnCount and assert the list is valid
        if (_param.requiredDVNCount == NIL_DVN_COUNT || _param.requiredDVNCount == DEFAULT) {
            if (_param.requiredDVNs.length != 0) revert InvalidRequiredDVNCount();
        } else {
            if (_param.requiredDVNs.length != _param.requiredDVNCount || _param.requiredDVNCount > MAX_COUNT)
                revert InvalidRequiredDVNCount();
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
            if (_param.optionalDVNs.length != 0) revert InvalidOptionalDVNCount();
            if (_param.optionalDVNThreshold != 0) revert InvalidOptionalDVNThreshold();
        } else {
            if (_param.optionalDVNs.length != _param.optionalDVNCount || _param.optionalDVNCount > MAX_COUNT)
                revert InvalidOptionalDVNCount();
            if (_param.optionalDVNThreshold == 0 || _param.optionalDVNThreshold > _param.optionalDVNCount)
                revert InvalidOptionalDVNThreshold();
            _assertNoDuplicates(_param.optionalDVNs);
        }
        // don't assert valid count here, as it needs to be validated along side default config

        ulnConfigs[_oapp][_eid] = _param;
    }

    function _assertNoDuplicates(address[] memory _dvns) private pure {
        address lastDVN = address(0);
        for (uint256 i = 0; i < _dvns.length; i++) {
            address dvn = _dvns[i];
            if (dvn <= lastDVN) revert Unsorted(); // to ensure no duplicates
            lastDVN = dvn;
        }
    }
}
