// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { IMessageLib, MessageLibType } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import { ISendLib, Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";

import { ReadLibConfig, SetDefaultReadLibConfigParam } from "../../contracts/uln/readlib/ReadLibBase.sol";
import { ReadLib1002 } from "../../contracts/uln/readlib/ReadLib1002.sol";
import { Treasury } from "../../contracts/Treasury.sol";
import { OptionsUtil } from "../util/OptionsUtil.sol";

contract CmdLibTest is Test, ReadLib1002 {
    using OptionsUtil for bytes;

    address internal constant MALICIOUS = address(0xabcd);

    constructor() ReadLib1002(address(new EndpointV2(1, address(this))), 10000, 20000) {}

    function test_withdraw_native() public {
        address worker = address(0xaaaa);
        fees[worker] = 100; // set fee to WORKER

        // fail if withdraw too much
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidAmount.selector, 101, 100));
        vm.prank(worker);
        this.withdrawFee(worker, 101);

        uint256 balanceBefore = address(worker).balance;
        vm.prank(worker);
        this.withdrawFee(worker, 100);
        uint256 balanceAfter = address(worker).balance;
        assertEq(balanceAfter - balanceBefore, 100);

        assertEq(fees[worker], 0);
    }

    function test_withdraw_native_alt() public {
        address worker = address(0xaaaa);
        fees[worker] = 100; // set fee to WORKER

        // mock endpoint.nativeToken()
        vm.mockCall(
            address(endpoint),
            abi.encodeWithSelector(EndpointV2.nativeToken.selector),
            abi.encode(address(0x1234))
        );
        // mock token transfer
        vm.mockCall(address(0x1234), abi.encodeWithSelector(ERC20.transfer.selector), abi.encode(true));

        // fail if withdraw too much
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidAmount.selector, 101, 100));
        vm.prank(worker);
        this.withdrawFee(worker, 101);

        vm.prank(worker);
        this.withdrawFee(worker, 100);

        fees[worker] = 0;
    }

    function test_supportsInterface() public {
        assertEq(this.supportsInterface(type(IMessageLib).interfaceId), true);
        assertEq(this.supportsInterface(type(ISendLib).interfaceId), true);
        assertEq(this.supportsInterface(type(IERC165).interfaceId), true);
    }

    function test_success_setConfig_getConfig() public {
        uint32 dstEid = 100;

        // setDefaultReadLibConfigs
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xdd));
        setDefaultReadLibConfigs(dstEid, readConfig); // set default config

        address oapp = address(0xaaaa);

        readConfig = buildReadLibConfig(address(0xdd22));
        SetConfigParam[] memory params = buildSetConfigParam(dstEid, CONFIG_TYPE_READ_LID_CONFIG, readConfig);

        vm.expectEmit(true, true, true, true, address(this));
        emit ReadLibConfigSet(oapp, dstEid, readConfig);
        vm.prank(endpoint);
        this.setConfig(oapp, params);

        // check if config is set
        bytes memory configData = this.getConfig(dstEid, oapp, CONFIG_TYPE_READ_LID_CONFIG);
        ReadLibConfig memory newReadConfig = abi.decode(configData, (ReadLibConfig));
        assertEq(newReadConfig.executor, address(0xe111));
        assertEq(newReadConfig.requiredDVNs[0], address(0xdd22));
        assertEq(newReadConfig.requiredDVNs.length, 1);
        assertEq(newReadConfig.requiredDVNCount, 1);
        assertEq(newReadConfig.optionalDVNs.length, 0);
        assertEq(newReadConfig.optionalDVNCount, 0);
        assertEq(newReadConfig.optionalDVNs.length, 0);
    }

    function test_revert_getConfig_unknown_configType() public {
        uint32 dstEid = 100;
        address oapp = address(0xaaaa);
        uint32 unknownConfigType = 100;

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidConfigType.selector, unknownConfigType));
        this.getConfig(dstEid, oapp, unknownConfigType);
    }

    function test_revert_setConfig_not_supported_eid() public {
        uint32 dstEid = 100;
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xdd));

        address oapp = address(0xaaaa);
        SetConfigParam[] memory params = buildSetConfigParam(dstEid, CONFIG_TYPE_READ_LID_CONFIG, readConfig);

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_UnsupportedEid.selector, dstEid));
        vm.prank(endpoint);
        this.setConfig(oapp, params);
    }

    function test_revert_only_endpoint_setConfig() public {
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xdd));

        address oapp = address(0xaaaa);
        SetConfigParam[] memory params = buildSetConfigParam(100, CONFIG_TYPE_READ_LID_CONFIG, readConfig);

        vm.expectRevert(abi.encodeWithSelector(LZ_MessageLib_OnlyEndpoint.selector));
        this.setConfig(oapp, params);
    }

    function test_revert_setConfig_invalid_configType() public {
        uint32 dstEid = 100;
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xdd));

        setDefaultReadLibConfigs(dstEid, readConfig); // set default config

        address oapp = address(0xaaaa);
        uint32 unknownConfigType = 100;
        SetConfigParam[] memory params = buildSetConfigParam(dstEid, unknownConfigType, readConfig);

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidConfigType.selector, unknownConfigType));
        vm.prank(endpoint);
        this.setConfig(oapp, params);
    }

    function test_isSupportedEid() public {
        uint32 dstEid = 100;
        assertEq(this.isSupportedEid(dstEid), false);

        setDefaultReadLibConfigs(dstEid, buildReadLibConfig(address(0xdd))); // set default config

        assertEq(this.isSupportedEid(dstEid), true);
    }

    function test_messageLibType() public {
        assertTrue(this.messageLibType() == MessageLibType.SendAndReceive);
    }

    function test_Version() public {
        (uint64 major, uint64 minor, uint64 endpointVersion) = this.version();
        assertEq(major, 10);
        assertEq(minor, 0);
        assertEq(endpointVersion, 2);
    }

    function test_quoteDVNs() public {
        address dvn = address(0xd1);
        address optionalDvn = address(0xd2);
        ReadLibConfig memory readConfig = buildReadLibConfig(dvn, optionalDvn);
        // mock dvn.getFee
        vm.mockCall(dvn, abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"), abi.encode(100));
        vm.mockCall(optionalDvn, abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"), abi.encode(200));

        uint256 totalFee = this.quoteDVNs(readConfig, address(0), "", "", "");
        assertEq(totalFee, 300);
    }

    function test_payDVNs() public {
        Packet memory packet = newPacket(1, 1, 1, address(0xa111), "cmd");
        address dvn = address(0xd1);
        address optionalDvn = address(0xd2);
        ReadLibConfig memory readConfig = buildReadLibConfig(dvn, optionalDvn);
        // mock dvn.assignJob
        vm.mockCall(dvn, abi.encodeWithSignature("assignJob(address,bytes,bytes,bytes)"), abi.encode(100));
        vm.mockCall(optionalDvn, abi.encodeWithSignature("assignJob(address,bytes,bytes,bytes)"), abi.encode(200));

        (uint256 totalFee, ) = this.payDVNs(readConfig, packet, "");
        assertEq(totalFee, 300);
        assertEq(fees[dvn], 100);
        assertEq(fees[optionalDvn], 200);
    }

    function test_payExecutor() public {
        address executor = address(0xe111);
        // mock executor.getFee
        vm.mockCall(executor, abi.encodeWithSignature("assignJob(address,bytes)"), abi.encode(100));

        uint256 executorFee = this.payExecutor(executor, address(0), "");
        assertEq(executorFee, 100);
        assertEq(fees[executor], 100);
    }

    function test_quote() public {
        uint32 cid = 1;
        // setup default config
        address dvn = address(0xd1);
        address optionalDvn = address(0xd2);
        ReadLibConfig memory readConfig = buildReadLibConfig(dvn, optionalDvn);
        // mock dvn.getFee
        vm.mockCall(dvn, abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"), abi.encode(100));
        vm.mockCall(optionalDvn, abi.encodeWithSignature("getFee(address,bytes,bytes,bytes)"), abi.encode(200));
        vm.mockCall(readConfig.executor, abi.encodeWithSignature("getFee(address,bytes)"), abi.encode(300));
        setDefaultReadLibConfigs(cid, readConfig);

        treasury = address(0xe222);
        // mock treasury.getFee
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.getFee.selector), abi.encode(400));

        Packet memory packet = newPacket(1, 1, cid, address(0xa111), "cmd");
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);
        MessagingFee memory msgFee = this.quote(packet, options, false);
        assertEq(msgFee.nativeFee, 100 + 200 + 300 + 400);
        assertEq(msgFee.lzTokenFee, 0);

        // quote with lzToken
        msgFee = this.quote(packet, options, true);
        assertEq(msgFee.nativeFee, 100 + 200 + 300);
        assertEq(msgFee.lzTokenFee, 400);
    }

    function test_send() public {
        uint32 cid = 1;
        // setup default config
        address dvn = address(0xd1);
        address optionalDvn = address(0xd2);
        ReadLibConfig memory readConfig = buildReadLibConfig(dvn, optionalDvn);
        // mock dvn.getFee
        vm.mockCall(dvn, abi.encodeWithSignature("assignJob(address,bytes,bytes,bytes)"), abi.encode(100));
        vm.mockCall(optionalDvn, abi.encodeWithSignature("assignJob(address,bytes,bytes,bytes)"), abi.encode(200));
        vm.mockCall(readConfig.executor, abi.encodeWithSignature("assignJob(address,bytes)"), abi.encode(300));
        setDefaultReadLibConfigs(cid, readConfig);

        treasury = address(0xe222);
        // mock treasury.payFee
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.payFee.selector), abi.encode(400));

        Packet memory packet = newPacket(1, 1, cid, address(0xa111), "cmd");
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);
        vm.prank(endpoint);
        (MessagingFee memory msgFee, ) = this.send(packet, options, false);
        assertEq(msgFee.nativeFee, 100 + 200 + 300 + 400);
        assertEq(msgFee.lzTokenFee, 0);

        // send with lzToken
        vm.prank(endpoint);
        (msgFee, ) = this.send(packet, options, true);
        assertEq(msgFee.nativeFee, 100 + 200 + 300);
        assertEq(msgFee.lzTokenFee, 400);

        // check cmdHashLookup
        assertEq(cmdHashLookup[packet.sender][cid][packet.nonce], keccak256(packet.message));
    }

    function test_revert_send_not_endpoint() public {
        Packet memory packet = newPacket(1, 1, 1, address(0xa111), "cmd");
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);
        vm.expectRevert(abi.encodeWithSelector(LZ_MessageLib_OnlyEndpoint.selector));

        vm.prank(MALICIOUS);
        this.send(packet, options, false);
    }

    function test_revert_send_invalid_receiver() public {
        Packet memory packet = newPacket(1, 1, 1, address(0xa111), "cmd");
        packet.receiver = bytes32(uint256(999)); // receiver != sender
        bytes memory options = OptionsUtil.newOptions().addExecutorLzReadOption(200000, 100, 0);
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidReceiver.selector));

        vm.prank(endpoint);
        this.send(packet, options, false);
    }

    function test_verify() public {
        bytes memory header = "header";
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");
        vm.expectEmit(true, true, true, true, address(this));
        vm.prank(address(0xd1));
        emit PayloadVerified(address(0xd1), header, cmdHash, payloadHash);
        this.verify(header, cmdHash, payloadHash);
    }

    function test_checkVerifiable_only_required_dvn() public {
        bytes32 headerHash = keccak256("header");
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xd1));
        // no one signed
        bool verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, false);

        // the required dvn signed
        hashLookup[headerHash][cmdHash][readConfig.requiredDVNs[0]] = payloadHash;

        verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, true);
    }

    function test_checkVerifiable_optional_dvn_2_threshold() public {
        bytes32 headerHash = keccak256("header");
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        address[] memory dvns = new address[](2);
        dvns[0] = address(0xd1);
        dvns[1] = address(0xd2);
        ReadLibConfig memory readConfig = ReadLibConfig(address(0xe111), 0, 2, 2, new address[](0), dvns); // 2 threshold
        // the optional dvn1 signed
        hashLookup[headerHash][cmdHash][dvns[0]] = payloadHash;

        bool verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, false); // still not enough

        // the optional dvn2 signed
        hashLookup[headerHash][cmdHash][dvns[1]] = payloadHash;

        verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, true);
    }

    function test_checkVerifiable_optional_dvn_1_threshold() public {
        bytes32 headerHash = keccak256("header");
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        address[] memory dvns = new address[](2);
        dvns[0] = address(0xd1);
        dvns[1] = address(0xd2);
        ReadLibConfig memory readConfig = ReadLibConfig(address(0xe111), 0, 2, 1, new address[](0), dvns); // 1 threshold
        // the optional dvn1 signed
        hashLookup[headerHash][cmdHash][dvns[0]] = payloadHash;

        bool verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, true); // enough

        // the optional dvn2 signed
        hashLookup[headerHash][cmdHash][dvns[1]] = payloadHash;

        verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, true);
    }

    function test_checkVerifiable_with_required_and_optional() public {
        bytes32 headerHash = keccak256("header");
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        address dvn1 = address(0xd1);
        address dvn2 = address(0xd2);
        ReadLibConfig memory readConfig = buildReadLibConfig(dvn1, dvn2);
        // the required dvn1 signed
        hashLookup[headerHash][cmdHash][dvn1] = payloadHash;

        bool verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, false); // not enough

        // the optional dvn2 signed
        hashLookup[headerHash][cmdHash][dvn2] = payloadHash;

        verified = this.verifiable(readConfig, headerHash, cmdHash, payloadHash);
        assertEq(verified, true);
    }

    function test_commitVerification() public {
        uint32 cid = 666;
        bytes memory cmd = "cmd";
        Packet memory packet = newPacket(1, cid, localEid, address(0xa111), cmd); // flip localEid and cid when receiving
        bytes memory payload = PacketV1Codec.encodePayload(packet);
        bytes memory header = PacketV1Codec.encodePacketHeader(packet);
        bytes32 headerHash = keccak256(header);
        bytes32 cmdHash = keccak256(cmd);
        bytes32 payloadHash = keccak256(payload);

        // setup cmdHashLookup
        cmdHashLookup[packet.sender][cid][packet.nonce] = cmdHash;
        // mock endpoint.verify
        vm.mockCall(address(endpoint), abi.encodeWithSelector(EndpointV2.verify.selector), abi.encode(""));
        // set default config
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xd1), address(0xd2));
        setDefaultReadLibConfigs(cid, readConfig);

        // verify by DVNs
        vm.prank(address(0xd1));
        this.verify(header, cmdHash, payloadHash);
        vm.prank(address(0xd2));
        this.verify(header, cmdHash, payloadHash);
        // check hashLookup set
        assertEq(hashLookup[headerHash][cmdHash][address(0xd1)], payloadHash);
        assertEq(hashLookup[headerHash][cmdHash][address(0xd2)], payloadHash);

        this.commitVerification(header, cmdHash, payloadHash);

        // check hashLookup cleared
        assertEq(hashLookup[headerHash][cmdHash][address(0xd1)], bytes32(0));
        assertEq(hashLookup[headerHash][cmdHash][address(0xd2)], bytes32(0));
    }

    function test_revert_commitVerification_invalid_header() public {
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidPacketHeader.selector));
        this.commitVerification("invalid header", cmdHash, payloadHash);
    }

    function test_revert_commitVerification_invalid_packet_version() public {
        bytes memory header = new bytes(81);
        bytes32 cmdHash = keccak256("cmd");
        bytes32 payloadHash = keccak256("payload");

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidPacketVersion.selector));
        this.commitVerification(header, cmdHash, payloadHash);
    }

    function test_revert_commitVerification_invalid_eid() public {
        bytes memory cmd = "cmd";
        Packet memory packet = newPacket(1, 1, localEid + 666, address(0xa111), cmd); // invalid eid
        bytes memory header = PacketV1Codec.encodePacketHeader(packet);
        bytes32 cmdHash = keccak256(cmd);
        bytes32 payloadHash = keccak256(PacketV1Codec.encodePayload(packet));

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidEid.selector));
        this.commitVerification(header, cmdHash, payloadHash);
    }

    function test_revert_commitVerification_invalid_cmdHash() public {
        bytes memory cmd = "cmd";
        Packet memory packet = newPacket(1, 1, localEid, address(0xa111), cmd);
        bytes memory header = PacketV1Codec.encodePacketHeader(packet);
        bytes32 cmdHash = keccak256(cmd);
        bytes32 payloadHash = keccak256(PacketV1Codec.encodePayload(packet));

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidCmdHash.selector));
        this.commitVerification(header, cmdHash, payloadHash);
    }

    function test_revert_commitVerification_verifying() public {
        bytes memory cmd = "cmd";
        Packet memory packet = newPacket(1, 1, localEid, address(0xa111), cmd);
        bytes memory header = PacketV1Codec.encodePacketHeader(packet);
        bytes32 cmdHash = keccak256(cmd);
        bytes32 payloadHash = keccak256(PacketV1Codec.encodePayload(packet));

        // setup cmdHashLookup
        cmdHashLookup[packet.sender][1][packet.nonce] = cmdHash;
        // set default cid config
        ReadLibConfig memory readConfig = buildReadLibConfig(address(0xd1), address(0xd2));
        setDefaultReadLibConfigs(1, readConfig);

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_Verifying.selector));
        this.commitVerification(header, cmdHash, payloadHash);
    }

    // ----- helper functions -----
    function buildReadLibConfig(address dvn) internal pure returns (ReadLibConfig memory) {
        address executor = address(0xe111);
        address[] memory dvns = new address[](1);
        dvns[0] = dvn;
        return ReadLibConfig(executor, 1, 0, 0, dvns, new address[](0));
    }

    function buildReadLibConfig(address dvn, address optionalDvn) internal pure returns (ReadLibConfig memory) {
        address executor = address(0xe111);
        address[] memory dvns = new address[](1);
        dvns[0] = dvn;
        address[] memory optionalDvns = new address[](1);
        optionalDvns[0] = optionalDvn;
        return ReadLibConfig(executor, 1, 1, 1, dvns, optionalDvns);
    }

    function buildSetConfigParam(
        uint32 dstEid,
        uint32 configType,
        ReadLibConfig memory readConfig
    ) internal pure returns (SetConfigParam[] memory) {
        bytes memory configData = abi.encode(readConfig);
        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam(dstEid, configType, configData);
        return params;
    }

    function setDefaultReadLibConfigs(uint32 dstEid, ReadLibConfig memory readConfig) internal {
        SetDefaultReadLibConfigParam[] memory setDefaultParams = new SetDefaultReadLibConfigParam[](1);
        setDefaultParams[0] = SetDefaultReadLibConfigParam(dstEid, readConfig);
        vm.prank(owner());
        this.setDefaultReadLibConfigs(setDefaultParams);
    }

    function newPacket(
        uint64 _nonce,
        uint32 _eid,
        uint32 _cid,
        address _oapp,
        bytes memory _cmd
    ) internal pure returns (Packet memory) {
        return Packet(_nonce, _eid, _oapp, _cid, bytes32(uint256(uint160(_oapp))), bytes32(0), _cmd);
    }

    // ----- wrap functions -----
    function quoteDVNs(
        ReadLibConfig memory _config,
        address _sender,
        bytes memory _pckHeader,
        bytes calldata _cmd,
        bytes memory _options
    ) public view returns (uint256) {
        return _quoteDVNs(_config, _sender, _pckHeader, _cmd, _options);
    }

    function payDVNs(
        ReadLibConfig memory _config,
        Packet calldata _packet,
        bytes memory _options
    ) public returns (uint256 totalFee, bytes memory encodedPacket) {
        return _payDVNs(_config, _packet, _options);
    }

    function payExecutor(
        address _executor,
        address _sender,
        bytes memory _executorOptions
    ) public returns (uint256 executorFee) {
        return _payExecutor(_executor, _sender, _executorOptions);
    }
}
