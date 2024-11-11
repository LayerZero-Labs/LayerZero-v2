// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { EndpointV2 } from "@layerzerolabs/lz-evm-protocol-v2/contracts/EndpointV2.sol";

import { ReadLib1002 } from "../../contracts/uln/readlib/ReadLib1002.sol";
import { Treasury } from "../../contracts/Treasury.sol";

contract ReadLib1002TreasuryTest is Test, ReadLib1002 {
    address internal constant ALICE = address(0xaaaa);
    address internal constant MALICIOUS = address(0xabcd);

    address internal constant TREASURY_DEFAULT = address(0x111111);

    constructor() ReadLib1002(address(new EndpointV2(1, address(this))), 10000, 20000) {
        treasury = TREASURY_DEFAULT;
    }

    function test_setTreasury() public {
        address newTreasury = address(0x1234);
        vm.prank(address(MALICIOUS));
        vm.expectRevert("Ownable: caller is not the owner");
        this.setTreasury(newTreasury);

        vm.prank(owner());
        this.setTreasury(newTreasury);

        (address treasury_, ) = this.getTreasuryAndNativeFeeCap();
        assertEq(treasury_, newTreasury);
    }

    function test_setTreasuryNativeFeeCap() public {
        (, uint256 feeCap) = this.getTreasuryAndNativeFeeCap();

        uint256 newNativeFeeCap = 100;
        vm.prank(address(MALICIOUS));
        vm.expectRevert("Ownable: caller is not the owner");
        this.setTreasuryNativeFeeCap(newNativeFeeCap);

        // bigger than cap
        newNativeFeeCap = feeCap + 1;
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_InvalidAmount.selector, newNativeFeeCap, feeCap));
        vm.prank(owner());
        this.setTreasuryNativeFeeCap(newNativeFeeCap);

        // smaller than cap
        newNativeFeeCap = feeCap - 1;
        vm.prank(owner());
        this.setTreasuryNativeFeeCap(newNativeFeeCap);

        (, uint256 nativeFeeCap) = this.getTreasuryAndNativeFeeCap();
        assertEq(nativeFeeCap, newNativeFeeCap);
    }

    function test_quote_no_treasury() public {
        vm.prank(owner());
        this.setTreasury(address(0));

        (uint256 nativeFee, uint256 lzFee) = this.quoteTreasury(ALICE, 1, 10000, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);

        (nativeFee, lzFee) = this.quoteTreasury(ALICE, 1, 10000, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_quote_treasury_return_unknown_data() public {
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.getFee.selector), hex"dead");

        uint256 totalNativeFee = 10000;
        (uint256 nativeFee, uint256 lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);

        (nativeFee, lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_quote_treasury_revert() public {
        vm.mockCallRevert(treasury, abi.encodeWithSelector(Treasury.getFee.selector), abi.encode("revert"));

        uint256 totalNativeFee = 10000;
        (uint256 nativeFee, uint256 lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);

        (nativeFee, lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_quote_treasury_return_big_fee() public {
        uint256 totalNativeFee = 10000;
        uint256 maxFee = totalNativeFee > treasuryNativeFeeCap ? totalNativeFee : treasuryNativeFeeCap;

        // bigger than totalNativeFee or treasuryNativeFeeCap
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.getFee.selector), abi.encode(maxFee + 1));
        (uint256 nativeFee, uint256 lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, maxFee);
        assertEq(lzFee, 0);

        // for lzFee it can be bigger than maxFee
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.getFee.selector), abi.encode(maxFee + 1));
        (nativeFee, lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, maxFee + 1);
    }

    function test_quote_success_treasury() public {
        uint256 totalNativeFee = 10000;
        uint256 treasuryFee = 100;
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.getFee.selector), abi.encode(treasuryFee));

        (uint256 nativeFee, uint256 lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, treasuryFee);
        assertEq(lzFee, 0);

        (nativeFee, lzFee) = this.quoteTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, treasuryFee);
    }

    function test_pay_no_treasury() public {
        vm.prank(owner());
        this.setTreasury(address(0));

        (uint256 nativeFee, uint256 lzFee) = this.payTreasury(ALICE, 1, 10000, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
        assertEq(fees[treasury], 0);

        (nativeFee, lzFee) = this.payTreasury(ALICE, 1, 10000, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_pay_treasury_return_unknown_data() public {
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.payFee.selector), hex"dead");

        uint256 totalNativeFee = 10000;
        (uint256 nativeFee, uint256 lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
        assertEq(fees[treasury], 0);

        (nativeFee, lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_pay_treasury_revert() public {
        vm.mockCallRevert(treasury, abi.encodeWithSelector(Treasury.payFee.selector), abi.encode("revert"));

        uint256 totalNativeFee = 10000;
        (uint256 nativeFee, uint256 lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
        assertEq(fees[treasury], 0);

        (nativeFee, lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, 0);
    }

    function test_pay_treasury_return_big_fee() public {
        uint256 totalNativeFee = 10000;
        uint256 maxFee = totalNativeFee > treasuryNativeFeeCap ? totalNativeFee : treasuryNativeFeeCap;

        // bigger than totalNativeFee or treasuryNativeFeeCap
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.payFee.selector), abi.encode(maxFee + 1));
        (uint256 nativeFee, uint256 lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, maxFee);
        assertEq(lzFee, 0);
        assertEq(fees[treasury], maxFee);

        // for lzFee it can be bigger than maxFee
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.payFee.selector), abi.encode(maxFee + 1));
        (nativeFee, lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, maxFee + 1);
    }

    function test_success_pay_treasury() public {
        uint256 totalNativeFee = 10000;
        uint256 treasuryFee = 100;
        vm.mockCall(treasury, abi.encodeWithSelector(Treasury.payFee.selector), abi.encode(treasuryFee));

        (uint256 nativeFee, uint256 lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, false);
        assertEq(nativeFee, treasuryFee);
        assertEq(lzFee, 0);
        assertEq(fees[treasury], treasuryFee);

        (nativeFee, lzFee) = this.payTreasury(ALICE, 1, totalNativeFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzFee, treasuryFee);
    }

    function test_withdraw_lzToken() public {
        address lzToken = address(0x1234);

        // revert if withdraw native alt token
        // mock endpoint.lzToken()
        vm.mockCall(address(endpoint), abi.encodeWithSelector(EndpointV2.nativeToken.selector), abi.encode(lzToken));
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_CannotWithdrawAltToken.selector));
        vm.prank(treasury);
        this.withdrawLzTokenFee(lzToken, treasury, 100);

        // clear mock
        vm.clearMockedCalls();

        // mock lzToken transfer
        vm.mockCall(lzToken, abi.encodeWithSelector(ERC20.transfer.selector), abi.encode(true));

        vm.prank(treasury);
        vm.expectEmit(true, true, true, true, address(this));
        emit LzTokenFeeWithdrawn(lzToken, treasury, 100);
        this.withdrawLzTokenFee(lzToken, treasury, 100);
    }

    function test_revert_withdraw_lzToken_not_treasury() public {
        address lzToken = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(LZ_RL_NotTreasury.selector));
        vm.prank(MALICIOUS);
        this.withdrawLzTokenFee(lzToken, MALICIOUS, 100);
    }

    function test_revert_withdraw_lzToken_nativeToken() public {
        address lzToken = address(0x1234);
        // mock endpoint nativeToken is lzToken
        vm.mockCall(address(endpoint), abi.encodeWithSelector(EndpointV2.nativeToken.selector), abi.encode(lzToken));

        vm.expectRevert(abi.encodeWithSelector(LZ_RL_CannotWithdrawAltToken.selector));
        vm.prank(treasury);
        this.withdrawLzTokenFee(lzToken, treasury, 100);
    }

    // ---- expose internal functions for testing ----
    function quoteTreasury(
        address _sender,
        uint32 _dstEid,
        uint256 _totalNativeFee,
        bool _payInLzToken
    ) public view returns (uint256 nativeFee, uint256 lzTokenFee) {
        return _quoteTreasury(_sender, _dstEid, _totalNativeFee, _payInLzToken);
    }

    function payTreasury(
        address _sender,
        uint32 _dstEid,
        uint256 _totalNativeFee,
        bool _payInLzToken
    ) public returns (uint256 treasuryNativeFee, uint256 lzTokenFee) {
        return _payTreasury(_sender, _dstEid, _totalNativeFee, _payInLzToken);
    }
}
