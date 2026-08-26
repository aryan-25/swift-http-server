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

import NIOCore
import NIOExtras
import NIOHTTPTypes

#if HTTP3
@_spi(HTTP3AsyncInterface) import NIOHTTP3
import NIOQUIC
#endif

@available(anyAppleOS 26.0, *)
extension NIOHTTPServer {
    /// Abstracts over the types of server channels ``NIOHTTPServer`` can serve.
    enum ServerChannel {
        struct PlaintextHTTP1_1 {
            let socketChannel: NIOAsyncChannel<NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>, Never>
            let quiescingHelper: ServerQuiescingHelper
        }

        struct SecureUpgrade {
            let socketChannel: NIOAsyncChannel<EventLoopFuture<NegotiatedChannel>, Never>
            let quiescingHelper: ServerQuiescingHelper
        }

        case plaintextHTTP1_1(PlaintextHTTP1_1)
        case secureUpgrade(SecureUpgrade)

        #if HTTP3
        struct HTTP3 {
            let socketChannel: any Channel
            let connectionMultiplexer:
                HTTP3ServerConnectionMultiplexer<
                    NIOAsyncChannel<HTTPRequestPart, HTTPResponsePart>,
                    QUICStreamCreator
                >
        }

        case http3(HTTP3)
        #endif

        /// The channel bound to the listening socket.
        var channel: any Channel {
            switch self {
            case .plaintextHTTP1_1(let plaintext):
                plaintext.socketChannel.channel

            case .secureUpgrade(let secureUpgrade):
                secureUpgrade.socketChannel.channel

            #if HTTP3
            case .http3(let http3):
                http3.socketChannel
            #endif
            }
        }
    }
}
