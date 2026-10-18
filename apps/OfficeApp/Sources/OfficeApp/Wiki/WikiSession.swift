// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The wiki API, as the client speaks it (wiki/Sources/WikiServer/App.swift
// is the other side). Models mirror the server's JSON; dates stay strings.

import Flutter
import Foundation

struct WikiUser: Decodable { var id: String; var login: String; var name: String; var isAdmin: Bool }
struct WikiSpace: Decodable { var id: String; var key: String; var name: String; var homePage: String? }
struct WikiPageNode: Decodable { var id: String; var parent: String?; var position: Int; var title: String; var slug: String; var tip: Int; var updatedAt: String }
struct WikiPage: Decodable {
    var id: String; var space: String; var parent: String?; var title: String; var slug: String
    var version: Int; var tip: Int; var body: String; var plainText: String; var links: [String]
    var author: String?; var createdAt: String
}
struct WikiVersion: Decodable { var version: Int; var base: Int?; var title: String; var author: String?; var createdAt: String }
struct WikiLock: Decodable { var pageID: String; var userID: String; var userName: String; var token: String; var expiresAt: String }

enum WikiError: Error, CustomStringConvertible {
    case http(Int, String)
    case decoding(String)
    var description: String {
        switch self {
        case .http(let code, let m): return code == 0 ? "cannot reach the server: \(m)" : m
        case .decoding(let m): return "unexpected answer: \(m)"
        }
    }
    var status: Int { if case .http(let c, _) = self { return c } else { return -1 } }
}

final class WikiSession {
    /// "" in a tab (same origin); "http://host:port" natively.
    let base: String
    let transport: WikiTransport
    private(set) var user: WikiUser?

    init(base: String) {
        self.base = base.hasSuffix("/") ? String(base.dropLast()) : base
        #if os(WASI)
        transport = WebTransport()
        #else
        transport = NativeTransport()
        #endif
    }

    /// The site URL for a page, as the shell serves it.
    func pageURL(space: String, id: String, slug: String) -> String { "\(base)/s/\(space)/p/\(id)/\(slug)" }
    func pageRoute(space: String, id: String, slug: String) -> String { "/s/\(space)/p/\(id)/\(slug)" }

    private func call<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil, raw: Data? = nil, contentType: String? = nil,
                                    as type: T.Type, _ completion: @escaping (Result<T, WikiError>) -> Void) {
        var body = raw
        var ct = contentType
        if let json {
            body = try? JSONSerialization.data(withJSONObject: json)
            ct = "application/json"
        }
        transport.request(method, base + path, body: body, contentType: ct) { r in
            guard r.ok else { completion(.failure(.http(r.status, r.message))); return }
            if T.self == Data.self { completion(.success(r.body as! T)); return }
            do { completion(.success(try JSONDecoder().decode(T.self, from: r.body))) }
            catch { completion(.failure(.decoding("\(error)"))) }
        }
    }

    struct Nothing: Decodable {}

    func me(_ done: @escaping (Result<WikiUser, WikiError>) -> Void) {
        call("GET", "/api/v1/me", as: WikiUser.self) { [weak self] r in
            if case .success(let u) = r { self?.user = u }
            done(r)
        }
    }
    func login(_ login: String, password: String, _ done: @escaping (Result<WikiUser, WikiError>) -> Void) {
        call("POST", "/api/v1/login", json: ["login": login, "password": password], as: WikiUser.self) { [weak self] r in
            if case .success(let u) = r { self?.user = u }
            done(r)
        }
    }
    func logout(_ done: @escaping () -> Void) {
        call("POST", "/api/v1/logout", json: [:], as: Nothing.self) { [weak self] _ in self?.user = nil; done() }
    }
    func spaces(_ done: @escaping (Result<[WikiSpace], WikiError>) -> Void) { call("GET", "/api/v1/spaces", as: [WikiSpace].self, done) }
    func space(_ key: String, _ done: @escaping (Result<WikiSpace, WikiError>) -> Void) { call("GET", "/api/v1/spaces/\(key)", as: WikiSpace.self, done) }
    func tree(_ key: String, _ done: @escaping (Result<[WikiPageNode], WikiError>) -> Void) { call("GET", "/api/v1/spaces/\(key)/tree", as: [WikiPageNode].self, done) }
    func page(_ id: String, version: Int? = nil, _ done: @escaping (Result<WikiPage, WikiError>) -> Void) {
        call("GET", "/api/v1/pages/\(id)" + (version.map { "?version=\($0)" } ?? ""), as: WikiPage.self, done)
    }
    func versions(_ id: String, _ done: @escaping (Result<[WikiVersion], WikiError>) -> Void) { call("GET", "/api/v1/pages/\(id)/versions", as: [WikiVersion].self, done) }
    func createPage(space: String, title: String, parent: String?, _ done: @escaping (Result<WikiPage, WikiError>) -> Void) {
        var json: [String: Any] = ["title": title]
        if let parent { json["parent"] = parent }
        call("POST", "/api/v1/spaces/\(space)/pages", json: json, as: WikiPage.self, done)
    }
    func save(_ id: String, title: String, body: String, plainText: String, links: [String], base: Int, lockToken: String?, _ done: @escaping (Result<WikiPage, WikiError>) -> Void) {
        var json: [String: Any] = ["title": title, "body": body, "plainText": plainText, "links": links, "base": base]
        if let lockToken { json["lockToken"] = lockToken }
        call("PUT", "/api/v1/pages/\(id)", json: json, as: WikiPage.self, done)
    }
    func deletePage(_ id: String, _ done: @escaping (Result<Nothing, WikiError>) -> Void) { call("DELETE", "/api/v1/pages/\(id)", as: Nothing.self, done) }
    func lock(_ id: String, token: String?, _ done: @escaping (Result<WikiLock, WikiError>) -> Void) {
        call("POST", "/api/v1/pages/\(id)/lock", json: token.map { ["token": $0] } ?? [:], as: WikiLock.self, done)
    }
    func currentLock(_ id: String, _ done: @escaping (Result<WikiLock, WikiError>) -> Void) { call("GET", "/api/v1/pages/\(id)/lock", as: WikiLock.self, done) }
    func unlock(_ id: String, token: String, _ done: @escaping () -> Void) {
        call("DELETE", "/api/v1/pages/\(id)/lock?token=\(token)", as: Nothing.self) { _ in done() }
    }
    func importFile(space: String, name: String, parent: String?, data: Data, _ done: @escaping (Result<WikiPage, WikiError>) -> Void) {
        var path = "/api/v1/spaces/\(space)/import?name=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "upload.docx")"
        if let parent { path += "&parent=\(parent)" }
        call("POST", path, raw: data, contentType: "application/octet-stream", as: WikiPage.self, done)
    }
    func exportDocx(_ id: String, _ done: @escaping (Result<Data, WikiError>) -> Void) { call("GET", "/api/v1/pages/\(id)/export.docx", as: Data.self, done) }

    // MARK: The page body

    static func decodeBody(_ body: String) -> RichDocument? {
        try? RichDocumentEnvelope.decode(Data(body.utf8))
    }

    static func encodeBody(_ doc: RichDocument) -> String? {
        var doc = doc
        doc.assignParagraphIDs()
        return (try? RichDocumentEnvelope.encode(doc)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// What the server indexes and shows in link previews.
    static func plainText(_ doc: RichDocument) -> String {
        doc.paragraphs.lazy.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Page ids this document links to (links of the form …/p/<id>/…).
    static func linkedPages(_ doc: RichDocument) -> [String] {
        var out: [String] = []
        for p in doc.paragraphs {
            for run in p.runs {
                guard let link = run.style.link, let r = link.range(of: "/p/") else { continue }
                let rest = link[r.upperBound...]
                let id = String(rest.prefix { $0 != "/" && $0 != "#" && $0 != "?" })
                if id.count == 36, !out.contains(id) { out.append(id) }
            }
        }
        return out
    }
}
