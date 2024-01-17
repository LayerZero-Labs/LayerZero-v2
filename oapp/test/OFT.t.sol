// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { OptionsBuilder } from "../contracts/oapp/libs/OptionsBuilder.sol";

import { OFTMock } from "./mocks/OFTMock.sol";
import { MessagingFee, MessagingReceipt } from "../contracts/oft/OFTCore.sol";
import { OFTAdapterMock } from "./mocks/OFTAdapterMock.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { OFTComposerMock } from "./mocks/OFTComposerMock.sol";
import { OFTInspectorMock, IOAppMsgInspector } from "./mocks/OFTInspectorMock.sol";
import { IOAppOptionsType3, EnforcedOptionParam } from "../contracts/oapp/libs/OAppOptionsType3.sol";

import { OFTMsgCodec } from "../contracts/oft/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "../contracts/oft/libs/OFTComposeMsgCodec.sol";

import { IOFT, SendParam, OFTReceipt } from "../contracts/oft/interfaces/IOFT.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { TestHelper } from "./TestHelper.sol";

contract OFTTest is TestHelper {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint32 cEid = 3;

    OFTMock aOFT;
    OFTMock bOFT;
    OFTAdapterMock cOFTAdapter;
    ERC20Mock cERC20Mock;

    OFTInspectorMock oAppInspector;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    uint256 public initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);
        vm.deal(userC, 1000 ether);

        super.setUp();
        setUpEndpoints(3, LibraryType.UltraLightNode);

        aOFT = OFTMock(
            _deployOApp(type(OFTMock).creationCode, abi.encode("aOFT", "aOFT", address(endpoints[aEid]), address(this)))
        );

        bOFT = OFTMock(
            _deployOApp(type(OFTMock).creationCode, abi.encode("bOFT", "bOFT", address(endpoints[bEid]), address(this)))
        );

        cERC20Mock = new ERC20Mock("cToken", "cToken");
        cOFTAdapter = OFTAdapterMock(
            _deployOApp(
                type(OFTAdapterMock).creationCode,
                abi.encode(address(cERC20Mock), address(endpoints[cEid]), address(this))
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](3);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        ofts[2] = address(cOFTAdapter);
        this.wireOApps(ofts);

        // mint tokens
        aOFT.mint(userA, initialBalance);
        bOFT.mint(userB, initialBalance);
        cERC20Mock.mint(userC, initialBalance);

        // deploy a universal inspector, can be used by each oft
        oAppInspector = new OFTInspectorMock();
    }

    function test_constructor() public {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));
        assertEq(cOFTAdapter.owner(), address(this));

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);
        assertEq(IERC20(cOFTAdapter.token()).balanceOf(userC), initialBalance);

        assertEq(aOFT.token(), address(aOFT));
        assertEq(bOFT.token(), address(bOFT));
        assertEq(cOFTAdapter.token(), address(cERC20Mock));
    }

    function test_send_oft() public {
        uint256 tokensToSend = 1 ether;
        SendParam memory sendParam = SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingFee memory fee = aOFT.quoteSend(sendParam, options, false, "", "");

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userA);
        aOFT.send{ value: fee.nativeFee }(sendParam, options, fee, payable(address(this)), "", "");
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(userB), initialBalance + tokensToSend);
    }

    function test_send_oft_compose_msg() public {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        SendParam memory sendParam = SendParam(bEid, addressToBytes32(address(composer)), tokensToSend, tokensToSend);
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        MessagingFee memory fee = aOFT.quoteSend(sendParam, options, false, composeMsg, "");

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(address(composer)), 0);

        vm.prank(userA);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = aOFT.send{ value: fee.nativeFee }(
            sendParam,
            options,
            fee,
            payable(address(this)),
            composeMsg,
            ""
        );
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            aEid,
            oftReceipt.amountCreditLD,
            abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    function test_oft_compose_codec() public {
        uint64 nonce = 1;
        uint32 srcEid = 2;
        uint256 amountCreditLD = 3;
        bytes memory composeMsg = hex"1234";

        bytes memory message = OFTComposeMsgCodec.encode(
            nonce,
            srcEid,
            amountCreditLD,
            abi.encodePacked(addressToBytes32(msg.sender), composeMsg)
        );
        (uint64 nonce_, uint32 srcEid_, uint256 amountCreditLD_, bytes32 composeFrom_, bytes memory composeMsg_) = this
            .decodeOFTComposeMsgCodec(message);

        assertEq(nonce_, nonce);
        assertEq(srcEid_, srcEid);
        assertEq(amountCreditLD_, amountCreditLD);
        assertEq(composeFrom_, addressToBytes32(msg.sender));
        assertEq(composeMsg_, composeMsg);
    }

    function decodeOFTComposeMsgCodec(
        bytes calldata message
    )
        public
        pure
        returns (uint64 nonce, uint32 srcEid, uint256 amountCreditLD, bytes32 composeFrom, bytes memory composeMsg)
    {
        nonce = OFTComposeMsgCodec.nonce(message);
        srcEid = OFTComposeMsgCodec.srcEid(message);
        amountCreditLD = OFTComposeMsgCodec.amountLD(message);
        composeFrom = OFTComposeMsgCodec.composeFrom(message);
        composeMsg = OFTComposeMsgCodec.composeMsg(message);
    }

    function test_debit_slippage_removeDust() public {
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = 1.23456789 ether;
        uint32 dstEid = aEid;

        // remove the dust form the shared decimal conversion
        assertEq(aOFT.removeDust(amountToSendLD), 1.234567 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, aOFT.removeDust(amountToSendLD), minAmountToCreditLD)
        );
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function test_debit_slippage_minAmountToCreditLD() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1.00000001 ether;
        uint32 dstEid = aEid;

        vm.expectRevert(abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD));
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function test_toLD() public {
        uint64 amountSD = 1000;
        assertEq(amountSD * aOFT.decimalConversionRate(), aOFT.toLD(uint64(amountSD)));
    }

    function test_toSD() public {
        uint256 amountLD = 1000000;
        assertEq(amountLD / aOFT.decimalConversionRate(), aOFT.toSD(amountLD));
    }

    function test_oft_debit_sender() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(aOFT.balanceOf(userA), initialBalance - amountToSendLD);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function test_oft_debit_this() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        aOFT.transfer(address(aOFT), amountToSendLD);
        assertEq(aOFT.balanceOf(userA), initialBalance - amountToSendLD);
        assertEq(aOFT.balanceOf(address(aOFT)), amountToSendLD);

        // reverts if a user tries to spend the tokens via debitThis AND the minimum exceeds the balance inside contract
        vm.prank(userB);
        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1)
        );
        aOFT.debit(amountToSendLD, minAmountToCreditLD + 1, dstEid);
        assertEq(aOFT.balanceOf(address(aOFT)), amountToSendLD);

        // Someone else can spend the tokens the user sent into the contract
        vm.prank(userB);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = aOFT.debit(0, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(aOFT.balanceOf(userA), initialBalance - amountToSendLD);
        assertEq(aOFT.balanceOf(address(this)), 0);
        assertEq(aOFT.balanceOf(address(aOFT)), 0);
    }

    function test_oft_credit() public {
        uint256 amountToCreditLD = 1 ether;
        uint32 srcEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        uint256 amountReceived = aOFT.credit(userA, amountToCreditLD, srcEid);

        assertEq(aOFT.balanceOf(userA), initialBalance + amountReceived);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function test_oft_adapter_debit_sender() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = cEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);

        vm.prank(userC);
        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1)
        );
        cOFTAdapter.debitView(amountToSendLD, minAmountToCreditLD + 1, dstEid);

        vm.prank(userC);
        cERC20Mock.approve(address(cOFTAdapter), amountToSendLD);
        vm.prank(userC);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = cOFTAdapter.debit(
            amountToSendLD,
            minAmountToCreditLD,
            dstEid
        );

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);
    }

    function test_oft_adapter_debit_this() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = cEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);

        vm.prank(userC);
        cERC20Mock.transfer(address(cOFTAdapter), amountToSendLD);
        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);
        // has no tokens to send
        assertEq(cERC20Mock.balanceOf(userB), 0);

        // check outbound amount
        assertEq(cOFTAdapter.outboundAmount(), 0);

        // reverts if a user tries to spend the tokens via debitThis AND the minimum exceeds the balance inside contract
        vm.prank(userB);
        vm.expectRevert(
            abi.encodeWithSelector(IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD + 1)
        );
        cOFTAdapter.debit(0, minAmountToCreditLD + 1, dstEid);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);

        // Someone else can spend the tokens another user has sent into the contract
        vm.prank(userB);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = cOFTAdapter.debit(0, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(userB), 0);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);
        assertEq(cOFTAdapter.outboundAmount(), amountToSendLD);
    }

    function test_oft_adapter_credit() public {
        uint256 amountToCreditLD = 1 ether;
        uint32 srcEid = cEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);

        vm.prank(userC);
        cERC20Mock.transfer(address(cOFTAdapter), amountToCreditLD);
        cOFTAdapter.increaseOutboundAmount(amountToCreditLD);

        uint256 amountReceived = cOFTAdapter.credit(userB, amountToCreditLD, srcEid);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToCreditLD);
        assertEq(cERC20Mock.balanceOf(address(userB)), amountReceived);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), 0);
        assertEq(cOFTAdapter.outboundAmount(), 0);
    }

    function test_oft_adapter_debit_this_dust_remains() public {
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = 1.234567 ether;
        uint32 dstEid = aEid;

        assertEq(cERC20Mock.balanceOf(userC), initialBalance);
        assertEq(cERC20Mock.balanceOf(address(this)), 0);

        vm.prank(userC);
        cERC20Mock.transfer(address(cOFTAdapter), amountToSendLD);
        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);

        assertEq(cOFTAdapter.outboundAmount(), 0);

        // Someone else can spend the tokens the user sent into the contract
        vm.prank(userB);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) = cOFTAdapter.debit(0, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, cOFTAdapter.removeDust(amountToSendLD));
        assertEq(amountToCreditLD, amountDebitedLD);
        assertEq(cOFTAdapter.outboundAmount(), amountDebitedLD);

        assertEq(cERC20Mock.balanceOf(userC), initialBalance - amountToSendLD);
        assertEq(cERC20Mock.balanceOf(address(cOFTAdapter)), amountToSendLD);
    }

    function decodeOFTMsgCodec(
        bytes calldata message
    ) public pure returns (bool isComposed, bytes32 sendTo, uint64 amountSD, bytes memory composeMsg) {
        isComposed = OFTMsgCodec.isComposed(message);
        sendTo = OFTMsgCodec.sendTo(message);
        amountSD = OFTMsgCodec.amountSD(message);
        composeMsg = OFTMsgCodec.composeMsg(message);
    }

    function test_oft_build_msg() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        SendParam memory sendParam = SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD);
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = hex"1234";
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message, ) = aOFT.buildMsgAndOptions(sendParam, extraOptions, composeMsg, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) = this.decodeOFTMsgCodec(
            message
        );

        assertEq(isComposed_, true);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        bytes memory expectedComposeMsg = abi.encodePacked(addressToBytes32(address(this)), composeMsg);
        assertEq(composeMsg_, expectedComposeMsg);
    }

    function test_oft_build_msg_no_compose_msg() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        SendParam memory sendParam = SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD);
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = "";
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message, ) = aOFT.buildMsgAndOptions(sendParam, extraOptions, composeMsg, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) = this.decodeOFTMsgCodec(
            message
        );

        assertEq(isComposed_, false);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        assertEq(composeMsg_, "");
    }

    function test_set_enforced_options() public {
        uint32 eid = 1;

        bytes memory optionsTypeOne = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory optionsTypeTwo = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);

        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam(eid, 1, optionsTypeOne);
        enforcedOptions[1] = EnforcedOptionParam(eid, 2, optionsTypeTwo);

        aOFT.setEnforcedOptions(enforcedOptions);

        assertEq(aOFT.enforcedOptions(eid, 1), optionsTypeOne);
        assertEq(aOFT.enforcedOptions(eid, 2), optionsTypeTwo);
    }

    function test_assert_options_type3_revert() public {
        uint32 eid = 1;
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0004"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0004"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0002"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0002"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0001"); // not type 3
        vm.expectRevert(abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0001"));
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0003"); // not type 3
        aOFT.setEnforcedOptions(enforcedOptions); // doesnt revert cus option type 3
    }

    function test_combine_options() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether,
            addressToBytes32(userA)
        );

        bytes memory expectedOptions = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function test_combine_options_no_extra_options() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, "");
        assertEq(combinedOptions, expectedOptions);
    }

    function test_combine_options_no_enforced_options() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether,
            addressToBytes32(userA)
        );

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether,
            addressToBytes32(userA)
        );

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function test_oapp_inspector_inspect() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        SendParam memory sendParam = SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD);
        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = "";
        uint256 amountToCreditLD = minAmountToCreditLD;

        // doesnt revert
        (bytes memory message, ) = aOFT.buildMsgAndOptions(sendParam, extraOptions, composeMsg, amountToCreditLD);

        // deploy a universal inspector, it automatically reverts
        oAppInspector = new OFTInspectorMock();
        // set the inspector
        aOFT.setMsgInspector(address(oAppInspector));

        // does revert because inspector is set
        vm.expectRevert(abi.encodeWithSelector(IOAppMsgInspector.InspectionFailed.selector, message, extraOptions));
        (message, ) = aOFT.buildMsgAndOptions(sendParam, extraOptions, composeMsg, amountToCreditLD);
    }
}
