// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Where a site's pages come from, and where edits go. Two stores: the
// built site, fetched as files (a tab on GitHub Pages, or the native app
// pointed at a URL) — read-only; and the cloned repository on disk, which
// the native app edits, builds and publishes with git. The reader is the
// same over both; it shows Edit, New page and Publish only where the
// store can write.

import Flutter
import Foundation

struct SiteError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

protocol SiteStore: AnyObject {
    /// Where the site is served, with a slash at both ends.
    var base: String { get }
    var canEdit: Bool { get }
    func manifest(_ done: @escaping (Result<SiteManifest, SiteError>) -> Void)
    func page(_ slug: String, _ done: @escaping (Result<SitePage, SiteError>) -> Void)
    func search(_ done: @escaping (Result<[SiteSearchEntry], SiteError>) -> Void)
    /// Store the page; answers with nil, or the message to show.
    func save(_ slug: String, _ page: SitePage, _ done: @escaping (String?) -> Void)
    /// A new page under `parent` (nil: top level); answers with its slug.
    func createPage(title: String, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void)
    /// Build and upload, with progress and actionable recovery guidance.
    func publish(message: String, progress: @escaping (SitePublishStage) -> Void, control: SitePublishControl, _ done: @escaping (SitePublishIssue?) -> Void)
    /// A new page from a document (a .docx imported); answers with its slug.
    func importPage(title: String, page: SitePage, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void)
    func previewUpdate(_ slug: String, page: SitePage, _ done: @escaping (Result<SiteRevision, SiteError>) -> Void)
    func applyUpdate(_ revision: SiteRevision, _ done: @escaping (String?) -> Void)
    func rename(_ slug: String, to title: String, _ done: @escaping (String?) -> Void)
    /// Remove a page; its children move up to its parent.
    func delete(_ slug: String, _ done: @escaping (String?) -> Void)
    /// Move a page one place among its siblings (`by` -1 up, +1 down).
    func move(_ slug: String, by: Int, _ done: @escaping (String?) -> Void)
    func setHome(_ slug: String, replacing expected: String, _ done: @escaping (String?) -> Void)
}

extension SiteStore {
    func previewUpdate(_ slug: String, page: SitePage, _ done: @escaping (Result<SiteRevision, SiteError>) -> Void) { done(.failure(SiteError("This site is read-only here."))) }
    func applyUpdate(_ revision: SiteRevision, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func save(_ slug: String, _ page: SitePage, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func createPage(title: String, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) { done(.failure(SiteError("This site is read-only here."))) }
    func publish(message: String, progress: @escaping (SitePublishStage) -> Void, control: SitePublishControl, _ done: @escaping (SitePublishIssue?) -> Void) { done(.setup("This site is read-only here.")) }
    func importPage(title: String, page: SitePage, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) { done(.failure(SiteError("This site is read-only here."))) }
    func rename(_ slug: String, to title: String, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func delete(_ slug: String, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func move(_ slug: String, by: Int, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func setHome(_ slug: String, replacing expected: String, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
}

/// The built site, by URL: `base` + manifest.json, pages/<slug>.json,
/// search.json. In a tab the base is a path on the same origin; natively
/// it may be a whole URL.
final class StaticSiteStore: SiteStore {
    let base: String
    let canEdit = false
    private let transport: WikiTransport

    init(base: String) {
        self.base = base.hasSuffix("/") ? base : base + "/"
        #if os(WASI)
        transport = WebTransport()
        #else
        transport = NativeTransport()
        #endif
    }

    private func fetch(_ file: String, _ done: @escaping (Result<Data, SiteError>) -> Void) {
        transport.request("GET", base + file, body: nil, contentType: nil) { r in
            done(r.ok ? .success(r.body) : .failure(SiteError("\(file): HTTP \(r.status)")))
        }
    }

    func manifest(_ done: @escaping (Result<SiteManifest, SiteError>) -> Void) {
        fetch(SiteFiles.manifest) { r in
            done(r.flatMap { data in
                do { return .success(try JSONDecoder().decode(SiteManifest.self, from: data)) }
                catch { return .failure(SiteError("manifest.json: \(error)")) }
            })
        }
    }

    func page(_ slug: String, _ done: @escaping (Result<SitePage, SiteError>) -> Void) {
        fetch(SiteFiles.pagePath(slug)) { r in
            done(r.flatMap { data in
                SiteFiles.decodePage(data).map { .success($0) } ?? .failure(SiteError("This page's content cannot be read by this build."))
            })
        }
    }

    func search(_ done: @escaping (Result<[SiteSearchEntry], SiteError>) -> Void) {
        fetch(SiteFiles.search) { r in
            done(r.flatMap { data in
                do { return .success(try JSONDecoder().decode([SiteSearchEntry].self, from: data)) }
                catch { return .failure(SiteError("search.json: \(error)")) }
            })
        }
    }
}

#if !os(WASI)
/// The cloned repository: pages read and written as files, the manifest
/// made from site.json, search over the pages themselves, and Publish =
/// build into `docs/` (or `out`), commit, push.
final class LocalSiteStore: SiteStore {
    let repo: String
    /// Where the build goes, relative to the repo: what GitHub Pages serves.
    let out: String
    let webStage: String?
    let base = "/"
    let canEdit = true

    init(repo: String, out: String = "docs", webStage: String? = nil) {
        self.repo = repo.hasSuffix("/") ? String(repo.dropLast()) : repo
        self.out = out
        self.webStage = webStage ?? SiteBuilder.defaultWebStage()
    }

    func manifest(_ done: @escaping (Result<SiteManifest, SiteError>) -> Void) {
        do { done(.success(SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo), base: "/"))) }
        catch { done(.failure(SiteError("\(error)"))) }
    }

    func page(_ slug: String, _ done: @escaping (Result<SitePage, SiteError>) -> Void) {
        let path = repo + "/" + SiteFiles.pagePath(slug)
        let data = FileManager.default.contents(atPath: path) ?? Data(SiteFiles.emptyBody.utf8)
        done(SiteFiles.decodePage(data).map { .success($0) } ?? .failure(SiteError("\(path): not a page this build can read.")))
    }

    func search(_ done: @escaping (Result<[SiteSearchEntry], SiteError>) -> Void) {
        do {
            let config = try SiteBuilder.readConfig(repo)
            var entries: [SiteSearchEntry] = []
            for (node, _) in SiteBuilder.manifest(from: config).flattened() {
                let data = FileManager.default.contents(atPath: repo + "/" + SiteFiles.pagePath(node.slug)) ?? Data(SiteFiles.emptyBody.utf8)
                let text = SiteFiles.decodePage(data).map { SiteFiles.plainText($0.document) } ?? ""
                entries.append(SiteSearchEntry(slug: node.slug, title: node.title, text: text))
            }
            done(.success(entries))
        } catch { done(.failure(SiteError("\(error)"))) }
    }

    func save(_ slug: String, _ page: SitePage, _ done: @escaping (String?) -> Void) {
        do {
            let path = repo + "/" + SiteFiles.pagePath(slug)
            try FileManager.default.createDirectory(atPath: repo + "/" + SiteFiles.pagesDir, withIntermediateDirectories: true)
            try RichDocumentEnvelope.encode(page.document, pageSetup: page.pageSetup).write(to: URL(fileURLWithPath: path), options: .atomic)
            done(nil)
        } catch { done("Could not save this page. Check that the publication folder is available and writable, then try again. Your edits are still open.") }
    }

    func createPage(title: String, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) {
        var blank = RichDocument()
        blank.styles = OfficeStyles.sheet
        importPage(title: title, page: SitePage(document: blank, pageSetup: nil), under: parent, done)
    }

    /// Synchronous, for the command line too: the page's file written and
    /// its node placed under `parent` (else at the top level).
    static func addPage(repo: String, title: String, page: SitePage, under parent: String?) throws -> String {
        var config = try SiteBuilder.readConfig(repo)
        let taken = Set(SiteBuilder.manifest(from: config).flattened().map(\.node.slug))
        var slug = SiteFiles.slug(for: title)
        var n = 2
        while taken.contains(slug) { slug = SiteFiles.slug(for: title) + "-\(n)"; n += 1 }
        let node = SiteNode(slug: slug, title: title)
        func insert(_ nodes: inout [SiteNode]) -> Bool {
            for i in nodes.indices {
                if nodes[i].slug == parent { nodes[i].children = (nodes[i].children ?? []) + [node]; return true }
                var kids = nodes[i].children ?? []
                if insert(&kids) { nodes[i].children = kids; return true }
            }
            return false
        }
        if parent == nil || !insert(&config.pages) { config.pages.append(node) }
        try FileManager.default.createDirectory(atPath: repo + "/" + SiteFiles.pagesDir, withIntermediateDirectories: true)
        try RichDocumentEnvelope.encode(page.document, pageSetup: page.pageSetup)
            .write(to: URL(fileURLWithPath: repo + "/" + SiteFiles.pagePath(slug)), options: .atomic)
        try SiteBuilder.writeConfig(config, to: repo)
        return slug
    }

    func importPage(title: String, page: SitePage, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) {
        do { done(.success(try Self.addPage(repo: repo, title: title, page: page, under: parent))) }
        catch { done(.failure(SiteError("\(error)"))) }
    }

    static func prepareUpdate(repo: String, slug: String, page: SitePage) throws -> SiteRevision {
        guard SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo)).node(slug) != nil,
              !slug.isEmpty, slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw SiteError("No valid page \(slug).")
        }
        let root = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        let source = root.appendingPathComponent(SiteFiles.pagePath(slug)).resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/") else { throw SiteError("The page source is outside this site.") }
        let data = try Data(contentsOf: source)
        guard let original = SiteFiles.decodePage(data) else { throw SiteError("Cannot read the current page.") }
        return SiteRevision(slug: slug, original: original, incoming: page, originalBytes: data)
    }

    static func applyUpdate(repo: String, revision: SiteRevision) throws {
        let current = try prepareUpdate(repo: repo, slug: revision.slug, page: revision.replacement)
        guard current.originalBytes == revision.originalBytes else {
            throw SiteError("This page changed since the preview. Open the revised file again to review the latest changes.")
        }
        try RichDocumentEnvelope.encode(revision.replacement.document, pageSetup: revision.replacement.pageSetup)
            .write(to: URL(fileURLWithPath: repo + "/" + SiteFiles.pagePath(revision.slug)), options: .atomic)
    }

    func previewUpdate(_ slug: String, page: SitePage, _ done: @escaping (Result<SiteRevision, SiteError>) -> Void) {
        do { done(.success(try Self.prepareUpdate(repo: repo, slug: slug, page: page))) }
        catch { done(.failure(SiteError("\(error)"))) }
    }

    func applyUpdate(_ revision: SiteRevision, _ done: @escaping (String?) -> Void) {
        do { try Self.applyUpdate(repo: repo, revision: revision); done(nil) }
        catch { done("\(error)") }
    }

    func rename(_ slug: String, to title: String, _ done: @escaping (String?) -> Void) {
        do {
            var config = try SiteBuilder.readConfig(repo)
            func visit(_ nodes: inout [SiteNode]) -> Bool {
                for i in nodes.indices {
                    if nodes[i].slug == slug { nodes[i].title = title; return true }
                    var kids = nodes[i].children ?? []
                    if visit(&kids) { nodes[i].children = kids; return true }
                }
                return false
            }
            guard visit(&config.pages) else { done("No page \(slug)."); return }
            try SiteBuilder.writeConfig(config, to: repo)
            done(nil)
        } catch { done("\(error)") }
    }

    func move(_ slug: String, by: Int, _ done: @escaping (String?) -> Void) {
        do {
            let r = try Self.movePage(repo: repo, slug: slug, by: by)
            done(r ? nil : "\(slug) is already at that end.")
        } catch { done("\(error)") }
    }

    /// Synchronous, for the command line too. False when the page is at
    /// the end it would move past.
    static func movePage(repo: String, slug: String, by: Int) throws -> Bool {
        var config = try SiteBuilder.readConfig(repo)
        var moved = false
        func visit(_ nodes: inout [SiteNode]) -> Bool {
            if let i = nodes.firstIndex(where: { $0.slug == slug }) {
                let j = i + by
                guard nodes.indices.contains(j) else { return true }
                nodes.swapAt(i, j)
                moved = true
                return true
            }
            for k in nodes.indices {
                var kids = nodes[k].children ?? []
                if visit(&kids) { nodes[k].children = kids; return true }
            }
            return false
        }
        guard visit(&config.pages) else { throw SiteError("No page \(slug).") }
        if moved { try SiteBuilder.writeConfig(config, to: repo) }
        return moved
    }

    func delete(_ slug: String, _ done: @escaping (String?) -> Void) {
        do {
            var config = try SiteBuilder.readConfig(repo)
            guard SiteBuilder.manifest(from: config).flattened().count > 1 else { done("The only page stays."); return }
            guard config.resolvedHome != slug else { done("Choose another home page before deleting this one."); return }
            // The node goes; its children take its place, in order.
            func visit(_ nodes: inout [SiteNode]) -> Bool {
                for i in nodes.indices {
                    if nodes[i].slug == slug {
                        let kids = nodes[i].children ?? []
                        nodes.replaceSubrange(i ... i, with: kids)
                        return true
                    }
                    var kids = nodes[i].children ?? []
                    if visit(&kids) { nodes[i].children = kids.isEmpty ? nil : kids; return true }
                }
                return false
            }
            guard visit(&config.pages) else { done("No page \(slug)."); return }
            try SiteBuilder.writeConfig(config, to: repo)
            try? FileManager.default.removeItem(atPath: repo + "/" + SiteFiles.pagePath(slug))
            done(nil)
        } catch { done("\(error)") }
    }

    func setHome(_ slug: String, replacing expected: String, _ done: @escaping (String?) -> Void) {
        do { try Self.chooseHome(repo: repo, slug: slug, replacing: expected); done(nil) }
        catch { done("\(error)") }
    }

    static func chooseHome(repo: String, slug: String, replacing expected: String) throws {
        var config = try SiteBuilder.readConfig(repo)
        guard config.resolvedHome == expected else {
            throw SiteError("The home page changed outside this preview. Reopen the publication before choosing it again.")
        }
        guard SiteBuilder.manifest(from: config).node(slug) != nil else { throw SiteError("Choose a page in this publication.") }
        _ = try SiteBuilder.validatedSources(repo: repo, config: config, web: nil)
        config.home = slug
        try SiteBuilder.writeConfig(config, to: repo)
    }

    func publish(message: String, progress: @escaping (SitePublishStage) -> Void, control: SitePublishControl, _ done: @escaping (SitePublishIssue?) -> Void) {
        progress(.checking)
        let repo = self.repo, out = self.out, web = self.webStage
        let worker = Thread {
            let problems = SiteHosting.readiness(repo: repo, web: web)
            let result = problems.isEmpty ? Self.publishNow(repo: repo, out: out, web: web, message: message, control: control, progress: { stage in
                DispatchQueue.main.async { progress(stage) }
            }).issue : SitePublishIssue.setup(problems.joined(separator: " "))
            DispatchQueue.main.async { done(result) }
        }
        // Website generation includes Writer layout and Word/PDF exports.
        // Debug builds exceed the small default Dispatch worker stack.
        worker.name = "Publish documents"
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
    }

    /// Build, commit only the publication paths (preserving unrelated staged
    /// work), and push. A push is not proof the host deployed the revision.
    static func publishNow(repo: String, out: String, web: String?, message: String, control: SitePublishControl = SitePublishControl(), progress: ((SitePublishStage) -> Void)? = nil) -> SitePublishResult {
        progress?(.checking)
        let text = message.trimmingWhitespace().isEmpty ? "Update site" : message
        do {
            let components = out.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  components.first != "pages", components.first != ".git", components.first != "site.json" else {
                throw SiteError("publish output must be a separate folder inside the site repository")
            }
            let root = git(["rev-parse", "--show-toplevel"], in: repo)
            guard root.status == 0,
                  URL(fileURLWithPath: root.output.trimmingWhitespace()).resolvingSymlinksInPath().path
                    == URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath().path else {
                throw SiteError("open the root of the site's own Git repository before publishing")
            }
            let repoURL = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
            guard repoURL.appendingPathComponent(out).resolvingSymlinksInPath().path.hasPrefix(repoURL.path + "/") else {
                throw SiteError("publish output must stay inside the site repository")
            }
            let problems = SiteHosting.gitProblems(repo: repo)
            guard problems.isEmpty else { return .init("", .setup(problems.joined(separator: " "))) }
            let pushArguments = try SiteHosting.pushArguments(repo: repo)
            let destination = try SitePublicationState.destination(repo: repo)
            let branch = git(["symbolic-ref", "--quiet", "--short", "HEAD"], in: repo).output.trimmingWhitespace()
            let target = String(pushArguments.last!.dropFirst("HEAD:".count))
            progress?(.building)
            let built = try SiteBuilder.build(repo: repo, out: repo + "/" + out, web: web, base: nil)
            let summary = "\(built.pages) pages built into \(out)/"
            let paths = [SiteFiles.config, SiteFiles.pagesDir, out]
            progress?(.saving)
            let staged = git(["--literal-pathspecs", "add", "-A", "--"] + paths, in: repo)
            guard staged.status == 0 else { return .init(summary, .local("Could not save the publication files to history. Check that the folder is writable and finish any other Git operation before retrying.")) }
            let changes = git(["--literal-pathspecs", "diff", "--cached", "--quiet", "--"] + paths, in: repo)
            if changes.status == 1 {
                let committed = git(["--literal-pathspecs", "commit", "--only", "-m", text, "--"] + paths, in: repo)
                guard committed.status == 0 else { return .init(summary, .local("Could not create the publication history entry. Check the author settings and any Git commit hooks or signing requirements before retrying.")) }
            } else if changes.status != 0 {
                return .init(summary, .local("Could not inspect the saved changes. Review the publication repository in Git before retrying."))
            }
            let head = git(["rev-parse", "--verify", "HEAD"], in: repo)
            guard head.status == 0 else { return .init(summary, .local("Could not identify the saved publication revision.")) }
            let revision = head.output.trimmingWhitespace()
            // Send a fixed revision so another local commit cannot cause
            // the receipt to describe a different upload.
            progress?(.uploading)
            let push = SiteGitUpload.push(repo: repo, revision: revision, target: target, control: control)
            if let reason = push.stopped {
                return .init(summary, reason == .cancelled ? .cancelled : .timedOut)
            }
            if push.status != 0 { return .init(summary, .upload(output: push.output)) }
            progress?(.recording)
            // A SHA source does not set tracking like --set-upstream HEAD.
            let tracking = git(["branch", "--set-upstream-to=origin/" + target.dropFirst("refs/heads/".count), branch], in: repo)
            guard (try? SitePublicationState.destination(repo: repo)) == destination else {
                return .init(summary, .sent("The destination changed during publishing. Review Publishing settings; the local publication status is unknown."))
            }
            do {
                try SitePublicationState.record(repo: repo, revision: revision, destination: destination, target: target, out: out)
            } catch {
                return .init(summary, .sent("The local publish record could not be saved. Check that the publication folder is writable; the local publication status is unknown."))
            }
            if tracking.status != 0 { return .init(summary, .sent("Git branch tracking could not be saved. Review Publishing settings before publishing again.")) }
            return .init("\(summary), pushed; deployment has not been verified")
        } catch {
            return .init("", .local("\(error)"))
        }
    }

    /// Run git in the repo; its output, both streams, and its status.
    static func git(_ args: [String], in repo: String, environment: [String: String] = [:]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", repo] + args
        if !environment.isEmpty {
            p.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in value }
            if environment["GIT_TERMINAL_PROMPT"] == "0" { p.standardInput = FileHandle.nullDevice }
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
#endif
