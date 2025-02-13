import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/msglibs/simpleMsglib/smlConnection/tests/main.fc'],
}
