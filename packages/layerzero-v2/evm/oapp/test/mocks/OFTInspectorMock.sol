// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IOAppMsgInspector } from "../../contracts/oapp/interfaces/IOAppMsgInspector.sol";

contract OFTInspectorMock is IOAppMsgInspector {
    function inspect(bytes calldata _message, bytes calldata _options) external pure returns (bool) {
        revert InspectionFailed(_message, _options);
    }
}
