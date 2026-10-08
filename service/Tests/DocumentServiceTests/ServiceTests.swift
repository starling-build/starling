// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import JWTKit
import Testing

@testable import DocumentService

struct ServiceTests {
    func signedClaims(
        issuer: String = "https://identity.example", audience: String = "starling-documents",
        expiration: Date = Date().addingTimeInterval(3600), notBefore: Date? = nil,
        verified: Bool = true
    ) -> AccessClaims {
        AccessClaims(
            iss: issuer, sub: "alice", aud: .init(value: [audience]), exp: .init(value: expiration),
            nbf: notBefore.map { .init(value: $0) }, email: "alice@example.test", email_verified: verified,
            name: "Alice")
    }
    @Test func verifiesIdentityClaims() async throws {
        // This generated fixture key is only for tests and is never a deployment identity.
        let pem = try String(
            contentsOf: Bundle.module.url(
                forResource: "test-rsa", withExtension: "pem", subdirectory: "Fixtures")!, encoding: .utf8)
        let privateKey = try Insecure.RSA.PrivateKey(pem: pem)
        let signing = JWTKeyCollection()
        let verifying = JWTKeyCollection()
        await signing.add(rsa: privateKey, digestAlgorithm: .sha256, kid: "test")
        await verifying.add(rsa: privateKey.publicKey, digestAlgorithm: .sha256, kid: "test")
        let auth = OIDCAuthentication(
            issuer: "https://identity.example", audience: "starling-documents", keys: verifying)
        let good = try await signing.sign(signedClaims(), kid: "test")
        let identity = try await auth.authenticate(good)
        #expect(identity.subject == "alice")
        #expect(identity.email == "alice@example.test")
        for claims in [
            signedClaims(issuer: "https://attacker.example"), signedClaims(audience: "some-other-app"),
            signedClaims(expiration: .distantPast), signedClaims(notBefore: .distantFuture),
        ] {
            let token = try await signing.sign(claims, kid: "test")
            await #expect(throws: ServiceError.self) { _ = try await auth.authenticate(token) }
        }
        let unverified = try await signing.sign(signedClaims(verified: false), kid: "test")
        #expect(try await auth.authenticate(unverified).email == nil)
        let hmac = JWTKeyCollection()
        await hmac.add(
            hmac: "this-is-only-a-unit-test-secret-with-32-bytes", digestAlgorithm: .sha256, kid: "test")
        let wrongAlgorithm = try await hmac.sign(signedClaims(), kid: "test")
        await #expect(throws: ServiceError.self) { _ = try await auth.authenticate(wrongAlgorithm) }
        let corrupted = good.dropLast(10) + "AAAAAAAAAA"
        await #expect(throws: ServiceError.self) { _ = try await auth.authenticate(String(corrupted)) }
    }
    @Test func blobPublicationIsImmutable() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let store = try DiskStorage(root: path)
        let key = UUID()
        let data = Data("original".utf8)
        try await store.put(data, key: key)
        try await store.put(data, key: key)  // retries are idempotent
        await #expect(throws: (any Error).self) { try await store.put(Data("changed".utf8), key: key) }
        #expect(try await store.get(key) == data)
        try await store.delete(key)
        try await store.delete(key)
        await #expect(throws: (any Error).self) { _ = try await store.get(key) }
    }
    @Test func uploadParametersRejectInvalidIdentifiers() throws {
        let input = JSON.object(["base_revision_id": .string("not-a-uuid")])
        #expect(throws: ServiceError.self) { _ = try input.optionalIdentifier("base_revision_id") }
        #expect(try JSON.object([:]).optionalIdentifier("base_revision_id") == nil)
    }
}
