// SPDX-License-Identifier: LZBL-1.2

pragma solidity 0.8.22;

import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";

contract CCIPDVNAdapter is CCIPReceiver, DVNAdapterBase {
    struct DstConfigParam {
        uint32 dstEid;
        // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#ethereum-sepolia
        // https://docs.chain.link/ccip/supported-networks/v1_0_0/mainnet
        uint64 chainSelector;
        uint16 multiplierBps;
        uint256 gasLimit;
        bytes peer;
    }

    struct DstConfig {
        uint64 chainSelector;
        uint16 multiplierBps;
        uint256 gasLimit;
        bytes peer;
    }

    address private constant NATIVE_GAS_TOKEN_ADDRESS = address(0);

    event DstConfigSet(DstConfigParam[] params);

    mapping(uint32 dstEid => DstConfig config) public dstConfig;
    mapping(uint64 chainSelector => uint32 eid) public CCIPChainToEid;

    constructor(
        address _sendLib,
        address _receiveLib,
        address[] memory _admins,
        address router
    ) CCIPReceiver(router) DVNAdapterBase(_sendLib, _receiveLib, _admins) {}

    /// @notice sets configuration (`chainSelector`, `multiplierBps`, `gasLimit` and `peer`) for destination chains
    /// @dev The `multiplierBps` can be updated separately using `setDstMultiplierBps` function
    /// @param _params array of chain configurations
    function setDstConfig(DstConfigParam[] calldata _params) external onlyAdmin {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam calldata param = _params[i];

            delete CCIPChainToEid[dstConfig[param.dstEid].chainSelector];

            CCIPChainToEid[param.chainSelector] = param.dstEid;
            dstConfig[param.dstEid] = DstConfig({
                chainSelector: param.chainSelector,
                multiplierBps: param.multiplierBps,
                gasLimit: param.gasLimit,
                peer: param.peer
            });
        }

        emit DstConfigSet(_params);
    }

    /// @notice sets fee multiplier in basis points for destination chains
    /// @param _params array of multipliers for destination chains
    function setDstMultiplier(DstMultiplierParam[] calldata _params) external onlyAdmin {
        for (uint256 i = 0; i < _params.length; i++) {
            DstMultiplierParam calldata param = _params[i];
            dstConfig[param.dstEid].multiplierBps = param.multiplierBps;
        }

        emit DstMultiplierSet(_params);
    }

    function getFee(
        uint32 _dstEid,
        uint64 /*_confirmations*/,
        address _sender,
        bytes calldata /*_options*/
    ) external view override returns (uint256 fee) {
        DstConfig storage config = dstConfig[_dstEid];

        Client.EVM2AnyMessage memory message = _createCCIPMessage(
            new bytes(PACKET_HEADER_SIZE),
            bytes32(0),
            config.peer,
            config.gasLimit
        );

        fee = _getCCIPFee(config.chainSelector, message);
        if (address(feeLib) != address(0)) {
            fee = feeLib.getFee(_dstEid, _sender, defaultMultiplierBps, config.multiplierBps, fee);
        }
    }

    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata /*_options*/
    ) external payable override onlySendLib returns (uint256 fee) {
        DstConfig memory config = dstConfig[_param.dstEid];

        Client.EVM2AnyMessage memory message = _createCCIPMessage(
            _param.packetHeader,
            _param.payloadHash,
            config.peer,
            config.gasLimit
        );

        fee = _getCCIPFee(config.chainSelector, message);
        _assertBalanceAndWithdrawFee(fee);

        IRouterClient(getRouter()).ccipSend{ value: fee }(config.chainSelector, message);

        if (address(feeLib) != address(0)) {
            fee = feeLib.getFee(_param.dstEid, _param.sender, defaultMultiplierBps, config.multiplierBps, fee);
        }
    }

    function _createCCIPMessage(
        bytes memory _packetHeader,
        bytes32 _payloadHash,
        bytes memory _receiver,
        uint256 _gasLimit
    ) private pure returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: _receiver,
            data: _encodePayload(_packetHeader, _payloadHash),
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: _gasLimit, strict: false })),
            feeToken: NATIVE_GAS_TOKEN_ADDRESS
        });
    }

    function _getCCIPFee(
        uint64 _dstChainSelector,
        Client.EVM2AnyMessage memory _message
    ) private view returns (uint256 ccipFee) {
        ccipFee = IRouterClient(getRouter()).getFee(_dstChainSelector, _message);
    }

    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        _assertPeer(_message.sourceChainSelector, _message.sender);
        _verify(_message.data);
    }

    function _assertPeer(uint64 _sourceChainSelector, bytes memory _sourceAddress) private view {
        uint32 sourceEid = CCIPChainToEid[_sourceChainSelector];
        bytes memory sourcePeer = dstConfig[sourceEid].peer;

        if (keccak256(_sourceAddress) != keccak256(sourcePeer)) revert Unauthorized();
    }
}
