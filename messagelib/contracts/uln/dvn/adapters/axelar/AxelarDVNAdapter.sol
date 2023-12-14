// SPDX-License-Identifier: LZBL-1.2

pragma solidity 0.8.22;

import { AxelarExecutable } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import { IAxelarGasService } from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";

contract AxelarDVNAdapter is AxelarExecutable, DVNAdapterBase {
    struct DstConfigParam {
        uint32 dstEid;
        uint16 multiplierBps;
        uint256 nativeGasFee;
        string peer;
        string chainName;
    }

    struct DstFeeParam {
        uint32 dstEid;
        uint256 nativeGasFee;
    }

    struct DstConfig {
        uint256 nativeGasFee;
        uint16 multiplierBps;
        string peer;
        string chainName;
    }

    event DstConfigSet(DstConfigParam[] params);
    event DstFeeSet(DstFeeParam[] params);

    IAxelarGasService public immutable gasService;

    mapping(uint32 dstEid => DstConfig config) public dstConfig;
    mapping(string axelarChain => uint32 eid) public axelarChainToEid;

    constructor(
        address _sendLib,
        address _receiveLib,
        address[] memory _admins,
        address _gateway,
        address _gasReceiver
    ) AxelarExecutable(_gateway) DVNAdapterBase(_sendLib, _receiveLib, _admins) {
        gasService = IAxelarGasService(_gasReceiver);
    }

    /// @notice sets configuration (`nativeGasFee`, `multiplierBps`, `peer`, and `chainName`) for destination chains
    /// @dev The `nativeGasFee` and `multiplierBps` can be updated separately using `setDstNativeGasFee` and `setDstMultiplier` functions
    /// @param _params array of chain configurations
    function setDstConfig(DstConfigParam[] calldata _params) external onlyAdmin {
        for (uint256 i = 0; i < _params.length; i++) {
            DstConfigParam calldata param = _params[i];

            delete axelarChainToEid[dstConfig[param.dstEid].chainName];

            axelarChainToEid[param.chainName] = param.dstEid;
            dstConfig[param.dstEid] = DstConfig({
                nativeGasFee: param.nativeGasFee,
                multiplierBps: param.multiplierBps,
                peer: param.peer,
                chainName: param.chainName
            });
        }

        emit DstConfigSet(_params);
    }

    /// @notice sets message fee in native gas for destination chains.
    /// @dev Axelar does not support quoting fee onchain. Instead, the fee needs to be obtained off-chain by querying through the Axelar SDK.
    /// @dev The fee may change over time when token prices change, requiring admins to monitor and make necessary updates to reflect the actual fee.
    /// @dev Adding a buffer to the required fee is advisable. Any surplus fee will be refunded asynchronously if it exceeds the necessary amount.
    /// https://docs.axelar.dev/dev/general-message-passing/gas-services/pay-gas
    /// https://github.com/axelarnetwork/axelarjs/blob/070c8fe061f1082e79772fdc5c4675c0237bbba2/packages/api/src/axelar-query/isomorphic.ts#L54
    /// https://github.com/axelarnetwork/axelar-cgp-solidity/blob/d4536599321774927bf9716178a9e360f8e0efac/contracts/gas-service/AxelarGasService.sol#L403
    /// @param _params array of message fees for destination chains
    function setDstNativeGasFee(DstFeeParam[] calldata _params) external onlyAdmin {
        // TODO - can delete and call setDstConfig instead?
        for (uint256 i = 0; i < _params.length; i++) {
            DstFeeParam calldata param = _params[i];
            dstConfig[param.dstEid].nativeGasFee = param.nativeGasFee;
        }

        emit DstFeeSet(_params);
    }

    /// @notice sets fee multiplier in basis points for destination chains
    /// @param _params array of multipliers for destination chains
    function setDstMultiplier(DstMultiplierParam[] calldata _params) external onlyAdmin {
        // TODO - can delete and call setDstConfig instead?
        for (uint256 i = 0; i < _params.length; i++) {
            DstMultiplierParam calldata param = _params[i];
            dstConfig[param.dstEid].multiplierBps = param.multiplierBps;
        }

        emit DstMultiplierSet(_params);
    }

    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata /*_options*/
    ) external payable override onlySendLib returns (uint256 fee) {
        DstConfig storage config = dstConfig[_param.dstEid];
        fee = config.nativeGasFee;
        string memory dstChainName = config.chainName;
        string memory dstPeer = config.peer;
        bytes memory payload = _encodePayload(_param.packetHeader, _param.payloadHash);

        _assertBalanceAndWithdrawFee(fee);

        // https://docs.axelar.dev/dev/general-message-passing/gas-services/pay-gas#paynativegasforcontractcall
        gasService.payNativeGasForContractCall{ value: fee }(
            address(this), // sender
            dstChainName, // destinationChain
            dstPeer, // destinationAddress
            payload, // payload
            address(this) // refundAddress
        );
        // https://docs.axelar.dev/dev/general-message-passing/gmp-messages#call-a-contract-on-chain-b-from-chain-a
        gateway.callContract(dstChainName, dstPeer, payload);

        if (address(feeLib) != address(0)) {
            fee = feeLib.getFee(_param.dstEid, _param.sender, defaultMultiplierBps, config.multiplierBps, fee);
        }
    }

    function getFee(
        uint32 _dstEid,
        uint64 /*_confirmations*/,
        address _sender,
        bytes calldata /*_options*/
    ) external view override returns (uint256 fee) {
        DstConfig storage config = dstConfig[_dstEid];
        fee = config.nativeGasFee;
        if (address(feeLib) != address(0)) {
            fee = feeLib.getFee(_dstEid, _sender, defaultMultiplierBps, config.multiplierBps, fee);
        }
    }

    function _execute(
        string calldata _sourceChain,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) internal override {
        _assertPeer(_sourceChain, _sourceAddress);
        _verify(_payload);
    }

    function _assertPeer(string calldata _sourceChain, string calldata _sourceAddress) private view {
        uint32 sourceEid = axelarChainToEid[_sourceChain];
        string memory sourcePeer = dstConfig[sourceEid].peer;

        if (keccak256(bytes(_sourceAddress)) != keccak256(bytes(sourcePeer))) revert Unauthorized();
    }
}
