// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import { SendLibBase, WorkerOptions, ExecutorConfig, SetDefaultExecutorConfigParam } from "../contracts/SendLibBase.sol";
import { ILayerZeroExecutor } from "../contracts/interfaces/ILayerZeroExecutor.sol";
import { ILayerZeroTreasury } from "../contracts/interfaces/ILayerZeroTreasury.sol";
import { Treasury } from "../contracts/Treasury.sol";

contract SendLibBaseTest is Test, SendLibBase {
    uint32 internal constant LOCAL_EID = 1;
    uint32 internal constant REMOTE_EID = 2;

    address private constant DEFAULT_CONFIG = address(0x0);
    address internal constant ENDPOINT = address(0x1234);
    address internal constant EXECUTOR = address(0x5678);
    uint256 internal constant OTHER_WORKER_FEE = 100;

    constructor() SendLibBase(ENDPOINT, LOCAL_EID, type(uint256).max, 0) {
        treasury = address(0xdead);
    }

    function test_setDefaultExecutorConfigs() public {
        vm.startPrank(owner());
        SetDefaultExecutorConfigParam[] memory params = new SetDefaultExecutorConfigParam[](1);

        // zero executor
        params[0] = SetDefaultExecutorConfigParam(1, ExecutorConfig(1, address(0)));
        vm.expectRevert(LZ_MessageLib_InvalidExecutor.selector);
        this.setDefaultExecutorConfigs(params);

        // zero message size
        params[0] = SetDefaultExecutorConfigParam(1, ExecutorConfig(0, EXECUTOR));
        vm.expectRevert(LZ_MessageLib_ZeroMessageSize.selector);
        this.setDefaultExecutorConfigs(params);

        // set default executor configs
        params[0] = SetDefaultExecutorConfigParam(1, ExecutorConfig(1, EXECUTOR));
        this.setDefaultExecutorConfigs(params);
        assertEq(executorConfigs[DEFAULT_CONFIG][1].maxMessageSize, 1);
        assertEq(executorConfigs[DEFAULT_CONFIG][1].executor, EXECUTOR);
    }

    function test_getExecutorConfig() public {
        // set default executor configs
        executorConfigs[DEFAULT_CONFIG][1] = ExecutorConfig(1, EXECUTOR);

        // get executor config
        ExecutorConfig memory config = this.getExecutorConfig(address(this), 1);
        assertEq(config.maxMessageSize, 1);
        assertEq(config.executor, EXECUTOR);

        // set custom executor
        executorConfigs[address(this)][1] = ExecutorConfig(2, address(1234));
        config = this.getExecutorConfig(address(this), 1);
        assertEq(config.maxMessageSize, 2);
        assertEq(config.executor, address(1234));
    }

    function test_assertMessageSize(uint256 _actual, uint256 _max) public {
        if (_actual > _max) {
            vm.expectRevert(abi.encodeWithSelector(LZ_MessageLib_InvalidMessageSize.selector, _actual, _max));
        }
        _assertMessageSize(_actual, _max);
    }

    function test_payExecutor(uint256 _fee) public {
        // mock executor.assignJob() and return the fee
        vm.mockCall(EXECUTOR, abi.encodeWithSelector(ILayerZeroExecutor.assignJob.selector), abi.encode(_fee));

        // check executor fee
        uint256 actualFee = _payExecutor(EXECUTOR, REMOTE_EID, address(this), 10, "");
        assertEq(actualFee, _fee);
        assertEq(fees[EXECUTOR], _fee); // bookkeeping
    }

    function test_payTreasury(uint256 _treasuryFee, uint256 _totalFee) public {
        vm.assume(_treasuryFee <= _totalFee);

        // mock treasury.getFee() and return the fee
        vm.mockCall(treasury, abi.encodeWithSelector(ILayerZeroTreasury.payFee.selector), abi.encode(_treasuryFee));

        // when pay treasury fee in native, nativeFee should be _treasuryFee and lzTokenFee should be 0
        (uint256 nativeFee, uint256 lzTokenFee) = _payTreasury(address(this), REMOTE_EID, _totalFee, false);
        assertEq(nativeFee, _treasuryFee);
        assertEq(lzTokenFee, 0);
        assertEq(fees[treasury], _treasuryFee); // bookkeeping
    }

    function test_quoteTreasury(uint256 _treasuryFee, uint256 _totalFee) public {
        // mock treasury.getFee() and return the fee
        vm.mockCall(treasury, abi.encodeWithSelector(ILayerZeroTreasury.getFee.selector), abi.encode(_treasuryFee));

        // pay treasury fee in lz token, the nativeFee should be 0, and lzTokenFee should be _treasuryFee
        (uint256 nativeFee, uint256 lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, _totalFee, true);
        assertEq(nativeFee, 0);
        assertEq(lzTokenFee, _treasuryFee);

        // when pay treasury fee in native, lzTokenFee should be 0
        // but the nativeFee should be the min of _treasuryFee and _totalFee
        (nativeFee, lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, _totalFee, false);
        uint256 expectedNativeFee = _treasuryFee < _totalFee ? _treasuryFee : _totalFee;
        assertEq(nativeFee, expectedNativeFee);
        assertEq(lzTokenFee, 0);
    }

    function test_quoteTreasuryRevert() public {
        // mock treasury.getFee() but revert
        vm.mockCallRevert(treasury, abi.encodeWithSelector(ILayerZeroTreasury.getFee.selector), "");

        // when fail to get treasury fee, quoteTreasuryFee should return (0, 0) instead of revert
        (uint256 nativeFee, uint256 lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, 10, false);
        assertEq(nativeFee, 0);
        assertEq(lzTokenFee, 0);
    }

    function test_quoteTreasuryEmptyReturn() public {
        // mock treasury.getFee() but no return value
        vm.mockCall(treasury, abi.encodeWithSelector(ILayerZeroTreasury.getFee.selector), "");

        (uint256 nativeFee, uint256 lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, 10, false);
        assertEq(nativeFee, 0);
        assertEq(lzTokenFee, 0);
    }

    function test_quoteTreasuryEOA() public {
        treasury = address(0x1234);

        (uint256 nativeFee, uint256 lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, 10, false);
        assertEq(nativeFee, 0);
        assertEq(lzTokenFee, 0);
    }

    //    function test_quoteTreasurySelfDestructed() public {
    //        Treasury treasuryContract = new Treasury();
    //        treasuryContract.setNativeFeeBP(1000); // 1/10
    //        treasury = address(treasuryContract);
    //
    //        (uint256 nativeFee, uint256 lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, 10, false);
    //        assertEq(nativeFee, 1);
    //        assertEq(lzTokenFee, 0);
    //
    //        // destroy treasury contract
    //        destroyAccount(address(treasuryContract), address(this));
    //
    //        (nativeFee, lzTokenFee) = _quoteTreasury(address(this), REMOTE_EID, 10, false);
    //        assertEq(nativeFee, 0);
    //        assertEq(lzTokenFee, 0);
    //    }

    function test_quote(uint256 _executorFee, uint256 _treasuryFee) public {
        vm.assume(_executorFee <= 10e10 && _treasuryFee <= 10e10 && _treasuryFee <= OTHER_WORKER_FEE + _executorFee);
        executorConfigs[DEFAULT_CONFIG][REMOTE_EID] = ExecutorConfig(1000, EXECUTOR);

        // mock executor.getFee()
        vm.mockCall(EXECUTOR, abi.encodeWithSelector(ILayerZeroExecutor.getFee.selector), abi.encode(_executorFee));

        // mock treasury.getFee()
        vm.mockCall(treasury, abi.encodeWithSelector(ILayerZeroTreasury.getFee.selector), abi.encode(_treasuryFee));

        (uint256 nativeFee, uint256 lzTokenFee) = this.quote(address(this), REMOTE_EID, 10, false, bytes("abc"));
        assertEq(nativeFee, OTHER_WORKER_FEE + _executorFee + _treasuryFee);
        assertEq(lzTokenFee, 0);
    }

    function test_debitFee(address _to, uint256 _amount, uint256 _maxAmount) public {
        vm.assume(_to != address(0x0));

        // mock that _to has _maxAmount fee
        fees[msg.sender] = _maxAmount;

        // if _amount > _maxAmount, assertAndDebitAmount should revert
        if (_amount > _maxAmount) {
            vm.expectRevert(abi.encodeWithSelector(LZ_MessageLib_InvalidAmount.selector, _amount, _maxAmount));
            _debitFee(_amount);
        } else {
            _debitFee(_amount);
            assertEq(fees[msg.sender], _maxAmount - _amount);
        }
    }

    // =================== override all abstract functions but do nothing ===================

    function _quoteVerifier(address, uint32, WorkerOptions[] memory) internal pure override returns (uint256) {
        return (OTHER_WORKER_FEE);
    }

    function _splitOptions(bytes calldata) internal pure override returns (bytes memory, WorkerOptions[] memory) {}

    function quote(
        address _sender,
        uint32 _dstEid,
        uint256 _msgSize,
        bool _payInLzToken,
        bytes calldata _options
    ) external view returns (uint256, uint256) {
        return _quote(_sender, _dstEid, _msgSize, _payInLzToken, _options);
    }
}
