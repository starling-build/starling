// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if !os(WASI)
import Foundation
import Flutter

/// The document a site's new pages start from — `template` in site.json,
/// a path inside the repository to a .docx (or any file the Writer
/// opens) or a stored page .json. It is to the site what a .dotx is to
/// Word: New page opens a copy of it, and a source that carries no design
/// of its own (Markdown, RTF, plain text) is imported in its design — the
/// template's styles, header and footer, page setup and document
/// settings, with the source's text. A .docx import keeps its own design.
enum SiteTemplate {
    /// The site's template page, or nil when site.json names none.
    static func load(repo: String, config: SiteConfig) throws -> SitePage? {
        guard let name = config.template?.trimmingWhitespace(), !name.isEmpty else { return nil }
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else {
            throw SiteBuilder.Failure("template must be a path inside the repository, not \(name)")
        }
        let path = repo + "/" + name
        guard let data = FileManager.default.contents(atPath: path) else {
            throw SiteBuilder.Failure("the template \(name) is missing")
        }
        if name.pathExtension.lowercased() == "json" {
            guard let page = SiteFiles.decodePage(data) else { throw SiteBuilder.Failure("the template \(name) is not a stored page") }
            return page
        }
        do {
            let opened = try OfficeFormats.read(data, named: path)
            return SitePage(document: opened.document, pageSetup: opened.pageSetup)
        } catch {
            throw SiteBuilder.Failure("the template \(name) could not be opened: \(error)")
        }
    }

    /// The site's template loaded, when it names one; else nil.
    static func load(repo: String) throws -> SitePage? {
        try load(repo: repo, config: SiteBuilder.readConfig(repo))
    }

    /// A new page: the template whole, as Word opens a document from a
    /// .dotx, its paragraphs given ids of their own.
    static func newPage(from template: SitePage) -> SitePage {
        var doc = template.document
        for i in doc.paragraphs.indices { doc.paragraphs[i].id = 0 }
        doc.assignParagraphIDs()
        return SitePage(document: doc, pageSetup: template.pageSetup)
    }

    /// `page` in the template's design with its own content: the template
    /// owns the styles, header and footer, page setup and settings; the
    /// page owns its paragraphs and what they refer to (tables, lists,
    /// notes). A style the page's paragraphs name that the template lacks
    /// is added from the page's sheet, so nothing falls back to Normal.
    static func dress(_ page: SitePage, in template: SitePage) -> SitePage {
        var doc = template.document
        let own = page.document
        doc.paragraphs = own.paragraphs
        doc.tableColumns = own.tableColumns
        doc.tableStyles = own.tableStyles
        doc.keptTables = own.keptTables
        doc.listFormats = own.listFormats
        doc.listCounterOf = own.listCounterOf
        doc.listRestarts = own.listRestarts
        doc.footnotes = own.footnotes
        doc.footnoteSeparator = own.footnoteSeparator
        doc.endnotes = own.endnotes
        doc.endnoteSeparator = own.endnoteSeparator
        doc.divMargins = own.divMargins
        doc.readFromFile = false
        // The template's cover is not here, so its first page is an
        // ordinary page: the header and footer run from page 1.
        doc.titlePage = false
        for style in own.styles.styles where doc.styles[style.id] == nil {
            doc.styles[style.id] = style
        }
        return SitePage(document: doc, pageSetup: template.pageSetup ?? page.pageSetup)
    }

    /// Whether a source file carries a design of its own: a Word file does
    /// (a zip, "PK"); Markdown, RTF and plain text do not.
    static func carriesDesign(_ data: Data) -> Bool {
        data.count > 4 && data[0] == 0x50 && data[1] == 0x4B
    }
}
#endif
