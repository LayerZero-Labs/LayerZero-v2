import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/endpoint/tests/serde.fc'],
}
