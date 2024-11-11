// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { EndpointV1 } from "../mocks/EndpointV1.sol";

import { NonceContractMock as NonceContract } from "../../contracts/uln/uln301/mocks/NonceContractMock.sol";
import { IDVN } from "../../contracts/uln/interfaces/IDVN.sol";
import { DVN } from "../../contracts/uln/dvn/DVN.sol";
import { DVNFeeLib } from "../../contracts/uln/dvn/DVNFeeLib.sol";
import { Executor } from "../../contracts/Executor.sol";
import { ExecutorFeeLib } from "../../contracts/ExecutorFeeLib.sol";
import { IExecutor } from "../../contracts/interfaces/IExecutor.sol";
import { PriceFeed } from "../../contracts/PriceFeed.sol";
import { Treasury } from "../../contracts/Treasury.sol";
import { TreasuryFeeHandler } from "../../contracts/uln/uln301/TreasuryFeeHandler.sol";
import { ExecutorConfig, SetDefaultExecutorConfigParam } from "../../contracts/SendLibBase.sol";
import { UlnConfig, SetDefaultUlnConfigParam } from "../../contracts/uln/UlnBase.sol";
import { SetDefaultExecutorParam } from "../../contracts/uln/uln301/ReceiveLibBaseE1.sol";
import { SendUln301 } from "../../contracts/uln/uln301/SendUln301.sol";
import { ReceiveUln301 } from "../../contracts/uln/uln301/ReceiveUln301.sol";
import { SendUln302 } from "../../contracts/uln/uln302/SendUln302.sol";
import { ReceiveUln302 } from "../../contracts/uln/uln302/ReceiveUln302.sol";

import { TokenMock } from "../mocks/TokenMock.sol";
import { Constant } from "./Constant.sol";
import { OptionsUtil } from "./OptionsUtil.sol";

library Setup {
    using OptionsUtil for bytes;

    struct FixtureV1 {
        uint16 eid;
        EndpointV1 endpointV1;
        SendUln301 sendUln301;
        ReceiveUln301 receiveUln301;
        Executor executor;
        DVN dvn;
        PriceFeed priceFeed;
        Treasury treasury;
        TreasuryFeeHandler treasuryFeeHandler;
        TokenMock lzToken;
    }

    struct FixtureV2 {
        uint32 eid;
        EndpointV2 endpointV2;
        SendUln302 sendUln302;
        ReceiveUln302 receiveUln302;
        Executor executor;
        DVN dvn;
        PriceFeed priceFeed;
        Treasury treasury;
        TokenMock lzToken;
    }

    function loadFixtureV1(uint16 eid) internal returns (FixtureV1 memory f) {
        f.eid = eid;
        // deploy endpointV1, sendUln301
        (f.endpointV1, f.sendUln301, f.receiveUln301, f.treasuryFeeHandler) = deployEndpointV1(
            eid,
            Constant.TREASURY_GAS_CAP,
            Constant.TREASURY_GAS_FOR_FEE_CAP
        );
        // deploy priceFee
        f.priceFeed = deployPriceFeed();
        // deploy dvn
        f.dvn = deployDVN(
            eid,
            address(f.sendUln301),
            address(f.receiveUln301),
            address(0),
            address(0),
            address(f.priceFeed)
        );
        // deploy executor
        f.executor = deployExecutor(
            address(0),
            address(f.sendUln301),
            address(f.receiveUln301),
            address(0),
            address(f.priceFeed)
        );
        // deploy treasury
        f.treasury = deployTreasury();
        // deploy LZ token
        f.lzToken = deployTokenMock();

        f.sendUln301.setTreasury(address(f.treasury));
        f.sendUln301.setLzToken(address(f.lzToken));

        f.endpointV1.newVersion(address(f.sendUln301));
        f.endpointV1.newVersion(address(f.receiveUln301));
        f.endpointV1.setDefaultSendVersion(1);
        f.endpointV1.setDefaultReceiveVersion(2);
    }

    function loadFixtureV2(uint32 eid) internal returns (FixtureV2 memory f) {
        f.eid = eid;
        // deploy endpointV2, sendUln302
        (f.endpointV2, f.sendUln302, f.receiveUln302) = deployEndpointV2(
            eid,
            Constant.TREASURY_GAS_CAP,
            Constant.TREASURY_GAS_FOR_FEE_CAP
        );
        // deploy priceFee
        f.priceFeed = deployPriceFeed();
        // deploy dvn
        f.dvn = deployDVN(
            eid,
            address(0),
            address(0),
            address(f.sendUln302),
            address(f.receiveUln302),
            address(f.priceFeed)
        );
        // deploy executor
        f.executor = deployExecutor(
            address(f.endpointV2),
            address(0),
            address(0),
            address(f.sendUln302),
            address(f.priceFeed)
        );
        // deploy treasury
        f.treasury = deployTreasury();
        // deploy LZ token
        f.lzToken = deployTokenMock();

        f.sendUln302.setTreasury(address(f.treasury));

        f.endpointV2.registerLibrary(address(f.sendUln302));
        f.endpointV2.setLzToken(address(f.lzToken));
        f.endpointV2.registerLibrary(address(f.receiveUln302));
    }

    function wireFixtureV1WithRemote(FixtureV1 memory f1, uint32 remoteEid) internal {
        address[] memory dvns = new address[](1);
        dvns[0] = address(f1.dvn);
        UlnConfig memory ulnConfig = UlnConfig(1, uint8(dvns.length), 0, 0, dvns, new address[](0));
        SetDefaultUlnConfigParam[] memory ulnConfigParams = new SetDefaultUlnConfigParam[](1);
        ulnConfigParams[0] = SetDefaultUlnConfigParam(remoteEid, ulnConfig);

        // set send uln config
        {
            f1.sendUln301.setDefaultUlnConfigs(ulnConfigParams);
            f1.sendUln301.setAddressSize(uint16(remoteEid), 20);

            SetDefaultExecutorConfigParam[] memory executorConfigParams = new SetDefaultExecutorConfigParam[](1);
            executorConfigParams[0] = SetDefaultExecutorConfigParam(
                remoteEid,
                ExecutorConfig(1000, address(f1.executor))
            );
            f1.sendUln301.setDefaultExecutorConfigs(executorConfigParams);
        }

        {
            // set receive uln config
            f1.receiveUln301.setDefaultUlnConfigs(ulnConfigParams);
            f1.receiveUln301.setAddressSize(uint16(remoteEid), 20);

            SetDefaultExecutorParam[] memory executorParams = new SetDefaultExecutorParam[](1);
            executorParams[0] = SetDefaultExecutorParam(remoteEid, address(f1.executor));
            f1.receiveUln301.setDefaultExecutors(executorParams);
        }

        IExecutor.DstConfigParam[] memory dstConfigParams = new IExecutor.DstConfigParam[](1);
        dstConfigParams[0] = IExecutor.DstConfigParam({
            dstEid: remoteEid,
            lzReceiveBaseGas: 5000,
            lzComposeBaseGas: 0,
            multiplierBps: 10000,
            floorMarginUSD: 1e10,
            nativeCap: 1 gwei
        });
        f1.executor.setDstConfig(dstConfigParams);
    }

    function wireFixtureV2WithRemote(FixtureV2 memory f2, uint32 remoteEid) internal {
        IExecutor.DstConfigParam[] memory dstConfigParams = new IExecutor.DstConfigParam[](1);
        dstConfigParams[0] = IExecutor.DstConfigParam({
            dstEid: remoteEid,
            lzReceiveBaseGas: 5000,
            lzComposeBaseGas: 0,
            multiplierBps: 10000,
            floorMarginUSD: 1e10,
            nativeCap: 1 gwei
        });
        f2.executor.setDstConfig(dstConfigParams);

        address[] memory dvns = new address[](1);
        dvns[0] = address(f2.dvn);
        UlnConfig memory ulnConfig = UlnConfig(1, uint8(dvns.length), 0, 0, dvns, new address[](0));
        SetDefaultUlnConfigParam[] memory ulnConfigParams = new SetDefaultUlnConfigParam[](1);
        ulnConfigParams[0] = SetDefaultUlnConfigParam(remoteEid, ulnConfig);

        // set send uln config
        SetDefaultExecutorConfigParam[] memory executorConfigParams = new SetDefaultExecutorConfigParam[](1);
        executorConfigParams[0] = SetDefaultExecutorConfigParam(remoteEid, ExecutorConfig(1000, address(f2.executor)));
        f2.sendUln302.setDefaultExecutorConfigs(executorConfigParams);
        f2.sendUln302.setDefaultUlnConfigs(ulnConfigParams);

        // set receive uln config
        f2.receiveUln302.setDefaultUlnConfigs(ulnConfigParams);

        f2.endpointV2.setDefaultSendLibrary(remoteEid, address(f2.sendUln302));
        f2.endpointV2.setDefaultReceiveLibrary(remoteEid, address(f2.receiveUln302), 0);
    }

    function deployEndpointV1(
        uint16 eid,
        uint256 treasuryGasCap,
        uint256 treasuryGasForFeeCap
    ) internal returns (EndpointV1, SendUln301, ReceiveUln301, TreasuryFeeHandler) {
        EndpointV1 endpointV1 = new EndpointV1(eid);
        TreasuryFeeHandler feeHandler = new TreasuryFeeHandler(address(endpointV1));
        SendUln301 sendUln301 = new SendUln301(
            address(endpointV1),
            treasuryGasCap,
            treasuryGasForFeeCap,
            address(new NonceContract(address(endpointV1))),
            eid,
            address(feeHandler)
        );
        ReceiveUln301 receiveUln301 = new ReceiveUln301(address(endpointV1), eid);

        return (endpointV1, sendUln301, receiveUln301, feeHandler);
    }

    function deployEndpointV2(
        uint32 eid,
        uint256 treasuryGasCap,
        uint256 treasuryGasForFeeCap
    ) internal returns (EndpointV2, SendUln302, ReceiveUln302) {
        // deploy endpointV2, sendUln302
        EndpointV2 endpointV2 = new EndpointV2(eid, address(this));
        SendUln302 sendUln302 = new SendUln302(address(endpointV2), treasuryGasCap, treasuryGasForFeeCap);
        ReceiveUln302 receiveUln302 = new ReceiveUln302(address(endpointV2));
        return (endpointV2, sendUln302, receiveUln302);
    }

    function deployPriceFeed() internal returns (PriceFeed) {
        PriceFeed priceFeed = new PriceFeed();
        priceFeed.initialize(address(this));
        return priceFeed;
    }

    function deployDVN(
        uint32 eid,
        address sendUln301,
        address receiveUln301,
        address sendUln302,
        address receiveUln302,
        address priceFeed
    ) internal returns (DVN) {
        address[] memory libs = new address[](4);
        libs[0] = sendUln301;
        libs[1] = receiveUln301;
        libs[2] = sendUln302;
        libs[3] = receiveUln302;
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

        return dvn;
    }

    function deployExecutor(
        address endpointV2,
        address sendUln301,
        address receiveUln301,
        address sendUln302,
        address priceFeed
    ) internal returns (Executor) {
        Executor executor = new Executor();
        ExecutorFeeLib executorFeeLib = new ExecutorFeeLib(1, 1e18);
        {
            address[] memory admins = new address[](1);
            admins[0] = address(this);
            address[] memory libs = new address[](3);
            libs[0] = sendUln301;
            libs[1] = receiveUln301;
            libs[2] = sendUln302;
            executor.initialize(endpointV2, receiveUln301, libs, priceFeed, address(this), admins);
            executor.setWorkerFeeLib(address(executorFeeLib));
        }
        return executor;
    }

    function deployTreasury() internal returns (Treasury) {
        Treasury treasury = new Treasury();
        return treasury;
    }

    function deployTokenMock() internal returns (TokenMock) {
        TokenMock lzToken = new TokenMock();
        return lzToken;
    }
}
