// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { OAppOptionsType3 } from "../../../contracts/oapp/libs/OAppOptionsType3.sol";
import { EnforcedOptionParam } from "../../../contracts/oapp/interfaces/IOAppOptionsType3.sol";

contract OptionsType3Mock is OAppOptionsType3 {
    constructor(bytes memory options, bool applyEnforcedOptions) {
        if (applyEnforcedOptions) {
            EnforcedOptionParam[] memory params = new EnforcedOptionParam[](1);
            params[0] = EnforcedOptionParam(1, 1, options);
            _setEnforcedOptions(params); // ensure enforced options can be set in the constructor
        }
    }

    function assertOptionsType3(bytes calldata options) public pure {
        _assertOptionsType3(options);
    }
}
