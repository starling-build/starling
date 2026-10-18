// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// wiki-server: serve, migrate, add-user, create-space, import.

import ArgumentParser
import Foundation
import Hummingbird
import Logging
import PostgresNIO

struct DatabaseOptions: ParsableArguments {
    @Option(name: .long, help: "Postgres URL, or set WIKI_DATABASE_URL") var database: String?

    func makeClient() throws -> PostgresClient {
        let urlText = database ?? ProcessInfo.processInfo.environment["WIKI_DATABASE_URL"] ?? "postgres://localhost/starling_wiki"
        guard let url = URL(string: urlText), let host = url.host else { throw ValidationError("not a database URL: \(urlText)") }
        let config = PostgresClient.Configuration(
            host: host, port: url.port ?? 5432,
            username: url.user ?? ProcessInfo.processInfo.environment["USER"] ?? "postgres",
            password: url.password,
            database: url.path.isEmpty ? nil : String(url.path.dropFirst()),
            tls: .disable)
        return PostgresClient(configuration: config)
    }
}

/// Run `body` with a live client; the client's run loop lives for the call.
func withStore<T: Sendable>(_ options: DatabaseOptions, _ body: @Sendable @escaping (Store) async throws -> T) async throws -> T {
    let client = try options.makeClient()
    var logger = Logger(label: "wiki")
    logger.logLevel = .info
    let store = Store(client: client, logger: logger)
    return try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { await client.run(); return nil }
        group.addTask { try await body(store) }
        var result: T?
        for try await r in group { if let r { result = r; break } }
        group.cancelAll()
        return result!
    }
}

@main
struct WikiServerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wiki-server", abstract: "The Starling wiki server (docs/plans/wiki.md).",
        subcommands: [Serve.self, Migrate.self, AddUser.self, CreateSpace.self, Import.self], defaultSubcommand: Serve.self)
}

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create or update the database schema.")
    @OptionGroup var db: DatabaseOptions
    func run() async throws { try await withStore(db) { try await $0.migrate() } }
}

struct AddUser: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add-user", abstract: "Add a local account.")
    @OptionGroup var db: DatabaseOptions
    @Argument var login: String
    @Option var name: String?
    @Option var password: String
    @Flag var admin = false
    func run() async throws {
        let user = try await withStore(db) { try await $0.addUser(login: login, name: name ?? login, password: password, admin: admin) }
        print("added \(user.login) (\(user.id))")
    }
}

struct CreateSpace: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create-space", abstract: "Create a space with its home page.")
    @OptionGroup var db: DatabaseOptions
    @Argument var key: String
    @Option var name: String?
    func run() async throws {
        let space = try await withStore(db) { try await $0.createSpace(key: key, name: name ?? key, by: nil) }
        print("created \(space.key): \(space.name) home \(space.homePage?.uuidString ?? "-")")
    }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Import files as pages of a space.")
    @OptionGroup var db: DatabaseOptions
    @Option(name: .long, help: "The headless OfficeApp binary") var officeApp: String
    @Option var space: String
    @Argument var files: [String]
    func run() async throws {
        let converter = Converter(officeApp: officeApp)
        try await withStore(db) { store in
            guard let sp = try await store.space(key: space) else { throw ValidationError("no space \(space)") }
            for f in files {
                let data = try Data(contentsOf: URL(fileURLWithPath: f))
                let body = try converter.toPage(data, named: f)
                let page = try await store.createPage(spaceID: sp.id, spaceKey: sp.key, parent: sp.homePage, title: ((f as NSString).lastPathComponent as NSString).deletingPathExtension, body: body, plainText: BodyText.plainText(body), links: [], by: nil)
                print("\(page.id) \(page.title)")
            }
        }
    }
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Serve the wiki.")
    @OptionGroup var db: DatabaseOptions
    @Option var host = "127.0.0.1"
    @Option var port = 8080
    @Option(name: .long, help: "The app's web build (index.html, app.wasm, …)") var webRoot = "web/office"
    @Option(name: .long, help: "The headless OfficeApp binary, for import and export") var officeApp: String?
    @Option(name: .long, help: "The URL users reach the site at, for link previews") var publicURL: String?
    @Option(name: .long, help: "DEVELOPMENT ONLY: every visitor without a session is this user; no sign-in") var devUser: String?

    func run() async throws {
        let client = try db.makeClient()
        var logger = Logger(label: "wiki")
        logger.logLevel = .info
        let store = Store(client: client, logger: logger)
        let indexPath = (webRoot as NSString).appendingPathComponent("index.html")
        let template = (try? String(contentsOfFile: indexPath, encoding: .utf8)) ?? "<!doctype html><html><head><title>Wiki</title></head><body>no web build at \(indexPath)</body></html>"
        let app = App(store: store, converter: Converter(officeApp: officeApp), shell: Shell(template: template), webRoot: webRoot,
                      publicURL: publicURL ?? "http://\(host):\(port)", logger: logger, devUser: devUser)
        if let devUser { logger.warning("--dev-user \(devUser): every visitor is signed in as them; never serve this way beyond a LAN") }
        let application = Application(
            router: app.router(),
            configuration: .init(address: .hostname(host, port: port), serverName: "starling-wiki"),
            logger: logger)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await client.run() }
            group.addTask { try await application.runService() }
            try await group.next()
            group.cancelAll()
        }
    }
}
