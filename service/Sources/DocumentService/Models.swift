// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import Hummingbird

public struct ServiceError: Error, Sendable {
    public var status: HTTPResponse.Status
    public var code: String
    public init(_ status: HTTPResponse.Status, _ code: String) {
        self.status = status
        self.code = code
    }
}

// JSON is the wire boundary only; file bytes remain in BlobStorage.
public enum JSON: Codable, Sendable, Equatable, ResponseEncodable {
    case object([String: JSON])
    case array([JSON])
    case string(String)
    case number(Int64)
    case bool(Bool)
    case null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int64.self) {
            self = .number(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSON].self) {
            self = .array(v)
        } else {
            self = .object(try c.decode([String: JSON].self))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSON {
        if case .object(let v) = self { return v[key] ?? .null }
        return .null
    }
    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    public var int: Int64? {
        if case .number(let v) = self { return v }
        return nil
    }
    public var uuid: UUID? { string.flatMap(UUID.init(uuidString:)) }
    public var items: [JSON] {
        if case .array(let v) = self { return v }
        return []
    }
    public func text(_ key: String, max: Int = 255) throws -> String {
        guard let value = self[key].string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
            value.utf8.count <= max, !value.unicodeScalars.contains(where: { $0.value < 32 })
        else {
            throw ServiceError(.badRequest, "invalid_\(key)")
        }
        return value
    }
    public func identifier(_ key: String) throws -> UUID {
        guard let value = self[key].uuid else { throw ServiceError(.badRequest, "invalid_\(key)") }
        return value
    }
    public func optionalIdentifier(_ key: String) throws -> UUID? {
        if self[key] == .null { return nil }
        return try identifier(key)
    }
}

public struct Identity: Codable, Sendable {
    public let issuer: String
    public let subject: String
    public let email: String?
    public let name: String
    public init(issuer: String, subject: String, email: String?, name: String) {
        self.issuer = issuer
        self.subject = subject
        self.email = email?.lowercased()
        self.name = name
    }
}

public struct Principal: Sendable {
    public let id: UUID
    public let email: String?
}
