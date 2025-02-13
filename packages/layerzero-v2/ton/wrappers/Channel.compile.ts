import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/channel/main.fc'],
}
