// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IMessageLib, MessageLibType } from "../interfaces/IMessageLib.sol";
import { Packet } from "../interfaces/ISendLib.sol";
import { ILayerZeroEndpointV2, MessagingFee, Origin } from "../interfaces/ILayerZeroEndpointV2.sol";
import { Errors } from "../libs/Errors.sol";
import { PacketV1Codec } from "./libs/PacketV1Codec.sol";
import { Transfer } from "../libs/Transfer.sol";

contract SimpleMessageLib is Ownable, ERC165 {
    using SafeERC20 for IERC20;
    using PacketV1Codec for bytes;

    address public immutable endpoint;
    address public immutable treasury;
    uint32 public immutable localEid;
    uint8 public constant PACKET_VERSION = 1;

    address public whitelistCaller;

    uint256 public lzTokenFee;
    uint256 public nativeFee;

    bytes public defaultOption;

    error OnlyEndpoint();
    error OnlyWhitelistCaller();
    error InvalidEndpoint(address expected, address actual);
    error ToIsAddressZero();
    error LzTokenIsAddressZero();
    error TransferFailed();

    // only the endpoint can call SEND() and setConfig()
    modifier onlyEndpoint() {
        if (endpoint != msg.sender) {
            revert OnlyEndpoint();
        }
        _;
    }

    constructor(address _endpoint, address _treasury) {
        endpoint = _endpoint;
        treasury = _treasury;
        localEid = ILayerZeroEndpointV2(_endpoint).eid();
        lzTokenFee = 99;
        nativeFee = 100;
        //        defaultOption = Options.encodeLegacyOptionsType1(200000);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IMessageLib).interfaceId || super.supportsInterface(interfaceId);
    }

    // no validation logic at all
    function validatePacket(bytes calldata packetBytes) external {
        if (whitelistCaller != address(0x0) && msg.sender != whitelistCaller) {
            revert OnlyWhitelistCaller();
        }
        Origin memory origin = Origin(packetBytes.srcEid(), packetBytes.sender(), packetBytes.nonce());
        ILayerZeroEndpointV2(endpoint).verify(origin, packetBytes.receiverB20(), keccak256(packetBytes.payload()));
    }

    // ------------------ onlyEndpoint ------------------
    function send(
        Packet calldata _packet,
        bytes memory _options,
        bool _payInLzToken
    ) external onlyEndpoint returns (MessagingFee memory fee, bytes memory encodedPacket, bytes memory options) {
        encodedPacket = PacketV1Codec.encode(_packet);

        options = _options.length == 0 ? defaultOption : _options;
        _handleMessagingParamsHook(encodedPacket, options);

        fee = MessagingFee(nativeFee, _payInLzToken ? lzTokenFee : 0);
    }

    // ------------------ onlyOwner ------------------
    function setDefaultOption(bytes memory _defaultOption) external onlyOwner {
        defaultOption = _defaultOption;
    }

    function setMessagingFee(uint256 _nativeFee, uint256 _lzTokenFee) external onlyOwner {
        nativeFee = _nativeFee;
        lzTokenFee = _lzTokenFee;
    }

    function setWhitelistCaller(address _whitelistCaller) external onlyOwner {
        whitelistCaller = _whitelistCaller;
    }

    function withdrawFee(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0x0)) {
            revert ToIsAddressZero();
        }

        address altTokenAddr = ILayerZeroEndpointV2(endpoint).nativeToken();

        // transfers native if altTokenAddr == address(0x0)
        Transfer.nativeOrToken(altTokenAddr, _to, _amount);
    }

    function withdrawLzTokenFee(address _to, uint256 _amount) external onlyOwner {
        if (_to == address(0x0)) {
            revert ToIsAddressZero();
        }
        address lzToken = ILayerZeroEndpointV2(endpoint).lzToken();
        if (lzToken == address(0x0)) {
            revert LzTokenIsAddressZero();
        }
        IERC20(lzToken).safeTransfer(_to, _amount);
    }

    // ------------------ View ------------------
    function quote(
        Packet calldata /*_packet*/,
        bytes calldata /*_options*/,
        bool _payInLzToken
    ) external view returns (MessagingFee memory) {
        return MessagingFee(nativeFee, _payInLzToken ? lzTokenFee : 0);
    }

    function isSupportedEid(uint32) external pure returns (bool) {
        return true;
    }

    function version() external pure returns (uint64 major, uint8 minor, uint8 endpointVersion) {
        return (0, 0, 2);
    }

    function messageLibType() external pure returns (MessageLibType) {
        return MessageLibType.SendAndReceive;
    }

    // ------------------ Internal ------------------
    function _handleMessagingParamsHook(bytes memory _encodedPacket, bytes memory _options) internal virtual {}

    fallback() external payable {
        revert Errors.LZ_NotImplemented();
    }

    receive() external payable {}
}
