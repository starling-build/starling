// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Immutable source for one review/build. Include every file Git can publish
/// under pages, even files outside reader navigation, and every configured page.
struct SitePublicationSnapshot {
    let config: SiteConfig
    let sources: [(node: SiteNode, depth: Int, data: Data)]
    let files: [String: Data]

    static func readFiles(repo: String) throws -> [String: Data] {
        let root = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        var result: [String: Data] = [:]
        var eligible: Set<String>?
        func read(_ path: String) throws {
            if let eligible, !eligible.contains(path), !eligible.contains(where: { $0.hasPrefix(path + "/") }) { return }
            let file = root.appendingPathComponent(path)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw SiteError("Publication source must use ordinary files, not symbolic links. Review the source folder before publishing.") }
            if values.isDirectory == true {
                for name in try fm.contentsOfDirectory(atPath: file.path).sorted() { try read(path + "/" + name) }
            } else {
                guard values.isRegularFile == true else { throw SiteError("Publication source contains a file that cannot be reviewed.") }
                result[path] = try Data(contentsOf: file)
            }
        }
        try read(SiteFiles.config)
        if fm.fileExists(atPath: root.appendingPathComponent(".git").path) {
            let listed = LocalSiteStore.git(["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", SiteFiles.pagesDir], in: repo)
            guard listed.status == 0 else { throw SiteError("Could not inspect the publication source files. Check local history before publishing.") }
            let config = try SiteBuilder.decodeConfig(result[SiteFiles.config]!)
            eligible = Set(listed.output.split(separator: "\0").map(String.init))
                .union(SiteBuilder.manifest(from: config).flattened().map { SiteFiles.pagePath($0.node.slug) })
        }
        try read(SiteFiles.pagesDir)
        return result
    }

    static func load(repo: String, web: String?) throws -> Self {
        let files = try readFiles(repo: repo)
        guard let bytes = files[SiteFiles.config] else { throw SiteError("Publication configuration is missing.") }
        let config = try SiteBuilder.decodeConfig(bytes)
        let sources = try SiteBuilder.validatedSources(repo: repo, config: config, web: web)
        guard sources.allSatisfy({ files[SiteFiles.pagePath($0.node.slug)] == $0.data }),
              try readFiles(repo: repo) == files else { throw SiteReviewedPublication.changed }
        return Self(config: config, sources: sources, files: files)
    }

    func validateCurrent(repo: String) throws {
        guard try Self.readFiles(repo: repo) == files else { throw SiteReviewedPublication.changed }
    }

    /// Compare raw bytes, not UTF-8 round trips: unlisted source may be binary.
    func validateTree(repo: String, tree: String) throws {
        let listing = try Self.gitData(["ls-tree", "-rz", "--full-tree", tree, "--", SiteFiles.config, SiteFiles.pagesDir], repo: repo)
        var found = Set<String>()
        for entry in listing.split(separator: 0) {
            guard let tab = entry.firstIndex(of: 9),
                  let path = String(data: Data(entry[entry.index(after: tab)...]), encoding: .utf8),
                  let expected = files[path], found.insert(path).inserted,
                  let header = String(data: Data(entry[..<tab]), encoding: .utf8) else { throw SiteReviewedPublication.Failure.transformed }
            let parts = header.split(separator: " ")
            guard parts.count == 3, ["100644", "100755"].contains(parts[0]), parts[1] == "blob",
                  try Self.gitData(["cat-file", "blob", String(parts[2])], repo: repo) == expected else { throw SiteReviewedPublication.Failure.transformed }
        }
        guard found == Set(files.keys) else { throw SiteReviewedPublication.Failure.transformed }
    }

    private static func gitData(_ arguments: [String], repo: String) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo] + arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SiteError("Could not verify the publication's saved source. Refresh publication review before retrying.") }
        return data
    }
}

struct SiteReviewedPublication {
    enum Failure: Error, CustomStringConvertible {
        case changed, transformed
        var description: String {
            switch self {
            case .changed: return "The publication changed after review. Check the included pages and destination, then continue again."
            case .transformed: return "The saved publication differs from the prepared version. Check concurrent Git operations, commit hooks and clean filters, then review again."
            }
        }
    }
    static let changed = Failure.changed
    struct Context: Equatable {
        let repo: String
        let out: String
        let web: String?
        let destination: String?
        let target: String?
        let branch: String?
        let head: String?

        static func load(repo: String, out: String, web: String?) -> Self {
            func value(_ args: [String]) -> String? {
                let result = LocalSiteStore.git(args, in: repo)
                return result.status == 0 ? result.output.trimmingWhitespace() : nil
            }
            return Self(repo: URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath().path,
                        out: out, web: web.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path },
                        destination: try? SitePublicationState.destination(repo: repo),
                        target: try? SiteHosting.pushArguments(repo: repo).last,
                        branch: value(["symbolic-ref", "--quiet", "--short", "HEAD"]),
                        head: value(["rev-parse", "--verify", "HEAD"]))
        }
    }
    let input: SitePublicationSnapshot
    let context: Context

    func validate(repo: String, out: String, web: String?, savedRevision: String? = nil) throws {
        let current = Context.load(repo: repo, out: out, web: web)
        let expected = Context(repo: context.repo, out: context.out, web: context.web, destination: context.destination,
                               target: context.target, branch: context.branch, head: savedRevision ?? context.head)
        guard current == expected else { throw Self.changed }
        try input.validateCurrent(repo: repo)
    }

    /// Commit hooks must not introduce a different history or replace the built
    /// website after its index tree was captured. Failed checks keep local work.
    func validateCommit(repo: String, revision: String, stagedTree: String) throws {
        let paths = [SiteFiles.config, SiteFiles.pagesDir, context.out]
        guard LocalSiteStore.git(["--literal-pathspecs", "diff", "--quiet", stagedTree, revision, "--"] + paths, in: repo).status == 0 else { throw Failure.transformed }
        if revision != context.head {
            let parents = LocalSiteStore.git(["show", "-s", "--format=%P", revision], in: repo)
            guard parents.status == 0, parents.output.trimmingWhitespace() == (context.head ?? "") else { throw Self.changed }
            let changed = LocalSiteStore.git(["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", "--root", revision], in: repo)
            guard changed.status == 0, changed.output.split(separator: "\0").allSatisfy({ path in
                path == SiteFiles.config || path.hasPrefix(SiteFiles.pagesDir + "/") || path.hasPrefix(context.out + "/")
            }) else { throw Failure.transformed }
        }
        try input.validateTree(repo: repo, tree: revision)
    }
}
#endif
