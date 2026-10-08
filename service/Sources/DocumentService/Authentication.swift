// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import Hummingbird
import JWTKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public protocol Authentication: Sendable {
    func authenticate(_ bearer: String) async throws -> Identity
}

/// Explicitly configured loopback-only development mode. Never enabled by absence of OIDC settings.
public struct DevelopmentAuthentication: Authentication {
    let tokens: [String: Identity]
    public init(tokens: [String: Identity]) { self.tokens = tokens }
    public func authenticate(_ bearer: String) async throws -> Identity {
        guard let identity = tokens[bearer] else { throw ServiceError(.unauthorized, "invalid_token") }
        return identity
    }
}

struct AccessClaims: JWTPayload {
    let iss: String
    let sub: String
    let aud: AudienceClaim
    let exp: ExpirationClaim
    let nbf: NotBeforeClaim?
    let email: String?
    let email_verified: Bool?
    let name: String?
    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
        try nbf?.verifyNotBefore()
    }
}

/// The configured provider must issue RS256 API access tokens with this service's audience.
/// The issuer and JWKS URL are trusted configuration, never supplied by a token.
public actor OIDCAuthentication: Authentication {
    let issuer: String
    let audience: String
    let jwksURL: URL
    var keys: JWTKeyCollection?
    var loadedAt = Date.distantPast
    public init(issuer: String, audience: String, jwksURL: URL) throws {
        guard jwksURL.scheme == "https", URL(string: issuer)?.scheme == "https" else {
            throw ServiceError(.internalServerError, "oidc_requires_https")
        }
        self.issuer = issuer
        self.audience = audience
        self.jwksURL = jwksURL
    }
    init(issuer: String, audience: String, keys: JWTKeyCollection) {
        self.issuer = issuer
        self.audience = audience
        self.keys = keys
        self.jwksURL = URL(string: "https://test.invalid/keys")!
        self.loadedAt = Date()
    }
    func reload() async throws {
        var request = URLRequest(url: jwksURL)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
            throw ServiceError(.serviceUnavailable, "identity_provider_unavailable")
        }
        let collection = JWTKeyCollection()
        try await collection.add(jwksJSON: String(decoding: data, as: UTF8.self))
        keys = collection
        loadedAt = Date()
    }
    public func authenticate(_ bearer: String) async throws -> Identity {
        guard bearer.utf8.count < 16_384, let header = bearer.split(separator: ".").first else {
            throw ServiceError(.unauthorized, "invalid_token")
        }
        var encoded = String(header).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
            of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
            let fields = try? JSONDecoder().decode([String: JSON].self, from: data),
            fields["alg"] == .string("RS256"), fields["kid"]?.string != nil
        else {
            throw ServiceError(.unauthorized, "unsupported_token")
        }
        if keys == nil || Date().timeIntervalSince(loadedAt) > 300 { try await reload() }
        do {
            let claims = try await keys!.verify(bearer, as: AccessClaims.self)
            guard claims.iss == issuer, !claims.sub.isEmpty else {
                throw ServiceError(.unauthorized, "invalid_issuer")
            }
            try claims.aud.verifyIntendedAudience(includes: audience)
            return Identity(
                issuer: claims.iss, subject: claims.sub,
                email: claims.email_verified == true ? claims.email : nil, name: claims.name ?? claims.sub)
        } catch { throw ServiceError(.unauthorized, "invalid_token") }
    }
}
