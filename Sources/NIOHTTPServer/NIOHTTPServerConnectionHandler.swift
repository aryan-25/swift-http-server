//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift HTTP Server open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift HTTP Server project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift HTTP Server project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A protocol for handling the lifecycle of a single ``NIOHTTPServer`` connection.
///
/// Conforming types receive each new connection as it arrives, run any
/// connection-scoped setup (loggers, metric dimensions, atomic counters), and
/// drive the request loop via
/// ``NIOHTTPServer/NIOHTTPServer/Connection/handleRequests(handler:)``. State that must
/// outlive ``handleConnection(connection:context:)`` should live in reference
/// types (classes, actors, atomics) the conformer captures or closes over —
/// the `connection` argument is consumed.
///
/// User code typically uses ``NIOHTTPServer/NIOHTTPServer/serve(connectionHandler:)-(Handler)``
/// (the protocol-based form) or ``NIOHTTPServer/NIOHTTPServer/serve(connectionHandler:)-((NIOHTTPServer.Connection,NIOHTTPServer.ConnectionContext)->Void)``
/// (the closure-based form). If only request-level work is needed, prefer
/// ``NIOHTTPServer/NIOHTTPServer/serve(handler:)``, which uses a built-in default connection handler.
@available(anyAppleOS 26.0, *)
public protocol NIOHTTPServerConnectionHandler: Sendable {
    /// Handle a single connection.
    ///
    /// - Parameters:
    ///   - connection: The active connection. The handler is expected to drive
    ///     the request loop by calling ``NIOHTTPServer/NIOHTTPServer/Connection/handleRequests(handler:)``
    ///     on it. If `handleConnection` returns without calling
    ///     `handleRequests`, the connection is dropped on scope exit, which
    ///     closes the underlying channel.
    ///   - context: Connection-scoped data. Borrowed for the duration of the
    ///     call.
    func handleConnection(
        connection: consuming sending NIOHTTPServer.Connection,
        context: NIOHTTPServer.ConnectionContext
    ) async throws
}
