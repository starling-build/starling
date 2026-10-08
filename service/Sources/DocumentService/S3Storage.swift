// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import SotoS3

/// Private bucket adapter. Objects are published with create-only conditional PUTs;
/// repeated upload URLs or retries cannot replace a committed revision's bytes.
public struct S3Storage: BlobStorage {
    let client: AWSClient
    let s3: S3
    let bucket: String
    public init(bucket: String, region: String, endpoint: String? = nil) {
        self.client = AWSClient()
        self.s3 = S3(client: client, region: Region(rawValue: region), endpoint: endpoint)
        self.bucket = bucket
    }
    func objectKey(_ key: UUID) -> String { "documents/" + key.uuidString.lowercased() }
    public func put(_ data: Data, key: UUID) async throws {
        do {
            _ = try await s3.putObject(
                .init(
                    body: .init(bytes: data), bucket: bucket,
                    contentType: "application/octet-stream", ifNoneMatch: "*", key: objectKey(key)))
        } catch {
            // Successful publication followed by a lost response is safe to retry.
            guard let existing = try? await get(key), existing == data else { throw error }
        }
    }
    public func get(_ key: UUID) async throws -> Data {
        let object = try await s3.getObject(.init(bucket: bucket, key: objectKey(key)))
        let bytes = try await object.body.collect(upTo: 33_554_432)
        return Data(bytes.readableBytesView)
    }
    public func delete(_ key: UUID) async throws {
        _ = try await s3.deleteObject(.init(bucket: bucket, key: objectKey(key)))
    }
    public func shutdown() async throws { try await client.shutdown() }
}
