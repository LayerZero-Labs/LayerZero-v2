import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/msglibs/simpleMsglib/smlManager/tests/permissions.fc'],
}
