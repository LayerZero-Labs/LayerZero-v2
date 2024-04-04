// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {OFTUpgradeable} from "../../contracts/oft/OFTUpgradeable.sol";
import {SendParam} from "../../contracts/oft/OFTCoreUpgradeable.sol";

contract OFTUpgradeableMock is OFTUpgradeable {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {}

    function initialize(string memory _name, string memory _symbol, address _delegate) external initializer {
        __OFT_init(_name, _symbol, _delegate);
        __Ownable_init();
        _transferOwnership(_delegate);
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    // @dev expose internal functions for testing purposes
    function debit(uint256 _amountToSendLD, uint256 _minAmountToCreditLD, uint32 _dstEid)
        public
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        return _debit(_amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function debitView(uint256 _amountToSendLD, uint256 _minAmountToCreditLD, uint32 _dstEid)
        public
        view
        returns (uint256 amountDebitedLD, uint256 amountToCreditLD)
    {
        return _debitView(_amountToSendLD, _minAmountToCreditLD, _dstEid);
    }

    function removeDust(uint256 _amountLD) public view returns (uint256 amountLD) {
        return _removeDust(_amountLD);
    }

    function toLD(uint64 _amountSD) public view returns (uint256 amountLD) {
        return _toLD(_amountSD);
    }

    function toSD(uint256 _amountLD) public view returns (uint64 amountSD) {
        return _toSD(_amountLD);
    }

    function credit(address _to, uint256 _amountToCreditLD, uint32 _srcEid) public returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountToCreditLD, _srcEid);
    }

    function buildMsgAndOptions(SendParam calldata _sendParam, uint256 _amountToCreditLD)
        public
        view
        returns (bytes memory message, bytes memory options)
    {
        return _buildMsgAndOptions(_sendParam, _amountToCreditLD);
    }
}
