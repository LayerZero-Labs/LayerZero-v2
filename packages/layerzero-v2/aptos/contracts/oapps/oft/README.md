# OFT

This package provides templates for OFT. Please take the following steps to create a new OFT project:

## Select an OFT type

We provide templates for the following OFT types:

1. **OFT (FA)** - This is an OFT project using the Fungible Asset standard. It operates by burning and minting OFT
   tokens upon send and receive respectively.
2. **OFT (Coin)** - This is an OFT project using the legacy Coin standard. It operates by burning and minting OFT tokens
   upon send and receive respectively.
3. **Adapter OFT (FA)** - This is an adapter OFT project using the Fungible Asset standard. It operates by withdrawing
   and depositing OFT tokens from escrow upon receive and send respectively.
4. **Adapter OFT (Coin)** - This is an adapter OFT project using the legacy Coin standard. It operates by withdrawing
   and depositing OFT tokens from escrow upon receive and send respectively.

These are all different configurations of the same template. The handlers in these modules can be configured to
give significant flexibility in the behavior of the OFT.

## Update the OFT configuration

1. Update the constants in the configurable OFT to reflect the desired configuration.
2. If special behavior is required, update the advanced configuration in the OFT template. Please be aware that changes
   will fundamentally alter the behavior of the OFT, and these changes should be independently audited.
3. Update the `use` line (marked by a CONFIGURATION band) in `oft.move` to reflect the selected OFT implementation.

## Cleanup unused OFT Template

Of the four OFT configurable templates, only one will be retained. The other three will be deleted. The retained
template will be used to create the OFT project. Also, only one of `oft_coin.move` and `oft_fa.move` will be retained.
The other will be deleted.

1. Delete the unused templates and keep the one you want to use.
2. Delete `friend` references to the unused templates from `oft_core.move`
