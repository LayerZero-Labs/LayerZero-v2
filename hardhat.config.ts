import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-deploy'
import '@nomicfoundation/hardhat-ethers'
import "dotenv/config";

const PRIVATE_KEY = process.env.PRIVATE_KEY

const config: HardhatUserConfig = {
  networks: {
		mainnet: {
			url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		sepolia: {
			url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		bsc: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		bsc_testnet: {
			url: `https://bnb-testnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		arbitrum: {
			url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		arbitrum_sepolia: {
			url: `https://arb-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		base: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		base_sepolia: {
			url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [PRIVATE_KEY!],
		},
		hyperliquid_testnet: {
			url: `https://rpc.hyperliquid-testnet.xyz/evm`,
			accounts: [PRIVATE_KEY!],
		},
	},
	etherscan: {
		// Your API key for Etherscan
		// Obtain one at https://bscscan.com/
		apiKey: process.env.BSC_API_KEY,
	},
	solidity: {
		compilers: [
			{
				version: `0.8.29`,
				settings: {
					evmVersion: `shanghai`,
					viaIR: true,
					optimizer: {
						enabled: true,
						runs: 200,
						details: {
							yul: true,
						},
					},
				},
			},
		],
	},
	mocha: {
		timeout: 1000000,
		bail: true,
	},
};

export default config;
