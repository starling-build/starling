// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The HTTP surface (docs/plans/wiki.md W1). /api/v1/... is JSON for the
// app; /s/<space>/p/<id>/... is the shell; everything else is a static file
// of the app's build.

import Foundation
import Hummingbird
import Logging
import NIOCore

struct WikiContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    var user: User?
    init(source: Source) {
        coreContext = .init(source: source)
    }
}

/// Reads the session cookie and puts the user on the context.
struct SessionMiddleware: RouterMiddleware {
    typealias Context = WikiContext
    let store: Store
    func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
        var context = context
        if let cookie = request.cookies[App.sessionCookie] {
            context.user = try await store.user(forSession: cookie.value)
        }
        return try await next(request, context)
    }
}

extension User: ResponseEncodable {}
extension Space: ResponseEncodable {}
extension PageNode: ResponseEncodable {}
extension PageContent: ResponseEncodable {}
extension VersionInfo: ResponseEncodable {}
extension Lock: ResponseEncodable {}

struct Message: ResponseEncodable { var ok: Bool; var message: String }

struct App {
    static let sessionCookie = "wiki_session"

    let store: Store
    let converter: Converter
    let shell: Shell
    let webRoot: String
    let publicURL: String
    let logger: Logger

    func readBody(_ request: Request, limit: Int = 64 << 20) async throws -> Data {
        let buffer = try await request.body.collect(upTo: limit)
        return Data(buffer.readableBytesView)
    }

    func pageID(_ context: WikiContext) throws -> UUID {
        guard let id = UUID(uuidString: try context.parameters.require("id")) else { throw HTTPError(.badRequest, message: "not a page id") }
        return id
    }

    func requireUser(_ context: WikiContext) throws -> User {
        guard let user = context.user else { throw HTTPError(.unauthorized, message: "sign in") }
        return user
    }

    func map(_ error: Error) -> Error {
        switch error {
        case StoreError.notFound(let s): return HTTPError(.notFound, message: s)
        case StoreError.conflict(let s): return HTTPError(.conflict, message: s)
        case StoreError.locked(let by): return HTTPError(.init(code: 423), message: "locked by \(by)")
        case StoreError.badRequest(let s): return HTTPError(.badRequest, message: s)
        default: return error
        }
    }

    func json<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return Response(status: status, headers: [.contentType: "application/json; charset=utf-8"], body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    func router() -> Router<WikiContext> {
        let router = Router(context: WikiContext.self)
        router.add(middleware: SessionMiddleware(store: store))
        let api = router.group("api/v1")

        // --- session
        struct LoginBody: Decodable { var login: String; var password: String }
        api.post("login") { request, context in
            let body = try await request.decode(as: LoginBody.self, context: context)
            guard let (user, token) = try await store.login(body.login, password: body.password) else {
                throw HTTPError(.unauthorized, message: "wrong login or password")
            }
            var response = try json(user)
            response.setCookie(Cookie(name: App.sessionCookie, value: token, maxAge: 30 * 24 * 3600, path: "/", httpOnly: true))
            return response
        }
        api.post("logout") { request, context in
            if let cookie = request.cookies[App.sessionCookie] { try await store.logout(token: cookie.value) }
            var response = try json(Message(ok: true, message: "signed out"))
            response.setCookie(Cookie(name: App.sessionCookie, value: "", maxAge: 0, path: "/", httpOnly: true))
            return response
        }
        api.get("me") { _, context in try json(try requireUser(context)) }

        // --- spaces
        api.get("spaces") { _, context in
            _ = try requireUser(context)
            return try json(try await store.spaces())
        }
        struct NewSpace: Decodable { var key: String; var name: String }
        api.post("spaces") { request, context in
            let user = try requireUser(context)
            let body = try await request.decode(as: NewSpace.self, context: context)
            do { return try json(try await store.createSpace(key: body.key, name: body.name, by: user), status: .created) }
            catch { throw map(error) }
        }
        api.get("spaces/:key") { _, context in
            _ = try requireUser(context)
            guard let space = try await store.space(key: try context.parameters.require("key")) else { throw HTTPError(.notFound) }
            return try json(space)
        }
        api.get("spaces/:key/tree") { _, context in
            _ = try requireUser(context)
            guard let space = try await store.space(key: try context.parameters.require("key")) else { throw HTTPError(.notFound) }
            return try json(try await store.tree(spaceID: space.id))
        }
        struct NewPage: Decodable { var title: String; var parent: UUID?; var body: String?; var plainText: String?; var links: [UUID]? }
        api.post("spaces/:key/pages") { request, context in
            let user = try requireUser(context)
            guard let space = try await store.space(key: try context.parameters.require("key")) else { throw HTTPError(.notFound) }
            let body = try await request.decode(as: NewPage.self, context: context)
            let plain = body.plainText ?? body.body.map { BodyText.plainText($0) } ?? ""
            do {
                return try json(try await store.createPage(spaceID: space.id, spaceKey: space.key, parent: body.parent, title: body.title, body: body.body, plainText: plain, links: body.links ?? [], by: user), status: .created)
            } catch { throw map(error) }
        }
        // A file (docx, rtf, md) as a new page: raw bytes, ?name= and ?parent=.
        api.post("spaces/:key/import") { request, context in
            let user = try requireUser(context)
            guard let space = try await store.space(key: try context.parameters.require("key")) else { throw HTTPError(.notFound) }
            let name = request.uri.queryParameters["name"].map(String.init) ?? "upload.docx"
            let parent = request.uri.queryParameters["parent"].flatMap { UUID(uuidString: String($0)) }
            let data = try await readBody(request)
            let body: String
            do { body = try converter.toPage(data, named: name) } catch { throw HTTPError(.unprocessableContent, message: "\(error)") }
            let title = (name as NSString).deletingPathExtension
            do {
                return try json(try await store.createPage(spaceID: space.id, spaceKey: space.key, parent: parent, title: title, body: body, plainText: BodyText.plainText(body), links: [], by: user), status: .created)
            } catch { throw map(error) }
        }

        // --- pages
        api.get("pages/:id") { request, context in
            _ = try requireUser(context)
            let version = request.uri.queryParameters["version"].flatMap { Int($0) }
            guard let page = try await store.page(try pageID(context), version: version) else { throw HTTPError(.notFound) }
            return try json(page)
        }
        struct SaveBody: Decodable { var title: String; var body: String; var plainText: String?; var links: [UUID]?; var base: Int; var lockToken: String? }
        api.put("pages/:id") { request, context in
            let user = try requireUser(context)
            let id = try pageID(context)
            let body = try await request.decode(as: SaveBody.self, context: context)
            do {
                return try json(try await store.save(id, title: body.title, body: body.body, plainText: body.plainText ?? BodyText.plainText(body.body), links: body.links ?? [], base: body.base, lockToken: body.lockToken, by: user))
            } catch { throw map(error) }
        }
        api.delete("pages/:id") { _, context in
            let user = try requireUser(context)
            try await store.delete(try pageID(context), by: user)
            return try json(Message(ok: true, message: "deleted"))
        }
        struct MoveBody: Decodable { var parent: UUID?; var position: Int }
        api.post("pages/:id/move") { request, context in
            let user = try requireUser(context)
            let body = try await request.decode(as: MoveBody.self, context: context)
            do { try await store.move(try pageID(context), parent: body.parent, position: body.position, by: user) } catch { throw map(error) }
            return try json(Message(ok: true, message: "moved"))
        }
        api.get("pages/:id/versions") { _, context in
            _ = try requireUser(context)
            return try json(try await store.versions(of: try pageID(context)))
        }
        api.get("pages/:id/export.docx") { _, context in
            _ = try requireUser(context)
            guard let page = try await store.page(try pageID(context)) else { throw HTTPError(.notFound) }
            let data: Data
            do { data = try converter.toDocx(page.body) } catch { throw HTTPError(.serviceUnavailable, message: "\(error)") }
            var headers = HTTPFields()
            headers[.contentType] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            headers[.contentDisposition] = "attachment; filename=\"\(page.slug).docx\""
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
        }

        // --- locks
        struct LockBody: Decodable { var token: String? }
        api.post("pages/:id/lock") { request, context in
            let user = try requireUser(context)
            let body = (try? await request.decode(as: LockBody.self, context: context)) ?? LockBody(token: nil)
            do { return try json(try await store.acquireLock(try pageID(context), token: body.token, by: user)) } catch { throw map(error) }
        }
        api.get("pages/:id/lock") { _, context in
            _ = try requireUser(context)
            guard let lock = try await store.lock(of: try pageID(context)), lock.expiresAt > Date() else { throw HTTPError(.notFound, message: "not locked") }
            return try json(lock)
        }
        api.delete("pages/:id/lock") { request, context in
            let user = try requireUser(context)
            let token = request.uri.queryParameters["token"].map(String.init) ?? ""
            try await store.releaseLock(try pageID(context), token: token, by: user)
            return try json(Message(ok: true, message: "unlocked"))
        }

        // --- the shell: every page URL is the app, with the page in its meta tags.
        let shellHandler: @Sendable (Request, WikiContext) async throws -> Response = { request, context in
            var title = "Wiki", description = ""
            if let idText = context.parameters.get("id"), let id = UUID(uuidString: idText), let page = try await store.page(id) {
                title = page.title
                description = page.plainText
            } else if let key = context.parameters.get("space"), let space = try await store.space(key: key) {
                title = space.name
            }
            let route = request.uri.path
            let html = shell.render(route: route, title: title, description: description, url: publicURL + route)
            return Response(status: .ok, headers: [.contentType: "text/html; charset=utf-8", .cacheControl: "no-cache"], body: .init(byteBuffer: ByteBuffer(string: html)))
        }
        router.get("/", use: shellHandler)
        router.get("/s/:space", use: shellHandler)
        router.get("/s/:space/p/:id", use: shellHandler)
        router.get("/s/:space/p/:id/**", use: shellHandler)
        router.get("/login", use: shellHandler)

        // --- the app's files
        router.add(middleware: FileMiddleware(webRoot, searchForIndexHtml: false, logger: logger))
        return router
    }
}
