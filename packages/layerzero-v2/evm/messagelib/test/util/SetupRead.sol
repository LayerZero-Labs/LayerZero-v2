// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { MessagingParams, MessagingReceipt, MessagingFee, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import { IDVN } from "../../contracts/uln/interfaces/IDVN.sol";
import { DVN } from "../../contracts/uln/dvn/DVN.sol";
import { DVNFeeLib, BitMap256 } from "../../contracts/uln/dvn/DVNFeeLib.sol";
import { Executor } from "../../contracts/Executor.sol";
import { ExecutorFeeLib } from "../../contracts/ExecutorFeeLib.sol";
import { IExecutor } from "../../contracts/interfaces/IExecutor.sol";
import { PriceFeed } from "../../contracts/PriceFeed.sol";
import { ILayerZeroPriceFeed } from "../../contracts/interfaces/ILayerZeroPriceFeed.sol";
import { Treasury } from "../../contracts/Treasury.sol";
import { TreasuryFeeHandler } from "../../contracts/uln/uln301/TreasuryFeeHandler.sol";
import { ExecutorConfig, SetDefaultExecutorConfigParam } from "../../contracts/SendLibBase.sol";
import { ReadLibConfig, SetDefaultReadLibConfigParam } from "../../contracts/uln/readlib/ReadLibBase.sol";
import { SetDefaultExecutorParam } from "../../contracts/uln/uln301/ReceiveLibBaseE1.sol";
import { ReadLib1002 } from "../../contracts/uln/readlib/ReadLib1002.sol";

import { TokenMock } from "../mocks/TokenMock.sol";
import { Constant } from "./Constant.sol";
import { OptionsUtil } from "./OptionsUtil.sol";

library SetupRead {
    using OptionsUtil for bytes;

    uint120 internal constant OneUSD = 1e20;

    struct FixtureRead {
        uint32 eid;
        EndpointV2 endpointV2;
        ReadLib1002 cmdLib;
        Executor executor;
        ExecutorFeeLib executorFeeLib;
        DVN dvn;
        address dvnSigner; // 1 signer
        DVNFeeLib dvnFeeLib;
        PriceFeed priceFeed;
        Treasury treasury;
        TokenMock lzToken;
        ReadOApp oapp;
    }

    function loadFixture(uint32 eid) internal returns (FixtureRead memory f) {
        f.eid = eid;
        // deploy endpointV2, sendUln302
        (f.endpointV2, f.cmdLib) = deployEndpointV2(eid, Constant.TREASURY_GAS_CAP, Constant.TREASURY_GAS_FOR_FEE_CAP);
        // deploy priceFee
        f.priceFeed = deployPriceFeed(eid);
        // deploy dvn
        (f.dvn, f.dvnFeeLib) = deployDVN(eid, address(f.cmdLib), address(f.priceFeed));
        // deploy executor
        (f.executor, f.executorFeeLib) = deployExecutor(
            eid,
            address(f.endpointV2),
            address(f.cmdLib),
            address(f.priceFeed)
        );
        // deploy treasury
        f.treasury = deployTreasury();
        // deploy LZ token
        f.lzToken = deployTokenMock();

        // deploy oapp
        f.oapp = new ReadOApp(address(f.endpointV2));

        f.cmdLib.setTreasury(address(f.treasury));

        f.endpointV2.registerLibrary(address(f.cmdLib));
        f.endpointV2.setLzToken(address(f.lzToken));
    }

    function wireFixtureV2WithChannel(FixtureRead memory f2, uint32 cid) internal {
        // dvn feelib set supported channels
        DVNFeeLib.SetSupportedCmdTypesParam[] memory supportedCmdTypes = new DVNFeeLib.SetSupportedCmdTypesParam[](1);
        supportedCmdTypes[0] = DVNFeeLib.SetSupportedCmdTypesParam({ targetEid: cid, types: BitMap256.wrap(3) });
        f2.dvnFeeLib.setSupportedCmdTypes(supportedCmdTypes);

        // cmdLib set default config
        address[] memory dvns = new address[](1);
        dvns[0] = address(f2.dvn);
        ReadLibConfig memory cmdLibConfig = ReadLibConfig(
            address(f2.executor),
            uint8(dvns.length),
            0,
            0,
            dvns,
            new address[](0)
        );
        SetDefaultReadLibConfigParam[] memory ulnConfigParams = new SetDefaultReadLibConfigParam[](1);
        ulnConfigParams[0] = SetDefaultReadLibConfigParam(cid, cmdLibConfig);
        f2.cmdLib.setDefaultReadLibConfigs(ulnConfigParams);

        f2.endpointV2.setDefaultSendLibrary(cid, address(f2.cmdLib));
        f2.endpointV2.setDefaultReceiveLibrary(cid, address(f2.cmdLib), 0);
    }

    function deployEndpointV2(
        uint32 eid,
        uint256 treasuryGasCap,
        uint256 treasuryGasForFeeCap
    ) internal returns (EndpointV2, ReadLib1002) {
        // deploy endpointV2, sendUln302
        EndpointV2 endpointV2 = new EndpointV2(eid, address(this));
        ReadLib1002 cmdLib = new ReadLib1002(address(endpointV2), treasuryGasCap, treasuryGasForFeeCap);
        return (endpointV2, cmdLib);
    }

    function deployPriceFeed(uint32 eid) internal returns (PriceFeed) {
        PriceFeed priceFeed = new PriceFeed();
        priceFeed.initialize(address(this));
        priceFeed.setNativeTokenPriceUSD(OneUSD); // 1 USD with 20 denominator

        // price feed
        ILayerZeroPriceFeed.UpdatePrice memory updatePrice = ILayerZeroPriceFeed.UpdatePrice({
            eid: eid,
            price: ILayerZeroPriceFeed.Price({
                priceRatio: priceFeed.getPriceRatioDenominator(), // 1:1
                gasPriceInUnit: 1e9, // 1 gwei
                gasPerByte: 1000
            })
        });
        ILayerZeroPriceFeed.UpdatePrice[] memory updates = new ILayerZeroPriceFeed.UpdatePrice[](1);
        updates[0] = updatePrice;
        priceFeed.setPrice(updates);

        return priceFeed;
    }

    function deployDVN(uint32 eid, address cmdLib, address priceFeed) internal returns (DVN, DVNFeeLib) {
        address[] memory libs = new address[](4);
        libs[0] = cmdLib;
        address[] memory signers = new address[](1);
        signers[0] = address(this);
        address[] memory admins = new address[](1);
        admins[0] = address(this);
        DVN dvn = new DVN(eid, eid, libs, priceFeed, signers, 1, admins);

        IDVN.DstConfigParam[] memory dstConfigParams = new IDVN.DstConfigParam[](1);
        dstConfigParams[0] = IDVN.DstConfigParam({ dstEid: eid, gas: 5000, multiplierBps: 0, floorMarginUSD: 0 });
        dvn.setDstConfig(dstConfigParams);
        DVNFeeLib dvnFeeLib = new DVNFeeLib(eid, 1e18);
        dvn.setWorkerFeeLib(address(dvnFeeLib));
        uint120 evmCallRequestV1FeeUSD = OneUSD;
        uint120 evmCallComputeV1ReduceFeeUSD = OneUSD;
        uint16 evmCallComputeV1MapBps = 1000; // 10% plug for each map call on request
        dvnFeeLib.setCmdFees(evmCallRequestV1FeeUSD, evmCallComputeV1ReduceFeeUSD, evmCallComputeV1MapBps);

        return (dvn, dvnFeeLib);
    }

    function deployExecutor(
        uint32 eid,
        address endpointV2,
        address cmdLib,
        address priceFeed
    ) internal returns (Executor, ExecutorFeeLib) {
        Executor executor = new Executor();
        ExecutorFeeLib executorFeeLib = new ExecutorFeeLib(EndpointV2(endpointV2).eid(), 1e18);
        {
            address[] memory admins = new address[](1);
            admins[0] = address(this);
            address[] memory libs = new address[](3);
            libs[0] = cmdLib;
            executor.initialize(endpointV2, address(0), libs, priceFeed, address(this), admins);
            executor.setWorkerFeeLib(address(executorFeeLib));

            IExecutor.DstConfigParam[] memory dstConfigParams = new IExecutor.DstConfigParam[](1);
            dstConfigParams[0] = IExecutor.DstConfigParam({
                dstEid: eid,
                lzReceiveBaseGas: 5000,
                lzComposeBaseGas: 5000,
                multiplierBps: 10000,
                floorMarginUSD: 0,
                nativeCap: 1 gwei
            });
            executor.setDstConfig(dstConfigParams);
        }
        return (executor, executorFeeLib);
    }

    function deployTreasury() internal returns (Treasury) {
        Treasury treasury = new Treasury();
        treasury.setLzTokenEnabled(true);
        treasury.setLzTokenFee(1e18); // 1 ZRO
        treasury.setNativeFeeBP(1000); // 10%
        return treasury;
    }

    function deployTokenMock() internal returns (TokenMock) {
        TokenMock lzToken = new TokenMock();
        return lzToken;
    }
}

contract ReadOApp {
    using OptionsUtil for bytes;

    // copy cmd from test_success_1_req_map_and_reduce
    bytes public constant cmd =
        hex"000100000001010000000100080000029aaabbccdd010001020000029a00000000000000000000000000000000000000000000000000000000000000";

    EndpointV2 public endpointV2;

    uint256 public ack;

    constructor(address _endpoint) {
        endpointV2 = EndpointV2(_endpoint);
    }

    function quote(uint32 _cid, bool _payInLzToken, bytes memory _options) public view returns (MessagingFee memory) {
        MessagingParams memory msgParams = MessagingParams(
            _cid,
            bytes32(uint256(uint160(address(this)))),
            cmd,
            _options,
            _payInLzToken
        );
        return endpointV2.quote(msgParams, address(this));
    }

    function send(
        uint32 _cid,
        bool _payInLzToken,
        bytes memory _options
    ) public payable returns (MessagingReceipt memory) {
        MessagingParams memory msgParams = MessagingParams(
            _cid,
            bytes32(uint256(uint160(address(this)))),
            cmd,
            _options,
            _payInLzToken
        );
        return endpointV2.send{ value: msg.value }(msgParams, address(this));
    }

    function lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata /*_message*/,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) public payable virtual {
        require(msg.sender == address(endpointV2), "ReadOApp: Invalid sender");
        ack += 1;
    }

    function allowInitializePath(Origin calldata /*origin*/) public view virtual returns (bool) {
        return true;
    }

    receive() external payable {}
}
