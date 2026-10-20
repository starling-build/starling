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
    /// The site's address, for sitemap.xml ("https://user.github.io/repo");
    /// without it the build writes no sitemap.
    var url: String? = nil
    /// The repository's address on GitHub ("https://github.com/user/repo"):
    /// the reader's History link opens a page's commits there.
    var repository: String? = nil
    var pages: [SiteNode]
    /// Legacy files use their first page until the next save pins that choice.
    var home: String? = nil
    var details: SitePublicationDetails? = nil
    var resolvedHome: String { home ?? pages.first?.slug ?? "index" }
}

/// `manifest.json`, as the build writes it and the reader fetches it.
struct SiteManifest: Codable {
    var title: String
    var base: String
    var home: String
    var pages: [SiteNode]
    var repository: String? = nil
    /// The build wrote `<slug>/<slug>.pdf` and `.docx` beside each page.
    var exports: Bool? = nil
    var details: SitePublicationDetails? = nil

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

    /// Every page has a slug alias, even the home page. Shared passage links
    /// use it so choosing a different home does not retarget an existing link.
    func paragraphRoute(_ slug: String, id: UInt32) -> String {
        base + slug + "/#p=\(id)"
    }

    /// The paths of a page's static exports under the site: PDF and Word.
    func exportPaths(_ slug: String) -> (pdf: String, docx: String) {
        (base + slug + "/" + slug + ".pdf", base + slug + "/" + slug + ".docx")
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

/// The document's paragraphs with their heading level (0 none, 1-3), for
/// the text layer the page keeps for screen readers: written by the build
/// into the shell page, replaced by the reader as it moves between pages.
enum SiteTextLayer {
    static func lines(of doc: RichDocument) -> [(level: Int, text: String)] {
        doc.paragraphs.compactMap { p in
            let text = p.text.trimmingWhitespace()
            guard !text.isEmpty else { return nil }
            let level = p.style.named == "Title" ? 1 : (p.style.heading.map { min(3, max(1, $0)) } ?? 0)
            return (level: level, text: text)
        }
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
        do {
            var config = try JSONDecoder().decode(SiteConfig.self, from: data)
            // Capture the legacy choice before an author reorders/deletes nodes.
            config.home = config.resolvedHome
            config.details = try config.details?.validated()
            return config
        }
        catch { throw Failure("\(path): \(error)") }
    }

    static func writeConfig(_ config: SiteConfig, to repo: String) throws {
        var config = config
        config.home = config.resolvedHome
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: URL(fileURLWithPath: repo + "/" + SiteFiles.config), options: .atomic)
    }

    static func manifest(from config: SiteConfig, base: String? = nil) -> SiteManifest {
        SiteManifest(title: config.title, base: SiteFiles.normalizedBase(base ?? config.base),
                     home: config.resolvedHome, pages: config.pages,
                     repository: config.repository?.trimmingWhitespace().isEmpty == false ? config.repository : nil,
                     details: config.details)
    }

    /// The web build to ship: `--web`, else `STARLING_WEB_STAGE`, else the
    /// stage build/web-app.sh leaves in the working directory.
    static func defaultWebStage() -> String? {
        let env = ProcessInfo.processInfo.environment
        // A packaged app carries the web build in Resources/web (build/macos-app.sh).
        for candidate in [env["STARLING_WEB_STAGE"], Bundle.main.resourcePath.map { $0 + "/web" },
                          FileManager.default.currentDirectoryPath + "/.stage-web-OfficeApp"] {
            if let c = candidate, FileManager.default.fileExists(atPath: c + "/index.html") { return c }
        }
        return nil
    }

    /// Shared by publication review and build, before either reads page paths.
    /// This validates source input only; output/hosting checks still run at build.
    static func validatedSources(repo: String, config: SiteConfig, web: String?) throws -> [(node: SiteNode, depth: Int, data: Data)] {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        var result: [(node: SiteNode, depth: Int, data: Data)] = []
        var slugs = Set<String>()
        let reserved = Set(["pages", "fonts", "skwasm", "manifest.json", "search.json", "404.html", "index.html", "robots.txt", "sitemap.xml"]
            + ((web.flatMap { try? fm.contentsOfDirectory(atPath: $0) }) ?? []))
        guard !config.pages.isEmpty else { throw Failure("the site needs at least one page") }
        _ = try config.details?.validated()
        guard manifest(from: config).node(config.resolvedHome) != nil else {
            throw Failure("the home page must name a page in this publication")
        }
        for (node, depth) in manifest(from: config).flattened() {
            guard !node.slug.isEmpty, node.slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                  !reserved.contains(node.slug.lowercased()), slugs.insert(node.slug.lowercased()).inserted else {
                throw Failure("invalid, reserved or duplicate page slug: \(node.slug)")
            }
            let file = source.appendingPathComponent(SiteFiles.pagePath(node.slug)).resolvingSymlinksInPath()
            guard (file.path == source.path || file.path.hasPrefix(source.path + "/")), let data = fm.contents(atPath: file.path), SiteFiles.decodePage(data) != nil else {
                throw Failure("\(node.slug): missing, unreadable or invalid source page")
            }
            result.append((node, depth, data))
        }
        return result
    }

    static func build(repo: String, out: String, web: String?, base: String?) throws -> Summary {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        let destination = URL(fileURLWithPath: out).standardizedFileURL.resolvingSymlinksInPath()
        func contains(_ parent: URL, _ child: URL) -> Bool {
            child.path == parent.path || child.path.hasPrefix(parent.path + "/")
        }
        guard !contains(destination, source),
              !contains(source.appendingPathComponent("pages"), destination),
              !contains(source.appendingPathComponent(".git"), destination) else {
            throw Failure("output must not overlap the repository, its pages or Git metadata")
        }
        if let web {
            let assets = URL(fileURLWithPath: web).standardizedFileURL.resolvingSymlinksInPath()
            guard !contains(destination, assets), !contains(assets, destination) else {
                throw Failure("output must not overlap the web build")
            }
        }
        let config = try readConfig(repo)
        _ = try validatedSources(repo: repo, config: config, web: web)
        if fm.fileExists(atPath: destination.path) {
            let existing = try fm.contentsOfDirectory(atPath: destination.path)
            guard existing.isEmpty || fm.fileExists(atPath: destination.appendingPathComponent(SiteFiles.manifest).path) else {
                throw Failure("refusing to build into \(out): it has files and no \(SiteFiles.manifest) — not a site build")
            }
        }
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".starling-build-" + UUID().uuidString)
        let backup = parent.appendingPathComponent(".starling-backup-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        let summary = try buildContents(repo: repo, out: staging.path, web: web, base: base)
        // A public identifier for this exact built version, installed with its files.
        try JSONEncoder().encode(SiteLivePublication.Marker(version: 1, build: UUID().uuidString))
            .write(to: staging.appendingPathComponent(SiteLivePublication.markerFile), options: .atomic)
        // GitHub Pages' custom-domain setting is hosting configuration.
        let cname = destination.appendingPathComponent("CNAME")
        if let data = fm.contents(atPath: cname.path) {
            try data.write(to: staging.appendingPathComponent("CNAME"), options: .atomic)
        }
        let hadOutput = fm.fileExists(atPath: destination.path)
        if hadOutput { try fm.moveItem(at: destination, to: backup) }
        do { try fm.moveItem(at: staging, to: destination) }
        catch {
            if hadOutput { try fm.moveItem(at: backup, to: destination) }
            throw error
        }
        if hadOutput { try? fm.removeItem(at: backup) }
        return Summary(pages: summary.pages, out: out, base: summary.base)
    }

    private static func buildContents(repo: String, out: String, web: String?, base: String?) throws -> Summary {
        let fm = FileManager.default
        let config = try readConfig(repo)
        var manifest = manifest(from: config, base: base)
        manifest.exports = true
        // The painter's theme for the PDFs, as `--convert` makes it.
        _ = OfficeFonts.register()
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        theme.disablesLigatures = true
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
        var hasCJK = false
        for (node, _) in manifest.flattened() {
            let src = repo + "/" + SiteFiles.pagePath(node.slug)
            guard let data = fm.contents(atPath: src) else { throw Failure("\(src): missing source page") }
            guard let page = SiteFiles.decodePage(data) else { throw Failure("\(src): not a page this build can read") }
            let doc = page.document
            try data.write(to: URL(fileURLWithPath: out + "/" + SiteFiles.pagePath(node.slug)), options: .atomic)
            // The page as a PDF and as Word, static, beside its shell: a
            // download for any reader, a link for crawlers and screen
            // readers, and instant for the reader's buttons.
            try fm.createDirectory(atPath: out + "/" + node.slug, withIntermediateDirectories: true)
            let setup = page.pageSetup ?? .letter
            if !PdfExport.write(doc, pageSetup: setup, theme: theme, to: out + "/" + node.slug + "/" + node.slug + ".pdf", title: node.title) {
                throw Failure("\(node.slug): could not write its PDF")
            }
            try OfficeFormats.write(doc, to: out + "/" + node.slug + "/" + node.slug + ".docx", pageSetup: setup)
            let text = SiteFiles.plainText(doc)
            if !hasCJK, text.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { hasCJK = true }
            entries.append(SiteSearchEntry(slug: node.slug, title: node.title, text: text))
            let html = SiteShellPage.render(template: template, base: manifest.base, route: manifest.route(node.slug),
                                            title: node.title, siteTitle: manifest.title,
                                            description: node.slug == manifest.home ? (config.details?.summary ?? SiteFiles.summary(doc)) : SiteFiles.summary(doc), text: text,
                                            lines: SiteShellPage.lines(of: doc),
                                            nav: manifest.flattened().map { (title: $0.node.title, route: manifest.route($0.node.slug), depth: $0.depth) },
                                            downloads: manifest.exportPaths(node.slug), details: config.details)
            if node.slug == manifest.home {
                try html.write(toFile: out + "/index.html", atomically: true, encoding: .utf8)
            }
            try html.write(toFile: out + "/" + node.slug + "/index.html", atomically: true, encoding: .utf8)
            count += 1
        }
        // Unknown routes remain navigable even when the app cannot load.
        try SiteShellPage.render(template: template, base: manifest.base, route: manifest.base, title: manifest.title,
                                 siteTitle: manifest.title, description: "", text: "This page could not be found. Choose a page from the publication.",
                                 nav: manifest.flattened().map { (title: $0.node.title, route: manifest.route($0.node.slug), depth: $0.depth) },
                                 details: config.details)
            .write(toFile: out + "/404.html", atomically: true, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: URL(fileURLWithPath: out + "/" + SiteFiles.manifest), options: .atomic)
        try encoder.encode(entries).write(to: URL(fileURLWithPath: out + "/" + SiteFiles.search), options: .atomic)
        // Pages would otherwise run the folder through Jekyll.
        fm.createFile(atPath: out + "/.nojekyll", contents: Data())
        // A sitemap and a robots.txt for crawlers, when the site knows its address.
        if let url = config.url?.trimmingWhitespace(), !url.isEmpty {
            let origin = url.hasSuffix("/") ? String(url.dropLast()) : url
            let host = origin.hasSuffix(manifest.base.dropLast()) && manifest.base != "/" ? String(origin.dropLast(manifest.base.count - 1)) : origin
            let locs = manifest.flattened().map { "  <url><loc>\(SiteShellPage.escape(host + manifest.route($0.node.slug)))</loc></url>" }
            let sitemap = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" + locs.joined(separator: "\n") + "\n</urlset>\n"
            try sitemap.write(toFile: out + "/sitemap.xml", atomically: true, encoding: .utf8)
            try "User-agent: *\nAllow: /\nSitemap: \(host)\(manifest.base)sitemap.xml\n".write(toFile: out + "/robots.txt", atomically: true, encoding: .utf8)
        }
        // The Chinese face (18 MB) ships only with a site that has Chinese
        // text somewhere; a site without any gets neither the file nor its
        // manifest entry.
        if !hasCJK { try pruneFonts(in: out, matching: "NotoSansSC") }
        return Summary(pages: count, out: out, base: manifest.base)
    }

    /// Drop the font files whose name contains `needle` from the build and
    /// from fonts/manifest.json.
    static func pruneFonts(in out: String, matching needle: String) throws {
        let fm = FileManager.default
        let dir = out + "/fonts"
        for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.contains(needle) {
            try fm.removeItem(atPath: dir + "/" + item)
        }
        let manifestPath = dir + "/manifest.json"
        guard let data = fm.contents(atPath: manifestPath),
              let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let kept = entries.filter { !(($0["url"] as? String) ?? "").contains(needle) }
        try JSONSerialization.data(withJSONObject: kept, options: [.prettyPrinted])
            .write(to: URL(fileURLWithPath: manifestPath), options: .atomic)
    }

}

/// The shell page: the app's index.html with the route, the base, and the
/// page's title and summary in meta tags, so a link unfurls. Readable HTML
/// is available before the interactive reader starts and if it cannot load.
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

    static func lines(of doc: RichDocument) -> [(level: Int, text: String)] { SiteTextLayer.lines(of: doc) }

    static func render(template: String, base: String, route: String, title: String, siteTitle: String,
                       description: String, text: String, lines: [(level: Int, text: String)] = [],
                       nav: [(title: String, route: String, depth: Int)] = [],
                       downloads: (pdf: String, docx: String)? = nil, details: SitePublicationDetails? = nil) -> String {
        let desc = String(description.replacingOccurrences(of: "\n", with: " ").prefix(300))
        let full = title == siteTitle ? title : "\(title) — \(siteTitle)"
        var meta = """
        <meta property="og:type" content="article">
        <meta property="og:site_name" content="\(escape(siteTitle))">
        <meta property="og:title" content="\(escape(title))">
        <meta property="og:description" content="\(escape(desc))">
        <meta name="description" content="\(escape(desc))">
        <meta name="starling-route" content="\(escape(route))">

        """
        if let byline = details?.byline { meta += "<meta name=\"author\" content=\"\(escape(byline))\">\n" }
        if let edition = details?.edition { meta += "<meta name=\"starling-edition\" content=\"\(escape(edition))\">\n" }
        if let rights = details?.rights { meta += "<meta name=\"copyright\" content=\"\(escape(rights))\">\n" }
        var html = template
        if let language = details?.language, let range = html.range(of: #"<html\b[^>]*>"#, options: .regularExpression) {
            var tag = String(html[range])
            if let lang = tag.range(of: #"\blang\s*=\s*("[^"]*"|'[^']*')"#, options: .regularExpression) {
                tag.replaceSubrange(lang, with: "lang=\"\(escape(language))\"")
            } else { tag.insert(contentsOf: " lang=\"\(escape(language))\"", at: tag.index(before: tag.endIndex)) }
            html.replaceSubrange(range, with: tag)
        }
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
        // Keep navigation and downloads available even for empty documents.
        // The app replaces the article as the reader moves between pages.
        if let r = html.range(of: "<body>") {
            let all = lines.isEmpty ? text.split(separator: "\n").map { (level: 0, text: String($0)) } : lines
            let elements = all.map { line -> String in
                let tag = (1 ... 3).contains(line.level) ? "h\(line.level)" : "p"
                return "<\(tag)>\(escape(line.text))</\(tag)>"
            }.joined(separator: "\n")
            // The site's pages as real links, so a crawler reaches every
            // page and a screen reader can move between them.
            let links = nav.map { "<li>" + String(repeating: "&nbsp;&nbsp;", count: $0.depth) + "<a href=\"" + escape($0.route) + "\">" + escape($0.title) + "</a></li>" }.joined(separator: "\n")
            let navHTML = nav.isEmpty ? "" : "<nav aria-label=\"Pages\"><ul>\n" + links + "\n</ul></nav>\n"
            let downloadsHTML = downloads.map { "<p class=\"starling-downloads\"><a href=\"" + escape($0.pdf) + "\">Download as PDF</a> · <a href=\"" + escape($0.docx) + "\">Download as Word</a></p>\n" } ?? ""
            let detailFields = [details?.byline, details?.summary, details?.edition, details?.rights].compactMap { $0 }
            let detailsHTML = detailFields.isEmpty ? "" : "<aside aria-label=\"About this publication\">" + detailFields.map { "<p>" + escape($0) + "</p>" }.joined() + "</aside>\n"
            html.replaceSubrange(r, with: "<body class=\"starling-publication\">\n" + SiteReaderFallback.markup + "<main id=\"starling-text\" class=\"starling-sr\" aria-label=\"" + escape(siteTitle) + "\">\n" + navHTML
                + detailsHTML + "<article id=\"starling-article\" aria-label=\"" + escape(title) + "\">\n" + downloadsHTML + elements + "\n</article>\n</main>")
        }
        return html
    }
}
#endif
