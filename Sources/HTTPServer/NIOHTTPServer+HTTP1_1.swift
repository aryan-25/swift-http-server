//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP Server open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP Server project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOPosix

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServer {
    func serveInsecureHTTP1_1(
        bindTarget: NIOHTTPServerConfiguration.BindTarget,
        handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>,
        asyncChannelConfiguration: NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>.Configuration
    ) async throws {
        let serverChannel = try await self.setupHTTP1_1ServerChannel(
            bindTarget: bindTarget,
            asyncChannelConfiguration: asyncChannelConfiguration
        )

        try await _serveInsecureHTTP1_1(serverChannel: serverChannel, handler: handler)
    }

    private func setupHTTP1_1ServerChannel(
        bindTarget: NIOHTTPServerConfiguration.BindTarget,
        asyncChannelConfiguration: NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>.Configuration
    ) async throws -> NIOAsyncChannel<NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>, Never> {
        switch bindTarget.backing {
        case .hostAndPort(let host, let port):
            let serverChannel = try await ServerBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                .bind(host: host, port: port) { channel in
                    self.setupHTTP1_1ConnectionChildChannel(
                        channel: channel,
                        asyncChannelConfiguration: asyncChannelConfiguration
                    )
                }

            try self.addressBound(serverChannel.channel.localAddress)

            return serverChannel
        }
    }

    func setupHTTP1_1ConnectionChildChannel(
        channel: any Channel,
        asyncChannelConfiguration: NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>.Configuration
    ) -> EventLoopFuture<NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>> {
        channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
            try channel.pipeline.syncOperations.addHandler(HTTP1ToHTTPServerCodec(secure: false))

            return try NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>(
                wrappingChannelSynchronously: channel,
                configuration: asyncChannelConfiguration
            )
        }
    }

    private func _serveInsecureHTTP1_1(
        serverChannel: NIOAsyncChannel<NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>, Never>,
        handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>
    ) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            try await serverChannel.executeThenClose { inbound in
                for try await http1Channel in inbound {
                    group.addTask {
                        try await self.handleRequestChannel(
                            channel: http1Channel,
                            handler: handler
                        )
                    }
                }
            }
        }
    }

    func serveInsecureHTTP1_1WithTestChannel(
        testChannel: NIOAsyncTestingChannel,
        handler: some HTTPServerRequestHandler<RequestReader, ResponseWriter>
    ) async throws {
        // The server requires a NIOAsyncChannel, so we create one from the test channel
        let serverTestAsyncChannel = try await testChannel.eventLoop.submit {
            return try NIOAsyncChannel<NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>, Never>(
                wrappingChannelSynchronously: testChannel,
                configuration: .init()
            )
        }.get()

        // Trick the server into thinking it's been bound to an address so that we don't leak the listening address
        // promise. In reality, the server hasn't been bound to any address: we will manually feed in requests and
        // observe responses.
        try self.addressBound(.init(ipAddress: "127.0.0.1", port: 8000))
        _ = try await self.listeningAddress

        try await _serveInsecureHTTP1_1(serverChannel: serverTestAsyncChannel, handler: handler)
    }
}
