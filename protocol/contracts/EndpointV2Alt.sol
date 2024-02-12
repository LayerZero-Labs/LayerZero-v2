// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { EndpointV2 } from "./EndpointV2.sol";
import { Errors } from "./libs/Errors.sol";

/// @notice this is the endpoint contract for layerzero v2 deployed on chains using ERC20 as native tokens
contract EndpointV2Alt is EndpointV2 {
    error LZ_OnlyAltToken();
    error InsufficientBalance();
    error TransferFailed();

    address internal immutable nativeErc20;

    event PaymentReceived(address indexed sender, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(uint32 _eid, address _owner, address _altToken) EndpointV2(_eid, _owner) {
        nativeErc20 = _altToken;
    }

    /// @dev handling native token payments on endpoint
    /// @dev internal function
    /// @param _required the amount required
    /// @param _supplied the amount supplied
    /// @param _receiver the receiver of the native token
    /// @param _refundAddress the address to refund the excess to
    function _payNative(
        uint256 _required,
        uint256 _supplied,
        address _receiver,
        address _refundAddress
    ) internal override {
        if (msg.value > 0) revert LZ_OnlyAltToken();
        _payToken(nativeErc20, _required, _supplied, _receiver, _refundAddress);
        emit PaymentReceived(msg.sender, _supplied);
    }

    /// @dev return the balance of the native token
    function _suppliedNative() internal view override returns (uint256) {
        return IERC20(nativeErc20).balanceOf(address(this));
    }

    /// @dev check if lzToken is set to the same address
    function setLzToken(address _lzToken) public override onlyOwner {
        if (_lzToken == nativeErc20) revert Errors.LZ_InvalidArgument();
        super.setLzToken(_lzToken);
        emit OwnershipTransferred(owner(), _lzToken);
    }

    function nativeToken() external view override returns (address) {
        return nativeErc20;
    }

    function isAuthorized(address caller) private view returns (bool) {
        return owner() == caller || /* other conditions */;
    }

    modifier onlyAuthorized() {
        require(isAuthorized(msg.sender), "Caller is not authorized");
        _;
    }

    function sensitiveOperation() public onlyAuthorized {
        // ... operation logic ...
    }

    address public implementation;

    function upgradeTo(address newImplementation) public onlyOwner {
        implementation = newImplementation;
    }

    fallback() external {
        address impl = implementation;
        require(impl != address(0));

        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr,   0, calldatasize())
            let result := delegatecall(gas(), impl, ptr, calldatasize(),   0,   0)
            let size := returndatasize()
            returndatacopy(ptr,   0, size)

            switch result
            case   0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }

    bool private stopped = false;

    modifier stopInEmergency {
        require(!stopped, "Stop in emergency mode");
        _;
    }

    modifier onlyInEmergency {
        require(stopped, "Only in emergency mode");
        _;
    }

    function toggleEmergency() external onlyOwner {
        stopped = !stopped;
    }

    function _payNative(...) internal override stopInEmergency {
        // ... existing logic ...
    }

    function batchPayments(uint256[] calldata amounts, address[] calldata receivers) external {
        require(amounts.length == receivers.length, "Array lengths must match");
        for (uint i =   0; i < amounts.length; i++) {
            _payNative(amounts[i], amounts[i], receivers[i], address(0));
        }
    }

    function _transferToken(address token, address recipient, uint256 amount) private {
        require(amount <= IERC20(token).balanceOf(address(this)), "Insufficient balance");
        bool success = IERC20(token).transfer(recipient, amount);
        require(success, "Transfer failed");
    }
}
