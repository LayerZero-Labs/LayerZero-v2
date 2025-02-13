import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/msglibs/ultralightnode/workerFeeLibs/maliciousFeeLib/main.fc'],
}
