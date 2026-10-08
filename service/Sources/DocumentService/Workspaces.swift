// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import PostgresNIO

extension Repository {
    public func workspaces(user: Principal, offset: Int = 0) async throws -> JSON {
        try await client.withConnection { c in
            .array(
                try await rows(
                    c,
                    """
                    SELECT row_to_json(w)::text FROM (SELECT w.*,m.role FROM workspaces w JOIN memberships m ON m.workspace_id=w.id
                    WHERE m.user_id=\(user.id) ORDER BY w.name,w.id LIMIT 200 OFFSET \(offset)) w
                    """))
        }
    }
    public func createWorkspace(user: Principal, input: JSON) async throws -> JSON {
        let name = try input.text("name")
        return try await client.withTransaction(logger: databaseLog) { c in
            let id = UUID()
            let result = try await one(
                c,
                "INSERT INTO workspaces(id,name,kind) VALUES(\(id),\(name),'team') RETURNING row_to_json(workspaces)::text"
            )
            try await execute(c, "INSERT INTO memberships VALUES(\(id),\(user.id),'owner')")
            try await audit(c, workspace: id, user: user.id, event: "workspace.created")
            return result
        }
    }
    public func members(workspace: UUID, user: Principal, offset: Int = 0) async throws -> JSON {
        try await client.withConnection { c in
            _ = try await role(c, workspace: workspace, user: user.id)
            return .array(
                try await rows(
                    c,
                    """
                    SELECT row_to_json(m)::text FROM (SELECT u.id,u.name,u.email,m.role FROM memberships m JOIN users u ON u.id=m.user_id
                    WHERE m.workspace_id=\(workspace) ORDER BY u.id LIMIT 1000 OFFSET \(offset)) m
                    """))
        }
    }
    public func removeMember(workspace: UUID, member: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            try await lock(c, workspace: workspace)
            let caller = try await role(c, workspace: workspace, user: user.id)
            let target = try await role(c, workspace: workspace, user: member)
            guard target != "owner", caller == "owner" || (caller == "admin" && target == "member") else {
                throw ServiceError(.forbidden, "cannot_remove_member")
            }
            try await execute(
                c, "DELETE FROM memberships WHERE workspace_id=\(workspace) AND user_id=\(member)")
            // Re-joining must not silently restore old document grants.
            try await execute(
                c,
                "DELETE FROM document_grants WHERE user_id=\(member) AND document_id IN (SELECT id FROM documents WHERE workspace_id=\(workspace))"
            )
            try await audit(c, workspace: workspace, user: user.id, event: "member.removed")
            return .object(["removed": .bool(true)])
        }
    }
    public func invite(workspace: UUID, user: Principal, input: JSON) async throws -> JSON {
        let email = try input.text("email").lowercased()
        let invitedRole = try input.text("role")
        guard email.contains("@"), ["admin", "member"].contains(invitedRole) else {
            throw ServiceError(.badRequest, "invalid_invitation")
        }
        return try await client.withTransaction(logger: databaseLog) { c in
            try await lock(c, workspace: workspace)
            let r = try await role(c, workspace: workspace, user: user.id)
            let workspaceKind = try await one(
                c, "SELECT to_json(kind)::text FROM workspaces WHERE id=\(workspace)")
            guard workspaceKind.string == "team", r == "owner" || (r == "admin" && invitedRole == "member")
            else {
                throw ServiceError(.forbidden, "cannot_invite")
            }
            let token = newToken()
            let id = UUID()
            let hash = digest(Data(token.utf8))
            try await execute(
                c,
                """
                INSERT INTO invitations(id,workspace_id,email,role,token_hash,created_by,expires_at)
                VALUES(\(id),\(workspace),\(email),\(invitedRole),\(hash),\(user.id),now()+interval '7 days')
                """)
            try await audit(c, workspace: workspace, user: user.id, event: "invitation.created")
            return .object(["id": .string(id.uuidString), "token": .string(token)])
        }
    }
    public func revokeInvitation(workspace: UUID, invitation: UUID, user: Principal) async throws -> JSON {
        try await client.withTransaction(logger: databaseLog) { c in
            try await lock(c, workspace: workspace)
            try await admin(c, workspace: workspace, user: user.id)
            let i = try await one(
                c,
                "UPDATE invitations SET revoked_at=now() WHERE id=\(invitation) AND workspace_id=\(workspace) RETURNING to_json(id)::text"
            )
            try await audit(c, workspace: workspace, user: user.id, event: "invitation.revoked")
            return .object(["id": i])
        }
    }
    public func acceptInvitation(token: String, user: Principal) async throws -> JSON {
        let hash = digest(Data(token.utf8))
        return try await client.withTransaction(logger: databaseLog) { c in
            let i = try await one(
                c, "SELECT row_to_json(i)::text FROM invitations i WHERE token_hash=\(hash)")
            let wid = i["workspace_id"].uuid!
            try await lock(c, workspace: wid)
            let valid = try await one(
                c,
                "SELECT row_to_json(i)::text FROM invitations i WHERE token_hash=\(hash) AND revoked_at IS NULL AND expires_at>now()"
            )
            guard user.email != nil, valid["email"].string == user.email,
                valid["accepted_by"] == .null || valid["accepted_by"].uuid == user.id
            else {
                throw ServiceError(.forbidden, "verified_invited_email_required")
            }
            // A removed member cannot replay an already-accepted invitation.
            if valid["accepted_by"] == .null {
                let r = valid["role"].string!
                try await execute(
                    c, "INSERT INTO memberships VALUES(\(wid),\(user.id),\(r)) ON CONFLICT DO NOTHING")
                try await execute(c, "UPDATE invitations SET accepted_by=\(user.id) WHERE token_hash=\(hash)")
                try await audit(c, workspace: wid, user: user.id, event: "invitation.accepted")
            }
            _ = try await role(c, workspace: wid, user: user.id)
            return .object(["workspace_id": .string(wid.uuidString)])
        }
    }
    public func activity(workspace: UUID, user: Principal, offset: Int = 0) async throws -> JSON {
        try await client.withConnection { c in
            try await admin(c, workspace: workspace, user: user.id)
            return .array(
                try await rows(
                    c,
                    "SELECT row_to_json(a)::text FROM (SELECT * FROM activity WHERE workspace_id=\(workspace) ORDER BY id DESC LIMIT 200 OFFSET \(offset)) a"
                ))
        }
    }
}
