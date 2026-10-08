// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation
import Hummingbird
import PostgresNIO

func jsonResponse(_ value: JSON, status: HTTPResponse.Status = .ok) throws -> Response {
    Response(
        status: status, headers: [.contentType: "application/json"],
        body: .init(byteBuffer: ByteBuffer(bytes: try JSONEncoder().encode(value))))
}
func binaryResponse(_ data: Data) -> Response {
    Response(
        status: .ok, headers: [.contentType: "application/octet-stream", .contentDisposition: "attachment"],
        body: .init(byteBuffer: ByteBuffer(bytes: data)))
}
func body(_ request: Request) async throws -> JSON {
    do {
        let bytes = try await request.body.collect(upTo: 65_536)
        return try JSONDecoder().decode(JSON.self, from: Data(bytes.readableBytesView))
    } catch let e as HTTPError { throw e } catch { throw ServiceError(.badRequest, "invalid_json") }
}
func listOffset(_ request: Request) throws -> Int {
    guard let value = request.uri.queryParameters["offset"] else { return 0 }
    guard let offset = Int(value), offset >= 0, offset <= 1_000_000 else {
        throw ServiceError(.badRequest, "invalid_offset")
    }
    return offset
}
func param(_ context: BasicRequestContext, _ name: String = "id") throws -> UUID {
    guard let id = UUID(uuidString: try context.parameters.require(name)) else {
        throw ServiceError(.badRequest, "invalid_identifier")
    }
    return id
}

struct ServiceMiddleware: RouterMiddleware {
    typealias Context = BasicRequestContext
    let allowedOrigins: Set<String>
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response)
        async throws -> Response
    {
        let origin = request.headers[.origin]
        var response: Response
        do {
            if let origin, !allowedOrigins.contains(origin) {
                throw ServiceError(.forbidden, "origin_not_allowed")
            }
            if request.method == .options {
                response = Response(status: .noContent)
            } else {
                response = try await next(request, context)
            }
        } catch {
            let e = (error as? PostgresTransactionError)?.closureError ?? error
            if let e = e as? ServiceError {
                response = try jsonResponse(.object(["error": .string(e.code)]), status: e.status)
            } else if let e = e as? HTTPResponseError {
                response = try e.response(from: request, context: context)
            } else {
                context.logger.error("Document service request failed")
                response = try jsonResponse(
                    .object(["error": .string("internal_error")]), status: .internalServerError)
            }
        }
        response.headers[.cacheControl] = "no-store"
        response.headers[.init("X-Content-Type-Options")!] = "nosniff"
        response.headers[.init("Referrer-Policy")!] = "no-referrer"
        if let origin, allowedOrigins.contains(origin) {
            response.headers[.accessControlAllowOrigin] = origin
            response.headers[.vary] = "Origin"
            response.headers[.accessControlAllowMethods] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
            response.headers[.accessControlAllowHeaders] = "Authorization, Content-Type"
        }
        return response
    }
}

public func makeRouter(
    repository r: Repository, authentication: any Authentication, allowedOrigins: Set<String> = []
) -> Router<BasicRequestContext> {
    let router = Router()
    router.add(middleware: ServiceMiddleware(allowedOrigins: allowedOrigins))
    @Sendable func user(_ request: Request) async throws -> Principal {
        guard let auth = request.headers[.authorization], auth.hasPrefix("Bearer "), auth.utf8.count < 16_400
        else {
            throw ServiceError(.unauthorized, "authentication_required")
        }
        return try await r.user(authentication.authenticate(String(auth.dropFirst(7))))
    }
    router.get("/health") { _, _ in JSON.object(["status": .string("ok")]) }
    router.get("/ready") { _, _ in
        try await r.client.withConnection { c in _ = try await one(c, "SELECT 'true'::text") }
        return JSON.object(["status": .string("ready")])
    }
    router.get("/v1/me") { request, _ in
        let u = try await user(request)
        return JSON.object(["id": .string(u.id.uuidString), "email": u.email.map(JSON.string) ?? .null])
    }
    router.get("/v1/workspaces") { request, _ in
        try await r.workspaces(user: user(request), offset: listOffset(request))
    }
    router.post("/v1/workspaces") { request, _ in
        try await r.createWorkspace(user: user(request), input: body(request))
    }
    router.get("/v1/workspaces/:id/members") { request, c in
        try await r.members(workspace: param(c), user: user(request), offset: listOffset(request))
    }
    router.delete("/v1/workspaces/:id/members/:member") { request, c in
        try await r.removeMember(workspace: param(c), member: param(c, "member"), user: user(request))
    }
    router.post("/v1/workspaces/:id/invitations") { request, c in
        try await r.invite(workspace: param(c), user: user(request), input: body(request))
    }
    router.delete("/v1/workspaces/:id/invitations/:invitation") { request, c in
        try await r.revokeInvitation(
            workspace: param(c), invitation: param(c, "invitation"), user: user(request))
    }
    router.post("/v1/invitations/accept") { request, _ in
        let u = try await user(request)
        let input = try await body(request)
        return try await r.acceptInvitation(token: input.text("token", max: 64), user: u)
    }
    router.get("/v1/workspaces/:id/activity") { request, c in
        try await r.activity(workspace: param(c), user: user(request), offset: listOffset(request))
    }
    router.get("/v1/workspaces/:id/documents") { request, c in
        try await r.documents(workspace: param(c), user: user(request), offset: listOffset(request))
    }
    router.post("/v1/workspaces/:id/documents") { request, c in
        try await r.createDocument(workspace: param(c), user: user(request), input: body(request))
    }
    router.get("/v1/workspaces/:id/folders") { request, c in
        try await r.folders(workspace: param(c), user: user(request))
    }
    router.post("/v1/workspaces/:id/folders") { request, c in
        try await r.createFolder(workspace: param(c), user: user(request), input: body(request))
    }
    router.post("/v1/documents/:id/move") { request, c in
        try await r.moveDocument(id: param(c), user: user(request), input: body(request))
    }
    router.get("/v1/documents/:id") { request, c in try await r.getDocument(id: param(c), user: user(request))
    }
    router.patch("/v1/documents/:id") { request, c in
        try await r.renameDocument(id: param(c), user: user(request), input: body(request))
    }
    router.delete("/v1/documents/:id") { request, c in
        try await r.trashDocument(id: param(c), user: user(request), restore: false)
    }
    router.post("/v1/documents/:id/restore") { request, c in
        try await r.trashDocument(id: param(c), user: user(request), restore: true)
    }
    router.post("/v1/documents/:id/admin-recovery") { request, c in
        try await r.recoverDocument(id: param(c), user: user(request))
    }
    router.get("/v1/documents/:id/grants") { request, c in
        try await r.grants(id: param(c), user: user(request))
    }
    router.post("/v1/documents/:id/grants") { request, c in
        try await r.grant(id: param(c), user: user(request), input: body(request))
    }
    router.delete("/v1/documents/:id/grants/:recipient") { request, c in
        try await r.revokeGrant(id: param(c), recipient: param(c, "recipient"), user: user(request))
    }
    router.get("/v1/documents/:id/shares") { request, c in
        try await r.links(id: param(c), user: user(request))
    }
    router.post("/v1/documents/:id/shares") { request, c in
        try await r.createLink(id: param(c), user: user(request), input: body(request))
    }
    router.delete("/v1/documents/:id/shares/:link") { request, c in
        try await r.revokeLink(id: param(c), link: param(c, "link"), user: user(request))
    }
    router.get("/v1/shares/:token") { _, c in try await r.sharedDocument(token: c.parameters.require("token"))
    }
    router.get("/v1/shares/:token/content") { _, c in
        try await binaryResponse(r.sharedContent(token: c.parameters.require("token")))
    }
    router.post("/v1/documents/:id/uploads") { request, c in
        try await r.prepareUpload(document: param(c), user: user(request), input: body(request))
    }
    router.get("/v1/uploads/:id") { request, c in try await r.getUpload(id: param(c), user: user(request)) }
    router.put("/v1/uploads/:id/content") { request, c in
        let u = try await user(request)
        let id = try param(c)
        // Authorize before collecting any large payload.
        _ = try await r.getUpload(id: id, user: u)
        let bytes = try await request.body.collect(upTo: 33_554_432)
        return try await r.uploadBytes(id: id, user: u, data: Data(bytes.readableBytesView))
    }
    router.get("/v1/uploads/:id/content") { request, c in
        try await binaryResponse(r.recoverUploadBytes(id: param(c), user: user(request)))
    }
    router.post("/v1/uploads/:id/commit") { request, c in
        let result = try await r.commitUpload(id: param(c), user: user(request))
        return try jsonResponse(result, status: result["state"].string == "conflict" ? .conflict : .ok)
    }
    router.get("/v1/documents/:id/content") { request, c in
        try await binaryResponse(r.content(document: param(c), revision: nil, user: user(request)))
    }
    router.get("/v1/documents/:id/revisions") { request, c in
        try await r.revisions(document: param(c), user: user(request), offset: listOffset(request))
    }
    router.get("/v1/documents/:id/revisions/:revision/content") { request, c in
        try await binaryResponse(
            r.content(document: param(c), revision: param(c, "revision"), user: user(request)))
    }
    router.post("/v1/documents/:id/revisions/:revision/restore") { request, c in
        try await r.restoreRevision(
            document: param(c), revision: param(c, "revision"), user: user(request), input: body(request))
    }
    return router
}
