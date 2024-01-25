// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { AxelarExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { ISendLib } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";
import { IAxelarDVNAdapter } from "../../../interfaces/adapters/IAxelarDVNAdapter.sol";
import { IAxelarDVNAdapterFeeLib } from "../../../interfaces/adapters/IAxelarDVNAdapterFeeLib.sol";

interface ISendLibBase {
    function fees(address _worker) external view returns (uint256);
}

/// @title AxelarDVNAdapter
/// @dev How Axelar DVN Adapter works:
///  1. Estimate gas fee off-chain using the Axelar SDK.
///     refer to https://docs.axelar.dev/dev/axelarjs-sdk/axelar-query-api#estimategasfee
///  2. Pay gas fee by calling `payNativeGasForContractCall` on the AxelarGasService contract.
///     refer to https://docs.axelar.dev/dev/general-message-passing/gas-services/pay-gas#paynativegasforcontractcall
///  3. Send message by calling `callContract` on the AxelarGateway contract.
///     refer to https://docs.axelar.dev/dev/general-message-passing/gmp-messages#call-a-contract-on-chain-b-from-chain-a
///  4. Refund surplus gas fee asynchronously.
///     refer to https://docs.axelar.dev/dev/general-message-passing/gas-services/refund
/// @dev Recovery:
///  1. If not enough gas fee is paid, the message will be hangup on source chain and can `add gas` to retry.
///     refer to https://docs.axelar.dev/dev/general-message-passing/recovery#increase-gas-payment-to-the-gas-receiver-on-the-source-chain
///  2. If the message is not executed on the destination chain, you can manually retry by calling `execute` on the `ReceiveAxelarDVNAdapter` contract.
///     refer to https://docs.axelar.dev/dev/general-message-passing/recovery#manually-execute-a-transfer
/// @dev As the Gas is estimated off-chain, we need to update the gas fee periodically on-chain by calling `setNativeGasFee` with the new fee.
contract AxelarDVNAdapter is DVNAdapterBase, AxelarExecutable, IAxelarDVNAdapter {
    mapping(string axelarChain => string peer) public peers; // by chain name
    mapping(uint32 dstEid => DstConfig) public dstConfig; // by dstEid

    // set default multiplier to 2.5x
    constructor(
        address[] memory _admins,
        address _gateway
    ) AxelarExecutable(_gateway) DVNAdapterBase(msg.sender, _admins, 12000) {}

    // ========================= OnlyAdmin =========================
    function setDstConfig(DstConfigParam[] calldata _params) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam calldata param = _params[i];

            delete peers[dstConfig[param.dstEid].chainName]; // delete old peer in case chain name by dstEid is updated
            peers[param.chainName] = param.peer; // update peer

            dstConfig[param.dstEid] = DstConfig(param.chainName, param.peer, param.multiplierBps, param.nativeGasFee); // update config by dstEid
        }

        emit DstConfigSet(_params);
    }

    /// @notice sets message fee in native gas for destination chains.
    /// @dev Axelar does not support quoting fee on-chain. Instead, the fee needs to be obtained off-chain by querying through the Axelar SDK.
    /// @dev The fee may change over time when token prices change, requiring admins to monitor and make necessary updates to reflect the actual fee.
    /// @dev Adding a buffer to the required fee is advisable. Any surplus fee will be refunded asynchronously if it exceeds the necessary amount.
    /// https://docs.axelar.dev/dev/general-message-passing/gas-services/pay-gas
    /// https://github.com/axelarnetwork/axelarjs/blob/070c8fe061f1082e79772fdc5c4675c0237bbba2/packages/api/src/axelar-query/isomorphic.ts#L54
    /// https://github.com/axelarnetwork/axelar-cgp-solidity/blob/d4536599321774927bf9716178a9e360f8e0efac/contracts/gas-service/AxelarGasService.sol#L403
    function setNativeGasFee(NativeGasFeeParam[] calldata _params) external onlyRole(ADMIN_ROLE) {
        for (uint256 i = 0; i < _params.length; i++) {
            NativeGasFeeParam calldata param = _params[i];
            dstConfig[param.dstEid].nativeGasFee = param.nativeGasFee;
        }
        emit NativeGasFeeSet(_params);
    }

    // ========================= OnlyWorkerFeeLib =========================
    function withdrawToFeeLib(address _sendLib) external {
        if (msg.sender != workerFeeLib) revert AxelarDVNAdapter_OnlyWorkerFeeLib();

        _withdrawFeeFromSendLib(_sendLib, workerFeeLib);
    }

    // ========================= OnlyMessageLib =========================
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata _options
    ) external payable override onlyAcl(_param.sender) returns (uint totalFee) {
        bytes32 receiveLib = _getAndAssertReceiveLib(msg.sender, _param.dstEid);

        IAxelarDVNAdapterFeeLib.Param memory feeLibParam = IAxelarDVNAdapterFeeLib.Param({
            dstEid: _param.dstEid,
            confirmations: _param.confirmations,
            sender: _param.sender,
            defaultMultiplierBps: defaultMultiplierBps
        });
        DstConfig memory config = dstConfig[_param.dstEid];

        bytes memory payload = _encode(receiveLib, _param.packetHeader, _param.payloadHash);

        totalFee = IAxelarDVNAdapterFeeLib(workerFeeLib).getFeeOnSend(
            feeLibParam,
            config,
            payload,
            _options,
            msg.sender
        );

        gateway.callContract(config.chainName, config.peer, payload);
    }

    // ========================= View =========================
    function getFee(
        uint32 _dstEid,
        uint64 _confirmations,
        address _sender,
        bytes calldata _options
    ) external view override returns (uint256 totalFee) {
        IAxelarDVNAdapterFeeLib.Param memory feeLibParam = IAxelarDVNAdapterFeeLib.Param(
            _dstEid,
            _confirmations,
            _sender,
            defaultMultiplierBps
        );

        totalFee = IAxelarDVNAdapterFeeLib(workerFeeLib).getFee(feeLibParam, dstConfig[_dstEid], _options);
    }

    // ========================= Internal =========================
    function _execute(
        string calldata _sourceChain,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) internal override {
        // assert peer is the same as the source chain
        _assertPeer(_sourceChain, _sourceAddress);

        _decodeAndVerify(_payload);
    }

    function _assertPeer(string memory _sourceChain, string memory _sourceAddress) private view {
        string memory sourcePeer = peers[_sourceChain];
        if (keccak256(bytes(_sourceAddress)) != keccak256(bytes(sourcePeer))) {
            revert AxelarDVNAdapter_UntrustedPeer(_sourceChain, _sourceAddress);
        }
    }
}
