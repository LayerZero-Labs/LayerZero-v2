// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { Test } from "forge-std/Test.sol";

import { PriceFeed } from "../contracts/PriceFeed.sol";
import { ILayerZeroPriceFeed } from "../contracts/interfaces/ILayerZeroPriceFeed.sol";

contract PriceFeedTest is Test {
    PriceFeed internal priceFeed;
    uint128 constant PRICE_RATIO_DENOMINATOR = 1e20;

    function setUp() public {
        priceFeed = new PriceFeed();
        priceFeed.initialize(address(this));
    }

    function testFuzz_estimateFeeWithDefaultModel(uint128 aptosPriceUSD, uint128 ethPriceUSD) public {
        // uint128 aptosPriceUSD = 8 * 10000; // 8 USD per APTOS(multiple 10^4), 8 decimals, eid = 1
        // uint128 ethPriceUSD = 2000 * 10000; // 2000 USD per ETH, 18 decimals, eid = 2
        vm.assume(aptosPriceUSD > 0 && aptosPriceUSD < 10000 * 10000); // aptos price lest than 10000 USD
        vm.assume(ethPriceUSD > 0 && ethPriceUSD < 1000000 * 10000); // eth price lest than 1000000 USD
        uint8 aptosDecimals = 8;
        uint16 aptosEid = 1;
        uint8 ethDecimals = 18;
        uint16 ethEid = 2;
        // aptos to eth
        uint128 priceAptos = uint128(
            (PRICE_RATIO_DENOMINATOR * ethPriceUSD * 10 ** aptosDecimals) / (aptosPriceUSD * 10 ** ethDecimals)
        );
        ILayerZeroPriceFeed.UpdatePrice[] memory updatePrices = new ILayerZeroPriceFeed.UpdatePrice[](1);
        updatePrices[0] = ILayerZeroPriceFeed.UpdatePrice(
            ethEid,
            ILayerZeroPriceFeed.Price(priceAptos, 10 * 10 ** 9, 16) // gasPrice 10Gwei, gasPerByte 16
        );
        priceFeed.setPrice(updatePrices);
        (uint256 fee, , , ) = priceFeed.estimateFeeByEid(ethEid, 1000, 30000);
        // assertEq(fee, 11500000); // 0.115 Aptos

        // eth to aptos
        uint128 priceEth = uint128(
            (PRICE_RATIO_DENOMINATOR * aptosPriceUSD * 10 ** ethDecimals) / (ethPriceUSD * 10 ** aptosDecimals)
        );
        updatePrices[0] = ILayerZeroPriceFeed.UpdatePrice(
            aptosEid,
            ILayerZeroPriceFeed.Price(priceEth, 100, 16) // Gas Unit Price 0.000001 APT, gasPerByte 16
        );
        priceFeed.setPrice(updatePrices);
        (fee, , , ) = priceFeed.estimateFeeByEid(aptosEid, 1000, 100000); // 1000 bytes, 100000 gas
        // assertEq(fee, 464000000000000); // 0.000464 ETH
    }
}
