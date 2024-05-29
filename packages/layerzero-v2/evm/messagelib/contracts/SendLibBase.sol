// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";

import { ILayerZeroExecutor } from "./interfaces/ILayerZeroExecutor.sol";
import { ILayerZeroTreasury } from "./interfaces/ILayerZeroTreasury.sol";
import { SafeCall } from "./libs/SafeCall.sol";
import { MessageLibBase } from "./MessageLibBase.sol";

struct WorkerOptions {
    uint8 workerId;
    bytes options;
}

struct SetDefaultExecutorConfigParam {
    uint32 eid;
    ExecutorConfig config;
}

struct ExecutorConfig {
    uint32 maxMessageSize;
    address executor;
}

/// @dev base contract for both SendLibBaseE1 and SendLibBaseE2
abstract contract SendLibBase is MessageLibBase, Ownable {
    using SafeCall for address;

    address private constant DEFAULT_CONFIG = address(0);
    uint16 internal constant TREASURY_MAX_COPY = 32;

    uint256 internal immutable treasuryGasLimit;
    uint256 internal treasuryNativeFeeCap;

    // config
    address public treasury;
    mapping(address oapp => mapping(uint32 eid => ExecutorConfig)) public executorConfigs;

    // accumulated fees for workers and treasury
    mapping(address worker => uint256) public fees;

    event ExecutorFeePaid(address executor, uint256 fee);
    event TreasurySet(address treasury);
    event DefaultExecutorConfigsSet(SetDefaultExecutorConfigParam[] params);
    event ExecutorConfigSet(address oapp, uint32 eid, ExecutorConfig config);
    event TreasuryNativeFeeCapSet(uint256 newTreasuryNativeFeeCap);

    error LZ_MessageLib_InvalidMessageSize(uint256 actual, uint256 max);
    error LZ_MessageLib_InvalidAmount(uint256 requested, uint256 available);
    error LZ_MessageLib_TransferFailed();
    error LZ_MessageLib_InvalidExecutor();
    error LZ_MessageLib_ZeroMessageSize();

    constructor(
        address _endpoint,
        uint32 _localEid,
        uint256 _treasuryGasLimit,
        uint256 _treasuryNativeFeeCap
    ) MessageLibBase(_endpoint, _localEid) {
        treasuryGasLimit = _treasuryGasLimit;
        treasuryNativeFeeCap = _treasuryNativeFeeCap;
    }

    function setDefaultExecutorConfigs(SetDefaultExecutorConfigParam[] calldata _params) external onlyOwner {
        for (uint256 i = 0; i < _params.length; ++i) {
            SetDefaultExecutorConfigParam calldata param = _params[i];

            if (param.config.executor == address(0x0)) revert LZ_MessageLib_InvalidExecutor();
            if (param.config.maxMessageSize == 0) revert LZ_MessageLib_ZeroMessageSize();

            executorConfigs[DEFAULT_CONFIG][param.eid] = param.config;
        }
        emit DefaultExecutorConfigsSet(_params);
    }

    /// @dev the new value can not be greater than the old value, i.e. down only
    function setTreasuryNativeFeeCap(uint256 _newTreasuryNativeFeeCap) external onlyOwner {
        // assert the new value is no greater than the old value
        if (_newTreasuryNativeFeeCap > treasuryNativeFeeCap)
            revert LZ_MessageLib_InvalidAmount(_newTreasuryNativeFeeCap, treasuryNativeFeeCap);
        treasuryNativeFeeCap = _newTreasuryNativeFeeCap;
        emit TreasuryNativeFeeCapSet(_newTreasuryNativeFeeCap);
    }

    // ============================ View ===================================
    // @dev get the executor config and if not set, return the default config
    function getExecutorConfig(address _oapp, uint32 _remoteEid) public view returns (ExecutorConfig memory rtnConfig) {
        ExecutorConfig storage defaultConfig = executorConfigs[DEFAULT_CONFIG][_remoteEid];
        ExecutorConfig storage customConfig = executorConfigs[_oapp][_remoteEid];

        uint32 maxMessageSize = customConfig.maxMessageSize;
        rtnConfig.maxMessageSize = maxMessageSize != 0 ? maxMessageSize : defaultConfig.maxMessageSize;

        address executor = customConfig.executor;
        rtnConfig.executor = executor != address(0x0) ? executor : defaultConfig.executor;
    }

    // ======================= Internal =======================
    function _assertMessageSize(uint256 _actual, uint256 _max) internal pure {
        if (_actual > _max) revert LZ_MessageLib_InvalidMessageSize(_actual, _max);
    }

    function _payExecutor(
        address _executor,
        uint32 _dstEid,
        address _sender,
        uint256 _msgSize,
        bytes memory _executorOptions
    ) internal returns (uint256 executorFee) {
        executorFee = ILayerZeroExecutor(_executor).assignJob(_dstEid, _sender, _msgSize, _executorOptions);
        if (executorFee > 0) {
            fees[_executor] += executorFee;
        }
        emit ExecutorFeePaid(_executor, executorFee);
    }

    function _payTreasury(
        address _sender,
        uint32 _dstEid,
        uint256 _totalNativeFee,
        bool _payInLzToken
    ) internal returns (uint256 treasuryNativeFee, uint256 lzTokenFee) {
        if (treasury != address(0x0)) {
            bytes memory callData = abi.encodeCall(
                ILayerZeroTreasury.payFee,
                (_sender, _dstEid, _totalNativeFee, _payInLzToken)
            );
            (bool success, bytes memory result) = treasury.safeCall(treasuryGasLimit, 0, TREASURY_MAX_COPY, callData);

            (treasuryNativeFee, lzTokenFee) = _parseTreasuryResult(_totalNativeFee, _payInLzToken, success, result);
            // fee should be in lzTokenFee if payInLzToken, otherwise in native
            if (treasuryNativeFee > 0) {
                fees[treasury] += treasuryNativeFee;
            }
        }
    }

    /// @dev the abstract process for quote() is:
    /// 0/ split out the executor options and options of other workers
    /// 1/ quote workers
    /// 2/ quote executor
    /// 3/ quote treasury
    /// @return nativeFee, lzTokenFee
    function _quote(
        address _sender,
        uint32 _dstEid,
        uint256 _msgSize,
        bool _payInLzToken,
        bytes calldata _options
    ) internal view returns (uint256, uint256) {
        (bytes memory executorOptions, WorkerOptions[] memory validationOptions) = _splitOptions(_options);

        // quote the verifier used in the library. for ULN, it is a list of DVNs
        uint256 nativeFee = _quoteVerifier(_sender, _dstEid, validationOptions);

        // quote executor
        ExecutorConfig memory config = getExecutorConfig(_sender, _dstEid);
        // assert msg size
        _assertMessageSize(_msgSize, config.maxMessageSize);

        nativeFee += ILayerZeroExecutor(config.executor).getFee(_dstEid, _sender, _msgSize, executorOptions);

        // quote treasury
        (uint256 treasuryNativeFee, uint256 lzTokenFee) = _quoteTreasury(_sender, _dstEid, nativeFee, _payInLzToken);
        nativeFee += treasuryNativeFee;

        return (nativeFee, lzTokenFee);
    }

    /// @dev this interface should be DoS-free if the user is paying with native. properties
    /// 1/ treasury can return an overly high lzToken fee
    /// 2/ if treasury returns an overly high native fee, it will be capped by maxNativeFee,
    ///    which can be reasoned with the configurations
    /// 3/ the owner can not configure the treasury in a way that force this function to revert
    function _quoteTreasury(
        address _sender,
        uint32 _dstEid,
        uint256 _totalNativeFee,
        bool _payInLzToken
    ) internal view returns (uint256 nativeFee, uint256 lzTokenFee) {
        // treasury must be set, and it has to be a contract
        if (treasury != address(0x0)) {
            bytes memory callData = abi.encodeCall(
                ILayerZeroTreasury.getFee,
                (_sender, _dstEid, _totalNativeFee, _payInLzToken)
            );
            (bool success, bytes memory result) = treasury.safeStaticCall(
                treasuryGasLimit,
                TREASURY_MAX_COPY,
                callData
            );

            return _parseTreasuryResult(_totalNativeFee, _payInLzToken, success, result);
        }
    }

    function _parseTreasuryResult(
        uint256 _totalNativeFee,
        bool _payInLzToken,
        bool _success,
        bytes memory _result
    ) internal view returns (uint256 nativeFee, uint256 lzTokenFee) {
        // failure, charges nothing
        if (!_success || _result.length < TREASURY_MAX_COPY) return (0, 0);

        // parse the result
        uint256 treasureFeeQuote = abi.decode(_result, (uint256));
        if (_payInLzToken) {
            lzTokenFee = treasureFeeQuote;
        } else {
            // pay in native
            // we must prevent high-treasuryFee Dos attack
            // nativeFee = min(treasureFeeQuote, maxNativeFee)
            // opportunistically raise the maxNativeFee to be the same as _totalNativeFee
            // can't use the _totalNativeFee alone because the oapp can use custom workers to force the fee to 0.
            // maxNativeFee = max (_totalNativeFee, treasuryNativeFeeCap)
            uint256 maxNativeFee = _totalNativeFee > treasuryNativeFeeCap ? _totalNativeFee : treasuryNativeFeeCap;

            // min (treasureFeeQuote, nativeFeeCap)
            nativeFee = treasureFeeQuote > maxNativeFee ? maxNativeFee : treasureFeeQuote;
        }
    }

    /// @dev authenticated by msg.sender only
    function _debitFee(uint256 _amount) internal {
        uint256 fee = fees[msg.sender];
        if (_amount > fee) revert LZ_MessageLib_InvalidAmount(_amount, fee);
        unchecked {
            fees[msg.sender] = fee - _amount;
        }
    }

    function _setTreasury(address _treasury) internal {
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    function _setExecutorConfig(uint32 _remoteEid, address _oapp, ExecutorConfig memory _config) internal {
        executorConfigs[_oapp][_remoteEid] = _config;
        emit ExecutorConfigSet(_oapp, _remoteEid, _config);
    }

    // ======================= Virtual =======================
    /// @dev these two functions will be overridden with specific logics of the library function
    function _quoteVerifier(
        address _oapp,
        uint32 _eid,
        WorkerOptions[] memory _options
    ) internal view virtual returns (uint256 nativeFee);

    /// @dev this function will split the options into executorOptions and validationOptions
    function _splitOptions(
        bytes calldata _options
    ) internal view virtual returns (bytes memory executorOptions, WorkerOptions[] memory validationOptions);
}
