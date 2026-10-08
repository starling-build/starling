// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import PostgresNIO

extension Repository {
    public func prepareUpload(document id: UUID, user: Principal, input: JSON) async throws -> JSON {
        let base = try input.optionalIdentifier("base_revision_id")
        let key = try input.text("idempotency_key", max: 128)
        let sha = try input.text("sha256").lowercased()
        guard sha.count == 64, sha.allSatisfy({ $0.isHexDigit && $0.isASCII }),
            let size = input["size"].int, size > 0, size <= 33_554_432
        else { throw ServiceError(.badRequest, "invalid_upload") }
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            let doc = try await document(c, id: id, user: user.id, write: true)
            if let previous = try await rows(
                c,
                "SELECT row_to_json(u)::text FROM uploads u WHERE document_id=\(id) AND creator_id=\(user.id) AND idempotency_key=\(key)"
            ).first {
                guard previous["sha256"].string == sha, previous["size"].int == size,
                    previous["base_revision_id"].uuid == base
                else {
                    throw ServiceError(.conflict, "idempotency_key_reused")
                }
                return previous
            }
            guard doc["current_revision_id"].uuid == base else {
                throw ServiceError(.conflict, "revision_conflict")
            }
            let quota = try await rows(
                c,
                """
                UPDATE workspaces SET reserved_bytes=reserved_bytes+\(size) WHERE id=\(wid)
                AND used_bytes+reserved_bytes+\(size)<=quota_bytes RETURNING to_json(id)::text
                """)
            guard !quota.isEmpty else { throw ServiceError(.contentTooLarge, "workspace_quota_exceeded") }
            let uid = UUID()
            return try await one(
                c,
                """
                INSERT INTO uploads(id,document_id,creator_id,base_revision_id,size,sha256,idempotency_key)
                VALUES(\(uid),\(id),\(user.id),\(base),\(size),\(sha),\(key)) RETURNING row_to_json(uploads)::text
                """)
        }
    }
    func upload(_ c: PostgresConnection, id: UUID, user: Principal) async throws -> (JSON, UUID) {
        let initial = try await one(
            c, "SELECT row_to_json(u)::text FROM uploads u WHERE id=\(id) AND creator_id=\(user.id)")
        let did = initial["document_id"].uuid!
        let wid = try await lockDocument(c, id: did)
        _ = try await document(c, id: did, user: user.id, write: true)
        let u = try await one(
            c,
            "SELECT row_to_json(u)::text FROM uploads u WHERE id=\(id) AND (expires_at>now() OR state='committed')"
        )
        return (u, wid)
    }
    public func uploadBytes(id: UUID, user: Principal, data: Data) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            let (u, _) = try await upload(c, id: id, user: user)
            guard ["pending", "uploaded"].contains(u["state"].string ?? "") else {
                throw ServiceError(.conflict, "upload_not_writable")
            }
            guard u["size"].int == Int64(data.count), u["sha256"].string == digest(data) else {
                throw ServiceError(.badRequest, "upload_checksum_or_size_mismatch")
            }
            try await storage.put(data, key: id)
            return try await one(
                c, "UPDATE uploads SET state='uploaded' WHERE id=\(id) RETURNING row_to_json(uploads)::text")
        }
    }
    public func commitUpload(id: UUID, user: Principal) async throws -> JSON {
        // A conflict is returned as a value so the transaction retains the uploaded copy.
        try await client.withTransaction(logger: databaseLog) { c in
            let (u, wid) = try await upload(c, id: id, user: user)
            if u["state"].string == "committed" { return u }
            guard ["uploaded", "conflict"].contains(u["state"].string ?? "") else {
                throw ServiceError(.conflict, "upload_incomplete")
            }
            let did = u["document_id"].uuid!
            let size = u["size"].int!
            let sha = u["sha256"].string!
            let doc = try await document(c, id: did, user: user.id, write: true)
            guard doc["current_revision_id"].uuid == u["base_revision_id"].uuid else {
                return try await one(
                    c,
                    "UPDATE uploads SET state='conflict' WHERE id=\(id) RETURNING row_to_json(uploads)::text")
            }
            let rid = UUID()
            let parent = u["base_revision_id"].uuid
            try await execute(
                c,
                "INSERT INTO revisions(id,document_id,parent_id,blob_key,size,sha256,author_id) VALUES(\(rid),\(did),\(parent),\(id),\(size),\(sha),\(user.id))"
            )
            try await execute(
                c, "UPDATE documents SET current_revision_id=\(rid),updated_at=now() WHERE id=\(did)")
            try await execute(
                c,
                "UPDATE workspaces SET reserved_bytes=reserved_bytes-\(size),used_bytes=used_bytes+\(size) WHERE id=\(wid)"
            )
            try await audit(c, workspace: wid, document: did, user: user.id, event: "revision.committed")
            return try await one(
                c,
                "UPDATE uploads SET state='committed',revision_id=\(rid) WHERE id=\(id) RETURNING row_to_json(uploads)::text"
            )
        }
    }
    public func getUpload(id: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in try await upload(c, id: id, user: user).0
        }
    }
    public func recoverUploadBytes(id: UUID, user: Principal) async throws -> Data {
        let u = try await getUpload(id: id, user: user)
        guard ["uploaded", "conflict", "committed"].contains(u["state"].string ?? "") else {
            throw ServiceError(.notFound, "content_unavailable")
        }
        return try await storage.get(id)
    }
    public func revisions(document id: UUID, user: Principal, offset: Int = 0) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await document(c, id: id, user: user.id)
            return .array(
                try await rows(
                    c,
                    "SELECT row_to_json(r)::text FROM (SELECT id,parent_id,size,sha256,author_id,created_at FROM revisions WHERE document_id=\(id) ORDER BY created_at DESC,id LIMIT 200 OFFSET \(offset)) r"
                ))
        }
    }
    public func content(document id: UUID, revision: UUID?, user: Principal) async throws -> Data {
        let key = try await client.withConnection { c in
            let doc = try await document(c, id: id, user: user.id)
            guard let rid = revision ?? doc["current_revision_id"].uuid else {
                throw ServiceError(.notFound, "empty_document")
            }
            return try await one(
                c, "SELECT to_json(blob_key)::text FROM revisions WHERE id=\(rid) AND document_id=\(id)"
            ).uuid!
        }
        return try await storage.get(key)
    }
    public func sharedContent(token: String) async throws -> Data {
        let doc = try await sharedDocument(token: token)
        guard let rid = doc["current_revision_id"].uuid else {
            throw ServiceError(.notFound, "empty_document")
        }
        let key = try await client.withConnection { c in
            try await one(c, "SELECT to_json(blob_key)::text FROM revisions WHERE id=\(rid)").uuid!
        }
        return try await storage.get(key)
    }
    public func restoreRevision(document id: UUID, revision: UUID, user: Principal, input: JSON) async throws
        -> JSON
    {
        let base = try input.identifier("base_revision_id")
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            let doc = try await document(c, id: id, user: user.id, write: true)
            guard doc["current_revision_id"].uuid == base else {
                throw ServiceError(.conflict, "revision_conflict")
            }
            // History remains append-only; the restored revision references the existing immutable blob.
            let old = try await one(
                c, "SELECT row_to_json(r)::text FROM revisions r WHERE id=\(revision) AND document_id=\(id)")
            let rid = UUID()
            let blob = old["blob_key"].uuid!
            let size = old["size"].int!
            let sha = old["sha256"].string!
            let restored = try await one(
                c,
                """
                INSERT INTO revisions(id,document_id,parent_id,blob_key,size,sha256,author_id)
                VALUES(\(rid),\(id),\(base),\(blob),\(size),\(sha),\(user.id)) RETURNING row_to_json(revisions)::text
                """)
            try await execute(
                c, "UPDATE documents SET current_revision_id=\(rid),updated_at=now() WHERE id=\(id)")
            try await audit(c, workspace: wid, document: id, user: user.id, event: "revision.restored")
            return restored
        }
    }
    /// Safe to run on more than one worker: workspace locks serialize quota release.
    /// An expired record is a durable deletion job, so failed blob cleanup is retried.
    public func cleanup() async throws {
        let ids = try await client.withConnection { c in
            try await rows(
                c,
                "SELECT to_json(id)::text FROM uploads WHERE state IN ('pending','uploaded','conflict') AND expires_at<=now() LIMIT 100"
            )
        }
        for id in ids.compactMap(\.uuid) {
            try await client.withTransaction(logger: databaseLog) { c in
                let u = try await one(c, "SELECT row_to_json(u)::text FROM uploads u WHERE id=\(id)")
                let wid = try await lockDocument(c, id: u["document_id"].uuid!)
                let expired = try await rows(
                    c,
                    "UPDATE uploads SET state='expired' WHERE id=\(id) AND state IN ('pending','uploaded','conflict') AND expires_at<=now() RETURNING to_json(size)::text"
                )
                if let size = expired.first?.int {
                    try await execute(
                        c, "UPDATE workspaces SET reserved_bytes=reserved_bytes-\(size) WHERE id=\(wid)")
                }
            }
        }
        let expired = try await client.withConnection { c in
            try await rows(
                c,
                "SELECT to_json(id)::text FROM uploads WHERE state='expired' AND expires_at<now() LIMIT 100")
        }
        for id in expired.compactMap(\.uuid) {
            try await storage.delete(id)
            // Preserve the idempotency tombstone, but don't repeatedly list deleted blobs.
            try await client.withConnection { c in
                try await execute(
                    c, "UPDATE uploads SET expires_at='infinity' WHERE id=\(id) AND state='expired'")
            }
        }
    }
}
