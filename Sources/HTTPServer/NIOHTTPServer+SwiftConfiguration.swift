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

public import Configuration
import NIOCertificateReloading
import SwiftASN1
public import X509

enum NIOHTTPServerConfigurationError: Error, CustomStringConvertible {
    case customVerificationCallbackProvidedWhenNotUsingMTLS

    var description: String {
        switch self {
        case .customVerificationCallbackProvidedWhenNotUsingMTLS:
            "Invalid configuration. A custom certificate verification callback was provided despite the server not being configured for mTLS."
        }
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration {
    /// Initialize the server configuration from a config reader.
    ///
    /// ## Configuration keys:
    ///
    /// All configuration keys are scoped under the `"httpServer"` key, which should have four sub-keys: `"bindTarget"`,
    /// `"transportSecurity"`, `"backpressureStrategy"`, and `"http2"`.
    ///
    /// ### Configuration keys for `"bindTarget"`:
    /// - `host` (string, required): The hostname or IP address the server will bind to (e.g., "localhost", "0.0.0.0").
    /// - `port` (int, required): The port number the server will listen on (e.g., 8080, 443).
    ///
    /// ### Configuration keys for `"transportSecurity"`:
    /// - `security` (string, required): The transport security for the server (permitted values: `"plaintext"`,
    ///   `"tls"`, `"reloadingTLS"`, `"mTLS"`, `"reloadingMTLS"`).
    ///
    /// #### Configuration keys for `"tls"`:
    /// - `certificateChainPEMString` (string, required): PEM-formatted certificate chain content.
    /// - `privateKeyPEMString` (string, required, secret): PEM-formatted private key content.
    ///
    /// #### Configuration keys for `"reloadingTLS"`:
    /// - `refreshInterval` (int, optional, default: 30): The interval (in seconds) at which the certificate chain and
    ///    private key will be reloaded.
    /// - `certificateChainPEMPath` (string, required): Path to the certificate chain PEM file.
    /// - `privateKeyPEMPath` (string, required): Path to the private key PEM file.
    ///
    /// #### Configuration keys for `"mTLS"`:
    /// - `certificateChainPEMString` (string, required): PEM-formatted certificate chain content.
    /// - `privateKeyPEMString` (string, required, secret): PEM-formatted private key content.
    /// - `trustRoots` (string array, optional, default: system trust roots):  The root certificates to trust when
    ///    verifying client certificates.
    /// - `certificateVerificationMode` (string, required): The client certificate validation behavior (permitted
    ///    values: "optionalVerification" or "noHostnameVerification").
    ///
    /// #### Configuration keys for `"reloadingMTLS"`:
    /// - `refreshInterval` (int, optional, default: 30): The interval (in seconds) at which the certificate chain and
    ///    private key will be reloaded.
    /// - `certificateChainPEMPath` (string, required): Path to the certificate chain PEM file.
    /// - `privateKeyPEMPath` (string, required): Path to the private key PEM file.
    /// - `trustRoots` (string array, optional, default: system trust roots):  The root certificates to trust when
    ///    verifying client certificates.
    /// - `certificateVerificationMode` (string, required): The client certificate validation behavior (permitted
    ///    values: "optionalVerification" or "noHostnameVerification").
    ///
    /// ### Configuration keys for `"backpressureStrategy"`:
    /// - `low` (int, optional, default: 2): The threshold below which the consumer will ask the producer to produce
    ///    more elements.
    /// - `high` (int, optional, default: 10): The threshold above which the producer will stop producing elements.
    ///
    /// ### Configuration keys for `"http2"`:
    /// - `maxFrameSize` (int, optional, default: 2^14):  The maximum frame size to be used in an HTTP/2 connection.
    /// - `targetWindowSize` (int, optional, default: 2^16 - 1): The target window size to be used in an HTTP/2
    ///    connection.
    /// - `maxConcurrentStreams` (int, optional, default: 100): The maximum number of concurrent streams in an HTTP/2
    ///    connection.
    ///
    /// - Parameters:
    ///   - config: The configuration reader to read configuration values from.
    ///   - customCertificateVerificationCallback: An optional client certificate verification callback to use when
    ///     mTLS is configured (i.e., when `"httpServer.transportSecurity.security"` is `"mTLS"` or `"reloadingMTLS"`).
    ///     If provided when mTLS is *not* configured, this initializer throws
    ///     ``NIOHTTPServerConfigurationError/customVerificationCallbackProvidedWhenNotUsingMTLS``. If set to `nil` when
    ///     mTLS *is* configured, the default client certificate verification logic of the underlying SSL implementation
    ///     is used.
    public init(
        config: ConfigReader,
        customCertificateVerificationCallback: (
            @Sendable ([Certificate]) async throws -> CertificateVerificationResult
        )? = nil
    ) throws {
        let snapshot = config.snapshot().scoped(to: "httpServer")

        self.init(
            bindTarget: try .init(config: snapshot.scoped(to: "bindTarget")),
            transportSecurity: try .init(
                config: snapshot.scoped(to: "transportSecurity"),
                customCertificateVerificationCallback: customCertificateVerificationCallback
            ),
            backpressureStrategy: .init(config: snapshot.scoped(to: "backpressureStrategy")),
            http2: .init(config: snapshot.scoped(to: "http2"))
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration.BindTarget {
    init(config: ConfigSnapshotReader) throws {
        self.init(
            backing: .hostAndPort(
                host: try config.requiredString(forKey: "host"),
                port: try config.requiredInt(forKey: "port")
            )
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration.TransportSecurity {
    init(
        config: ConfigSnapshotReader,
        customCertificateVerificationCallback: (
            @Sendable ([Certificate]) async throws -> CertificateVerificationResult
        )? = nil
    ) throws {
        let security = try config.requiredString(forKey: "security", as: TransportSecurityKind.self)

        // A custom verification callback can only be used when the server is configured for mTLS.
        if let _ = customCertificateVerificationCallback, !security.isMTLS() {
            throw NIOHTTPServerConfigurationError.customVerificationCallbackProvidedWhenNotUsingMTLS
        }

        switch security {
        case .plaintext:
            self = .plaintext

        case .tls:
            self = try .tls(config: config)

        case .reloadingTLS:
            self = try .reloadingTLS(config: config)

        case .mTLS:
            self = try .mTLS(
                config: config,
                customCertificateVerificationCallback: customCertificateVerificationCallback
            )

        case .reloadingMTLS:
            self = try .reloadingMTLS(
                config: config,
                customCertificateVerificationCallback: customCertificateVerificationCallback
            )
        }
    }

    private static func tls(config: ConfigSnapshotReader) throws -> Self {
        let certificateChainPEMString = try config.requiredString(forKey: "certificateChainPEMString")
        let privateKeyPEMString = try config.requiredString(forKey: "privateKeyPEMString", isSecret: true)

        return Self.tls(
            certificateChain: try PEMDocument.parseMultiple(pemString: certificateChainPEMString)
                .map { try Certificate(pemEncoded: $0.pemString) },
            privateKey: try .init(pemEncoded: privateKeyPEMString)
        )
    }

    private static func reloadingTLS(config: ConfigSnapshotReader) throws -> Self {
        let refreshInterval = config.int(forKey: "refreshInterval", default: 30)
        let certificateChainPEMPath = try config.requiredString(forKey: "certificateChainPEMPath")
        let privateKeyPEMPath = try config.requiredString(forKey: "privateKeyPEMPath")

        return try Self.tls(
            certificateReloader: TimedCertificateReloader(
                refreshInterval: .seconds(refreshInterval),
                certificateSource: .init(location: .file(path: certificateChainPEMPath), format: .pem),
                privateKeySource: .init(location: .file(path: privateKeyPEMPath), format: .pem)
            )
        )
    }

    private static func mTLS(
        config: ConfigSnapshotReader,
        customCertificateVerificationCallback: (
            @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
        )? = nil
    ) throws -> Self {
        let certificateChainPEMString = try config.requiredString(forKey: "certificateChainPEMString")
        let privateKeyPEMString = try config.requiredString(forKey: "privateKeyPEMString", isSecret: true)
        let trustRoots = config.stringArray(forKey: "trustRoots")
        let verificationMode = try config.requiredString(
            forKey: "certificateVerificationMode",
            as: VerificationMode.self
        )

        return Self.mTLS(
            certificateChain: try PEMDocument.parseMultiple(pemString: certificateChainPEMString)
                .map { try Certificate(pemEncoded: $0.pemString) },
            privateKey: try .init(pemEncoded: privateKeyPEMString),
            trustRoots: try trustRoots?.map { try Certificate(pemEncoded: $0) },
            certificateVerification: .init(verificationMode),
            customCertificateVerificationCallback: customCertificateVerificationCallback
        )
    }

    private static func reloadingMTLS(
        config: ConfigSnapshotReader,
        customCertificateVerificationCallback: (
            @Sendable ([X509.Certificate]) async throws -> CertificateVerificationResult
        )? = nil
    ) throws -> Self {
        let refreshInterval = config.int(forKey: "refreshInterval", default: 30)
        let certificateChainPEMPath = try config.requiredString(forKey: "certificateChainPEMPath")
        let privateKeyPEMPath = try config.requiredString(forKey: "privateKeyPEMPath")
        let trustRoots = config.stringArray(forKey: "trustRoots")
        let verificationMode = try config.requiredString(
            forKey: "certificateVerificationMode",
            as: VerificationMode.self
        )

        return try Self.mTLS(
            certificateReloader: TimedCertificateReloader(
                refreshInterval: .seconds(refreshInterval),
                certificateSource: .init(location: .file(path: certificateChainPEMPath), format: .pem),
                privateKeySource: .init(location: .file(path: privateKeyPEMPath), format: .pem)
            ),
            trustRoots: try trustRoots?.map { try Certificate(pemEncoded: $0) },
            certificateVerification: .init(verificationMode),
            customCertificateVerificationCallback: customCertificateVerificationCallback
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration.BackPressureStrategy {
    init(config: ConfigSnapshotReader) {
        self.init(
            backing: .watermark(
                low: config.int(
                    forKey: "low",
                    default: NIOHTTPServerConfiguration.BackPressureStrategy.DEFAULT_WATERMARK_LOW
                ),
                high: config.int(
                    forKey: "high",
                    default: NIOHTTPServerConfiguration.BackPressureStrategy.DEFAULT_WATERMARK_HIGH
                )
            )
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration.HTTP2 {
    init(config: ConfigSnapshotReader) {
        self.init(
            maxFrameSize: config.int(
                forKey: "maxFrameSize",
                default: NIOHTTPServerConfiguration.HTTP2.DEFAULT_MAX_FRAME_SIZE
            ),
            targetWindowSize: config.int(
                forKey: "targetWindowSize",
                default: NIOHTTPServerConfiguration.HTTP2.DEFAULT_TARGET_WINDOW_SIZE
            ),
            /// The default value, ``NIOHTTPServerConfiguration.HTTP2.DEFAULT_TARGET_WINDOW_SIZE``, is `nil`. However,
            /// we can only specify a non-nil `default` argument to `config.int(...)`. But `config.int(...)` already
            /// defaults to `nil` if it can't find the `"maxConcurrentStreams"` key, so that works for us.
            maxConcurrentStreams: config.int(forKey: "maxConcurrentStreams")
        )
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NIOHTTPServerConfiguration.TransportSecurity {
    fileprivate enum TransportSecurityKind: String {
        case plaintext
        case tls
        case reloadingTLS
        case mTLS
        case reloadingMTLS

        func isMTLS() -> Bool {
            switch self {
            case .mTLS, .reloadingMTLS:
                return true

            default:
                return false
            }
        }
    }

    /// A wrapper over ``CertificateVerificationMode``.
    fileprivate enum VerificationMode: String {
        case optionalVerification
        case noHostnameVerification
    }
}

@available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension CertificateVerificationMode {
    fileprivate init(_ mode: NIOHTTPServerConfiguration.TransportSecurity.VerificationMode) {
        switch mode {
        case .optionalVerification:
            self.init(mode: .optionalVerification)
        case .noHostnameVerification:
            self.init(mode: .noHostnameVerification)
        }
    }
}
