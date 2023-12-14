// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IWorker {
    event SetWorkerLib(address workerLib);
    event SetPriceFeed(address priceFeed);
    event SetDefaultMultiplierBps(uint16 multiplierBps);
    event SetSupportedOptionTypes(uint32 dstEid, uint8[] optionTypes);
    event Withdraw(address lib, address to, uint256 amount);

    error NotAllowed();
    error OnlyMessageLib();
    error RoleRenouncingDisabled();

    function setPriceFeed(address _priceFeed) external;

    function priceFeed() external view returns (address);

    function setDefaultMultiplierBps(uint16 _multiplierBps) external;

    function defaultMultiplierBps() external view returns (uint16);

    function withdrawFee(address _lib, address _to, uint256 _amount) external;

    function setSupportedOptionTypes(uint32 _eid, uint8[] calldata _optionTypes) external;

    function getSupportedOptionTypes(uint32 _eid) external view returns (uint8[] memory);
}
