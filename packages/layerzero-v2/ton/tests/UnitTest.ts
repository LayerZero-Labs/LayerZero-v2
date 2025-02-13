import { Address, Cell, Contract, ContractProvider, SendMode, Sender, beginCell, contractAddress } from '@ton/core'

export interface UnitTestConfig {}

export function testCaseConfigToCell(config: UnitTestConfig): Cell {
    return beginCell().endCell()
}

export class UnitTest implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell }
    ) {}

    static createFromAddress(address: Address): UnitTest {
        return new UnitTest(address)
    }

    static createFromConfig(config: UnitTestConfig, code: Cell, workchain = 0): UnitTest {
        const data = testCaseConfigToCell(config)
        const init = { code, data }
        return new UnitTest(contractAddress(workchain, init), init)
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint): Promise<void> {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        })
    }

    async sendTest(provider: ContractProvider, via: Sender, value: bigint, testNum = 0n): Promise<void> {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            // opcode, query_id, failed_count, success_count
            body: beginCell()
                .storeUint(testNum, 32)
                .storeUint(1, 64) // query_id
                .storeUint(BigInt('0x' + via.address!.hash.toString('hex')), 256)
                .storeCoins(0)
                .storeRef(beginCell().endCell())
                .endCell(),
        })
    }

    async getTestName(provider: ContractProvider, via: Sender, testNum = 0n): Promise<string> {
        const { stack } = await provider.get('get_test_name', [{ type: 'int', value: testNum }])
        return stack.readString()
    }
}
