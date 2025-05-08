// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { IAny2EVMMessageReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";
import { ICCIPDVNAdapter } from "../../../interfaces/adapters/ICCIPDVNAdapter.sol";
import { ICCIPDVNAdapterFeeLib } from "../../../interfaces/adapters/ICCIPDVNAdapterFeeLib.sol";

/// @title CCIPDVNAdapter
/// @dev How CCIP DVN Adapter works:
/// 1. Estimate gas cost for the message on-chain by calling `getFee` on the Router contract.
///     refer to https://docs.chain.link/ccip/api-reference/i-router-client#getfee
/// 2. Call `ccipSend` on the Router contract to send the message.
///     refer to https://docs.chain.link/ccip/api-reference/i-router-client#ccipsend
/// @dev Recovery:
/// 1. If not enough gas paid, the message will be failed to execute on the destination chain, you can manually retry by calling `manuallyExecute` on the `OffRamp` contract.
///     refer to https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/offRamp/EVM2EVMOffRamp.sol#L222
contract CCIPDVNAdapter is DVNAdapterBase, IAny2EVMMessageReceiver, ICCIPDVNAdapter {
    address private constant NATIVE_GAS_TOKEN_ADDRESS = address(0);

    IRouterClient public immutable router;

    mapping(uint32 dstEid => DstConfig) public dstConfig;
    mapping(uint64 srcChainSelector => SrcConfig) public srcConfig;

    constructor(address[] memory _admins, address _router) DVNAdapterBase(msg.sender, _admins, 12000) {
        router = IRouterClient(_router);
    }

    // ========================= OnlyAdmin =========================
    /// @notice sets configuration for destination chains
    /// @param _params array of chain configurations
    function setDstConfig(DstConfigParam[] calldata _params) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam calldata param = _params[i];

            uint32 eid = param.eid % 30000;

            // set once per chainSelector
            // only one adapter per dvn that services both endpoint v1 and v2
            // we standardize the eid stored here with mod 30000
            if (dstConfig[eid].chainSelector == 0) {
                dstConfig[eid].chainSelector = param.chainSelector;
                dstConfig[eid].peer = param.peer;
                srcConfig[param.chainSelector].eid = eid;
                srcConfig[param.chainSelector].peer = param.peer;
            }

            dstConfig[eid].multiplierBps = param.multiplierBps;
            dstConfig[eid].gas = param.gas;
        }

        emit DstConfigSet(_params);
    }

    // ========================= OnlyMessageLib =========================
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata _options
    ) external payable override onlyAcl(_param.sender) returns (uint256 totalFee) {
        bytes32 receiveLib = _getAndAssertReceiveLib(msg.sender, _param.dstEid);

        ICCIPDVNAdapterFeeLib.Param memory feeLibParam = ICCIPDVNAdapterFeeLib.Param(
            _param.dstEid,
            _param.confirmations,
            _param.sender,
            defaultMultiplierBps
        );

        DstConfig memory config = dstConfig[_param.dstEid % 30000];

        bytes memory data = _encode(receiveLib, _param.packetHeader, _param.payloadHash);
        Client.EVM2AnyMessage memory message = _createCCIPMessage(data, config.peer, config.gas);

        IRouterClient ccipRouter = router;
        uint256 ccipFee;
        (ccipFee, totalFee) = ICCIPDVNAdapterFeeLib(workerFeeLib).getFeeOnSend(
            feeLibParam,
            config,
            message,
            _options,
            ccipRouter
        );

        _assertBalanceAndWithdrawFee(msg.sender, ccipFee);

        ccipRouter.ccipSend{ value: ccipFee }(config.chainSelector, message);
    }

    // ========================= OnlyRouter =========================
    function ccipReceive(Client.Any2EVMMessage calldata _message) external {
        if (msg.sender != address(router)) revert CCIPDVNAdapter_InvalidRouter(msg.sender);

        SrcConfig memory config = srcConfig[_message.sourceChainSelector];

        _assertPeer(_message.sourceChainSelector, _message.sender, config.peer);

        _decodeAndVerify(config.eid, _message.data);
    }

    // ========================= View =========================
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view override onlyAcl(_sender) returns (uint256 totalFee) {
        ICCIPDVNAdapterFeeLib.Param memory feeLibParam = ICCIPDVNAdapterFeeLib.Param(
            _dstEid,
            _confirmations,
            _sender,
            defaultMultiplierBps
        );

        DstConfig memory config = dstConfig[_dstEid % 30000];

        bytes memory data = _encodeEmpty();
        Client.EVM2AnyMessage memory message = _createCCIPMessage(data, config.peer, config.gas);

        totalFee = ICCIPDVNAdapterFeeLib(workerFeeLib).getFee(feeLibParam, config, message, _options, router);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAny2EVMMessageReceiver).interfaceId || super.supportsInterface(interfaceId);
    }

    // ========================= Internal =========================
    function _createCCIPMessage(
        bytes memory _data,
        bytes memory _receiver,
        uint256 _gas
    ) private pure returns (Client.EVM2AnyMessage memory message) {
        message = Client.EVM2AnyMessage({
            receiver: _receiver,
            data: _data,
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({ gasLimit: _gas, strict: false })),
            feeToken: NATIVE_GAS_TOKEN_ADDRESS
        });
    }

    function _assertPeer(uint64 _sourceChainSelector, bytes memory _sourceAddress, bytes memory peer) private pure {
        if (keccak256(_sourceAddress) != keccak256(peer)) {
            revert CCIPDVNAdapter_UntrustedPeer(_sourceChainSelector, _sourceAddress);
        }
    }
}
