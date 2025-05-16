import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Contract, ContractFactory } from "ethers";

describe("MockNFT (MyONFT721) Tests", function () {
  let myONFT721: Contract;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;
  let mockLzEndpointAddress: string;
  let mockDelegate: string;
  let contractAddress: string;
  
  const TOKEN_NAME = "Mock NFT";
  const TOKEN_SYMBOL = "MNFT";

  beforeEach(async function () {
    // Get signers
    [owner, user1, user2] = await ethers.getSigners();
    
    // Deploy a mock LZ endpoint for testing
    const MockLzEndpointFactory: ContractFactory = await ethers.getContractFactory("EndpointV2Mock");
    const mockLzEndpoint = await MockLzEndpointFactory.deploy(1, owner.address);
    mockLzEndpointAddress = await mockLzEndpoint.getAddress();
    
    // Verify the mock endpoint was deployed successfully
    const code = await ethers.provider.getCode(mockLzEndpointAddress);
    expect(code).to.not.equal("0x", "Mock LZ Endpoint not deployed");
    
    mockDelegate = await owner.getAddress();

    // Deploy the upgradeable contract using OpenZeppelin's upgrades plugin
    const MyONFT721Factory = await ethers.getContractFactory("MyONFT721") as any;
    
    // Deploy the proxy with the implementation
    myONFT721 = await upgrades.deployProxy(
      MyONFT721Factory, 
      [TOKEN_NAME, TOKEN_SYMBOL, mockLzEndpointAddress, mockDelegate],
      { initializer: 'initialize' }
    ) as unknown as Contract;
    
    // Wait for deployment to complete
    contractAddress = await myONFT721.getAddress();
  });

  describe("Initialization", function () {
    it("should initialize with correct name and symbol", async function () {
      expect(await myONFT721.name()).to.equal(TOKEN_NAME);
      expect(await myONFT721.symbol()).to.equal(TOKEN_SYMBOL);
    });

    it("should set the owner correctly", async function () {
      expect(await myONFT721.owner()).to.equal(await owner.getAddress());
    });

    it("should not allow initialization twice", async function () {
      await expect(
        myONFT721.initialize(TOKEN_NAME, TOKEN_SYMBOL, mockLzEndpointAddress, mockDelegate)
      ).to.be.revertedWithCustomError(myONFT721, "InvalidInitialization");
    });
  });

  describe("Minting functionality", function () {
    it("should mint a token to a user", async function () {
      const tokenId = 1;
      const userAddress = await user1.getAddress();
      
      await myONFT721.mint(userAddress, tokenId);
      
      expect(await myONFT721.ownerOf(tokenId)).to.equal(userAddress);
      expect(await myONFT721.balanceOf(userAddress)).to.equal(1);
    });

    it("should allow minting multiple tokens to different users", async function () {
      const user1Address = await user1.getAddress();
      const user2Address = await user2.getAddress();
      
      await myONFT721.mint(user1Address, 1);
      await myONFT721.mint(user1Address, 2);
      await myONFT721.mint(user2Address, 3);
      
      expect(await myONFT721.ownerOf(1)).to.equal(user1Address);
      expect(await myONFT721.ownerOf(2)).to.equal(user1Address);
      expect(await myONFT721.ownerOf(3)).to.equal(user2Address);
      
      expect(await myONFT721.balanceOf(user1Address)).to.equal(2);
      expect(await myONFT721.balanceOf(user2Address)).to.equal(1);
    });

    it("should not allow minting a token that already exists", async function () {
      const tokenId = 1;
      const userAddress = await user1.getAddress();
      
      await myONFT721.mint(userAddress, tokenId);
      
      await expect(
        myONFT721.mint(userAddress, tokenId)
      ).to.be.revertedWithCustomError(myONFT721, "ERC721InvalidSender");
    });
  });

  describe("Upgradeable pattern", function () {
    it("should be upgradeable to a new implementation", async function () {
      // Deploy a new implementation of MyONFT721
      const MyONFT721V2Factory = await ethers.getContractFactory("MyONFT721v2") as any;
      
      // Upgrade the proxy to point to the new implementation
      const upgradedMyONFT721 = await upgrades.upgradeProxy(
        contractAddress,
        MyONFT721V2Factory
      ) as unknown as Contract;
      
      // Verify the upgrade maintained the state
      expect(await upgradedMyONFT721.name()).to.equal(TOKEN_NAME);
      expect(await upgradedMyONFT721.symbol()).to.equal(TOKEN_SYMBOL);
      expect(await upgradedMyONFT721.owner()).to.equal(await owner.getAddress());
      
      // Mint a token with the upgraded contract
      const tokenId = 1;
      const userAddress = await user1.getAddress();
      
      await upgradedMyONFT721.mint(userAddress, tokenId);
      
      expect(await upgradedMyONFT721.ownerOf(tokenId)).to.equal(userAddress);
    });
    
    it("should maintain state after upgrade", async function () {
      // Mint some tokens before upgrade
      const user1Address = await user1.getAddress();
      const user2Address = await user2.getAddress();
      
      await myONFT721.mint(user1Address, 1);
      await myONFT721.mint(user2Address, 2);
      
      // Deploy a new implementation
      const MyONFT721V2Factory = await ethers.getContractFactory("MyONFT721v2") as any;
      
      // Upgrade the proxy
      const upgradedMyONFT721 = await upgrades.upgradeProxy(
        contractAddress,
        MyONFT721V2Factory
      ) as unknown as Contract;
      
      // Verify the state is maintained
      expect(await upgradedMyONFT721.ownerOf(1)).to.equal(user1Address);
      expect(await upgradedMyONFT721.ownerOf(2)).to.equal(user2Address);
      expect(await upgradedMyONFT721.balanceOf(user1Address)).to.equal(1);
      expect(await upgradedMyONFT721.balanceOf(user2Address)).to.equal(1);
    });

    it("should burn a token after upgrade", async function () {
      // Mint a token before upgrade
      const user1Address = await user1.getAddress();
      await myONFT721.mint(user1Address, 1);

      //verify token exists
      expect(await myONFT721.ownerOf(1)).to.equal(user1Address);
      
      // Deploy a new implementation
      const MyONFT721V2Factory = await ethers.getContractFactory("MyONFT721v2") as any;
      
      // Upgrade the proxy
      const upgradedMyONFT721 = await upgrades.upgradeProxy(
        contractAddress,
        MyONFT721V2Factory
      ) as unknown as Contract;

      //verify token exists
      expect(await myONFT721.ownerOf(1)).to.equal(user1Address);
      
      // Burn the token
      await upgradedMyONFT721.burn(1);

      expect(await upgradedMyONFT721.balanceOf(user1Address)).to.equal(0);
    });
  });
});