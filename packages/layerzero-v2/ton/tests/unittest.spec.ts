import assert from 'assert'

import { Cell, toNano } from '@ton/core'
import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox'

import { UnitTest } from './UnitTest'
import { globalTestResults } from './globalTestResults'

import '@ton/test-utils'

function getTestSummary(testName: string, testCases: { [key: string]: boolean }): string {
    const passedTests = Object.keys(testCases).filter((test) => testCases[test])
    const failedTests = Object.keys(testCases).filter((test) => !testCases[test])

    let printStr = testName + '\n'
    if (passedTests.length > 0) {
        printStr += `\x1b[32m ✓ ${passedTests.length} tests passed.\n`
    }

    if (failedTests.length > 0) {
        printStr += `\x1b[31m ❌ ${failedTests.length} tests failed:\n`
        failedTests.forEach((test) => {
            printStr += `  - ${test}\n`
        })
    }
    return printStr
}

export const runUnitTests = (testName: string, contractName: string): void => {
    describe(testName, () => {
        let code: Cell

        beforeAll(() => {
            const { hex } = require(`../build/${contractName}.compiled.json`) as { hex: string }
            assert(typeof hex === 'string', `Invalid artifact for ${contractName}`)

            code = Cell.fromHex(hex)
        })

        let blockchain: Blockchain
        let testCase: SandboxContract<UnitTest>
        let deployer: SandboxContract<TreasuryContract>

        beforeEach(async () => {
            blockchain = await Blockchain.create()

            testCase = blockchain.openContract(UnitTest.createFromConfig({}, code))

            deployer = await blockchain.treasury('deployer')

            const deployResult = await testCase.sendDeploy(deployer.getSender(), toNano('1'))

            expect(deployResult.transactions).toHaveTransaction({
                from: deployer.address,
                to: testCase.address,
                deploy: true,
                success: true,
            })
        })

        it(testName, async () => {
            let done = false
            const test_results: { [key: string]: boolean } = {}
            for (let testNum = 0n; !done; testNum++) {
                // the check is done inside beforeEach
                // blockchain and testCase are ready to use
                const result = await testCase.sendTest(deployer.getSender(), toNano('10000'), testNum)
                // search the json stringified result for the string "unhandled out-of-gas exception"
                const txns = result.transactions

                let unhandledException = false
                // starting from -1 because the first one is the external message from wallet to contract
                txns.forEach((item) => {
                    if (item.vmLogs.toString().includes('unhandled out-of-gas exception')) {
                        console.log(`Test number ${testNum} OUT OF GAS`)
                    }
                    if (item.vmLogs.toString().includes('default exception handler')) {
                        console.error(`Unhandled exception in ${testName} test ${testNum}`)
                        unhandledException = true
                    }
                })

                done = result.externals.some((item) => {
                    const event_topic = item.info.dest?.value
                    if (event_topic == 1n) {
                        return true
                    }
                    return false
                })
                if (!done) {
                    const contractTestName = await testCase.getTestName(deployer.getSender(), testNum)
                    let success = true
                    result.events.forEach((item) => {
                        // TODO fix this
                        // @ts-expect-error type mismatch
                        if (item.bounced as boolean) {
                            success = false
                        }
                    })
                    if (contractTestName in test_results) {
                        throw new Error(`Duplicate test name ${contractTestName}`)
                    }
                    // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
                    test_results[contractTestName] = success && !unhandledException
                    globalTestResults[testName] = test_results
                    expect(success)
                }
            }
        })
    })
}

// Library tests
runUnitTests('Msglib Packet Codec', 'MsglibPacketCodec.test')
runUnitTests('LZ Classes', 'LzClasses.test')
runUnitTests('LZ Classes Serde', 'LzClassesSerde.test')
runUnitTests('Uln Send Config', 'UlnSendConfig.test')
runUnitTests('Uln Receive Config', 'UlnReceiveConfig.test')
runUnitTests('MsgData', 'MsgData.test')
runUnitTests('MsgData Serde', 'MsgDataSerde.test')
runUnitTests('LZ Test Utils', 'LzUtil.test')
runUnitTests('Base Contract', 'BaseContract.test')
runUnitTests('Classlib', 'Classlib.test')
runUnitTests('Pipelined Out-of-Order', 'PipelinedOutOfOrder.test')
runUnitTests('Pipelined Out-of-Order Serde', 'PipelinedOutOfOrderSerde.test')
runUnitTests('Txn Context', 'TxnContext.test')

// Endpoint tests
runUnitTests('Controller', 'Controller.test')
runUnitTests('Actions Serde', 'ActionsSerde.test')
runUnitTests('Controller Permissions', 'Controller.permissions.test')
runUnitTests('Controller Assertions', 'Controller.assertions.test')
runUnitTests('Endpoint', 'Endpoint.test')
runUnitTests('Endpoint Permissions', 'Endpoint.permissions.test')
runUnitTests('Endpoint SetEpConfigDefaults', 'EndpointSetEpConfigDefaults.test')
runUnitTests('Endpoint Serde', 'EndpointSerde.test')
runUnitTests('Channel Send', 'ChannelSend.test')
runUnitTests('Channel Serde', 'ChannelSerde.test')
runUnitTests('Channel Msglib Send Callback', 'ChannelMsglibSendCallback.test')
runUnitTests('Channel Receive', 'ChannelReceive.test')
runUnitTests('Channel Receive Lz Receive Callback', 'ChannelReceiveCallback.test')
runUnitTests('Channel CommitPacket', 'ChannelCommitPacket.test')
runUnitTests('Channel Receive View', 'ChannelReceiveView.test')
runUnitTests('Channel Burn', 'ChannelBurn.test')
runUnitTests('Channel Burn Default Config', 'ChannelBurnDefaultConfig.test')
runUnitTests('Channel Initialize', 'ChannelInitialize.test')
runUnitTests('Channel Nilify', 'ChannelNilify.test')
runUnitTests('Channel Nilify Default Config', 'ChannelNilifyDefaultConfig.test')
runUnitTests('Channel Msglib Integration', 'ChannelMsglibIntegration.test')
runUnitTests('Channel Config', 'ChannelConfig.test')
runUnitTests('Channel Permissions', 'Channel.permissions.test')

// // OApp tests
// // runUnitTests('Counter', 'Counter.test')
// // runUnitTests('Counter Permissions', 'Counter.permissions.test')
// // runUnitTests('Counter Setters', 'Counter.setters.test')

// Msglib Tests
// Simple Msglib tests
// runUnitTests('SML Manager', 'SmlManager.test')
// runUnitTests('SML Manager Permissions', 'SmlManager.permissions.test')
// runUnitTests('SML Connection', 'SmlConnection.test')
// runUnitTests('SML Connection Permissions', 'SmlConnection.permissions.test')

// UltralightNode tests
runUnitTests('ULN MsgData Serde', 'UlnMsgDataSerde.test')
runUnitTests('ULN Manager', 'UlnManager.test')
runUnitTests('ULN Manager Permissions', 'UlnManagerPermissions.test')
runUnitTests('ULN Manager Util', 'UlnManagerUtil.test')
runUnitTests('ULN', 'Uln.test')
runUnitTests('ULN Permissions', 'UlnPermissions.test')
runUnitTests('ULN Management', 'UlnManagement.test')
runUnitTests('ULN Util', 'UlnUtil.test')
runUnitTests('ULN Serde', 'UlnSerde.test')
runUnitTests('ULN Send With Mock Fee Lib', 'UlnSend.test')
runUnitTests('ULN Send With Default Executor Fee Lib', 'UlnSendWithDefaultExecFeeLib.test')
runUnitTests('ULN Send With Arbitrum Executor Fee Lib', 'UlnSendWithArbExecFeeLib.test')
runUnitTests('ULN Send With Optimism Executor Fee Lib', 'UlnSendWithOpExecFeeLib.test')
runUnitTests('ULN Send With Arbitrum Dvn Fee Lib', 'UlnSendWithArbDvnFeeLib.test')
runUnitTests('ULN Send With Optimism Dvn Fee Lib', 'UlnSendWithOpDvnFeeLib.test')
runUnitTests('ULN Send With Default Dvn Fee Lib', 'UlnSendWithDefaultDvnFeeLib.test')
runUnitTests('ULN Send With Malicious Fee Lib 1', 'badFeeLib1.test')
runUnitTests('ULN Send With Malicious Fee Lib 2', 'badFeeLib2.test')
runUnitTests('ULN Send With Malicious Fee Lib 3', 'badFeeLib3.test')
runUnitTests('ULN Send With Malicious Fee Lib 4', 'badFeeLib4.test')
runUnitTests('ULN Send With Malicious Fee Lib 5', 'badFeeLib5.test')
runUnitTests('ULN Send With Malicious Fee Lib 6', 'badFeeLib6.test')
runUnitTests('ULN Send With Malicious Fee Lib 7', 'badFeeLib7.test')
runUnitTests('ULN Send With Malicious Fee Lib 8', 'badFeeLib8.test')
runUnitTests('ULN Send With Malicious Fee Lib 9', 'badFeeLib9.test')
runUnitTests('ULN Send With Malicious Fee Lib 10', 'badFeeLib10.test')
runUnitTests('ULN Send With Malicious Fee Lib 11', 'badFeeLib11.test')
runUnitTests('ULN Send With Malicious Fee Lib 12', 'badFeeLib12.test')
runUnitTests('ULN Connection', 'UlnConnection.test')
runUnitTests('ULN Connection Serde', 'UlnConnectionSerde.test')
runUnitTests('ULN Connection Permissions', 'UlnConnectionPermissions.test')
runUnitTests('ULN Send Worker Factory', 'UlnSendWorkerFactory.test')

// priceFeed Cache tests
runUnitTests('priceFeed Cache', 'PriceFeedCache.test')
runUnitTests('priceFeed Cache serde', 'PriceFeedCacheSerde.test')
runUnitTests('priceFeed Cache Permissions', 'PriceFeedCache.test.permissions')

// Proxy tests
runUnitTests('Proxy', 'Proxy.test')
runUnitTests('Proxy Permissions', 'Proxy.permissions.test')

// Worker tests
runUnitTests('Worker Core', 'WorkerCore.test')
runUnitTests('Worker Core Serde', 'WorkerCoreSerde.test')
runUnitTests('Worker Core MsgData Serde', 'WorkerCoreMsgDataSerde.test')

runUnitTests('Executor', 'Executor.test')
runUnitTests('Executor Permissions', 'ExecutorPermissions.test')
runUnitTests('Executor Serde', 'ExecutorSerde.test')
runUnitTests('Dvn', 'Dvn.test')
runUnitTests('Dvn Permissions', 'DvnPermissions.test')
runUnitTests('Dvn Serde', 'DvnSerde.test')

runUnitTests('PriceFeedFeeLib serde', 'PriceFeedFeeLibSerde.test')
runUnitTests('ExecutorFeeLib serde', 'ExecutorFeeLibSerde.test')
runUnitTests('DvnFeeLib serde', 'DvnFeeLibSerde.test')

// todo: make this look nicer
afterAll(() => {
    let printString = ''
    for (const testName in globalTestResults) {
        printString += '\x1b[0m' + getTestSummary(testName, globalTestResults[testName])
    }
    console.log(printString)
})
