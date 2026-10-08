// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation

extension Repository {
    public func folders(workspace: UUID, user: Principal) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await role(c, workspace: workspace, user: user.id)
            return .array(
                try await rows(
                    c,
                    "SELECT row_to_json(f)::text FROM folders f WHERE workspace_id=\(workspace) ORDER BY name,id"
                ))
        }
    }
    public func createFolder(workspace: UUID, user: Principal, input: JSON) async throws -> JSON {
        let name = try input.text("name")
        return try await client.withTransaction(logger: databaseLog) { c in
            try await lock(c, workspace: workspace)
            _ = try await role(c, workspace: workspace, user: user.id)
            let id = UUID()
            let result = try await one(
                c,
                "INSERT INTO folders(id,workspace_id,name) VALUES(\(id),\(workspace),\(name)) RETURNING row_to_json(folders)::text"
            )
            try await audit(c, workspace: workspace, user: user.id, event: "folder.created")
            return result
        }
    }
    public func moveDocument(id: UUID, user: Principal, input: JSON) async throws -> JSON {
        let folder = try input.optionalIdentifier("folder_id")
        return try await client.withTransaction(logger: databaseLog) { c in
            let wid = try await lockDocument(c, id: id)
            _ = try await document(c, id: id, user: user.id, write: true)
            if let folder {
                _ = try await one(
                    c, "SELECT to_json(id)::text FROM folders WHERE id=\(folder) AND workspace_id=\(wid)")
            }
            let result = try await one(
                c,
                "UPDATE documents SET folder_id=\(folder),updated_at=now() WHERE id=\(id) RETURNING row_to_json(documents)::text"
            )
            try await audit(c, workspace: wid, document: id, user: user.id, event: "document.moved")
            return result
        }
    }
}
