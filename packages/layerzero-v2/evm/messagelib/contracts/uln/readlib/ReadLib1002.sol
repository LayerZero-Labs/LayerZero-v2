// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { ILayerZeroEndpointV2, MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { IMessageLib, MessageLibType, SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { ISendLib, Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { Transfer } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/Transfer.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { ILayerZeroReadExecutor } from "../../interfaces/ILayerZeroReadExecutor.sol";
import { ILayerZeroReadDVN } from "../interfaces/ILayerZeroReadDVN.sol";
import { ILayerZeroTreasury } from "../../interfaces/ILayerZeroTreasury.sol";

import { UlnOptions } from "../libs/UlnOptions.sol";
import { DVNOptions } from "../libs/DVNOptions.sol";
import { SafeCall } from "../../libs/SafeCall.sol";

import { MessageLibBase } from "../../MessageLibBase.sol";
import { ReadLibBase, ReadLibConfig } from "./ReadLibBase.sol";

contract ReadLib1002 is ISendLib, ERC165, ReadLibBase, MessageLibBase {
    using PacketV1Codec for bytes;
    using SafeCall for address;

    uint32 internal constant CONFIG_TYPE_READ_LID_CONFIG = 1;

    uint16 internal constant TREASURY_MAX_COPY = 32;

    uint256 internal immutable treasuryGasLimit;

    mapping(address oapp => mapping(uint32 eid => mapping(uint64 nonce => bytes32 cmdHash))) public cmdHashLookup;
    mapping(bytes32 headerHash => mapping(bytes32 cmdHash => mapping(address dvn => bytes32 payloadHash)))
        public hashLookup;

    // accumulated fees for workers and treasury
    mapping(address worker => uint256 fee) public fees;
    uint256 internal treasuryNativeFeeCap;
    address internal treasury;

    event PayloadVerified(address dvn, bytes header, bytes32 cmdHash, bytes32 payloadHash);
    event ExecutorFeePaid(address executor, uint256 fee);
    event DVNFeePaid(address[] requiredDVNs, address[] optionalDVNs, uint256[] fees);
    event NativeFeeWithdrawn(address worker, address receiver, uint256 amount);
    event LzTokenFeeWithdrawn(address lzToken, address receiver, uint256 amount);
    event TreasurySet(address treasury);
    event TreasuryNativeFeeCapSet(uint256 newTreasuryNativeFeeCap);

    error LZ_RL_InvalidReceiver();
    error LZ_RL_InvalidPacketHeader();
    error LZ_RL_InvalidCmdHash();
    error LZ_RL_InvalidPacketVersion();
    error LZ_RL_InvalidEid();
    error LZ_RL_Verifying();
    error LZ_RL_InvalidConfigType(uint32 configType);
    error LZ_RL_InvalidAmount(uint256 requested, uint256 available);
    error LZ_RL_NotTreasury();
    error LZ_RL_CannotWithdrawAltToken();

    constructor(
        address _endpoint,
        uint256 _treasuryGasLimit,
        uint256 _treasuryGasForFeeCap
    ) MessageLibBase(_endpoint, ILayerZeroEndpointV2(_endpoint).eid()) {
        treasuryGasLimit = _treasuryGasLimit;
        treasuryNativeFeeCap = _treasuryGasForFeeCap;
    }

    function supportsInterface(bytes4 _interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return
            _interfaceId == type(IMessageLib).interfaceId ||
            _interfaceId == type(ISendLib).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    // ============================ OnlyOwner ===================================

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @dev the new value can not be greater than the old value, i.e. down only
    function setTreasuryNativeFeeCap(uint256 _newTreasuryNativeFeeCap) external onlyOwner {
        // assert the new value is no greater than the old value
        if (_newTreasuryNativeFeeCap > treasuryNativeFeeCap)
            revert LZ_RL_InvalidAmount(_newTreasuryNativeFeeCap, treasuryNativeFeeCap);
        treasuryNativeFeeCap = _newTreasuryNativeFeeCap;
        emit TreasuryNativeFeeCapSet(_newTreasuryNativeFeeCap);
    }

    // ============================ OnlyEndpoint ===================================

    function send(
        Packet calldata _packet,
        bytes calldata _options,
        bool _payInLzToken
    ) external onlyEndpoint returns (MessagingFee memory, bytes memory) {
        // the receiver must be the same as the sender
        if (AddressCast.toBytes32(_packet.sender) != _packet.receiver) revert LZ_RL_InvalidReceiver();

        // pay worker and treasury
        (bytes memory encodedPacket, uint256 totalNativeFee) = _payWorkers(_packet, _options);
        (uint256 treasuryNativeFee, uint256 lzTokenFee) = _payTreasury(
            _packet.sender,
            _packet.dstEid,
            totalNativeFee,
            _payInLzToken
        );
        totalNativeFee += treasuryNativeFee;

        // store the cmdHash for verification in order to prevent reorg attack
        cmdHashLookup[_packet.sender][_packet.dstEid][_packet.nonce] = keccak256(_packet.message);

        return (MessagingFee(totalNativeFee, lzTokenFee), encodedPacket);
    }

    function setConfig(address _oapp, SetConfigParam[] calldata _params) external onlyEndpoint {
        for (uint256 i = 0; i < _params.length; i++) {
            SetConfigParam calldata param = _params[i];
            _assertSupportedEid(param.eid);
            if (param.configType == CONFIG_TYPE_READ_LID_CONFIG) {
                _setReadLibConfig(param.eid, _oapp, abi.decode(param.config, (ReadLibConfig)));
            } else {
                revert LZ_RL_InvalidConfigType(param.configType);
            }
        }
    }

    // ============================ External ===================================
    /// @dev The verification will be done in the same chain where the packet is sent.
    /// @dev dont need to check endpoint verifiable here to save gas, as it will reverts if not verifiable.
    /// @param _packetHeader - the srcEid should be the localEid and the dstEid should be the channel id.
    ///        The original packet header in PacketSent event should be processed to flip the srcEid and dstEid.
    function commitVerification(bytes calldata _packetHeader, bytes32 _cmdHash, bytes32 _payloadHash) external {
        // assert packet header is of right size 81
        if (_packetHeader.length != 81) revert LZ_RL_InvalidPacketHeader();
        // assert packet header version is the same
        if (_packetHeader.version() != PacketV1Codec.PACKET_VERSION) revert LZ_RL_InvalidPacketVersion();
        // assert the packet is for this endpoint
        if (_packetHeader.dstEid() != localEid) revert LZ_RL_InvalidEid();

        // cache these values to save gas
        address receiver = _packetHeader.receiverB20();
        uint32 srcEid = _packetHeader.srcEid(); // channel id
        uint64 nonce = _packetHeader.nonce();

        // reorg protection. to allow reverification, the cmdHash cant be removed
        if (cmdHashLookup[receiver][srcEid][nonce] != _cmdHash) revert LZ_RL_InvalidCmdHash();

        ReadLibConfig memory config = getReadLibConfig(receiver, srcEid);
        _verifyAndReclaimStorage(config, keccak256(_packetHeader), _cmdHash, _payloadHash);

        // endpoint will revert if nonce <= lazyInboundNonce
        Origin memory origin = Origin(srcEid, _packetHeader.sender(), nonce);
        ILayerZeroEndpointV2(endpoint).verify(origin, receiver, _payloadHash);
    }

    /// @dev DVN verifies the payload with the packet header and command hash
    /// @param _packetHeader - the packet header is needed for event only, which can be conveniently for off-chain to track the packet state.
    function verify(bytes calldata _packetHeader, bytes32 _cmdHash, bytes32 _payloadHash) external {
        hashLookup[keccak256(_packetHeader)][_cmdHash][msg.sender] = _payloadHash;
        emit PayloadVerified(msg.sender, _packetHeader, _cmdHash, _payloadHash);
    }

    function withdrawFee(address _to, uint256 _amount) external {
        uint256 fee = fees[msg.sender];
        if (_amount > fee) revert LZ_RL_InvalidAmount(_amount, fee);
        unchecked {
            fees[msg.sender] = fee - _amount;
        }

        // transfers native if nativeToken == address(0x0)
        address nativeToken = ILayerZeroEndpointV2(endpoint).nativeToken();
        Transfer.nativeOrToken(nativeToken, _to, _amount);
        emit NativeFeeWithdrawn(msg.sender, _to, _amount);
    }

    // ============================ Treasury ===================================

    /// @dev _lzToken is a user-supplied value because lzToken might change in the endpoint before all lzToken can be taken out
    function withdrawLzTokenFee(address _lzToken, address _to, uint256 _amount) external {
        if (msg.sender != treasury) revert LZ_RL_NotTreasury();

        // lz token cannot be the same as the native token
        if (ILayerZeroEndpointV2(endpoint).nativeToken() == _lzToken) revert LZ_RL_CannotWithdrawAltToken();

        Transfer.token(_lzToken, _to, _amount);

        emit LzTokenFeeWithdrawn(_lzToken, _to, _amount);
    }

    // ============================ View ===================================

    function quote(
        Packet calldata _packet,
        bytes calldata _options,
        bool _payInLzToken
    ) external view returns (MessagingFee memory) {
        // split workers options
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(_options);

        address sender = _packet.sender;
        uint32 dstEid = _packet.dstEid;

        // quote the executor and dvns
        ReadLibConfig memory config = getReadLibConfig(sender, dstEid);
        uint256 nativeFee = _quoteDVNs(
            config,
            sender,
            PacketV1Codec.encodePacketHeader(_packet),
            _packet.message,
            dvnOptions
        );
        nativeFee += ILayerZeroReadExecutor(config.executor).getFee(sender, executorOptions);

        // quote treasury
        (uint256 treasuryNativeFee, uint256 lzTokenFee) = _quoteTreasury(sender, dstEid, nativeFee, _payInLzToken);
        nativeFee += treasuryNativeFee;

        return MessagingFee(nativeFee, lzTokenFee);
    }

    function verifiable(
        ReadLibConfig calldata _config,
        bytes32 _headerHash,
        bytes32 _cmdHash,
        bytes32 _payloadHash
    ) external view returns (bool) {
        return _checkVerifiable(_config, _headerHash, _cmdHash, _payloadHash);
    }

    function getConfig(uint32 _eid, address _oapp, uint32 _configType) external view returns (bytes memory) {
        if (_configType == CONFIG_TYPE_READ_LID_CONFIG) {
            return abi.encode(getReadLibConfig(_oapp, _eid));
        } else {
            revert LZ_RL_InvalidConfigType(_configType);
        }
    }

    function getTreasuryAndNativeFeeCap() external view returns (address, uint256) {
        return (treasury, treasuryNativeFeeCap);
    }

    function isSupportedEid(uint32 _eid) external view returns (bool) {
        return _isSupportedEid(_eid);
    }

    function messageLibType() external pure returns (MessageLibType) {
        return MessageLibType.SendAndReceive;
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (10, 0, 2);
    }

    // ============================ Internal ===================================

    /// 1/ handle executor
    /// 2/ handle other workers
    function _payWorkers(
        Packet calldata _packet,
        bytes calldata _options
    ) internal returns (bytes memory encodedPacket, uint256 totalNativeFee) {
        // split workers options
        (bytes memory executorOptions, bytes memory dvnOptions) = UlnOptions.decode(_options);

        // handle executor
        ReadLibConfig memory config = getReadLibConfig(_packet.sender, _packet.dstEid);
        totalNativeFee = _payExecutor(config.executor, _packet.sender, executorOptions);

        // handle dvns
        (uint256 dvnFee, bytes memory packetBytes) = _payDVNs(config, _packet, dvnOptions);
        totalNativeFee += dvnFee;

        encodedPacket = packetBytes;
    }

    function _payDVNs(
        ReadLibConfig memory _config,
        Packet calldata _packet,
        bytes memory _options
    ) internal returns (uint256 totalFee, bytes memory encodedPacket) {
        bytes memory packetHeader = PacketV1Codec.encodePacketHeader(_packet);
        bytes memory payload = PacketV1Codec.encodePayload(_packet);

        uint256[] memory dvnFees;
        (totalFee, dvnFees) = _assignDVNJobs(_config, _packet.sender, packetHeader, _packet.message, _options);

        encodedPacket = abi.encodePacked(packetHeader, payload);
        emit DVNFeePaid(_config.requiredDVNs, _config.optionalDVNs, dvnFees);
    }

    function _assignDVNJobs(
        ReadLibConfig memory _config,
        address _sender,
        bytes memory _packetHeader,
        bytes calldata _cmd,
        bytes memory _options
    ) internal returns (uint256 totalFee, uint256[] memory dvnFees) {
        (bytes[] memory optionsArray, uint8[] memory dvnIds) = DVNOptions.groupDVNOptionsByIdx(_options);

        uint8 dvnsLength = _config.requiredDVNCount + _config.optionalDVNCount;
        dvnFees = new uint256[](dvnsLength);
        for (uint8 i = 0; i < dvnsLength; ++i) {
            address dvn = i < _config.requiredDVNCount
                ? _config.requiredDVNs[i]
                : _config.optionalDVNs[i - _config.requiredDVNCount];

            bytes memory options = "";
            for (uint256 j = 0; j < dvnIds.length; ++j) {
                if (dvnIds[j] == i) {
                    options = optionsArray[j];
                    break;
                }
            }

            dvnFees[i] = ILayerZeroReadDVN(dvn).assignJob(_sender, _packetHeader, _cmd, options);
            if (dvnFees[i] > 0) {
                fees[dvn] += dvnFees[i];
                totalFee += dvnFees[i];
            }
        }
    }

    function _quoteDVNs(
        ReadLibConfig memory _config,
        address _sender,
        bytes memory _packetHeader,
        bytes calldata _cmd,
        bytes memory _options
    ) internal view returns (uint256 totalFee) {
        (bytes[] memory optionsArray, uint8[] memory dvnIndices) = DVNOptions.groupDVNOptionsByIdx(_options);

        // here we merge 2 list of dvns into 1 to allocate the indexed dvn options to the right dvn
        uint8 dvnsLength = _config.requiredDVNCount + _config.optionalDVNCount;
        for (uint8 i = 0; i < dvnsLength; ++i) {
            address dvn = i < _config.requiredDVNCount
                ? _config.requiredDVNs[i]
                : _config.optionalDVNs[i - _config.requiredDVNCount];

            bytes memory options = "";
            // it is a double loop here. however, if the list is short, the cost is very acceptable.
            for (uint256 j = 0; j < dvnIndices.length; ++j) {
                if (dvnIndices[j] == i) {
                    options = optionsArray[j];
                    break;
                }
            }
            totalFee += ILayerZeroReadDVN(dvn).getFee(_sender, _packetHeader, _cmd, options);
        }
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

    function _verifyAndReclaimStorage(
        ReadLibConfig memory _config,
        bytes32 _headerHash,
        bytes32 _cmdHash,
        bytes32 _payloadHash
    ) internal {
        if (!_checkVerifiable(_config, _headerHash, _cmdHash, _payloadHash)) {
            revert LZ_RL_Verifying();
        }

        // iterate the required DVNs
        if (_config.requiredDVNCount > 0) {
            for (uint8 i = 0; i < _config.requiredDVNCount; ++i) {
                delete hashLookup[_headerHash][_cmdHash][_config.requiredDVNs[i]];
            }
        }

        // iterate the optional DVNs
        if (_config.optionalDVNCount > 0) {
            for (uint8 i = 0; i < _config.optionalDVNCount; ++i) {
                delete hashLookup[_headerHash][_cmdHash][_config.optionalDVNs[i]];
            }
        }
    }

    /// @dev for verifiable view function
    /// @dev checks if this verification is ready to be committed to the endpoint
    function _checkVerifiable(
        ReadLibConfig memory _config,
        bytes32 _headerHash,
        bytes32 _cmdHash,
        bytes32 _payloadHash
    ) internal view returns (bool) {
        // iterate the required DVNs
        if (_config.requiredDVNCount > 0) {
            for (uint8 i = 0; i < _config.requiredDVNCount; ++i) {
                if (!_verified(_config.requiredDVNs[i], _headerHash, _cmdHash, _payloadHash)) {
                    // return if any of the required DVNs haven't signed
                    return false;
                }
            }
            if (_config.optionalDVNCount == 0) {
                // returns early if all required DVNs have signed and there are no optional DVNs
                return true;
            }
        }

        // then it must require optional validations
        uint8 threshold = _config.optionalDVNThreshold;
        for (uint8 i = 0; i < _config.optionalDVNCount; ++i) {
            if (_verified(_config.optionalDVNs[i], _headerHash, _cmdHash, _payloadHash)) {
                // increment the optional count if the optional DVN has signed
                threshold--;
                if (threshold == 0) {
                    // early return if the optional threshold has hit
                    return true;
                }
            }
        }

        // return false as a catch-all
        return false;
    }

    function _verified(
        address _dvn,
        bytes32 _headerHash,
        bytes32 _cmdHash,
        bytes32 _expectedPayloadHash
    ) internal view returns (bool verified) {
        verified = hashLookup[_headerHash][_cmdHash][_dvn] == _expectedPayloadHash;
    }

    function _payExecutor(
        address _executor,
        address _sender,
        bytes memory _executorOptions
    ) internal returns (uint256 executorFee) {
        executorFee = ILayerZeroReadExecutor(_executor).assignJob(_sender, _executorOptions);
        if (executorFee > 0) {
            fees[_executor] += executorFee;
        }
        emit ExecutorFeePaid(_executor, executorFee);
    }

    receive() external payable {}
}
