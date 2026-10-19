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
    /// Build the site and push it; answers with nil, or what went wrong.
    func publish(message: String, _ done: @escaping (String?) -> Void)
}

extension SiteStore {
    func save(_ slug: String, _ page: SitePage, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
    func createPage(title: String, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) { done(.failure(SiteError("This site is read-only here."))) }
    func publish(message: String, _ done: @escaping (String?) -> Void) { done("This site is read-only here.") }
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
        } catch { done("Could not write the page: \(error)") }
    }

    func createPage(title: String, under parent: String?, _ done: @escaping (Result<String, SiteError>) -> Void) {
        do {
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
            var blank = RichDocument()
            blank.styles = OfficeStyles.sheet
            try FileManager.default.createDirectory(atPath: repo + "/" + SiteFiles.pagesDir, withIntermediateDirectories: true)
            try RichDocumentEnvelope.encode(blank).write(to: URL(fileURLWithPath: repo + "/" + SiteFiles.pagePath(slug)), options: .atomic)
            try SiteBuilder.writeConfig(config, to: repo)
            done(.success(slug))
        } catch { done(.failure(SiteError("\(error)"))) }
    }

    func publish(message: String, _ done: @escaping (String?) -> Void) {
        let repo = self.repo, out = self.out, web = self.webStage
        DispatchQueue.global().async {
            let result = Self.publishNow(repo: repo, out: out, web: web, message: message).failure
            DispatchQueue.main.async { done(result) }
        }
    }

    /// Build into `out`, `git add -A`, commit (nothing to commit is fine),
    /// push. What the Publish button and `--site-publish` both run; blocks.
    static func publishNow(repo: String, out: String, web: String?, message: String) -> (summary: String, failure: String?) {
        let text = message.trimmingWhitespace().isEmpty ? "Update site" : message
        do {
            let built = try SiteBuilder.build(repo: repo, out: repo + "/" + out, web: web, base: nil)
            let summary = "\(built.pages) pages built into \(out)/"
            for step in [["add", "-A"], ["commit", "-m", text]] {
                let r = git(step, in: repo)
                if r.status != 0 {
                    if step[0] == "commit", r.output.containsSubstring("nothing to commit") { continue }
                    return (summary, "\(summary), but git \(step.joined(separator: " ")): \(r.output.trimmingWhitespace())")
                }
            }
            let push = git(["push"], in: repo)
            if push.status != 0 { return (summary, "\(summary), but git push: \(push.output.trimmingWhitespace())") }
            return ("\(summary), committed and pushed", nil)
        } catch {
            return ("", "Build failed: \(error)")
        }
    }

    /// Run git in the repo; its output, both streams, and its status.
    static func git(_ args: [String], in repo: String) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "-C", repo] + args
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
