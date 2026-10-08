// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import DocumentService
import Foundation
import Hummingbird
import PostgresNIO

@main struct Server {
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        func required(_ key: String) throws -> String {
            guard let value = env[key], !value.isEmpty else { throw ConfigurationError.missing(key) }
            return value
        }
        let host = env["STARLING_HOST"] ?? "127.0.0.1"
        let authentication: any Authentication
        if let devFile = env["STARLING_DEV_IDENTITIES"] {
            guard host == "127.0.0.1" else { throw ConfigurationError.developmentMustBeLoopback }
            let identities = try JSONDecoder().decode(
                [String: Identity].self, from: Data(contentsOf: URL(fileURLWithPath: devFile)))
            guard !identities.isEmpty, identities.keys.allSatisfy({ $0.count >= 32 }) else {
                throw ConfigurationError.invalidDevelopmentTokens
            }
            authentication = DevelopmentAuthentication(tokens: identities)
        } else {
            guard let jwksURL = URL(string: try required("OIDC_JWKS_URL")) else {
                throw ConfigurationError.invalidJWKSURL
            }
            authentication = try OIDCAuthentication(
                issuer: required("OIDC_ISSUER"), audience: required("OIDC_AUDIENCE"), jwksURL: jwksURL)
        }
        let databaseHost = env["PGHOST"] ?? "127.0.0.1"
        let config: PostgresClient.Configuration
        if databaseHost.hasPrefix("/") {
            config = .init(
                unixSocketPath: databaseHost + "/.s.PGSQL." + (env["PGPORT"] ?? "5432"),
                username: try required("PGUSER"), password: env["PGPASSWORD"],
                database: try required("PGDATABASE"))
        } else {
            config = .init(
                host: databaseHost, port: Int(env["PGPORT"] ?? "5432") ?? 5432,
                username: try required("PGUSER"),
                password: env["PGPASSWORD"], database: try required("PGDATABASE"),
                tls: env["PGSSLMODE"] == "disable" ? .disable : .require(.makeClientConfiguration()))
        }
        let client = PostgresClient(configuration: config)
        let storage: any BlobStorage
        if let bucket = env["S3_BUCKET"] {
            storage = S3Storage(
                bucket: bucket, region: env["AWS_REGION"] ?? "us-east-1", endpoint: env["S3_ENDPOINT"])
        } else {
            storage = try DiskStorage(
                root: URL(fileURLWithPath: env["STARLING_STORAGE_PATH"] ?? "./data/blobs"))
        }
        let repository = Repository(client: client, storage: storage)
        // Start the connection pool before migrations or worker requests.
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { await client.run() }
                try await repository.migrate()
                if CommandLine.arguments.contains("--cleanup") {
                    try await repository.cleanup()
                    group.cancelAll()
                    return
                }
                let origins = Set(
                    (env["STARLING_ALLOWED_ORIGINS"] ?? "").split(separator: ",").map(String.init))
                let app = Application(
                    router: makeRouter(
                        repository: repository, authentication: authentication, allowedOrigins: origins),
                    configuration: .init(address: .hostname(host, port: Int(env["PORT"] ?? "8090") ?? 8090)))
                group.addTask {
                    while !Task.isCancelled {
                        do { try await repository.cleanup() } catch {
                            Logger(label: "starling.documents.cleanup").error("Cleanup failed; will retry")
                        }
                        try await Task.sleep(for: .seconds(300))
                    }
                }
                defer { group.cancelAll() }
                try await app.runService()
            }
            try await storage.shutdown()
        } catch {
            try? await storage.shutdown()
            throw error
        }
    }
}
enum ConfigurationError: Error {
    case missing(String)
    case developmentMustBeLoopback, invalidDevelopmentTokens, invalidJWKSURL
}
