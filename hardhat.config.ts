import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const config: HardhatUserConfig = {
  networks: {
		mainnet: {
			url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_MAINNET!],
		},
		sepolia: {
			url: `https://eth-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_SEPOLIA!],
		},
		bsc: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_BSC || ``],
		},
		bsc_testnet: {
			url: `https://bnb-testnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_BSC_TESTNET!],
		},
		arbitrum: {
			url: `https://arb-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_ARBITRUM || ``],
		},
		arbitrum_sepolia: {
			url: `https://arb-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_ARBITRUM_SEPOLIA || ``],
		},
		base: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_BASE || ``],
		},
		base_sepolia: {
			url: `https://base-sepolia.g.alchemy.com/v2/${process.env.ALCHEMY_API_KEY}`,
			accounts: [process.env.PRIVATE_KEY_BASE_SEPOLIA || ``],
		},
		hyperliquid_testnet: {
			url: `https://rpc.hyperliquid-testnet.xyz/evm`,
			accounts: [process.env.PRIVATE_KEY_HYPERLIQUID_TESTNET || ``],
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
