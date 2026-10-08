// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import PostgresNIO

extension Repository {
    public func documents(workspace: UUID, user: Principal, offset: Int = 0) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await role(c, workspace: workspace, user: user.id)
            return .array(
                try await rows(
                    c,
                    """
                    SELECT row_to_json(d)::text FROM documents d WHERE workspace_id=\(workspace)
                    AND (owner_id=\(user.id) OR EXISTS(SELECT 1 FROM document_grants g WHERE g.document_id=d.id AND g.user_id=\(user.id)))
                    ORDER BY updated_at DESC,id LIMIT 200 OFFSET \(offset)
                    """))
        }
    }
    public func createDocument(workspace: UUID, user: Principal, input: JSON) async throws -> JSON {
        let name = try input.text("name")
        let kind = try input.text("kind")
        guard ["docx", "pptx", "xlsx"].contains(kind) else {
            throw ServiceError(.badRequest, "unsupported_document_kind")
        }
        return try await client.withTransaction(logger: databaseLog) { c in
            try await lock(c, workspace: workspace)
            _ = try await role(c, workspace: workspace, user: user.id)
            let id = UUID()
            let doc = try await one(
                c,
                """
                INSERT INTO documents(id,workspace_id,owner_id,name,kind) VALUES(\(id),\(workspace),\(user.id),\(name),\(kind))
                RETURNING row_to_json(documents)::text
                """)
            try await audit(c, workspace: workspace, document: id, user: user.id, event: "document.created")
            return doc
        }
    }
    public func getDocument(id: UUID, user: Principal) async throws -> JSON {
        try await client.withConnection { c in try await document(c, id: id, user: user.id) }
    }
    public func renameDocument(id: UUID, user: Principal, input: JSON) async throws -> JSON {
        let name = try input.text("name")
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, write: true)
            let doc = try await one(
                c,
                "UPDATE documents SET name=\(name),updated_at=now() WHERE id=\(id) RETURNING row_to_json(documents)::text"
            )
            try await audit(c, workspace: wid, document: id, user: user.id, event: "document.renamed")
            return doc
        }
    }
    public func trashDocument(id: UUID, user: Principal, restore: Bool) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, owner: true, includeTrash: true)
            let date: Date? = restore ? nil : Date()
            let doc = try await one(
                c,
                "UPDATE documents SET deleted_at=\(date),updated_at=now() WHERE id=\(id) RETURNING row_to_json(documents)::text"
            )
            // Restoring a document never silently reactivates old public links.
            if !restore {
                try await execute(
                    c,
                    "UPDATE share_links SET revoked_at=now() WHERE document_id=\(id) AND revoked_at IS NULL")
            }
            try await audit(
                c, workspace: wid, document: id, user: user.id,
                event: restore ? "document.restored" : "document.trashed")
            return doc
        }
    }
    public func recoverDocument(id: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            try await admin(c, workspace: wid, user: user.id)
            let doc = try await one(
                c,
                "UPDATE documents SET owner_id=\(user.id),updated_at=now() WHERE id=\(id) RETURNING row_to_json(documents)::text"
            )
            try await audit(c, workspace: wid, document: id, user: user.id, event: "document.admin_recovery")
            return doc
        }
    }
    public func grant(id: UUID, user: Principal, input: JSON) async throws -> JSON {
        let recipient = try input.identifier("user_id")
        let permission = try input.text("permission")
        guard ["viewer", "editor"].contains(permission) else {
            throw ServiceError(.badRequest, "invalid_permission")
        }
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, owner: true)
            _ = try await role(c, workspace: wid, user: recipient)
            try await execute(
                c,
                """
                INSERT INTO document_grants VALUES(\(id),\(recipient),\(permission))
                ON CONFLICT(document_id,user_id) DO UPDATE SET permission=excluded.permission
                """)
            try await audit(c, workspace: wid, document: id, user: user.id, event: "document.grant_changed")
            return .object(["user_id": .string(recipient.uuidString), "permission": .string(permission)])
        }
    }
    public func revokeGrant(id: UUID, recipient: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, owner: true)
            try await execute(
                c, "DELETE FROM document_grants WHERE document_id=\(id) AND user_id=\(recipient)")
            try await audit(c, workspace: wid, document: id, user: user.id, event: "document.grant_revoked")
            return .object(["revoked": .bool(true)])
        }
    }
    public func grants(id: UUID, user: Principal) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await document(c, id: id, user: user.id, owner: true)
            return .array(
                try await rows(
                    c,
                    "SELECT row_to_json(g)::text FROM document_grants g WHERE document_id=\(id) ORDER BY user_id"
                ))
        }
    }
    public func createLink(id: UUID, user: Principal, input: JSON) async throws -> JSON {
        let hours = input["expires_in_hours"].int ?? 24
        guard hours > 0, hours <= 720 else { throw ServiceError(.badRequest, "invalid_expiry") }
        let expiry = Date().addingTimeInterval(Double(hours) * 3600)
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, owner: true)
            let token = newToken()
            let hash = digest(Data(token.utf8))
            let link = UUID()
            try await execute(
                c, "INSERT INTO share_links VALUES(\(link),\(id),\(hash),\(user.id),\(expiry),NULL)")
            try await audit(c, workspace: wid, document: id, user: user.id, event: "share.created")
            return .object([
                "id": .string(link.uuidString), "token": .string(token), "permission": .string("viewer"),
            ])
        }
    }
    public func links(id: UUID, user: Principal) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await document(c, id: id, user: user.id, owner: true)
            return .array(
                try await rows(
                    c,
                    "SELECT row_to_json(s)::text FROM (SELECT id,expires_at,revoked_at FROM share_links WHERE document_id=\(id)) s"
                ))
        }
    }
    public func revokeLink(id: UUID, link: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, owner: true)
            _ = try await one(
                c,
                "UPDATE share_links SET revoked_at=now() WHERE id=\(link) AND document_id=\(id) RETURNING to_json(id)::text"
            )
            try await audit(c, workspace: wid, document: id, user: user.id, event: "share.revoked")
            return .object(["revoked": .bool(true)])
        }
    }
    public func sharedDocument(token: String) async throws -> JSON {
        guard token.utf8.count == 64 else { throw ServiceError(.notFound, "share_not_found") }
        let hash = digest(Data(token.utf8))
        return try await client.withConnection { c in
            try await one(
                c,
                """
                SELECT row_to_json(d)::text FROM (SELECT d.id,d.name,d.kind,d.current_revision_id FROM documents d
                JOIN share_links s ON s.document_id=d.id WHERE s.token_hash=\(hash) AND s.revoked_at IS NULL
                AND s.expires_at>now() AND d.deleted_at IS NULL) d
                """)
        }
    }
}
