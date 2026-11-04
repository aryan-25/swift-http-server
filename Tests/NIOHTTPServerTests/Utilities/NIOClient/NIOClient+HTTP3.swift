//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP Server open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift HTTP Server project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP Server project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if HTTP3

import HTTP3
import Logging
import NIOCore
@_spi(HTTP3AsyncInterface) import NIOHTTP3
import NIOHTTPServer
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOPosix
import NIOQUIC

/// Opens HTTP/3 connections over a QUIC client channel.
@available(anyAppleOS 27.0, *)
struct TestHTTP3Client: Sendable {
    let quicHandler: NIOLoopBound<QUICHandler<QUICStreamChannels>>
    let logger: Logger
    let settings: HTTP3Settings
    let configuration: HTTP3ClientConfiguration
    let additionalConnectionChannelInitializer: (@Sendable (any Channel) throws -> Void)?

    /// Opens a new connection to `remoteAddress`.
    /// - Returns: The QUIC connection channel, and the HTTP/3 connection for opening request streams on it.
    func connect(
        serverName: String,
        remoteAddress: SocketAddress
    ) async throws -> (connectionChannel: any Channel, connection: HTTP3ClientConnection) {
        try await self.quicHandler.eventLoop.flatSubmit {
            // `createOutboundConnection` doesn't pass on the initializer's output, so carry it out with a promise.
            let outputPromise = self.quicHandler.eventLoop.makePromise(
                of: (connectionChannel: any Channel, connection: HTTP3ClientConnection).self
            )
            let connectionFuture = self.quicHandler.value.createOutboundConnection(
                serverName: serverName,
                remoteAddress: remoteAddress,
                connectionInitializer: { connectionChannel, streamCreator in
                    let output = connectionChannel.eventLoop.makeCompletedFuture {
                        let connection = try connectionChannel.pipeline.syncOperations
                            .configureAsyncHTTP3ClientPipeline(
                                configuration: self.configuration,
                                settings: self.settings,
                                streamCreator: streamCreator,
                                logger: self.logger
                            )
                        try self.additionalConnectionChannelInitializer?(connectionChannel)
                        return (connectionChannel: connectionChannel, connection: connection)
                    }
                    output.cascade(to: outputPromise)
                    return output.map { _ in }
                },
                inboundStreamInitializer: { streamChannel in
                    do {
                        let http3Handler = try streamChannel.parent!.pipeline.syncOperations.handler(
                            type: HTTP3ConnectionHandler<QUICStreamCreator>.self
                        )
                        return http3Handler.inboundStreamReceived(streamChannel)
                    } catch {
                        return streamChannel.eventLoop.makeFailedFuture(error)
                    }
                }
            )
            connectionFuture.cascadeFailure(to: outputPromise)
            return connectionFuture.flatMap { _ in outputPromise.futureResult }
        }.get()
    }
}

@available(anyAppleOS 27.0, *)
extension DatagramBootstrap {
    /// Sets up a test HTTP/3 client and returns the QUIC channel and a client for opening connections over it.
    func setupTestHTTP3Client(
        logger: Logger,
        trustRootsPath: String,
        quicConfiguration: QUICConfiguration,
        http3ClientConfiguration: HTTP3ClientConfiguration = .defaults,
        http3ConnectionSettings: HTTP3Settings = .init(),
        additionalConnectionChannelInitializer: (@Sendable (any Channel) throws -> Void)? = nil
    ) async throws -> (any Channel, TestHTTP3Client) {
        try await self.channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: "127.0.0.1", port: 0) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let quicHandler = QUICHandler(
                        channel: channel,
                        quicConfiguration: quicConfiguration,
                        asyncVerifier: try! .init(
                            trustRootsPath: trustRootsPath,
                            certificateVerification: .noHostnameVerification,
                            eventLoop: channel.eventLoop
                        ),
                        authenticator: nil,
                        logger: logger,
                        inboundConnectionInitializer: { _, _ in fatalError() },
                        inboundStreamInitializer: { _ in fatalError() },
                        noMoreConnections: {}
                    )
                    try channel.pipeline.syncOperations.addHandler(quicHandler)

                    let client = TestHTTP3Client(
                        quicHandler: NIOLoopBound(quicHandler, eventLoop: channel.eventLoop),
                        logger: logger,
                        settings: http3ConnectionSettings,
                        configuration: http3ClientConfiguration,
                        additionalConnectionChannelInitializer: additionalConnectionChannelInitializer
                    )

                    return (channel, client)
                }
            }
    }
}

@available(anyAppleOS 27.0, *)
extension HTTP3ClientConnection {
    /// Opens a single request stream on this connection wrapped in a `NIOAsyncChannel`. The stream is closed by the
    /// caller using `executeThenClose`.
    func makeRequestStream() async throws -> NIOAsyncChannel<HTTPResponsePart, HTTPRequestPart> {
        try await self.openStream {
            let streamChannel = $0.channel
            return streamChannel.eventLoop.makeCompletedFuture {
                try NIOAsyncChannel<HTTPResponsePart, HTTPRequestPart>(
                    wrappingChannelSynchronously: streamChannel,
                    configuration: .init(isOutboundHalfClosureEnabled: true)
                )
            }
        }
    }
}

#endif  // HTTP3
