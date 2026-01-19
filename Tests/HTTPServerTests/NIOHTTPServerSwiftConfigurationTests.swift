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

import Configuration
import Crypto
import Foundation
import NIOCertificateReloading
import SwiftASN1
import Testing
import X509

@testable import HTTPServer

@Suite
struct NIOHTTPServerSwiftConfigurationTests {
    // MARK: - BindTarget Tests
    @Test("BindTarget: valid host and port")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBindTargetWithValidConfig() throws {
        let provider = InMemoryProvider(values: ["host": "localhost", "port": 8080])

        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let bindTarget = try NIOHTTPServerConfiguration.BindTarget(config: snapshot)

        switch bindTarget.backing {
        case .hostAndPort(let host, let port):
            #expect(host == "localhost")
            #expect(port == 8080)
        }
    }

    @Test("BindTarget: init fails with missing host")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBindTargetMissingHost() throws {
        let provider = InMemoryProvider(values: ["port": 8080])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            try NIOHTTPServerConfiguration.BindTarget(config: snapshot)
        }
    }

    @Test("BindTarget: init fails with missing port")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBindTargetMissingPort() throws {
        let provider = InMemoryProvider(values: ["host": "localhost"])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            try NIOHTTPServerConfiguration.BindTarget(config: snapshot)
        }
    }

    // MARK: - BackPressureStrategy Tests

    @Test("BackPressureStrategy: default values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBackPressureStrategyDefaults() throws {
        // Don't provide anything. All values have defaults.
        let provider = InMemoryProvider(values: [:])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let strategy = NIOHTTPServerConfiguration.BackPressureStrategy(config: snapshot)

        switch strategy.backing {
        case .watermark(let low, let high):
            #expect(low == NIOHTTPServerConfiguration.BackPressureStrategy.DEFAULT_WATERMARK_LOW)
            #expect(high == NIOHTTPServerConfiguration.BackPressureStrategy.DEFAULT_WATERMARK_HIGH)
        }
    }

    @Test("BackPressureStrategy: custom values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBackPressureStrategyCustomValues() throws {
        let provider = InMemoryProvider(values: ["low": 5, "high": 20])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let strategy = NIOHTTPServerConfiguration.BackPressureStrategy(config: snapshot)

        switch strategy.backing {
        case .watermark(let low, let high):
            #expect(low == 5)
            #expect(high == 20)
        }
    }

    @Test("BackPressureStrategy: partial custom values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testBackPressureStrategyPartialCustom() throws {
        let provider = InMemoryProvider(values: ["low": 3])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let strategy = NIOHTTPServerConfiguration.BackPressureStrategy(config: snapshot)

        switch strategy.backing {
        case .watermark(let low, let high):
            #expect(low == 3)
            #expect(high == NIOHTTPServerConfiguration.BackPressureStrategy.DEFAULT_WATERMARK_HIGH)
        }
    }

    // MARK: - HTTP2 Tests

    @Test("HTTP2: default values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testHTTP2Defaults() throws {
        let provider = InMemoryProvider(values: [:])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let http2 = NIOHTTPServerConfiguration.HTTP2(config: snapshot)

        #expect(http2.maxFrameSize == NIOHTTPServerConfiguration.HTTP2.DEFAULT_MAX_FRAME_SIZE)
        #expect(http2.targetWindowSize == NIOHTTPServerConfiguration.HTTP2.DEFAULT_TARGET_WINDOW_SIZE)
        #expect(http2.maxConcurrentStreams == nil)
    }

    @Test("HTTP2: custom values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testHTTP2CustomValues() throws {
        let provider = InMemoryProvider(values: ["maxFrameSize": 1, "targetWindowSize": 2, "maxConcurrentStreams": 3])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let http2 = NIOHTTPServerConfiguration.HTTP2(config: snapshot)

        #expect(http2.maxFrameSize == 1)
        #expect(http2.targetWindowSize == 2)
        #expect(http2.maxConcurrentStreams == 3)
    }

    @Test("HTTP2: partial custom values")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testHTTP2PartialCustom() throws {
        let provider = InMemoryProvider(values: ["maxFrameSize": 5])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let http2 = NIOHTTPServerConfiguration.HTTP2(config: snapshot)

        #expect(http2.maxFrameSize == 5)
        #expect(http2.targetWindowSize == NIOHTTPServerConfiguration.HTTP2.DEFAULT_TARGET_WINDOW_SIZE)
        #expect(http2.maxConcurrentStreams == nil)
    }

    // MARK: - TransportSecurity Tests

    @Test("TransportSecurity: invalid security type")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testTransportSecurityInvalidSecurityType() throws {
        let provider = InMemoryProvider(values: ["security": "<this_security_type_does_not_exist>"])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)
        }
    }

    @Test("TransportSecurity: custom verification callback without mTLS being enabled")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testTransportSecurityCannotInitializeWithCustomCallbackWhenMTLSNotEnabled() throws {
        let provider = InMemoryProvider(values: ["security": "tls"])
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let error = #expect(throws: Error.self) {
            // The custom verification callback will not be used when mTLS is not enabled. This is therefore an invalid
            // config, and we should expect an error.
            try NIOHTTPServerConfiguration.TransportSecurity(
                config: snapshot,
                customCertificateVerificationCallback: { peerCertificates in
                    .failed(.init(reason: "test"))
                }
            )
        }

        #expect(error as? NIOHTTPServerConfigurationError == .customVerificationCallbackProvidedWhenNotUsingMTLS)
    }

    // MARK: - TransportSecurity TLS Tests

    @Test("TransportSecurity.TLS: valid config")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testTLSWithValidConfig() throws {
        let chain = try TestCA.makeSelfSignedChain()
        let certsPEM = try chain.chainPEMString
        let keyPEM = try chain.privateKey.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "tls",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)

        switch transportSecurity.backing {
        case .tls(let certificateChain, let privateKey):
            #expect(certificateChain == chain.chain)
            #expect(privateKey == chain.privateKey)
        default:
            Issue.record("Expected TLS backing, got different type")
        }
    }

    @Test("TransportSecurity.TLS: init fails with missing certificate")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testTLSMissingCertificate() throws {
        let chain = try TestCA.makeSelfSignedChain()
        let keyPEM = try chain.privateKey.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "tls",
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)
        }
    }

    @Test("TransportSecurity.TLS: init fails with missing private key")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testTLSMissingPrivateKey() throws {
        let chain = try TestCA.makeSelfSignedChain()
        let certsPEM = try chain.chainPEMString

        let provider = InMemoryProvider(
            values: [
                "security": "tls",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)
        }
    }

    // MARK: - TransportSecurity Reloading TLS Tests

    @Test("TransportSecurity.reloadingTLS: valid config")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testReloadingTLS() async throws {
        let provider = InMemoryProvider(
            values: [
                "security": "reloadingTLS",
                "certificateChainPEMPath": .init(.string("cert.pem"), isSecret: false),
                "privateKeyPEMPath": .init(.string("key.pem"), isSecret: false),
                "refreshInterval": 60,
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)

        guard case .reloadingTLS = transportSecurity.backing else {
            Issue.record("Expected reloadingTLS backing, got \(transportSecurity.backing)")
            return
        }
    }

    // MARK: - TransportSecurity mTLS Tests

    @Test("TransportSecurity.mTLS: custom verification callback")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testMTLSWithValidConfig() throws {
        let serverChain = try TestCA.makeSelfSignedChain()
        let clientChain = try TestCA.makeSelfSignedChain()

        let certsPEM = try serverChain.chainPEMString
        let keyPEM = try serverChain.privateKey.serializeAsPEM().pemString
        let trustRootPEM = try clientChain.ca.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "mTLS",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
                "trustRoots": .init(.stringArray([trustRootPEM]), isSecret: false),
                "certificateVerificationMode": "noHostnameVerification",
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        // Initialize with a custom verification callback
        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(
            config: snapshot,
            customCertificateVerificationCallback: { peerCerts in
                .certificateVerified(.init(.init(uncheckedCertificateChain: peerCerts)))
            }
        )

        switch transportSecurity.backing {
        case .mTLS(let certificateChain, let privateKey, let trustRoots, let verification, let callback):
            #expect(certificateChain == [serverChain.leaf, serverChain.ca])
            #expect(privateKey == serverChain.privateKey)
            #expect(trustRoots == [clientChain.ca])
            #expect(verification.mode == .noHostnameVerification)
            #expect(callback != nil)
        default:
            Issue.record("Expected mTLS backing, got \(transportSecurity.backing)")
        }
    }

    @Test("TransportSecurity.mTLS: optional verification mode")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testMTLSWithOptionalVerification() throws {
        let serverChain = try TestCA.makeSelfSignedChain()
        let certsPEM = try serverChain.chainPEMString
        let keyPEM = try serverChain.privateKey.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "mTLS",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
                "certificateVerificationMode": "optionalVerification",
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)

        switch transportSecurity.backing {
        case .mTLS(let certificateChain, let privateKey, _, let verification, _):
            #expect(certificateChain == [serverChain.leaf, serverChain.ca])
            #expect(privateKey == serverChain.privateKey)
            #expect(verification.mode == .optionalVerification)
        default:
            Issue.record("Expected mTLS backing, got \(transportSecurity.backing)")
        }
    }

    @Test("TransportSecurity.mTLS: invalid verification mode")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testMTLSWithInvalidVerificationMode() throws {
        let serverChain = try TestCA.makeSelfSignedChain()

        let certsPEM = try serverChain.chainPEMString
        let keyPEM = try serverChain.privateKey.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "mTLS",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
                "certificateVerificationMode": "<this_mode_does_not_exist>",
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        #expect(throws: Error.self) {
            _ = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)
        }
    }

    @Test("TransportSecurity.mTLS: default trust roots")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testMTLSDefaultTrustRoots() throws {
        let serverChain = try TestCA.makeSelfSignedChain()

        let certsPEM = try serverChain.chainPEMString
        let keyPEM = try serverChain.privateKey.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "mTLS",
                "certificateChainPEMString": .init(.string(certsPEM), isSecret: false),
                "privateKeyPEMString": .init(.string(keyPEM), isSecret: true),
                "certificateVerificationMode": "noHostnameVerification",
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)

        switch transportSecurity.backing {
        case .mTLS(_, _, let trustRoots, _, _):
            // trustRoots should be nil
            #expect(trustRoots == nil)
        default:
            Issue.record("Expected mTLS backing, got \(transportSecurity.backing)")
        }
    }

    // MARK: - TransportSecurity Reloading mTLS Tests

    @Test("TransportSecurity.reloadingMTLS: valid config")
    @available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
    func testReloadingMTLSWithValidConfig() async throws {
        let chain = try TestCA.makeSelfSignedChain()
        let trustRootPEM = try chain.ca.serializeAsPEM().pemString

        let provider = InMemoryProvider(
            values: [
                "security": "reloadingMTLS",
                "certificateChainPEMPath": .init(.string("certs.pem"), isSecret: false),
                "privateKeyPEMPath": .init(.string("key.pem"), isSecret: false),
                "trustRoots": .init(.stringArray([trustRootPEM]), isSecret: false),
                "certificateVerificationMode": "noHostnameVerification",
                "refreshInterval": 45,
            ]
        )
        let config = ConfigReader(provider: provider)
        let snapshot = config.snapshot()

        let transportSecurity = try NIOHTTPServerConfiguration.TransportSecurity(config: snapshot)

        switch transportSecurity.backing {
        case .reloadingMTLS(_, let trustRoots, _, _):
            #expect(trustRoots == [chain.ca])
        default:
            Issue.record("Expected reloadingMTLS backing, got different type")
        }
    }
}
