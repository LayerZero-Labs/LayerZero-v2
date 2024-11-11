// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { IWorker } from "../contracts/interfaces/IWorker.sol";
import { DVN } from "../contracts/uln/dvn/DVN.sol";
import { ExecuteParam } from "../contracts/uln/dvn/DVN.sol";
import { IReceiveUlnE2 } from "../contracts/uln/interfaces/IReceiveUlnE2.sol";
import { IDVN } from "../contracts/uln/interfaces/IDVN.sol";
import { IDVNFeeLib } from "../contracts/uln/interfaces/IDVNFeeLib.sol";
import { ILayerZeroDVN } from "../contracts/uln/interfaces/ILayerZeroDVN.sol";

import { Setup } from "./util/Setup.sol";
import { PacketUtil } from "./util/Packet.sol";
import { Constant } from "./util/Constant.sol";

contract DVNTest is Test {
    using BytesLib for bytes;

    bytes32 internal constant MESSAGE_LIB_ROLE = keccak256("MESSAGE_LIB_ROLE");
    bytes32 internal constant ALLOWLIST = keccak256("ALLOWLIST");
    bytes32 internal constant DENYLIST = keccak256("DENYLIST");
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event SetDstConfig(IDVN.DstConfigParam[] params);
    event AssignJob(uint32 dstEid, address oapp, uint64 confirmations, uint256 totalFee);
    event SetWorkerLib(address workerLib);
    event SetPriceFeed(address priceFeed);
    event SetDefaultMultiplierBps(uint16 multiplierBps);
    event Withdraw(address lib, address to, uint256 amount);

    Setup.FixtureV2 internal fixtureV2;
    DVN internal dvn;
    uint32 internal eid;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal charlie = address(0x3);

    function setUp() public {
        fixtureV2 = Setup.loadFixtureV2(Constant.EID_ETHEREUM);
        dvn = fixtureV2.dvn;
        eid = fixtureV2.eid;
    }

    function test_SetAdmin() public {
        bool isAdmin = dvn.hasRole(ADMIN_ROLE, alice);
        assertTrue(!isAdmin, "alice is not admin");

        dvn.grantRole(ADMIN_ROLE, alice); // address(this) is admin, so it can set others to be admin
        isAdmin = dvn.hasRole(ADMIN_ROLE, alice);
        assertTrue(isAdmin, "alice is admin");
    }

    function test_Revert_SetAdmin_NotByAdmin() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(bob),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        vm.prank(bob);
        dvn.grantRole(ADMIN_ROLE, alice); // bob is not admin, so it cannot set others to be admin
    }

    function test_AddSigner() public {
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(alice, true);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(bob, true);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(charlie, true);

        assertEq(dvn.signers(alice), true, "alice is signer");
        assertEq(dvn.signers(bob), true, "bob is signer");
        assertEq(dvn.signers(charlie), true, "charlie is signer");
    }

    function test_Revert_SetSigner_NotBySelf() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.setSigner(alice, true);
    }

    function test_SetQuorum() public {
        // add 2 signers before setting quorum
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(alice, true);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(bob, true);

        // set quorum to 2
        vm.prank(address(dvn)); // only self can set quorum
        dvn.setQuorum(2);

        assertEq(dvn.quorum(), 2, "quorum is 2");
    }

    function test_Revert_SetQuorum_NotBySelf() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.setQuorum(2);
    }

    function test_GrantRole_MessageLib() public {
        // only self can grant MessageLib role
        vm.prank(address(dvn));
        dvn.grantRole(MESSAGE_LIB_ROLE, alice);
        assertTrue(dvn.hasRole(MESSAGE_LIB_ROLE, alice), "alice has message lib role");
    }

    function test_Revert_GrantRole_MessageLib_NotBySelf() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.grantRole(MESSAGE_LIB_ROLE, alice);
    }

    function test_Revert_GrantRole_MessageLib_IfAdmin() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        dvn.grantRole(MESSAGE_LIB_ROLE, alice); // address(this) is admin
    }

    function test_GrantRevokeRole_AllowList() public {
        // only self can grant AllowList role
        vm.prank(address(dvn));
        dvn.grantRole(ALLOWLIST, alice);
        assertTrue(dvn.hasRole(ALLOWLIST, alice), "alice has AllowList role");

        uint256 allowlistSize = dvn.allowlistSize();
        assertEq(allowlistSize, 1, "allowlist size is 1");

        // only self can grant AllowList role
        vm.prank(address(dvn));
        dvn.revokeRole(ALLOWLIST, alice);
        assertTrue(!dvn.hasRole(ALLOWLIST, alice), "alice has no AllowList role");

        allowlistSize = dvn.allowlistSize();
        assertEq(allowlistSize, 0, "allowlist size is 0");
    }

    function test_Revert_GrantRevokeRole_AllowList_NotBySelf() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.grantRole(ALLOWLIST, alice);

        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.revokeRole(ALLOWLIST, alice);
    }

    function test_Revert_GrantRevokeRole_AllowList_IfAdmin() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        dvn.grantRole(ALLOWLIST, alice); // address(this) is admin

        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        dvn.revokeRole(ALLOWLIST, alice); // address(this) is admin
    }

    function test_GrantRevokeRole_DENYLIST() public {
        // only self can grant DENYLIST role
        vm.prank(address(dvn));
        dvn.grantRole(DENYLIST, alice);
        assertTrue(dvn.hasRole(DENYLIST, alice), "alice has DENYLIST role");

        // only self can grant DENYLIST role
        vm.prank(address(dvn));
        dvn.revokeRole(DENYLIST, alice);
        assertTrue(!dvn.hasRole(DENYLIST, alice), "alice has no DENYLIST role");
    }

    function test_Revert_GrantRevokeRole_DENYLIST_NotBySelf() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.grantRole(DENYLIST, alice);

        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        vm.prank(bob);
        dvn.revokeRole(DENYLIST, alice);
    }

    function test_Revert_GrantRevokeRole_DENYLIST_IfAdmin() public {
        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        dvn.grantRole(DENYLIST, alice); // address(this) is admin

        vm.expectRevert(DVN.DVN_OnlySelf.selector);
        dvn.revokeRole(DENYLIST, alice); // address(this) is admin
    }

    function test_GrantRevokeRole_ADMIN() public {
        // only admin can grant ADMIN_ROLE role
        dvn.grantRole(ADMIN_ROLE, alice);
        assertTrue(dvn.hasRole(ADMIN_ROLE, alice), "alice has ADMIN_ROLE role");

        // only admin can grant ADMIN_ROLE role
        dvn.revokeRole(ADMIN_ROLE, alice);
        assertTrue(!dvn.hasRole(ADMIN_ROLE, alice), "alice has no ADMIN_ROLE role");
    }

    function test_Revert_GrantRevokeRole_ADMIN_NotByAdmin() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(bob),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        vm.prank(bob);
        dvn.grantRole(ADMIN_ROLE, alice);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(bob),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        vm.prank(bob);
        dvn.revokeRole(ADMIN_ROLE, alice);
    }

    function test_Revert_GrantRevokeRole_ADMIN_IfSelf() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(dvn)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        vm.prank(address(dvn));
        dvn.grantRole(ADMIN_ROLE, alice);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(dvn)),
                " is missing role ",
                Strings.toHexString(uint256(ADMIN_ROLE), 32)
            )
        );
        vm.prank(address(dvn));
        dvn.revokeRole(ADMIN_ROLE, alice);
    }

    function test_Revert_GrantRevokeRole_UnknownRole() public {
        bytes32 unknownRole = bytes32(uint256(123));
        vm.expectRevert(abi.encodeWithSelector(DVN.DVN_InvalidRole.selector, unknownRole));
        dvn.grantRole(unknownRole, alice);

        vm.expectRevert(abi.encodeWithSelector(DVN.DVN_InvalidRole.selector, unknownRole));
        dvn.revokeRole(unknownRole, alice);
    }

    function test_SetDstConfig() public {
        IDVN.DstConfigParam[] memory params = new IDVN.DstConfigParam[](1);
        params[0] = IDVN.DstConfigParam(1, 1, 1, 1);
        vm.expectEmit(true, false, false, true);
        emit SetDstConfig(params);
        dvn.setDstConfig(params);
    }

    function test_Revert_SetDstConfig_NotByAdmin() public {
        IDVN.DstConfigParam[] memory params = new IDVN.DstConfigParam[](1);
        params[0] = IDVN.DstConfigParam(1, 1, 1, 1);
        // not admin
        vm.expectRevert();
        vm.prank(bob);
        dvn.setDstConfig(params);
    }

    function test_QuorumChangeAdmin() public {
        // add signer first
        address signer = vm.addr(1);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(signer, true);

        bool isAdmin = dvn.hasRole(ADMIN_ROLE, alice);
        assertTrue(!isAdmin, "alice is not admin");

        bytes memory data = abi.encode(alice);
        bytes memory signatures;
        {
            bytes32 hash = dvn.hashCallData(eid, address(dvn), data, 1000);
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // sign by signer
            signatures = abi.encodePacked(r, s, v);
        }
        dvn.quorumChangeAdmin(ExecuteParam(eid, address(dvn), data, 1000, signatures));

        isAdmin = dvn.hasRole(ADMIN_ROLE, alice);
        assertTrue(isAdmin, "alice is admin");
    }

    function test_Revert_QuorumChangeAdmin_Expired() public {
        // add signer first
        address signer = vm.addr(1);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(signer, true);

        bytes memory data = abi.encode(alice);
        bytes memory signatures;
        {
            bytes32 hash = dvn.hashCallData(eid, address(dvn), data, 0);
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // sign by signer
            signatures = abi.encodePacked(r, s, v);
        }
        vm.expectRevert(DVN.DVN_InstructionExpired.selector);
        dvn.quorumChangeAdmin(ExecuteParam(eid, address(dvn), data, 0, signatures));
    }

    function test_Revert_QuorumChangeAdmin_InvalidVid() public {
        // add signer first
        address signer = vm.addr(1);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(signer, true);

        uint32 invalidVid = 123;
        bytes memory data = abi.encode(alice);
        bytes memory signatures;
        {
            bytes32 hash = dvn.hashCallData(invalidVid, address(dvn), data, 1000);
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // sign by signer
            signatures = abi.encodePacked(r, s, v);
        }
        vm.expectRevert(abi.encodeWithSelector(DVN.DVN_InvalidVid.selector, invalidVid));
        dvn.quorumChangeAdmin(ExecuteParam(invalidVid, address(dvn), data, 1000, signatures));
    }

    function test_Revert_QuorumChangeAdmin_InvalidTarget() public {
        // add signer first
        address signer = vm.addr(1);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(signer, true);

        address invalidTarget = address(this);
        bytes memory data = abi.encode(alice);
        bytes memory signatures;
        {
            bytes32 hash = dvn.hashCallData(eid, invalidTarget, data, 1000);
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // sign by signer
            signatures = abi.encodePacked(r, s, v);
        }
        vm.expectRevert(abi.encodeWithSelector(DVN.DVN_InvalidTarget.selector, invalidTarget));
        dvn.quorumChangeAdmin(ExecuteParam(eid, invalidTarget, data, 1000, signatures));
    }

    function test_Execute() public {
        // add signer first
        address signer = vm.addr(1);
        vm.prank(address(dvn)); // only self can set signer
        dvn.setSigner(signer, true);

        bytes memory data = abi.encodeWithSelector(DVN.setSigner.selector, alice, true); // proposal: set alice as signer
        bytes memory signatures;
        {
            bytes32 hash = dvn.hashCallData(eid, address(dvn), data, 1000);
            bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash); // sign by signer
            signatures = abi.encodePacked(r, s, v);
        }
        ExecuteParam[] memory params = new ExecuteParam[](1);
        params[0] = ExecuteParam(eid, address(dvn), data, 1000, signatures);
        dvn.execute(params);

        assertEq(dvn.signers(alice), true, "alice is signer");
    }

    function test_Revert_Execute_NotByAdmin() public {
        ExecuteParam[] memory params = new ExecuteParam[](1);
        params[0] = ExecuteParam(eid, address(dvn), "", 1000, "");
        // not admin
        vm.expectRevert();
        vm.prank(bob);
        dvn.execute(params);
    }

    function test_Revert_AssignJob_NotByMessageLib() public {
        vm.expectRevert();
        dvn.assignJob(ILayerZeroDVN.AssignJobParam(0, "", "", 0, address(0)), "");
    }

    function test_Revert_AssignJob_UlnV2_NotByMessageLib() public {
        vm.expectRevert();
        dvn.assignJob(0, 0, 0, address(0));
    }

    function test_Revert_AssignJob_NotAcl_Denied() public {
        // set deniedSender to denylist
        address deniedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(DENYLIST, deniedSender);

        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        vm.prank(address(fixtureV2.sendUln302));
        dvn.assignJob(ILayerZeroDVN.AssignJobParam(0, "", "", 0, deniedSender), "");
    }

    function test_Revert_AssignJob_NotAcl_NotInAllowList() public {
        // set allowed sender to allowlist
        address allowedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(ALLOWLIST, allowedSender);

        address sender = address(2);
        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        vm.prank(address(fixtureV2.sendUln302));
        dvn.assignJob(ILayerZeroDVN.AssignJobParam(0, "", "", 0, sender), "");
    }

    function test_Revert_AssignJob_Read_NotByMessageLib() public {
        vm.expectRevert();
        dvn.assignJob(address(1), "", "", "");
    }

    function test_Revert_AssignJob_Read_NotAcl_Denied() public {
        // set deniedSender to denylist
        address deniedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(DENYLIST, deniedSender);

        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        vm.prank(address(fixtureV2.sendUln302));
        dvn.assignJob(deniedSender, "", "", "");
    }

    function test_Revert_AssignJob_Read_NotAcl_NotInAllowList() public {
        // set allowed sender to allowlist
        address allowedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(ALLOWLIST, allowedSender);

        address sender = address(2);
        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        vm.prank(address(fixtureV2.sendUln302));
        dvn.assignJob(sender, "", "", "");
    }

    function test_GetFee() public {
        // mock feeLib getFee
        address workerFeeLib = dvn.workerFeeLib();
        string memory sig = "getFee((address,uint32,uint64,address,uint64,uint16),(uint64,uint16,uint128),bytes)";
        vm.mockCall(workerFeeLib, abi.encodeWithSignature(sig), abi.encode(100));
        assertEq(dvn.getFee(0, 0, address(0), ""), 100, "fee is mocked by 100");
    }

    function test_GetFee_UlnV2() public {
        // mock feeLib getFee
        address workerFeeLib = dvn.workerFeeLib();
        string memory sig = "getFee((address,uint32,uint64,address,uint64,uint16),(uint64,uint16,uint128),bytes)";
        vm.mockCall(workerFeeLib, abi.encodeWithSignature(sig), abi.encode(100));
        assertEq(dvn.getFee(0, 0, 0, address(0)), 100, "fee is mocked by 100");
    }

    function test_Revert_GetFee_NotAcl_Denied() public {
        // set deniedSender to denylist
        address deniedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(DENYLIST, deniedSender);

        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        dvn.getFee(0, 0, deniedSender, "");
    }

    function test_Revert_GetFee_NotAcl_NotInAllowList() public {
        // set allowed sender to allowlist
        address allowedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(ALLOWLIST, allowedSender);

        address sender = address(2);
        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        dvn.getFee(0, 0, sender, "");
    }

    function test_GetFee_Read() public {
        // mock feeLib getFee for Read
        address workerFeeLib = dvn.workerFeeLib();
        string memory sig = "getFee((address,address,uint64,uint16),(uint64,uint16,uint128),bytes,bytes)";
        vm.mockCall(workerFeeLib, abi.encodeWithSignature(sig), abi.encode(100));
        assertEq(dvn.getFee(address(0), "", "", ""), 100, "fee is mocked by 100");
    }

    function test_Revert_GetFee_Read_NotAcl_Denied() public {
        // set deniedSender to denylist
        address deniedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(DENYLIST, deniedSender);

        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        dvn.getFee(deniedSender, "", "", "");
    }

    function test_Revert_GetFee_Read_NotAcl_NotInAllowList() public {
        // set allowed sender to allowlist
        address allowedSender = address(1);
        vm.prank(address(dvn));
        dvn.grantRole(ALLOWLIST, allowedSender);

        address sender = address(2);
        vm.expectRevert(IWorker.Worker_NotAllowed.selector);
        dvn.getFee(sender, "", "", "");
    }

    function test_WithdrawFee() public {
        // mock
        vm.mockCall(
            address(fixtureV2.sendUln302),
            abi.encodeWithSelector(fixtureV2.sendUln302.withdrawFee.selector),
            ""
        );
        vm.expectEmit(true, false, false, true);
        emit Withdraw(address(fixtureV2.sendUln302), address(1), 100);
        dvn.withdrawFee(address(fixtureV2.sendUln302), address(1), 100);
    }

    function test_Revert_WithdrawFee_NotByAdmin() public {
        vm.expectRevert();
        vm.prank(bob);
        dvn.withdrawFee(address(0), address(0), 0);
    }

    function test_Revert_WithdrawFee_NotUlnLib() public {
        address unknownUlnLib = address(1);
        vm.expectRevert(IWorker.Worker_OnlyMessageLib.selector);
        dvn.withdrawFee(unknownUlnLib, address(1), 0);
    }

    function test_SetPriceFeed() public {
        vm.expectEmit(true, false, false, true);
        emit SetPriceFeed(address(1));
        dvn.setPriceFeed(address(1));
    }

    function test_Revert_SetPriceFeed_NotByAdmin() public {
        vm.expectRevert();
        vm.prank(bob);
        dvn.setPriceFeed(address(1));
    }

    function test_SetWorkerFeeLib() public {
        vm.expectEmit(true, false, false, true);
        emit SetWorkerLib(address(1));
        dvn.setWorkerFeeLib(address(1));
    }

    function test_Revert_SetWorkerFeeLib_NotByAdmin() public {
        vm.expectRevert();
        vm.prank(bob);
        dvn.setWorkerFeeLib(address(1));
    }

    function test_SetDefaultMultiplierBps() public {
        vm.expectEmit(true, false, false, true);
        emit SetDefaultMultiplierBps(100);
        dvn.setDefaultMultiplierBps(100);
    }

    function test_Revert_SetDefaultMultiplierBps_NotByAdmin() public {
        vm.expectRevert();
        vm.prank(bob);
        dvn.setDefaultMultiplierBps(100);
    }
}
