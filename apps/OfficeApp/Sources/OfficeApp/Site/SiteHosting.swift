// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

#if !os(WASI)
/// Local hosting configuration. None of these operations contacts a server.
enum SiteHosting {
    struct Snapshot {
        let bytes: Data
        let config: SiteConfig
    }

    struct Settings {
        let title: String
        let repository: String?
        let url: String?
        let base: String?

        init(title: String, repository: String, url: String) throws {
            let title = title.trimmingWhitespace()
            guard !title.isEmpty else { throw SiteError("Enter a publication title.") }
            self.title = title
            let repository = repository.trimmingWhitespace()
            self.repository = repository.isEmpty ? nil : try SiteHosting.githubRepository(repository)
            let address = url.trimmingWhitespace()
            if address.isEmpty { self.url = nil; self.base = nil; return }
            guard let parts = URLComponents(string: address), parts.scheme == "https",
                  let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
                  parts.query == nil, parts.fragment == nil, parts.port == nil,
                  parts.percentEncodedPath == parts.path,
                  parts.path.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-._/".contains($0)) }),
                  !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
                  !parts.path.contains("//") else {
                throw SiteError("Enter an HTTPS website address without credentials, a port, query or fragment. Use a simple path such as /handbook/.")
            }
            let base = SiteFiles.normalizedBase(parts.path)
            self.base = base
            self.url = "https://" + host.lowercased() + base
        }
    }

    /// Accept a web repository URL in the form; recognize existing SSH Git
    /// remotes too when comparing, without changing the author's transport.
    static func githubRepository(_ input: String, allowSSH: Bool = false) throws -> String {
        var raw = input.trimmingWhitespace()
        if allowSSH, raw.hasPrefix("git@github.com:") {
            raw = "https://github.com/" + raw.dropFirst("git@github.com:".count)
        } else if allowSSH, raw.hasPrefix("ssh://git@github.com/") {
            raw = "https://github.com/" + raw.dropFirst("ssh://git@github.com/".count)
        }
        guard let parts = URLComponents(string: raw), parts.scheme == "https", parts.host?.lowercased() == "github.com",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil, parts.percentEncodedPath == parts.path else {
            throw SiteError("Use a repository address like https://github.com/owner/handbook, without credentials.")
        }
        var path = parts.path
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        let pieces = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasPrefix("/"), pieces.count == 2,
              pieces.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }) else {
            throw SiteError("Enter the repository address, not a file, branch or GitHub settings page.")
        }
        return "https://github.com/" + pieces.joined(separator: "/")
    }

    static func suggestedURL(repository: String) throws -> String {
        let canonical = try githubRepository(repository)
        let parts = canonical.split(separator: "/")
        let owner = String(parts[2]).lowercased(), name = String(parts[3])
        return "https://\(owner).github.io/" + (name.lowercased() == owner + ".github.io" ? "" : name + "/")
    }

    static func pagesSettingsURL(repository: String) throws -> String {
        try githubRepository(repository) + "/settings/pages"
    }

    static func pagesSource(repo: String, out: String) throws -> String {
        guard out == "docs" else {
            throw SiteError("This publication builds into \(out)/. GitHub's branch publishing supports /docs or the repository root. Use a deployment workflow for this custom output folder.")
        }
        let target = try pushArguments(repo: repo).last!
        let branch = String(target.dropFirst("HEAD:refs/heads/".count))
        return "Choose Deploy from a branch, branch \(branch), and folder /docs, then Save. Publish once before selecting the branch if it is not listed."
    }

    static func load(repo: String) throws -> Snapshot {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json"))
        return Snapshot(bytes: bytes, config: try JSONDecoder().decode(SiteConfig.self, from: bytes))
    }

    /// Optimistic check protects intervening title/tree edits. Preserve unknown
    /// config keys as well as the page hierarchy for forward compatibility.
    static func save(_ settings: Settings, repo: String, expected: Snapshot) throws {
        let path = URL(fileURLWithPath: repo + "/site.json")
        guard try Data(contentsOf: path) == expected.bytes else {
            throw SiteError("The publication settings changed elsewhere. Close and reopen Hosting before saving.")
        }
        guard var object = try JSONSerialization.jsonObject(with: expected.bytes) as? [String: Any] else {
            throw SiteError("The publication configuration is not an object.")
        }
        object["title"] = settings.title
        object["repository"] = settings.repository
        object["url"] = settings.url
        // Clearing a URL should not silently reset an existing project base.
        if let base = settings.base { object["base"] = base }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
    }

    static func requireRoot(_ repo: String) throws {
        let root = LocalSiteStore.git(["rev-parse", "--show-toplevel"], in: repo)
        guard root.status == 0,
              URL(fileURLWithPath: root.output.trimmingWhitespace()).resolvingSymlinksInPath().path
                == URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath().path else {
            throw SiteError("Open the root of the publication's own Git repository.")
        }
    }

    static func connect(repo: String) throws {
        try requireRoot(repo)
        let snapshot = try load(repo: repo)
        let wanted = try githubRepository(snapshot.config.repository ?? "")
        let remotes = LocalSiteStore.git(["remote"], in: repo)
        guard remotes.status == 0 else { throw SiteError("Could not inspect local Git remotes.") }
        if remotes.output.split(separator: "\n").contains("origin") {
            let existing = LocalSiteStore.git(["remote", "get-url", "--all", "origin"], in: repo)
            guard existing.status == 0,
                  (try? githubRepository(existing.output.trimmingWhitespace(), allowSSH: true).lowercased()) == wanted.lowercased() else {
                throw SiteError("An origin remote is already configured for a different destination. It was not changed. Use that repository address or review the remote in Git.")
            }
            return
        }
        let result = LocalSiteStore.git(["remote", "add", "origin", wanted + ".git"], in: repo)
        guard result.status == 0 else { throw SiteError("Could not add origin. Check the repository's Git configuration; no files were published.") }
    }

    /// Local Git blockers, also checked before publishing can build or commit.
    static func gitProblems(repo: String) -> [String] {
        do { try requireRoot(repo) } catch { return ["\(error)"] }
        var problems: [String] = []
        do { _ = try pushArguments(repo: repo) } catch { problems.append("\(error)") }
        for identity in ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] {
            if LocalSiteStore.git(["var", identity], in: repo).status != 0 {
                problems.append("Save your author name and email in Publishing settings before publishing.")
                break
            }
        }
        if LocalSiteStore.git(["remote", "get-url", "origin"], in: repo).status != 0 {
            problems.append("Connect the publication repository as origin before publishing.")
        }
        let unmerged = LocalSiteStore.git(["ls-files", "--unmerged"], in: repo)
        if unmerged.status != 0 || !unmerged.output.trimmingWhitespace().isEmpty {
            problems.append("Resolve Git conflicts before publishing.")
        }
        for marker in ["MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"] {
            let path = LocalSiteStore.git(["rev-parse", "--git-path", marker], in: repo).output.trimmingWhitespace()
            let absolute = path.hasPrefix("/") ? path : repo + "/" + path
            if !path.isEmpty, FileManager.default.fileExists(atPath: absolute) {
                problems.append("Finish or abort the current Git merge, rebase or cherry-pick before publishing.")
                break
            }
        }
        return problems
    }

    /// Explicit remote and refspec prevent push.default, remote.pushDefault
    /// or remote.origin.push from uploading unrelated branches/destinations.
    /// Preserve a deliberately configured origin branch name.
    static func pushArguments(repo: String) throws -> [String] {
        let branch = LocalSiteStore.git(["symbolic-ref", "--quiet", "--short", "HEAD"], in: repo)
        guard branch.status == 0 else { throw SiteError("Check out a branch before publishing; HEAD is detached.") }
        let name = branch.output.trimmingWhitespace()
        let remote = LocalSiteStore.git(["config", "--get", "branch.\(name).remote"], in: repo)
        if remote.status == 0, remote.output.trimmingWhitespace() != "origin" {
            throw SiteError("This branch tracks a different remote. Review its Git upstream before publishing to origin.")
        }
        let merge = LocalSiteStore.git(["config", "--get", "branch.\(name).merge"], in: repo)
        let target = merge.status == 0 ? merge.output.trimmingWhitespace() : "refs/heads/" + name
        guard target.hasPrefix("refs/heads/"), LocalSiteStore.git(["check-ref-format", target], in: repo).status == 0 else {
            throw SiteError("The upstream branch configuration is invalid. Review it in Git before publishing.")
        }
        let urls = LocalSiteStore.git(["remote", "get-url", "--push", "--all", "origin"], in: repo)
        if urls.status == 0, urls.output.split(separator: "\n").count != 1 {
            throw SiteError("Origin has multiple push destinations. Choose one publication destination in Git first.")
        }
        return ["push", "--set-upstream", "--", "origin", "HEAD:" + target]
    }

    static func readiness(repo: String, web: String?) -> [String] {
        var problems = gitProblems(repo: repo)
        do {
            let config = try load(repo: repo).config
            let settings = try Settings(title: config.title, repository: config.repository ?? "", url: config.url ?? "")
            if settings.url == nil { problems.append("Save the website address. Its path determines the site's asset URLs.") }
            if let base = settings.base, base != SiteFiles.normalizedBase(config.base) {
                problems.append("The website address and build base differ. Save Hosting settings to align them.")
            }
            if let wanted = settings.repository {
                let actual = LocalSiteStore.git(["remote", "get-url", "--push", "--all", "origin"], in: repo)
                if actual.status == 0,
                   (try? githubRepository(actual.output.trimmingWhitespace(), allowSSH: true).lowercased()) != wanted.lowercased() {
                    problems.append("The origin push destination differs from the saved repository. Review Git before publishing.")
                }
            } else { problems.append("Save a GitHub repository address, then connect it.") }
        } catch { problems.append("\(error)") }
        if let web, FileManager.default.fileExists(atPath: web + "/app.wasm"),
           FileManager.default.fileExists(atPath: web + "/index.html") {} else {
            problems.append("The web reader is missing. Use a packaged app with web resources, or build the OfficeApp web stage.")
        }
        return problems
    }
}
#endif
