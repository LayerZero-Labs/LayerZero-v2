// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { MessagingFee } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SendUln302 } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";

import { TestHelper } from "../TestHelper.sol";

contract SendUln302Mock is SendUln302 {
    // offchain packets schedule
    TestHelper public testHelper;

    constructor(
        address payable _verifyHelper,
        address _endpoint,
        uint256 _treasuryGasCap,
        uint256 _treasuryGasForFeeCap
    ) SendUln302(_endpoint, _treasuryGasCap, _treasuryGasForFeeCap) {
        testHelper = TestHelper(_verifyHelper);
    }

    function send(
        Packet calldata _packet,
        bytes calldata _options,
        bool _payInLzToken
    ) public override returns (MessagingFee memory fee, bytes memory encodedPacket) {
        (fee, encodedPacket) = super.send(_packet, _options, _payInLzToken);
        testHelper.schedulePacket(encodedPacket, _options);
    }
}
