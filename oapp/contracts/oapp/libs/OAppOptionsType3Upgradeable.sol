// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IOAppOptionsType3, EnforcedOptionParam} from "../interfaces/IOAppOptionsType3.sol";

/**
 * @title OAppOptionsType3
 * @dev Abstract contract implementing the IOAppOptionsType3 interface with type 3 options.
 */
abstract contract OAppOptionsType3Upgradeable is IOAppOptionsType3, OwnableUpgradeable {
    struct OAppOptionsType3Storage {
        // @dev The "msgType" should be defined in the child contract.
        mapping(uint32 => mapping(uint16 => bytes)) enforcedOptions;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzerov2.storage.oappoptionstype3")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OAppOptionsType3StorageLocation =
        0x8d2bda5d9f6ffb5796910376005392955773acee5548d0fcdb10e7c264ea0000;

    uint16 internal constant OPTION_TYPE_3 = 3;

    function _getOAppOptionsType3Storage() internal pure returns (OAppOptionsType3Storage storage $) {
        assembly {
            $.slot := OAppOptionsType3StorageLocation
        }
    }

    /**
     * @dev Ownable is not initialized here on purpose. It should be initialized in the child contract to
     * accommodate the different version of Ownable.
     */
    function __OAppOptionsType3_init() internal onlyInitializing {}

    function __OAppOptionsType3_init_unchained() internal onlyInitializing {}

    function enforcedOptions(uint32 _eid, uint16 _msgType) public view returns (bytes memory) {
        OAppOptionsType3Storage storage $ = _getOAppOptionsType3Storage();
        return $.enforcedOptions[_eid][_msgType];
    }

    /**
     * @dev Sets the enforced options for specific endpoint and message type combinations.
     * @param _enforcedOptions An array of EnforcedOptionParam structures specifying enforced options.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Provides a way for the OApp to enforce things like paying for PreCrime, AND/OR minimum dst lzReceive gas amounts etc.
     * @dev These enforced options can vary as the potential options/execution on the remote may differ as per the msgType.
     * eg. Amount of lzReceive() gas necessary to deliver a lzCompose() message adds overhead you dont want to pay
     * if you are only making a standard LayerZero message ie. lzReceive() WITHOUT sendCompose().
     */
    function setEnforcedOptions(EnforcedOptionParam[] calldata _enforcedOptions) public virtual onlyOwner {
        OAppOptionsType3Storage storage $ = _getOAppOptionsType3Storage();
        for (uint256 i = 0; i < _enforcedOptions.length; i++) {
            // @dev Enforced options are only available for optionType 3, as type 1 and 2 dont support combining.
            _assertOptionsType3(_enforcedOptions[i].options);
            $.enforcedOptions[_enforcedOptions[i].eid][_enforcedOptions[i].msgType] = _enforcedOptions[i].options;
        }

        emit EnforcedOptionSet(_enforcedOptions);
    }

    /**
     * @notice Combines options for a given endpoint and message type.
     * @param _eid The endpoint ID.
     * @param _msgType The OAPP message type.
     * @param _extraOptions Additional options passed by the caller.
     * @return options The combination of caller specified options AND enforced options.
     *
     * @dev If there is an enforced lzReceive option:
     * - {gasLimit: 200k, msg.value: 1 ether} AND a caller supplies a lzReceive option: {gasLimit: 100k, msg.value: 0.5 ether}
     * - The resulting options will be {gasLimit: 300k, msg.value: 1.5 ether} when the message is executed on the remote lzReceive() function.
     * @dev This presence of duplicated options is handled off-chain in the verifier/executor.
     */
    function combineOptions(uint32 _eid, uint16 _msgType, bytes calldata _extraOptions)
        public
        view
        virtual
        returns (bytes memory)
    {
        OAppOptionsType3Storage storage $ = _getOAppOptionsType3Storage();
        bytes memory enforced = $.enforcedOptions[_eid][_msgType];

        // No enforced options, pass whatever the caller supplied, even if it's empty or legacy type 1/2 options.
        if (enforced.length == 0) return _extraOptions;

        // No caller options, return enforced
        if (_extraOptions.length == 0) return enforced;

        // @dev If caller provided _extraOptions, must be type 3 as its the ONLY type that can be combined.
        if (_extraOptions.length >= 2) {
            _assertOptionsType3(_extraOptions);
            // @dev Remove the first 2 bytes containing the type from the _extraOptions and combine with enforced.
            return bytes.concat(enforced, _extraOptions[2:]);
        }

        // No valid set of options was found.
        revert InvalidOptions(_extraOptions);
    }

    /**
     * @dev Internal function to assert that options are of type 3.
     * @param _options The options to be checked.
     */
    function _assertOptionsType3(bytes calldata _options) internal pure virtual {
        uint16 optionsType = uint16(bytes2(_options[0:2]));
        if (optionsType != OPTION_TYPE_3) revert InvalidOptions(_options);
    }
}
