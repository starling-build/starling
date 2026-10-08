// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import Hummingbird
import PostgresNIO

let databaseLog = Logger(label: "starling.documents.database")

func rows(_ connection: PostgresConnection, _ query: PostgresQuery) async throws -> [JSON] {
    var result: [JSON] = []
    for try await value in try await connection.query(query, logger: databaseLog).decode(String.self) {
        result.append(try JSONDecoder().decode(JSON.self, from: Data(value.utf8)))
    }
    return result
}
func execute(_ connection: PostgresConnection, _ query: PostgresQuery) async throws {
    for try await _ in try await connection.query(query, logger: databaseLog) {}
}
func one(_ connection: PostgresConnection, _ query: PostgresQuery) async throws -> JSON {
    guard let value = try await rows(connection, query).first else {
        throw ServiceError(.notFound, "not_found")
    }
    return value
}

public struct Repository: Sendable {
    public let client: PostgresClient
    public let storage: any BlobStorage
    public init(client: PostgresClient, storage: any BlobStorage) {
        self.client = client
        self.storage = storage
    }

    public func migrate() async throws {
        try await client.withTransaction(logger: databaseLog) { c in
            try await execute(c, "SELECT pg_advisory_xact_lock(73100981)")
            try await execute(c, "CREATE TABLE IF NOT EXISTS schema_migrations(version integer PRIMARY KEY)")
            let existing = try await rows(
                c, "SELECT to_json(version)::text FROM schema_migrations WHERE version=1")
            if existing.isEmpty {
                let url = Bundle.module.url(
                    forResource: "001", withExtension: "sql", subdirectory: "Migrations")!
                let migration = try String(contentsOf: url, encoding: .utf8)
                for statement in migration.components(separatedBy: "-- statement") {
                    try await execute(c, PostgresQuery(unsafeSQL: statement))
                }
                try await execute(c, "INSERT INTO schema_migrations VALUES (1)")
            }
        }
    }

    public func user(_ identity: Identity) async throws -> Principal {
        try await client.withTransaction(logger: databaseLog) { c in
            let uid = UUID()
            let user = try await one(
                c,
                """
                INSERT INTO users(id,issuer,subject,email,name) VALUES(\(uid),\(identity.issuer),\(identity.subject),\(identity.email),\(identity.name))
                ON CONFLICT(issuer,subject) DO UPDATE SET email=excluded.email,name=excluded.name
                RETURNING row_to_json(users)::text
                """)
            let id = user["id"].uuid!
            let workspace = UUID()
            try await execute(
                c,
                """
                INSERT INTO workspaces(id,name,kind,personal_owner) VALUES(\(workspace),'Personal','personal',\(id)) ON CONFLICT(personal_owner) DO NOTHING
                """)
            try await execute(
                c,
                """
                INSERT INTO memberships(workspace_id,user_id,role) SELECT id,\(id),'owner' FROM workspaces WHERE personal_owner=\(id)
                ON CONFLICT DO NOTHING
                """)
            return Principal(id: id, email: identity.email)
        }
    }

    // Every mutation first locks its workspace. Membership/grant changes, quota reservations,
    // and revision commits therefore share one serialization boundary across API instances.
    func lock(_ c: PostgresConnection, workspace: UUID) async throws {
        _ = try await one(c, "SELECT to_json(id)::text FROM workspaces WHERE id=\(workspace) FOR UPDATE")
    }
    func role(_ c: PostgresConnection, workspace: UUID, user: UUID) async throws -> String {
        guard
            let role = try await rows(
                c,
                "SELECT to_json(role)::text FROM memberships WHERE workspace_id=\(workspace) AND user_id=\(user)"
            ).first?.string
        else {
            throw ServiceError(.notFound, "workspace_not_found")
        }
        return role
    }
    func admin(_ c: PostgresConnection, workspace: UUID, user: UUID) async throws {
        guard try await role(c, workspace: workspace, user: user) != "member" else {
            throw ServiceError(.forbidden, "workspace_admin_required")
        }
    }
    func document(
        _ c: PostgresConnection, id: UUID, user: UUID, write: Bool = false, owner: Bool = false,
        includeTrash: Bool = false
    ) async throws -> JSON {
        let doc = try await one(c, "SELECT row_to_json(d)::text FROM documents d WHERE id=\(id)")
        let wid = doc["workspace_id"].uuid!
        _ = try await role(c, workspace: wid, user: user)
        if !includeTrash && doc["deleted_at"] != .null { throw ServiceError(.notFound, "document_not_found") }
        if doc["owner_id"].uuid == user { return doc }
        if owner { throw ServiceError(.forbidden, "document_owner_required") }
        guard
            let permission = try await rows(
                c,
                "SELECT to_json(permission)::text FROM document_grants WHERE document_id=\(id) AND user_id=\(user)"
            ).first?.string,
            !write || permission == "editor"
        else { throw ServiceError(.notFound, "document_not_found") }
        return doc
    }
    func lockDocument(_ c: PostgresConnection, id: UUID) async throws -> UUID {
        let doc = try await one(c, "SELECT to_json(workspace_id)::text FROM documents WHERE id=\(id)")
        let wid = doc.uuid!
        try await lock(c, workspace: wid)
        return wid
    }
    func audit(_ c: PostgresConnection, workspace: UUID, document: UUID? = nil, user: UUID, event: String)
        async throws
    {
        try await execute(
            c,
            "INSERT INTO activity(workspace_id,document_id,actor_id,event) VALUES(\(workspace),\(document),\(user),\(event))"
        )
    }
}
