@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix
@_spi(AsyncChannel) import NIOHTTP2
import HTTPTypes
import NIOHTTPTypesHTTP1
import NIOHTTPTypesHTTP2
import NIOHTTPTypes
import NIOSSL
import X509
import Crypto
import Foundation

public struct RequestBody: AsyncSequence {
    public typealias Element = ByteBuffer

    private let iterator: NIOAsyncChannelInboundStream<HTTPTypeRequestPart>.AsyncIterator

    init(iterator: NIOAsyncChannelInboundStream<HTTPTypeRequestPart>.AsyncIterator) {
        self.iterator = iterator
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: self.iterator)
    }
}

extension RequestBody {
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = ByteBuffer

        private var iterator: NIOAsyncChannelInboundStream<HTTPTypeRequestPart>.AsyncIterator?

        init(iterator: NIOAsyncChannelInboundStream<HTTPTypeRequestPart>.AsyncIterator) {
            self.iterator = iterator
        }

        public mutating func next() async throws -> ByteBuffer? {
            switch try await self.iterator?.next() {
            case .head:
                fatalError()
            case .body(let chunk):
                return chunk
            case .end, .none:
                self.iterator = nil
                return nil
            }
        }
    }
}

public struct ResponseHeaderWriter: ~Copyable {
    private let writer: NIOAsyncChannelOutboundWriter<HTTPTypeResponsePart>

    init(writer: NIOAsyncChannelOutboundWriter<HTTPTypeResponsePart>) {
        self.writer = writer
    }

    public consuming func writeResponseHead(_ response: HTTPResponse) async throws -> ResponseBodyWriter {
        try await self.writer.write(.head(response))
        return ResponseBodyWriter(writer: self.writer)
    }
}

public struct ResponseBodyWriter: ~Copyable {
    private let writer: NIOAsyncChannelOutboundWriter<HTTPTypeResponsePart>

    
    init(writer: NIOAsyncChannelOutboundWriter<HTTPTypeResponsePart>) {
        self.writer = writer
    }

    public func writeBodyChunk(_ chunk: ByteBuffer) async throws {
        try await self.writer.write(.body(chunk))
    }

    public consuming func writeEnd(_ trailers: HTTPFields?) async throws {
        try await self.writer.write(.end(trailers))
    }
}

public protocol HTTPResponder: Sendable {
    func respond(request: HTTPRequest, body: RequestBody, responseHeaderWriter: consuming ResponseHeaderWriter) async throws
}

extension NIOHTTP2Handler.AsyncStreamMultiplexer: @unchecked Sendable where InboundStreamOutput: Sendable {} // TODO: Remove me
extension NIONegotiatedHTTPVersion: @unchecked Sendable where HTTP1Output: Sendable, HTTP2Output: Sendable {}


public final class HTTPServer<Responder: HTTPResponder>: Sendable {
    private typealias ServerChannel = NIOAsyncChannel<EventLoopFuture<NIOProtocolNegotiationResult<NIONegotiatedHTTPVersion<NIOAsyncChannel<HTTPTypeRequestPart, HTTPTypeResponsePart>, (NIOAsyncChannel<HTTP2Frame, HTTP2Frame>, NIOHTTP2Handler.AsyncStreamMultiplexer<NIOAsyncChannel<HTTPTypeRequestPart, HTTPTypeResponsePart>>)>>>, Never>
    private enum State: Sendable {
        case initial(Responder, EventLoopGroup)
        case running
        case finished
    }

    private var state: State

    public init(
        responder: Responder,
        eventLoopGroup: any EventLoopGroup // TODO: We probably want to take a universal server bootstrap here
    ) {
        self.state = .initial(responder, eventLoopGroup)
    }

    public func run() async throws {
        switch self.state {
        case .initial(let responder, let eventLoopGroup):
            let now = Date()
            let issuerKey = P256.Signing.PrivateKey()
            let issuerName = try DistinguishedName {
                CommonName("Issuer")
            }
            let leafKey = P256.Signing.PrivateKey()
            let leafName = try DistinguishedName {
                CommonName("Leaf")
            }
            let leaf = try Certificate(
                version: .v3,
                serialNumber: .init(),
                publicKey: .init(leafKey.publicKey),
                notValidBefore: now - 5000,
                notValidAfter: now + 5000,
                issuer: issuerName,
                subject: leafName,
                signatureAlgorithm: .ecdsaWithSHA256,
                extensions: try Certificate.Extensions {
                    Critical(
                        BasicConstraints.notCertificateAuthority
                    )
                },
                issuerPrivateKey: .init(issuerKey)
            )
            let certificateChain = try NIOSSLCertificate.fromPEMBytes(Array(leaf.serializeAsPEM().pemString.utf8))
            var tlsConfiguration = try TLSConfiguration.makeServerConfiguration(
                certificateChain: certificateChain.map { .certificate($0) },
                privateKey: .privateKey(.init(bytes: Array(leafKey.pemRepresentation.utf8), format: NIOSSLSerializationFormats.pem))
            )
            tlsConfiguration.applicationProtocols = NIOHTTP2SupportedALPNProtocols
            let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
            let channel = try await ServerBootstrap(group: eventLoopGroup)
                .bind(host: "127.0.0.1", port: 1995) { channel in
                    return channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext))
                        .flatMap {
                            channel.configureAsyncHTTPServerPipeline { http1ConnectionChannel in
                                http1ConnectionChannel.eventLoop.makeCompletedFuture {
                                    try http1ConnectionChannel.pipeline.syncOperations.addHandler(HTTP1ToHTTPServerCodec(secure: false))
                                    return try NIOAsyncChannel(
                                        synchronouslyWrapping: http1ConnectionChannel,
                                        configuration: .init(
                                            inboundType: HTTPTypeRequestPart.self,
                                            outboundType: HTTPTypeResponsePart.self
                                        )
                                    )
                                }
                            } http2ConnectionInitializer: { http2ConnectionChannel in
                                http2ConnectionChannel.eventLoop.makeCompletedFuture {
                                    try NIOAsyncChannel(
                                        synchronouslyWrapping: http2ConnectionChannel,
                                        configuration: .init(
                                            inboundType: HTTP2Frame.self,
                                            outboundType: HTTP2Frame.self
                                        )
                                    )
                                }
                            } http2InboundStreamInitializer: { http2StreamChannel in
                                http2StreamChannel.eventLoop.makeCompletedFuture {
                                    try http2StreamChannel.pipeline.syncOperations.addHandler(HTTP2FramePayloadToHTTPServerCodec())
                                    return try NIOAsyncChannel(
                                        synchronouslyWrapping: http2StreamChannel,
                                        configuration: .init(
                                            inboundType: HTTPTypeRequestPart.self,
                                            outboundType: HTTPTypeResponsePart.self
                                        )
                                    )
                                }
                            }
                        }
                }

            self.state = .running
            try await self.handleServerChannel(channel, responder: responder)

        case .running:
            fatalError()
        case .finished:
            fatalError()
        }
    }

    private func handleServerChannel(
        _ serverChannel: ServerChannel,
        responder: Responder
    ) async throws {
        try await withThrowingDiscardingTaskGroup { group in
            for try await connection in serverChannel.inboundStream {
                group.addTask {
                    do {
                        switch try await connection.getResult() {
                        case .http1_1(let http1Channel):
                            print("HTTP1 connection opened")
                            await self.handleHTTPRequestChannel(http1Channel, responder: responder)
                            print("HTTP1 connection closed")

                        case .http2((_, let http2Multiplexer)):
                            print("HTTP2 connection opened")
                            try await withThrowingDiscardingTaskGroup { group in
                                for try await http2StreamChannel in http2Multiplexer.inbound {
                                    print("HTTP2 stream opened")
                                    group.addTask {
                                        await self.handleHTTPRequestChannel(http2StreamChannel, responder: responder)
                                    }
                                }
                            }
                            print("HTTP2 connection closed")
                        }
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }

    private func handleHTTPRequestChannel(
        _ channel: NIOAsyncChannel<HTTPTypeRequestPart, HTTPTypeResponsePart>,
        responder: Responder
    ) async {
        do {
            var iterator = channel.inboundStream.makeAsyncIterator()
            guard case .head(let request) = try await iterator.next() else {
                fatalError()
            }

            do {
                try await responder.respond(
                    request: request,
                    body: .init(iterator: iterator),
                    responseHeaderWriter: .init(writer: channel.outboundWriter)
                )
            } catch {
                // TODO: What happens here
            }
        } catch {
            print(error)
        }
    }

}
