// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Errors } from "../contracts/libs/Errors.sol";

import { LayerZeroTest } from "./utils/LayerZeroTest.sol";
import { MessageLibMock } from "./mocks/MessageLibMock.sol";

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

contract MessageLibManagerTest is LayerZeroTest {
    address internal constant OAPP = address(0xdead);
    address internal constant DELEGATE = address(0xbeef);

    address internal msglib;
    address internal newMsglib;
    address internal invalidMsglib;

    function setUp() public override {
        super.setUp();
        msglib = address(simpleMsgLib);
        newMsglib = address(new MessageLibMock(true));
        invalidMsglib = address(new MessageLibMock(false));
    }

    function test_constructor() public {
        assertTrue(endpoint.isRegisteredLibrary(blockedLibrary));
    }

    function test_registerLibraryByNotOwner() public {
        vm.startPrank(address(0x0)); // test not owner
        vm.expectRevert("Ownable: caller is not the owner");
        endpoint.registerLibrary(newMsglib);
        assertFalse(endpoint.isRegisteredLibrary(newMsglib));
    }

    function test_registerLibrary() public {
        endpoint.registerLibrary(newMsglib);
        assertTrue(endpoint.isRegisteredLibrary(newMsglib));

        // cant register again
        vm.expectRevert(Errors.AlreadyRegistered.selector);
        endpoint.registerLibrary(newMsglib);

        // check all registered libraries
        address[] memory libs = endpoint.getRegisteredLibraries();
        assertEq(libs.length, 3);
        assertEq(libs[0], blockedLibrary);
        assertEq(libs[1], msglib);
        assertEq(libs[2], newMsglib);
    }

    function test_registerInvalidLibrary() public {
        // register an EOA and revert with an empty error message
        vm.expectRevert();
        endpoint.registerLibrary(address(0x1));

        // register a contract without the required interface
        vm.expectRevert(Errors.UnsupportedInterface.selector);
        endpoint.registerLibrary(invalidMsglib);
    }

    function test_setDefaultSendLibraryByNotOwner() public {
        vm.startPrank(address(0x0)); // not owner
        vm.expectRevert("Ownable: caller is not the owner");
        endpoint.setDefaultSendLibrary(2, msglib);
    }

    function test_setDefaultSendLibraryWithUnregisteredLib() public {
        vm.expectRevert(Errors.OnlyRegisteredLib.selector);
        endpoint.setDefaultSendLibrary(2, newMsglib);
    }

    function test_setDefaultSendLibrary() public {
        // set new default
        endpoint.setDefaultSendLibrary(2, blockedLibrary);

        address defaultSendLib = endpoint.defaultSendLibrary(2);
        assertEq(defaultSendLib, blockedLibrary);

        bool isDefault = endpoint.isDefaultSendLibrary(address(0x0), 2);
        assertEq(isDefault, true);

        // set default to the same library
        vm.expectRevert(Errors.SameValue.selector);
        endpoint.setDefaultSendLibrary(2, blockedLibrary);
    }

    function test_setDefaultSendLibraryWithInvalidEid() public {
        endpoint.registerLibrary(newMsglib);
        vm.expectRevert(Errors.UnsupportedEid.selector);
        endpoint.setDefaultSendLibrary(type(uint32).max, newMsglib);
    }

    function test_setDefaultReceiveLibraryByNotOwner() public {
        vm.startPrank(address(0x0)); // not owner
        vm.expectRevert("Ownable: caller is not the owner");
        endpoint.setDefaultReceiveLibrary(2, msglib, 0);
    }

    function test_setDefaultReceiveLibraryWithUnregisteredLib() public {
        vm.expectRevert(Errors.OnlyRegisteredLib.selector);
        endpoint.setDefaultReceiveLibrary(2, newMsglib, 0);
    }

    function test_setDefaultReceiveLibrary() public {
        // set new default
        endpoint.setDefaultReceiveLibrary(2, blockedLibrary, 0);

        address defaultReceiveLib = endpoint.defaultReceiveLibrary(2);
        assertEq(defaultReceiveLib, blockedLibrary);

        // set default to the same library
        vm.expectRevert(Errors.SameValue.selector);
        endpoint.setDefaultReceiveLibrary(2, blockedLibrary, 0);
    }

    function test_setDefaultReceiveLibraryWithInvalidEid() public {
        endpoint.registerLibrary(newMsglib);
        vm.expectRevert(Errors.UnsupportedEid.selector);
        endpoint.setDefaultReceiveLibrary(type(uint32).max, newMsglib, 0);
    }

    function test_setDefaultReceiveLibraryTimeoutByNotOwner() public {
        vm.startPrank(address(0x0)); // not owner
        vm.expectRevert("Ownable: caller is not the owner");
        endpoint.setDefaultReceiveLibraryTimeout(2, msglib, 0);
    }

    function test_setDefaultReceiveLibraryTimeoutWithUnregisteredLib() public {
        vm.expectRevert(Errors.OnlyRegisteredLib.selector);
        endpoint.setDefaultReceiveLibraryTimeout(2, newMsglib, 0);
    }

    function test_setDefaultReceiveLibraryTimeoutWithUnsupportedEid() public {
        endpoint.registerLibrary(newMsglib);
        vm.expectRevert(Errors.UnsupportedEid.selector);
        endpoint.setDefaultReceiveLibraryTimeout(type(uint32).max, newMsglib, 0);
    }

    function test_setDefaultReceiveLibraryTimeoutWithInvalidTimestamp() public {
        vm.roll(10); // set block.number to 10
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidExpiry.selector));
        endpoint.setDefaultReceiveLibraryTimeout(2, blockedLibrary, 9);
    }

    function test_setDefaultReceiveLibraryTimeout() public {
        vm.roll(10); // set block.number to 10

        // change default receive library with 1 grace period
        endpoint.setDefaultReceiveLibrary(2, blockedLibrary, 1);
        (address lastLib, uint256 expiry) = endpoint.defaultReceiveLibraryTimeout(2);
        assertEq(lastLib, msglib);
        assertEq(expiry, 10 + 1);

        // set timeout to 15 and change the timeout library
        endpoint.setDefaultReceiveLibraryTimeout(2, blockedLibrary, 15);
        (lastLib, expiry) = endpoint.defaultReceiveLibraryTimeout(2);
        assertEq(lastLib, blockedLibrary);
        assertEq(expiry, 15);

        // disable timeout
        endpoint.setDefaultReceiveLibraryTimeout(2, msglib, 0);
        (lastLib, expiry) = endpoint.defaultReceiveLibraryTimeout(2);
        assertEq(lastLib, address(0));
        assertEq(expiry, 0);
    }

    function _test_setSendLibrary(address delegate) internal {
        vm.startPrank(delegate);
        endpoint.setSendLibrary(delegate, 2, blockedLibrary);

        address sendLib = endpoint.getSendLibrary(delegate, 2);
        assertEq(sendLib, blockedLibrary);

        bool isDefault = endpoint.isDefaultSendLibrary(delegate, 2);
        assertFalse(isDefault);

        // set to the same library
        vm.expectRevert(Errors.SameValue.selector);
        endpoint.setSendLibrary(delegate, 2, blockedLibrary);

        // set to the default library
        endpoint.setSendLibrary(delegate, 2, address(0));
        sendLib = endpoint.getSendLibrary(delegate, 2);
        assertEq(sendLib, msglib);
    }

    function test_setSendLibrary() public {
        vm.startPrank(OAPP);
        endpoint.setDelegate(DELEGATE);
        _test_setSendLibrary(OAPP);
    }

    function test_setSendLibrary_delegated() public {
        vm.startPrank(DELEGATE);
        vm.expectRevert(abi.encodeWithSelector(Errors.Unauthorized.selector));
        endpoint.setSendLibrary(OAPP, 2, blockedLibrary);
        _test_setSendLibrary(DELEGATE);
    }

    function test_setSendLibraryWithUnregisteredLib() public {
        vm.startPrank(OAPP);
        vm.expectRevert(Errors.OnlyRegisteredOrDefaultLib.selector);
        endpoint.setSendLibrary(OAPP, 2, newMsglib);
    }

    function test_setSendLibraryWithInvalidEid() public {
        endpoint.registerLibrary(newMsglib);
        vm.startPrank(OAPP);
        vm.expectRevert(Errors.UnsupportedEid.selector);
        endpoint.setSendLibrary(OAPP, type(uint32).max, newMsglib);
    }

    function test_getSendLibraryWithInvalidEid() public {
        vm.expectRevert(Errors.DefaultSendLibUnavailable.selector);
        endpoint.getSendLibrary(OAPP, type(uint32).max);
    }

    function _test_setReceiveLibrary(address _delegate) internal {
        vm.startPrank(_delegate);

        // fail to set non-default library with grace period
        vm.expectRevert(Errors.OnlyNonDefaultLib.selector);
        endpoint.setReceiveLibrary(OAPP, 2, blockedLibrary, 1);

        // set non-default library
        endpoint.setReceiveLibrary(OAPP, 2, blockedLibrary, 0);
        (address receiveLib, bool isDefault) = endpoint.getReceiveLibrary(OAPP, 2);
        assertEq(receiveLib, blockedLibrary);
        assertFalse(isDefault);

        // set to the same library
        vm.expectRevert(Errors.SameValue.selector);
        endpoint.setReceiveLibrary(OAPP, 2, blockedLibrary, 0);

        // set to the default library
        endpoint.setReceiveLibrary(OAPP, 2, address(0), 0);
        receiveLib = endpoint.getSendLibrary(OAPP, 2);
        assertEq(receiveLib, msglib);
    }

    function test_setReceiveLibrary() public {
        _test_setReceiveLibrary(OAPP);
    }

    function test_setReceiveLibrary_delegated() public {
        vm.startPrank(OAPP);
        endpoint.setDelegate(DELEGATE);
        _test_setReceiveLibrary(DELEGATE);
    }

    function test_setReceiveLibrary_undelegated() public {
        vm.startPrank(OAPP);
        endpoint.setDelegate(DELEGATE);
        _test_setReceiveLibrary(OAPP);
    }

    function test_setReceiveLibrary_unauthorized() public {
        // Should revert if setDelegate not called
        vm.expectRevert();
        _test_setReceiveLibrary(DELEGATE);
    }

    function test_getReceiveLibraryWithInvalidEid() public {
        vm.expectRevert(Errors.DefaultReceiveLibUnavailable.selector);
        endpoint.getReceiveLibrary(OAPP, type(uint32).max);
    }

    function _test_setReceiveLibraryTimeout(address _delegate) public {
        vm.roll(10); // set block.number to 10
        vm.startPrank(_delegate);

        // change default receive library with 1 grace period
        endpoint.setReceiveLibrary(OAPP, 2, blockedLibrary, 0);
        endpoint.setReceiveLibrary(OAPP, 2, msglib, 1);
        (address lastLib, uint256 expiry) = endpoint.receiveLibraryTimeout(OAPP, 2);
        assertEq(lastLib, blockedLibrary);
        assertEq(expiry, 10 + 1);

        // set timeout to 15 and change the timeout library
        endpoint.setReceiveLibraryTimeout(OAPP, 2, msglib, 15);
        (lastLib, expiry) = endpoint.receiveLibraryTimeout(OAPP, 2);
        assertEq(lastLib, msglib);
        assertEq(expiry, 15);
    }

    function test_setReceiveLibraryTimeout() public {
        _test_setReceiveLibraryTimeout(OAPP);
    }

    function test_setReceiveLibraryTimeout_delegated() public {
        vm.prank(OAPP);
        endpoint.setDelegate(DELEGATE);
        _test_setReceiveLibraryTimeout(DELEGATE);
    }

    function test_setReceiveLibraryTimeout_undelegated() public {
        vm.prank(OAPP);
        endpoint.setDelegate(DELEGATE);
        _test_setReceiveLibraryTimeout(OAPP);
    }

    function test_setReceiveLibraryTimeoutWithUnregisteredLib() public {
        vm.startPrank(OAPP);
        vm.expectRevert(Errors.OnlyRegisteredLib.selector);
        endpoint.setReceiveLibraryTimeout(OAPP, 2, newMsglib, 0);
    }

    function test_setReceiveLibraryTimeoutWithInvalidEid() public {
        endpoint.registerLibrary(newMsglib);
        vm.startPrank(OAPP);
        vm.expectRevert(Errors.UnsupportedEid.selector);
        endpoint.setReceiveLibraryTimeout(OAPP, type(uint32).max, newMsglib, 0);
    }

    function test_setReceiveLibraryTimeoutWithInvalidTimestamp() public {
        vm.roll(10); // set block.number to 10
        vm.startPrank(OAPP);
        endpoint.setReceiveLibrary(OAPP, 2, blockedLibrary, 0); // change to non-default library first
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidExpiry.selector));
        endpoint.setReceiveLibraryTimeout(OAPP, 2, msglib, 9); // invalid number
    }

    function test_isValidReceiveLibraryForDefaultLibrary() public {
        // initialize the oapp inside the messageLibManager
        vm.prank(OAPP);

        // default receive library is msglib
        bool isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertTrue(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, blockedLibrary);
        assertFalse(isValid);

        // change the default receive library to blockedLibrary with 5 grace period
        // then both msglib and blockedLibrary are valid before number 15
        vm.roll(10); // set block.number to 10
        endpoint.setDefaultReceiveLibrary(2, blockedLibrary, 5);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertTrue(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, blockedLibrary);
        assertTrue(isValid);

        // after number 15, only blockedLibrary is valid
        vm.roll(15);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertFalse(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, blockedLibrary);
        assertTrue(isValid);
    }

    function test_isValidReceiveLibraryForNonDefaultLibrary() public {
        vm.roll(10); // set block.number to 10
        endpoint.registerLibrary(newMsglib); // register a new library

        // oapp set receive library to newMsglib
        // the new library is valid, but the default library is not
        vm.startPrank(OAPP);
        // initialize the oapp inside the messageLibManager
        endpoint.setReceiveLibrary(OAPP, 2, newMsglib, 0);
        bool isValid = endpoint.isValidReceiveLibrary(OAPP, 2, newMsglib);
        assertTrue(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertFalse(isValid);

        // oapp set the timeout for the msglib before number 15
        // both newMsglib and msglib are valid before number 15
        endpoint.setReceiveLibraryTimeout(OAPP, 2, msglib, 15);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, newMsglib);
        assertTrue(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertTrue(isValid);

        // after number 15, only newMsglib is valid
        vm.roll(15);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, newMsglib);
        assertTrue(isValid);
        isValid = endpoint.isValidReceiveLibrary(OAPP, 2, msglib);
        assertFalse(isValid);
    }
}
