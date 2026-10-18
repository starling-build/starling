// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Everything the server keeps, behind one type. Postgres through
// PostgresNIO; every method is one statement or one short transaction.

import Crypto
import Foundation
import Logging
import PostgresNIO

struct User: Codable, Sendable {
    var id: UUID
    var login: String
    var name: String
    var isAdmin: Bool
}

struct Space: Codable, Sendable {
    var id: UUID
    var key: String
    var name: String
    var homePage: UUID?
}

/// A page as the tree shows it.
struct PageNode: Codable, Sendable {
    var id: UUID
    var parent: UUID?
    var position: Int
    var title: String
    var slug: String
    var tip: Int
    var updatedAt: Date
}

/// A page with one version's content.
struct PageContent: Codable, Sendable {
    var id: UUID
    var space: String
    var parent: UUID?
    var title: String
    var slug: String
    var version: Int
    var tip: Int
    var body: String
    var plainText: String
    var links: [UUID]
    var author: String?
    var createdAt: Date
}

struct VersionInfo: Codable, Sendable {
    var version: Int
    var base: Int?
    var title: String
    var author: String?
    var createdAt: Date
}

struct Lock: Codable, Sendable {
    var pageID: UUID
    var userID: UUID
    var userName: String
    var token: String
    var expiresAt: Date
}

enum StoreError: Error, CustomStringConvertible {
    case notFound(String)
    case conflict(String)
    case locked(by: String)
    case badRequest(String)
    var description: String {
        switch self {
        case .notFound(let s): return "not found: \(s)"
        case .conflict(let s): return "conflict: \(s)"
        case .locked(let by): return "locked by \(by)"
        case .badRequest(let s): return s
        }
    }
}

final class Store: Sendable {
    let client: PostgresClient
    let logger: Logger

    init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    // MARK: Migrations

    func migrate() async throws {
        try await client.query("CREATE TABLE IF NOT EXISTS schema_migrations (version BIGINT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())", logger: logger)
        var applied = Set<Int>()
        for try await (v) in try await client.query("SELECT version FROM schema_migrations", logger: logger).decode(Int.self) { applied.insert(v) }
        for (i, sql) in Schema.migrations.enumerated() where !applied.contains(i + 1) {
            logger.info("applying migration \(i + 1)")
            try await client.withConnection { conn in
                try await conn.query("BEGIN", logger: logger)
                for statement in sql.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !statement.isEmpty {
                    try await conn.query(PostgresQuery(unsafeSQL: statement), logger: logger)
                }
                try await conn.query("INSERT INTO schema_migrations (version) VALUES (\(i + 1))", logger: logger)
                try await conn.query("COMMIT", logger: logger)
            }
        }
    }

    // MARK: Users and sessions

    /// salt$rounds$hex — SHA-256 iterated; local accounts only (SSO is W2).
    static func hashPassword(_ password: String, salt: String? = nil, rounds: Int = 50_000) -> String {
        let salt = salt ?? Data((0 ..< 16).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
        var digest = Data((salt + password).utf8)
        for _ in 0 ..< rounds { digest = Data(SHA256.hash(data: digest)) }
        return "\(salt)$\(rounds)$" + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ password: String, against stored: String) -> Bool {
        let parts = stored.split(separator: "$", maxSplits: 2).map(String.init)
        guard parts.count == 3, let rounds = Int(parts[1]) else { return false }
        return hashPassword(password, salt: parts[0], rounds: rounds) == stored
    }

    func addUser(login: String, name: String, password: String, admin: Bool) async throws -> User {
        let id = UUID()
        try await client.query("INSERT INTO users (id, login, name, password, is_admin) VALUES (\(id), \(login), \(name), \(Store.hashPassword(password)), \(admin))", logger: logger)
        return User(id: id, login: login, name: name, isAdmin: admin)
    }

    func login(_ login: String, password: String) async throws -> (User, token: String)? {
        let rows = try await client.query("SELECT id, login, name, password, is_admin FROM users WHERE login = \(login)", logger: logger)
        for try await (id, login, name, stored, admin) in rows.decode((UUID, String, String, String?, Bool).self) {
            guard let stored, Store.verify(password, against: stored) else { return nil }
            let token = Data((0 ..< 32).map { _ in UInt8.random(in: 0 ... 255) }).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            let expires = Date().addingTimeInterval(30 * 24 * 3600)
            try await client.query("INSERT INTO sessions (token, user_id, expires_at) VALUES (\(token), \(id), \(expires))", logger: logger)
            return (User(id: id, login: login, name: name, isAdmin: admin), token)
        }
        return nil
    }

    func user(forSession token: String) async throws -> User? {
        let rows = try await client.query("SELECT u.id, u.login, u.name, u.is_admin FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = \(token) AND s.expires_at > now()", logger: logger)
        for try await (id, login, name, admin) in rows.decode((UUID, String, String, Bool).self) {
            return User(id: id, login: login, name: name, isAdmin: admin)
        }
        return nil
    }

    func logout(token: String) async throws {
        try await client.query("DELETE FROM sessions WHERE token = \(token)", logger: logger)
    }

    // MARK: Spaces

    func spaces() async throws -> [Space] {
        var out: [Space] = []
        for try await (id, key, name, home) in try await client.query("SELECT id, key, name, home_page FROM spaces ORDER BY name", logger: logger).decode((UUID, String, String, UUID?).self) {
            out.append(Space(id: id, key: key, name: name, homePage: home))
        }
        return out
    }

    func space(key: String) async throws -> Space? {
        for try await (id, key, name, home) in try await client.query("SELECT id, key, name, home_page FROM spaces WHERE key = \(key)", logger: logger).decode((UUID, String, String, UUID?).self) {
            return Space(id: id, key: key, name: name, homePage: home)
        }
        return nil
    }

    func createSpace(key: String, name: String, by user: User?) async throws -> Space {
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { throw StoreError.badRequest("a space key is letters, digits, - and _") }
        if try await space(key: key) != nil { throw StoreError.conflict("space \(key) exists") }
        let id = UUID()
        try await client.query("INSERT INTO spaces (id, key, name) VALUES (\(id), \(key), \(name))", logger: logger)
        // Every space opens on a home page.
        let home = try await createPage(spaceID: id, spaceKey: key, parent: nil, title: name, body: nil, plainText: "", links: [], by: user)
        try await client.query("UPDATE spaces SET home_page = \(home.id) WHERE id = \(id)", logger: logger)
        try await audit(user, "space.create", key, "{}")
        return Space(id: id, key: key, name: name, homePage: home.id)
    }

    // MARK: Pages

    static func slug(_ title: String) -> String {
        var out = ""
        var dash = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch); dash = false }
            else if !dash, !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "page" : String(out.prefix(80))
    }

    func tree(spaceID: UUID) async throws -> [PageNode] {
        var out: [PageNode] = []
        let rows = try await client.query("SELECT id, parent_id, position, title, slug, tip, updated_at FROM pages WHERE space_id = \(spaceID) AND deleted_at IS NULL ORDER BY parent_id, position, created_at", logger: logger)
        for try await (id, parent, position, title, slug, tip, updated) in rows.decode((UUID, UUID?, Int, String, String, Int, Date).self) {
            out.append(PageNode(id: id, parent: parent, position: position, title: title, slug: slug, tip: tip, updatedAt: updated))
        }
        return out
    }

    /// An empty page body, when a page is made without one. The client
    /// knows the model; the server only needs something valid to store.
    static let emptyBody = #"{"schema":1,"document":{"paragraphs":[{"text":"","runs":[{"length":0,"style":{}}],"style":{}}]}}"#

    func createPage(spaceID: UUID, spaceKey: String, parent: UUID?, title: String, body: String?, plainText: String, links: [UUID], by user: User?) async throws -> PageContent {
        let id = UUID()
        let slug = Store.slug(title)
        let position: Int = try await {
            for try await (n) in try await client.query("SELECT COALESCE(MAX(position), -1) + 1 FROM pages WHERE space_id = \(spaceID) AND parent_id IS NOT DISTINCT FROM \(parent)", logger: logger).decode(Int.self) { return n }
            return 0
        }()
        let body = body ?? Store.emptyBody
        let linksJSON = "[" + links.map { "\"\($0.uuidString)\"" }.joined(separator: ",") + "]"
        try await client.withConnection { conn in
            try await conn.query("BEGIN", logger: logger)
            try await conn.query("INSERT INTO pages (id, space_id, parent_id, position, title, slug, tip, created_by) VALUES (\(id), \(spaceID), \(parent), \(position), \(title), \(slug), 1, \(user?.id))", logger: logger)
            try await conn.query("INSERT INTO page_versions (page_id, version, base, title, body, plain_text, links, author_id) VALUES (\(id), 1, NULL, \(title), \(body), \(plainText), \(linksJSON), \(user?.id))", logger: logger)
            try await conn.query("COMMIT", logger: logger)
        }
        try await audit(user, "page.create", id.uuidString, "{\"title\":\(jsonString(title))}")
        return PageContent(id: id, space: spaceKey, parent: parent, title: title, slug: slug, version: 1, tip: 1, body: body, plainText: plainText, links: links, author: user?.name, createdAt: Date())
    }

    func page(_ id: UUID, version: Int? = nil) async throws -> PageContent? {
        let rows = try await client.query("""
            SELECT p.id, s.key, p.parent_id, p.title, p.slug, v.version, p.tip, v.body, v.plain_text, v.links, u.name, v.created_at
            FROM pages p JOIN spaces s ON s.id = p.space_id
            JOIN page_versions v ON v.page_id = p.id AND v.version = COALESCE(\(version), p.tip)
            LEFT JOIN users u ON u.id = v.author_id
            WHERE p.id = \(id) AND p.deleted_at IS NULL
            """, logger: logger)
        for try await (id, space, parent, title, slug, version, tip, body, plain, links, author, created) in rows.decode((UUID, String, UUID?, String, String, Int, Int, String, String, String, String?, Date).self) {
            let linkIDs = (try? JSONDecoder().decode([UUID].self, from: Data(links.utf8))) ?? []
            return PageContent(id: id, space: space, parent: parent, title: title, slug: slug, version: version, tip: tip, body: body, plainText: plain, links: linkIDs, author: author, createdAt: created)
        }
        return nil
    }

    func versions(of id: UUID) async throws -> [VersionInfo] {
        var out: [VersionInfo] = []
        let rows = try await client.query("SELECT v.version, v.base, v.title, u.name, v.created_at FROM page_versions v LEFT JOIN users u ON u.id = v.author_id WHERE v.page_id = \(id) ORDER BY v.version DESC", logger: logger)
        for try await (version, base, title, author, created) in rows.decode((Int, Int?, String, String?, Date).self) {
            out.append(VersionInfo(version: version, base: base, title: title, author: author, createdAt: created))
        }
        return out
    }

    /// A new version. `base` is the version the author edited from; it
    /// must be the tip (W1 — merge comes in W3). `lockToken`, when the page
    /// is locked, must be the holder's.
    func save(_ id: UUID, title: String, body: String, plainText: String, links: [UUID], base: Int, lockToken: String?, by user: User) async throws -> PageContent {
        if let lock = try await lock(of: id), lock.expiresAt > Date(), lock.token != lockToken {
            throw StoreError.locked(by: lock.userName)
        }
        let linksJSON = "[" + links.map { "\"\($0.uuidString)\"" }.joined(separator: ",") + "]"
        let slug = Store.slug(title)
        var newVersion = 0
        try await client.withConnection { conn in
            try await conn.query("BEGIN", logger: logger)
            var tip = -1
            for try await (t) in try await conn.query("SELECT tip FROM pages WHERE id = \(id) AND deleted_at IS NULL FOR UPDATE", logger: logger).decode(Int.self) { tip = t }
            guard tip >= 0 else { try await conn.query("ROLLBACK", logger: logger); throw StoreError.notFound("page \(id)") }
            guard tip == base else { try await conn.query("ROLLBACK", logger: logger); throw StoreError.conflict("page is at version \(tip), you edited \(base)") }
            newVersion = tip + 1
            try await conn.query("INSERT INTO page_versions (page_id, version, base, title, body, plain_text, links, author_id) VALUES (\(id), \(newVersion), \(base), \(title), \(body), \(plainText), \(linksJSON), \(user.id))", logger: logger)
            try await conn.query("UPDATE pages SET tip = \(newVersion), title = \(title), slug = \(slug), updated_at = now() WHERE id = \(id)", logger: logger)
            try await conn.query("COMMIT", logger: logger)
        }
        try await audit(user, "page.save", id.uuidString, "{\"version\":\(newVersion)}")
        guard let page = try await page(id) else { throw StoreError.notFound("page \(id)") }
        return page
    }

    func move(_ id: UUID, parent: UUID?, position: Int, by user: User) async throws {
        if let parent {
            // Not under itself or its own descendant.
            var p: UUID? = parent
            var hops = 0
            while let cur = p, hops < 1000 {
                if cur == id { throw StoreError.badRequest("a page cannot move under itself") }
                p = nil
                for try await (pp) in try await client.query("SELECT parent_id FROM pages WHERE id = \(cur)", logger: logger).decode(UUID?.self) { p = pp }
                hops += 1
            }
        }
        try await client.query("UPDATE pages SET parent_id = \(parent), position = \(position), updated_at = now() WHERE id = \(id) AND deleted_at IS NULL", logger: logger)
        try await audit(user, "page.move", id.uuidString, "{}")
    }

    func delete(_ id: UUID, by user: User) async throws {
        try await client.query("UPDATE pages SET deleted_at = now() WHERE id = \(id)", logger: logger)
        try await client.query("UPDATE pages SET parent_id = (SELECT parent_id FROM pages WHERE id = \(id)) WHERE parent_id = \(id)", logger: logger)
        try await audit(user, "page.delete", id.uuidString, "{}")
    }

    // MARK: Search

    struct Hit: Codable, Sendable {
        var id: UUID
        var space: String
        var title: String
        var slug: String
        var snippet: String
        var updatedAt: Date
    }

    /// Pages whose current version's title or text matches `query`: word
    /// matches through the text-search index, and a plain substring
    /// match for queries the tokeniser cannot split (CJK, code).
    func search(_ query: String, space: String?, limit: Int = 50) async throws -> [Hit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let like = "%" + q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        let rows = try await client.query("""
            SELECT p.id, s.key, p.title, p.slug, v.plain_text, p.updated_at
            FROM pages p JOIN spaces s ON s.id = p.space_id
            JOIN page_versions v ON v.page_id = p.id AND v.version = p.tip
            WHERE p.deleted_at IS NULL
              AND (\(space)::text IS NULL OR s.key = \(space)::text)
              AND (to_tsvector('simple', v.title || ' ' || v.plain_text) @@ plainto_tsquery('simple', \(q))
                   OR v.title ILIKE \(like) OR v.plain_text ILIKE \(like))
            ORDER BY p.updated_at DESC
            LIMIT \(limit)
            """, logger: logger)
        var out: [Hit] = []
        for try await (id, key, title, slug, text, updated) in rows.decode((UUID, String, String, String, String, Date).self) {
            out.append(Hit(id: id, space: key, title: title, slug: slug, snippet: Store.snippet(text, around: q), updatedAt: updated))
        }
        return out
    }

    /// Up to ~160 characters around the first match, or the text's start.
    static func snippet(_ text: String, around q: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let r = flat.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(flat.prefix(160)) }
        let start = flat.index(r.lowerBound, offsetBy: -60, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 100, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start ..< end] + (end < flat.endIndex ? "…" : "")
    }

    // MARK: Locks

    func lock(of id: UUID) async throws -> Lock? {
        let rows = try await client.query("SELECT l.page_id, l.user_id, u.name, l.token, l.expires_at FROM page_locks l JOIN users u ON u.id = l.user_id WHERE l.page_id = \(id)", logger: logger)
        for try await (page, user, name, token, expires) in rows.decode((UUID, UUID, String, String, Date).self) {
            return Lock(pageID: page, userID: user, userName: name, token: token, expiresAt: expires)
        }
        return nil
    }

    static let lockLife: TimeInterval = 5 * 60

    /// Take or renew the lock. A token renews its own; an expired lock, or
    /// the same user's, is taken over.
    func acquireLock(_ id: UUID, token: String?, by user: User) async throws -> Lock {
        let now = Date()
        if let existing = try await lock(of: id), existing.expiresAt > now, existing.userID != user.id, existing.token != token {
            throw StoreError.locked(by: existing.userName)
        }
        let token = token ?? UUID().uuidString
        let expires = now.addingTimeInterval(Store.lockLife)
        try await client.query("""
            INSERT INTO page_locks (page_id, user_id, token, expires_at) VALUES (\(id), \(user.id), \(token), \(expires))
            ON CONFLICT (page_id) DO UPDATE SET user_id = \(user.id), token = \(token), expires_at = \(expires)
            """, logger: logger)
        return Lock(pageID: id, userID: user.id, userName: user.name, token: token, expiresAt: expires)
    }

    func releaseLock(_ id: UUID, token: String, by user: User) async throws {
        try await client.query("DELETE FROM page_locks WHERE page_id = \(id) AND (token = \(token) OR user_id = \(user.id))", logger: logger)
    }

    // MARK: Audit

    func audit(_ user: User?, _ action: String, _ subject: String, _ detail: String) async throws {
        try await client.query("INSERT INTO audit (user_id, action, subject, detail) VALUES (\(user?.id), \(action), \(subject), \(detail))", logger: logger)
    }
}

func jsonString(_ s: String) -> String {
    let data = try? JSONEncoder().encode([s])
    let text = data.map { String(decoding: $0, as: UTF8.self) } ?? "[\"\"]"
    return String(text.dropFirst().dropLast())
}
