import Crypto
// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

public protocol BlobStorage: Sendable {
    func put(_ data: Data, key: UUID) async throws
    func get(_ key: UUID) async throws -> Data
    func delete(_ key: UUID) async throws
    func shutdown() async throws
}
extension BlobStorage { public func shutdown() async throws {} }

public func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func newToken() -> String { (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined() }

/// Private local object store for a single-host deployment. Keys are server-generated UUIDs;
/// objects are immutable, and storage is never exposed through a static file route.
public struct DiskStorage: BlobStorage {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
    public func put(_ data: Data, key: UUID) async throws {
        let path = root.appendingPathComponent(key.uuidString)
        try await Task.detached {
            let temporary = path.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            // Linking a complete temporary object gives an atomic, create-only publication.
            do { try FileManager.default.linkItem(at: temporary, to: path) } catch {
                // A retry may repeat the exact same upload, but cannot replace its bytes.
                guard let existing = try? Data(contentsOf: path), existing == data else { throw error }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            let directory = open(path.deletingLastPathComponent().path, O_RDONLY)
            guard directory >= 0 else { throw POSIXError(.EIO) }
            defer { _ = close(directory) }
            guard fsync(directory) == 0 else { throw POSIXError(.EIO) }
        }.value
    }
    public func get(_ key: UUID) async throws -> Data {
        let path = root.appendingPathComponent(key.uuidString)
        return try await Task.detached { try Data(contentsOf: path) }.value
    }
    public func delete(_ key: UUID) async throws {
        let path = root.appendingPathComponent(key.uuidString)
        try await Task.detached {
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
        }.value
    }
}
