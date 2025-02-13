import { CompilerConfig } from '@ton/blueprint'

export const compile: CompilerConfig = {
    lang: 'func',
    targets: ['src/protocol/channel/tests/channelCommitPacket.fc'],
}
