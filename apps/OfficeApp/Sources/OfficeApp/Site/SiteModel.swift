// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A site is a git repository (docs/plans/site.md): `site.json` names it and
// orders its pages, `pages/<slug>.json` holds each page as the document
// model (RichDocumentEnvelope), and the built site — the wasm Writer, the
// pages, a manifest, a search index and one shell page per route — is a
// folder GitHub Pages serves. Nothing of a page is rendered as HTML: the
// shell page carries the title and summary in meta tags for link
// previews, and the Writer draws the page.
//
// The model here compiles for the browser too; the builder is native only.

import Flutter
import Foundation

/// One page in the tree, as `site.json` lists it.
struct SiteNode: Codable, Equatable {
    var slug: String
    var title: String
    var children: [SiteNode]? = nil
}

/// `site.json`.
struct SiteConfig: Codable {
    var title: String
    /// Where the site is served: "/" for a user site, "/repo/" for a
    /// project site. The build's `--base` overrides it.
    var base: String? = nil
    var pages: [SiteNode]
}

/// `manifest.json`, as the build writes it and the reader fetches it.
struct SiteManifest: Codable {
    var title: String
    var base: String
    var home: String
    var pages: [SiteNode]

    /// The tree, depth first, with each node's depth.
    func flattened() -> [(node: SiteNode, depth: Int)] {
        var out: [(SiteNode, Int)] = []
        func walk(_ nodes: [SiteNode], _ depth: Int) {
            for n in nodes {
                out.append((n, depth))
                walk(n.children ?? [], depth + 1)
            }
        }
        walk(pages, 0)
        return out
    }

    func node(_ slug: String) -> SiteNode? {
        flattened().first { $0.node.slug == slug }?.node
    }

    /// The route of a page under the base: the home page is the base itself.
    func route(_ slug: String) -> String {
        slug == home ? base : base + slug + "/"
    }
}

/// A page as stored: the document and, when it came from a paged file,
/// the page it is laid out for (the reader's page view; nil is flow only).
struct SitePage {
    var document: RichDocument
    var pageSetup: PageSetup?
}

/// One line of `search.json`.
struct SiteSearchEntry: Codable {
    var slug: String
    var title: String
    var text: String
}

enum SiteFiles {
    static let config = "site.json"
    static let pagesDir = "pages"
    static let manifest = "manifest.json"
    static let search = "search.json"

    static func pagePath(_ slug: String) -> String { "\(pagesDir)/\(slug).json" }

    /// A slug from a title: lower-case letters and digits, runs of anything
    /// else collapsed to one dash, nothing at the ends.
    static func slug(for title: String) -> String {
        var out = ""
        var dash = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber {
                if dash, !out.isEmpty { out.append("-") }
                dash = false
                out.append(ch)
            } else {
                dash = true
            }
        }
        return out.isEmpty ? "page" : out
    }

    /// A base with a slash at both ends; nil or "" is "/".
    static func normalizedBase(_ base: String?) -> String {
        var b = (base ?? "").trimmingWhitespace()
        if b.isEmpty { return "/" }
        if !b.hasPrefix("/") { b = "/" + b }
        if !b.hasSuffix("/") { b += "/" }
        return b
    }

    /// The route's slug: the path after the base, without slashes; "" is
    /// the home page. A path that does not start with the base (served
    /// from somewhere else, or a stray prefix) is read from its last part.
    static func slug(ofRoute route: String, base: String) -> String {
        var path = route
        if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<q]) }
        var rest = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
        while rest.hasPrefix("/") { rest.removeFirst() }
        while rest.hasSuffix("/") { rest.removeLast() }
        if rest.hasSuffix("/index.html") { rest = String(rest.dropLast("/index.html".count)) }
        if rest == "index.html" { rest = "" }
        return rest.split(separator: "/").last.map(String.init) ?? ""
    }

    static func plainText(_ doc: RichDocument) -> String {
        doc.paragraphs.lazy.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The first paragraphs, for a link preview.
    static func summary(_ doc: RichDocument, limit: Int = 300) -> String {
        var out = ""
        for p in doc.paragraphs where !p.text.trimmingWhitespace().isEmpty {
            if !out.isEmpty { out += " " }
            out += p.text.trimmingWhitespace()
            if out.count >= limit { break }
        }
        return out.count > limit ? String(out.prefix(limit)) : out
    }

    /// The server's and the build's "no content yet".
    static let emptyBody = "{}"

    static func decodePage(_ data: Data) -> SitePage? {
        let text = String(decoding: data, as: UTF8.self)
        if text.trimmingWhitespace() == emptyBody { return SitePage(document: RichDocument(), pageSetup: nil) }
        guard let envelope = try? RichDocumentEnvelope.decodeEnvelope(data) else { return nil }
        return SitePage(document: envelope.document, pageSetup: envelope.pageSetup)
    }
}

#if !os(WASI)
/// `OfficeApp --site-build`: the repository folder into the folder Pages
/// serves. Native only — it reads and writes files and copies the web build.
enum SiteBuilder {
    struct Summary {
        var pages: Int
        var out: String
        var base: String
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ s: String) { description = s }
    }

    static func readConfig(_ repo: String) throws -> SiteConfig {
        let path = repo + "/" + SiteFiles.config
        guard let data = FileManager.default.contents(atPath: path) else { throw Failure("no \(SiteFiles.config) in \(repo)") }
        do { return try JSONDecoder().decode(SiteConfig.self, from: data) }
        catch { throw Failure("\(path): \(error)") }
    }

    static func writeConfig(_ config: SiteConfig, to repo: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: URL(fileURLWithPath: repo + "/" + SiteFiles.config), options: .atomic)
    }

    static func manifest(from config: SiteConfig, base: String? = nil) -> SiteManifest {
        SiteManifest(title: config.title, base: SiteFiles.normalizedBase(base ?? config.base),
                     home: config.pages.first?.slug ?? "index", pages: config.pages)
    }

    /// The web build to ship: `--web`, else `STARLING_WEB_STAGE`, else the
    /// stage build/web-app.sh leaves in the working directory.
    static func defaultWebStage() -> String? {
        let env = ProcessInfo.processInfo.environment
        for candidate in [env["STARLING_WEB_STAGE"], FileManager.default.currentDirectoryPath + "/.stage-web-OfficeApp"] {
            if let c = candidate, FileManager.default.fileExists(atPath: c + "/index.html") { return c }
        }
        return nil
    }

    static func build(repo: String, out: String, web: String?, base: String?) throws -> Summary {
        let fm = FileManager.default
        let config = try readConfig(repo)
        let manifest = manifest(from: config, base: base)
        guard let web, fm.fileExists(atPath: web + "/index.html"), fm.fileExists(atPath: web + "/app.wasm") else {
            throw Failure("no web build to ship: pass --web <stage> or set STARLING_WEB_STAGE (build/web-app.sh OfficeApp --package apps/OfficeApp)")
        }
        // The output is ours to replace, but only when it is ours: a folder
        // with files in it and no manifest is somebody else's.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: out, isDirectory: &isDir) {
            guard isDir.boolValue else { throw Failure("\(out) is a file") }
            let existing = (try? fm.contentsOfDirectory(atPath: out)) ?? []
            if !existing.isEmpty, !fm.fileExists(atPath: out + "/" + SiteFiles.manifest) {
                throw Failure("refusing to build into \(out): it has files and no \(SiteFiles.manifest) — not a site build")
            }
        }
        try fm.createDirectory(atPath: out, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: out + "/" + SiteFiles.pagesDir, withIntermediateDirectories: true)

        // The app, except its index.html, which every shell page is made from.
        guard let template = try? String(contentsOfFile: web + "/index.html", encoding: .utf8) else { throw Failure("cannot read \(web)/index.html") }
        for item in try fm.contentsOfDirectory(atPath: web) where item != "index.html" && !item.hasPrefix(".") {
            let dst = out + "/" + item
            if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
            try fm.copyItem(atPath: web + "/" + item, toPath: dst)
        }

        var entries: [SiteSearchEntry] = []
        var count = 0
        for (node, _) in manifest.flattened() {
            let src = repo + "/" + SiteFiles.pagePath(node.slug)
            let data = fm.contents(atPath: src) ?? Data(SiteFiles.emptyBody.utf8)
            guard let doc = SiteFiles.decodePage(data)?.document else { throw Failure("\(src): not a page this build can read") }
            try data.write(to: URL(fileURLWithPath: out + "/" + SiteFiles.pagePath(node.slug)), options: .atomic)
            let text = SiteFiles.plainText(doc)
            entries.append(SiteSearchEntry(slug: node.slug, title: node.title, text: text))
            let html = SiteShellPage.render(template: template, base: manifest.base, route: manifest.route(node.slug),
                                            title: node.title, siteTitle: manifest.title,
                                            description: SiteFiles.summary(doc), text: text)
            if node.slug == manifest.home {
                try html.write(toFile: out + "/index.html", atomically: true, encoding: .utf8)
            }
            try fm.createDirectory(atPath: out + "/" + node.slug, withIntermediateDirectories: true)
            try html.write(toFile: out + "/" + node.slug + "/index.html", atomically: true, encoding: .utf8)
            count += 1
        }
        // An unknown route still loads the app, which says what it could not find.
        try SiteShellPage.render(template: template, base: manifest.base, route: manifest.base, title: manifest.title,
                                 siteTitle: manifest.title, description: "", text: "")
            .write(toFile: out + "/404.html", atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: out + "/" + SiteFiles.manifest), options: .atomic)
        try encoder.encode(entries).write(to: URL(fileURLWithPath: out + "/" + SiteFiles.search), options: .atomic)
        // Pages would otherwise run the folder through Jekyll.
        fm.createFile(atPath: out + "/.nojekyll", contents: Data())
        return Summary(pages: count, out: out, base: manifest.base)
    }
}

/// The shell page: the app's index.html with the route, the base, and the
/// page's title and summary in meta tags, so a link unfurls. The body stays
/// the canvas; the page's text rides in <noscript> for crawlers and
/// readers with scripts off, which is text, not layout.
enum SiteShellPage {
    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }

    static func render(template: String, base: String, route: String, title: String, siteTitle: String,
                       description: String, text: String) -> String {
        let desc = String(description.replacingOccurrences(of: "\n", with: " ").prefix(300))
        let full = title == siteTitle ? title : "\(title) — \(siteTitle)"
        let meta = """
        <meta property="og:type" content="article">
        <meta property="og:site_name" content="\(escape(siteTitle))">
        <meta property="og:title" content="\(escape(title))">
        <meta property="og:description" content="\(escape(desc))">
        <meta name="description" content="\(escape(desc))">
        <meta name="starling-route" content="\(escape(route))">

        """
        var html = template
        if let r = html.range(of: "<head>") { html.replaceSubrange(r, with: "<head>\n<base href=\"\(escape(base))\">") }
        if let r = html.range(of: "<title>") { html.replaceSubrange(r, with: meta + "<title>") }
        else if let r = html.range(of: "</head>") { html.replaceSubrange(r, with: meta + "</head>") }
        if let r = html.range(of: #"<title>[^<]*</title>"#, options: .regularExpression) {
            html.replaceSubrange(r, with: "<title>\(escape(full))</title>")
        }
        // The app's command line: site mode, served under this base.
        if let r = html.range(of: "args: [],") {
            html.replaceSubrange(r, with: "args: ['--site', '\(escape(base))'],")
        }
        if !text.isEmpty, let r = html.range(of: "<body>") {
            let paragraphs = text.split(separator: "\n").map { "<p>\(escape(String($0)))</p>" }.joined(separator: "\n")
            html.replaceSubrange(r, with: "<body>\n<noscript><main><h1>\(escape(title))</h1>\n\(paragraphs)\n</main></noscript>")
        }
        return html
    }
}
#endif
