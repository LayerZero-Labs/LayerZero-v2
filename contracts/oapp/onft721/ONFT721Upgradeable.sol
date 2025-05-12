// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { ERC721Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import { ONFT721CoreUpgradeable } from "./ONFT721CoreUpgradeable.sol";

/**
 * @title ONFT721 Contract
 * @dev ONFT721 is an ERC-721 token that extends the functionality of the ONFT721Core contract.
 */
abstract contract ONFT721Upgradeable is ONFT721CoreUpgradeable, ERC721Upgradeable {
    struct ONFT721Storage {
        string baseTokenURI;
    }

    // keccak256(abi.encode(uint256(keccak256("primefi.layerzero.storage.onft721")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ONFT721StorageLocation = 0xa5a99e5d707b91b39b61e115bcc168c190d746f2210fdee1a2c5310845432400;

    function _getONFT721Storage() internal pure returns (ONFT721Storage storage ds) {
        assembly {
            ds.slot := ONFT721StorageLocation
        }
    }

    event BaseURISet(string baseURI);

    /**
     * @dev Constructor for the ONFT721 contract.
     * @param _name The name of the ONFT.
     * @param _symbol The symbol of the ONFT.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    function __ONFT721_init(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) internal onlyInitializing {
        __ERC721_init(_name, _symbol);
        __ONFT721Core_init(_lzEndpoint, _delegate);
    }

    /**
     * @notice Retrieves the address of the underlying ERC721 implementation (ie. this contract).
     */
    function token() external view returns (address) {
        return address(this);
    }

    function setBaseURI(string calldata _baseTokenURI) external onlyOwner {
        ONFT721Storage storage $ = _getONFT721Storage();
        $.baseTokenURI = _baseTokenURI;
        emit BaseURISet($.baseTokenURI);
    }

    function _baseURI() internal view override returns (string memory) {
        ONFT721Storage storage $ = _getONFT721Storage();
        return $.baseTokenURI;
    }

    /**
     * @notice Indicates whether the ONFT721 contract requires approval of the 'token()' to send.
     * @dev In the case of ONFT where the contract IS the token, approval is NOT required.
     * @return requiresApproval Needs approval of the underlying token implementation.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    function _debit(address _from, uint256 _tokenId, uint32 /*_dstEid*/) internal virtual override {
        if (_from != ERC721Upgradeable.ownerOf(_tokenId)) revert OnlyNFTOwner(_from, ERC721Upgradeable.ownerOf(_tokenId));
        _burn(_tokenId);
    }

    function _credit(address _to, uint256 _tokenId, uint32 /*_srcEid*/) internal virtual override {
        _mint(_to, _tokenId);
    }
}
