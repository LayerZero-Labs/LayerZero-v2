// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.22;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IMessageLib, MessageLibType } from "./interfaces/IMessageLib.sol";
import { IMessageLibManager, SetConfigParam } from "./interfaces/IMessageLibManager.sol";
import { Errors } from "./libs/Errors.sol";
import { BlockedMessageLib } from "./messagelib/BlockedMessageLib.sol";

abstract contract MessageLibManager is Ownable, IMessageLibManager {
    address private constant DEFAULT_LIB = address(0);

    // the library that reverts both on send and quote
    // must be configured on construction and be immutable
    address public immutable blockedLibrary;

    // only registered libraries all valid libraries
    // the blockedLibrary will be registered on construction
    address[] internal registeredLibraries;
    mapping(address lib => bool) public isRegisteredLibrary;

    // both sendLibrary and receiveLibrary config can be lazily resolved
    mapping(address sender => mapping(uint32 dstEid => address lib)) internal sendLibrary;
    mapping(address receiver => mapping(uint32 srcEid => address lib)) internal receiveLibrary;
    mapping(address receiver => mapping(uint32 srcEid => Timeout)) public receiveLibraryTimeout;

    mapping(uint32 dstEid => address lib) public defaultSendLibrary;
    mapping(uint32 srcEid => address lib) public defaultReceiveLibrary;
    mapping(uint32 srcEid => Timeout) public defaultReceiveLibraryTimeout;

    constructor() {
        blockedLibrary = address(new BlockedMessageLib());
        registerLibrary(blockedLibrary);
    }

    modifier onlyRegistered(address _lib) {
        if (!isRegisteredLibrary[_lib]) revert Errors.OnlyRegisteredLib();
        _;
    }

    modifier isSendLib(address _lib) {
        if (_lib != DEFAULT_LIB) {
            if (IMessageLib(_lib).messageLibType() == MessageLibType.Receive) revert Errors.OnlySendLib();
        }
        _;
    }

    modifier isReceiveLib(address _lib) {
        if (_lib != DEFAULT_LIB) {
            if (IMessageLib(_lib).messageLibType() == MessageLibType.Send) revert Errors.OnlyReceiveLib();
        }
        _;
    }

    modifier onlyRegisteredOrDefault(address _lib) {
        if (!isRegisteredLibrary[_lib] && _lib != DEFAULT_LIB) revert Errors.OnlyRegisteredOrDefaultLib();
        _;
    }

    /// @dev check if the library supported the eid.
    modifier onlySupportedEid(address _lib, uint32 _eid) {
        /// @dev doesnt need to check for default lib, because when they are initially added they get passed through this modifier
        if (_lib != DEFAULT_LIB) {
            if (!IMessageLib(_lib).isSupportedEid(_eid)) revert Errors.UnsupportedEid();
        }
        _;
    }

    function getRegisteredLibraries() external view returns (address[] memory) {
        return registeredLibraries;
    }

    /// @notice The Send Library is the Oapp specified library that will be used to send the message to the destination
    /// endpoint. If the Oapp does not specify a Send Library, the default Send Library will be used.
    /// @dev If the Oapp does not have a selected Send Library, this function will resolve to the default library
    /// configured by LayerZero
    /// @return lib address of the Send Library
    /// @param _sender The address of the Oapp that is sending the message
    /// @param _dstEid The destination endpoint id
    function getSendLibrary(address _sender, uint32 _dstEid) public view returns (address lib) {
        lib = sendLibrary[_sender][_dstEid];
        if (lib == DEFAULT_LIB) {
            lib = defaultSendLibrary[_dstEid];
            if (lib == address(0x0)) revert Errors.DefaultSendLibUnavailable();
        }
    }

    function isDefaultSendLibrary(address _sender, uint32 _dstEid) public view returns (bool) {
        return sendLibrary[_sender][_dstEid] == DEFAULT_LIB;
    }

    /// @dev the receiveLibrary can be lazily resolved that if not set it will point to the default configured by LayerZero
    function getReceiveLibrary(address _receiver, uint32 _srcEid) public view returns (address lib, bool isDefault) {
        lib = receiveLibrary[_receiver][_srcEid];
        if (lib == DEFAULT_LIB) {
            lib = defaultReceiveLibrary[_srcEid];
            if (lib == address(0x0)) revert Errors.DefaultReceiveLibUnavailable();
            isDefault = true;
        }
    }

    /// @dev called when the endpoint checks if the msgLib attempting to verify the msg is the configured msgLib of the Oapp
    /// @dev this check provides the ability for Oapp to lock in a trusted msgLib
    /// @dev it will fist check if the msgLib is the currently configured one. then check if the msgLib is the one in grace period of msgLib versioning upgrade
    function isValidReceiveLibrary(
        address _receiver,
        uint32 _srcEid,
        address _actualReceiveLib
    ) public view returns (bool) {
        // early return true if the _actualReceiveLib is the currently configured one
        (address expectedReceiveLib, bool isDefault) = getReceiveLibrary(_receiver, _srcEid);
        if (_actualReceiveLib == expectedReceiveLib) {
            return true;
        }

        // check the timeout condition otherwise
        // if the Oapp is using defaultReceiveLibrary, use the default Timeout config
        // otherwise, use the Timeout configured by the Oapp
        Timeout memory timeout = isDefault
            ? defaultReceiveLibraryTimeout[_srcEid]
            : receiveLibraryTimeout[_receiver][_srcEid];

        // requires the _actualReceiveLib to be the same as the one in grace period and the grace period has not expired
        // block.number is uint256 so timeout.expiry must > 0, which implies a non-ZERO value
        if (timeout.lib == _actualReceiveLib && timeout.expiry > block.number) {
            // timeout lib set and has not expired
            return true;
        }

        // returns false by default
        return false;
    }

    //------- Owner interfaces
    /// @dev all libraries have to implement the erc165 interface to prevent wrong configurations
    /// @dev only owner
    function registerLibrary(address _lib) public onlyOwner {
        // must have the right interface
        if (!IERC165(_lib).supportsInterface(type(IMessageLib).interfaceId)) revert Errors.UnsupportedInterface();
        // must have not been registered
        if (isRegisteredLibrary[_lib]) revert Errors.AlreadyRegistered();

        // insert into both the map and the list
        isRegisteredLibrary[_lib] = true;
        registeredLibraries.push(_lib);

        emit LibraryRegistered(_lib);
    }

    /// @dev owner setting the defaultSendLibrary
    /// @dev can set to the blockedLibrary, which is a registered library
    /// @dev the msgLib must enable the support before they can be registered to the endpoint as the default
    /// @dev only owner
    function setDefaultSendLibrary(
        uint32 _eid,
        address _newLib
    ) external onlyOwner onlyRegistered(_newLib) isSendLib(_newLib) onlySupportedEid(_newLib, _eid) {
        address oldLib = defaultSendLibrary[_eid];
        // must provide a different value
        if (oldLib == _newLib) revert Errors.SameValue();
        defaultSendLibrary[_eid] = _newLib;
        emit DefaultSendLibrarySet(_eid, _newLib);
    }

    /// @dev owner setting the defaultSendLibrary
    /// @dev must be a registered library (including blockLibrary) with the eid support enabled
    /// @dev in version migration, it can add a grace period to the old library. if the grace period is 0, it will delete the timeout configuration.
    /// @dev only owner
    function setDefaultReceiveLibrary(
        uint32 _eid,
        address _newLib,
        uint256 _gracePeriod
    ) external onlyOwner onlyRegistered(_newLib) isReceiveLib(_newLib) onlySupportedEid(_newLib, _eid) {
        address oldLib = defaultReceiveLibrary[_eid];
        // must provide a different value
        if (oldLib == _newLib) revert Errors.SameValue();

        defaultReceiveLibrary[_eid] = _newLib;
        emit DefaultReceiveLibrarySet(_eid, oldLib, _newLib);

        if (_gracePeriod > 0) {
            // override the current default timeout to the [old_lib + new expiry]
            Timeout storage timeout = defaultReceiveLibraryTimeout[_eid];
            timeout.lib = oldLib;
            timeout.expiry = block.number + _gracePeriod;
            emit DefaultReceiveLibraryTimeoutSet(_eid, oldLib, timeout.expiry);
        } else {
            // otherwise, remove the old configuration.
            delete defaultReceiveLibraryTimeout[_eid];
            emit DefaultReceiveLibraryTimeoutSet(_eid, oldLib, 0);
        }
    }

    /// @dev owner setting the defaultSendLibrary
    /// @dev must be a registered library (including blockLibrary) with the eid support enabled
    /// @dev can used to (1) extend the current configuration (2) force remove the current configuration (3) change to a new configuration
    /// @param _expiry the block number when lib expires
    function setDefaultReceiveLibraryTimeout(
        uint32 _eid,
        address _lib,
        uint256 _expiry
    ) external onlyRegistered(_lib) isReceiveLib(_lib) onlySupportedEid(_lib, _eid) onlyOwner {
        if (_expiry == 0) {
            // force remove the current configuration
            delete defaultReceiveLibraryTimeout[_eid];
        } else {
            // override it with new configuration
            if (_expiry <= block.number) revert Errors.InvalidExpiry();
            Timeout storage timeout = defaultReceiveLibraryTimeout[_eid];
            timeout.lib = _lib;
            timeout.expiry = _expiry;
        }
        emit DefaultReceiveLibraryTimeoutSet(_eid, _lib, _expiry);
    }

    /// @dev returns true only if both the default send/receive libraries are set
    function isSupportedEid(uint32 _eid) external view returns (bool) {
        return defaultSendLibrary[_eid] != address(0) && defaultReceiveLibrary[_eid] != address(0);
    }

    //------- OApp interfaces
    /// @dev Oapp setting the sendLibrary
    /// @dev must be a registered library (including blockLibrary) with the eid support enabled
    /// @dev authenticated by the Oapp
    function setSendLibrary(
        address _oapp,
        uint32 _eid,
        address _newLib
    ) external onlyRegisteredOrDefault(_newLib) isSendLib(_newLib) onlySupportedEid(_newLib, _eid) {
        _assertAuthorized(_oapp);

        address oldLib = sendLibrary[_oapp][_eid];
        // must provide a different value
        if (oldLib == _newLib) revert Errors.SameValue();
        sendLibrary[_oapp][_eid] = _newLib;
        emit SendLibrarySet(_oapp, _eid, _newLib);
    }

    /// @dev Oapp setting the receiveLibrary
    /// @dev must be a registered library (including blockLibrary) with the eid support enabled
    /// @dev in version migration, it can add a grace period to the old library. if the grace period is 0, it will delete the timeout configuration.
    /// @dev authenticated by the Oapp
    /// @param _gracePeriod the number of blocks from now until oldLib expires
    function setReceiveLibrary(
        address _oapp,
        uint32 _eid,
        address _newLib,
        uint256 _gracePeriod
    ) external onlyRegisteredOrDefault(_newLib) isReceiveLib(_newLib) onlySupportedEid(_newLib, _eid) {
        _assertAuthorized(_oapp);

        address oldLib = receiveLibrary[_oapp][_eid];
        // must provide new values
        if (oldLib == _newLib) revert Errors.SameValue();
        receiveLibrary[_oapp][_eid] = _newLib;
        emit ReceiveLibrarySet(_oapp, _eid, oldLib, _newLib);

        if (_gracePeriod > 0) {
            // to simplify the logic, we only allow to set timeout if neither the new lib nor old lib is DEFAULT_LIB, which would should read the default timeout configurations
            // (1) if the Oapp wants to fall back to the DEFAULT, then set the newLib to DEFAULT with grace period == 0
            // (2) if the Oapp wants to change to a non DEFAULT from DEFAULT, then set the newLib to 'non-default' with _gracePeriod == 0, then use setReceiveLibraryTimeout() interface
            if (oldLib == DEFAULT_LIB || _newLib == DEFAULT_LIB) revert Errors.OnlyNonDefaultLib();

            // write to storage
            Timeout memory timeout = Timeout({ lib: oldLib, expiry: block.number + _gracePeriod });
            receiveLibraryTimeout[_oapp][_eid] = timeout;
            emit ReceiveLibraryTimeoutSet(_oapp, _eid, oldLib, timeout.expiry);
        } else {
            delete receiveLibraryTimeout[_oapp][_eid];
            emit ReceiveLibraryTimeoutSet(_oapp, _eid, oldLib, 0);
        }
    }

    /// @dev Oapp setting the defaultSendLibrary
    /// @dev must be a registered library (including blockLibrary) with the eid support enabled
    /// @dev can used to (1) extend the current configuration (2)  force remove the current configuration (3) change to a new configuration
    /// @param _expiry the block number when lib expires
    function setReceiveLibraryTimeout(
        address _oapp,
        uint32 _eid,
        address _lib,
        uint256 _expiry
    ) external onlyRegistered(_lib) isReceiveLib(_lib) onlySupportedEid(_lib, _eid) {
        _assertAuthorized(_oapp);

        (, bool isDefault) = getReceiveLibrary(_oapp, _eid);
        // if current library is DEFAULT, Oapp cant set the timeout
        if (isDefault) revert Errors.OnlyNonDefaultLib();

        if (_expiry == 0) {
            // force remove the current configuration
            delete receiveLibraryTimeout[_oapp][_eid];
        } else {
            // override it with new configuration
            if (_expiry <= block.number) revert Errors.InvalidExpiry();
            Timeout storage timeout = receiveLibraryTimeout[_oapp][_eid];
            timeout.lib = _lib;
            timeout.expiry = _expiry;
        }
        emit ReceiveLibraryTimeoutSet(_oapp, _eid, _lib, _expiry);
    }

    //------- library config setter/getter. all pass-through functions to the msgLib

    /// @dev authenticated by the _oapp
    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external onlyRegistered(_lib) {
        _assertAuthorized(_oapp);

        IMessageLib(_lib).setConfig(_oapp, _params);
    }

    /// @dev a view function to query the current configuration of the OApp
    function getConfig(
        address _oapp,
        address _lib,
        uint32 _eid,
        uint32 _configType
    ) external view onlyRegistered(_lib) returns (bytes memory config) {
        return IMessageLib(_lib).getConfig(_eid, _oapp, _configType);
    }

    function _assertAuthorized(address _oapp) internal virtual;
}
