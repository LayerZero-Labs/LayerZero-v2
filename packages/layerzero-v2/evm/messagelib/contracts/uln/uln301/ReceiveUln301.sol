// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { IUltraLightNode301 } from "./interfaces/IUltraLightNode301.sol";
import { ReceiveLibBaseE1 } from "./ReceiveLibBaseE1.sol";
import { ReceiveUlnBase } from "../ReceiveUlnBase.sol";
import { UlnConfig } from "../UlnBase.sol";

/// @dev ULN301 will be deployed on EndpointV1 and is for backward compatibility with ULN302 on EndpointV2. 301 can talk to both 301 and 302
/// @dev This is a gluing contract. It simply parses the requests and forward to the super.impl() accordingly.
/// @dev In this case, it combines the logic of ReceiveUlnBase and ReceiveLibBaseE1
contract ReceiveUln301 is IUltraLightNode301, ReceiveUlnBase, ReceiveLibBaseE1 {
    using PacketV1Codec for bytes;
    using SafeCast for uint32; // for chain ID uint32 to uint16 conversion

    uint256 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint256 internal constant CONFIG_TYPE_ULN = 2;

    error LZ_ULN_InvalidConfigType(uint256 configType);

    constructor(address _endpoint, uint32 _localEid) ReceiveLibBaseE1(_endpoint, _localEid) {}

    // ============================ OnlyEndpoint ===================================

    function setConfig(
        uint16 _eid,
        address _oapp,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyEndpoint {
        _assertSupportedEid(_eid);
        if (_configType == CONFIG_TYPE_EXECUTOR) {
            _setExecutor(_eid, _oapp, abi.decode(_config, (address)));
        } else if (_configType == CONFIG_TYPE_ULN) {
            _setUlnConfig(_eid, _oapp, abi.decode(_config, (UlnConfig)));
        } else {
            revert LZ_ULN_InvalidConfigType(_configType);
        }
    }

    // ============================ External ===================================

    /// @dev in 301, this is equivalent to execution as in Endpoint V2
    /// @dev dont need to check endpoint verifiable here to save gas, as it will reverts if not verifiable.
    function commitVerification(bytes calldata _packet, uint256 _gasLimit) external {
        bytes calldata header = _packet.header();
        _assertHeader(header, localEid);

        // cache these values to save gas
        address receiver = _packet.receiverB20();
        uint16 srcEid = _packet.srcEid().toUint16();

        UlnConfig memory config = getUlnConfig(receiver, srcEid);
        _verifyAndReclaimStorage(config, keccak256(header), _packet.payloadHash());

        // endpoint will revert if nonce != ++inboundNonce
        _execute(srcEid, _packet.sender(), receiver, _packet.nonce(), _packet.message(), _gasLimit);
    }

    function verify(bytes calldata _packetHeader, bytes32 _payloadHash, uint64 _confirmations) external {
        _verify(_packetHeader, _payloadHash, _confirmations);
    }

    // ============================ View ===================================

    function getConfig(uint16 _eid, address _oapp, uint256 _configType) external view override returns (bytes memory) {
        if (_configType == CONFIG_TYPE_EXECUTOR) {
            return abi.encode(getExecutor(_oapp, _eid));
        } else if (_configType == CONFIG_TYPE_ULN) {
            return abi.encode(getUlnConfig(_oapp, _eid));
        } else {
            revert LZ_ULN_InvalidConfigType(_configType);
        }
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (3, 0, 1);
    }
}
