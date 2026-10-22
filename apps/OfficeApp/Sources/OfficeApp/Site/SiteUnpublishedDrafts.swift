// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Flutter

#if !os(WASI)
/// Chapters which have never been included. Both their title and document stay
/// outside site.json, source files, generated output and Git's tracked history.
enum SiteUnpublishedDrafts {
    struct Draft: Codable, Equatable {
        let version: Int
        let id: String
        let slug: String
        var title: String
        var working: Data
        var setAside: Bool? = nil
        var isSetAside: Bool { setAside == true }
        var node: SiteNode { SiteNode(slug: slug, title: title) }
    }

    private static func directory(repo: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: repo + "/.git") else { return nil }
        let git = try SitePublicationState.receiptURL(repo: repo).deletingLastPathComponent().resolvingSymlinksInPath()
        let directory = git.appendingPathComponent("starling-unpublished")
        guard directory.resolvingSymlinksInPath().path == directory.path else {
            throw SiteError("Unpublished chapter storage must stay in this publication's local history folder.")
        }
        return directory
    }

    static func loadAll(repo: String) throws -> [Draft] {
        guard let directory = try directory(repo: repo),
              FileManager.default.fileExists(atPath: directory.path) else { return [] }
        var result: [Draft] = []
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard file.pathExtension == "json", properties.isRegularFile == true, properties.isSymbolicLink != true,
                  file.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.path else {
                throw SiteError("Unexpected file in unpublished chapter storage. Recover it before publishing.")
            }
            let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: file))
            guard (draft.version == 1 || draft.version == 2),
                  (draft.version == 1 ? draft.setAside == nil : draft.setAside != nil), UUID(uuidString: draft.id) != nil,
                  !draft.slug.isEmpty, draft.slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
                  file.lastPathComponent == draft.slug + ".json", !draft.title.trimmingWhitespace().isEmpty,
                  SiteFiles.decodePage(draft.working) != nil else {
                throw SiteError("An unpublished chapter cannot be read by this version. Recover it before publishing.")
            }
            result.append(draft)
        }
        return result.sorted { $0.slug < $1.slug }
    }

    static func load(repo: String, slug: String) throws -> Draft? {
        try loadAll(repo: repo).first { $0.slug == slug }
    }

    static func authorManifest(repo: String) throws -> SiteManifest {
        var manifest = SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo), base: "/")
        for draft in try loadAll(repo: repo) where !draft.isSetAside {
            // An interrupted inclusion can already have inserted this node.
            if manifest.node(draft.slug) == nil { manifest.pages.append(draft.node) }
        }
        return manifest
    }

    private static func write(_ draft: Draft, repo: String) throws {
        guard let directory = try directory(repo: repo) else {
            throw SiteError("Unpublished chapters require local history. Create a publication from Writer's Home first.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(draft.slug + ".json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw SiteError("Invalid unpublished chapter storage.") }
        try JSONEncoder().encode(draft).write(to: file, options: .atomic)
    }

    private static func hasHistory(repo: String, slug: String) throws -> Bool {
        let path = SiteFiles.pagePath(slug)
        let index = LocalSiteStore.git(["--literal-pathspecs", "ls-files", "--", path], in: repo)
        let history = LocalSiteStore.git(["--literal-pathspecs", "log", "--all", "--full-history", "--format=%H", "--", path], in: repo)
        guard index.status == 0, history.status == 0 else { throw SiteError("Could not check the chapter's local history.") }
        return !index.output.isEmpty || !history.output.isEmpty
    }

    static func create(repo: String, title: String, page: SitePage) throws -> String {
        try SiteDrafts.mutate(repo: repo) {
            guard try directory(repo: repo) != nil else {
                throw SiteError("Create a publication from Writer's Home before adding an unpublished chapter.")
            }
            let title = title.trimmingWhitespace()
            guard !title.isEmpty else { throw SiteError("Give this chapter a title.") }
            let taken = Set(try authorManifest(repo: repo).flattened().map { $0.node.slug.lowercased() })
                .union(try loadAll(repo: repo).map { $0.slug.lowercased() })
                .union(try SiteDrafts.loadAll(repo: repo).keys.map { $0.lowercased() })
                .union(SiteBuilder.reservedSlugs(web: SiteBuilder.defaultWebStage()))
            let base = SiteFiles.slug(for: title)
            var slug = base, number = 2
            while try taken.contains(slug.lowercased()) || FileManager.default.fileExists(atPath: repo + "/" + SiteFiles.pagePath(slug))
                    || hasHistory(repo: repo, slug: slug) {
                slug = base + "-" + String(number); number += 1
            }
            var document = page.document
            document.assignParagraphIDs()
            let draft = Draft(version: 1, id: UUID().uuidString, slug: slug, title: title,
                              working: try RichDocumentEnvelope.encode(document, pageSetup: page.pageSetup))
            try write(draft, repo: repo)
            return slug
        }
    }

    /// Called under the shared cross-process draft lock.
    static func saveUnlocked(_ data: Data, repo: String, draft: Draft, expectedStorageID: String?) throws {
        guard !draft.isSetAside else { throw SiteError("This chapter was set aside. Keep your edits open, restore the draft in publication review, then reopen it before saving.") }
        guard expectedStorageID == nil || expectedStorageID == draft.id else {
            throw SiteError("The draft's release choice changed in another window. Save a separate copy before reopening.")
        }
        try validateSources(repo: repo, slugs: Set(SiteBuilder.manifest(from: SiteBuilder.readConfig(repo)).flattened().map(\.node.slug)))
        var updated = draft
        updated.working = data
        try write(updated, repo: repo)
    }

    static func rename(repo: String, slug: String, title: String) throws {
        try SiteDrafts.mutate(repo: repo) {
            guard var draft = try load(repo: repo, slug: slug), !draft.isSetAside, !title.trimmingWhitespace().isEmpty else {
                throw SiteError("Choose an unpublished chapter and a nonempty title.")
            }
            draft.title = title.trimmingWhitespace()
            try write(draft, repo: repo)
        }
    }

    static func setAside(repo: String, expected: Draft) throws {
        try changeAvailability(repo: repo, expected: expected, setAside: true)
    }

    static func restore(repo: String, expected: Draft) throws {
        try changeAvailability(repo: repo, expected: expected, setAside: false)
    }

    /// A single atomic record replacement retains the complete document. Keep
    /// the address reserved and privacy checks active while it is out of view.
    private static func changeAvailability(repo: String, expected: Draft, setAside: Bool) throws {
        try SiteDrafts.mutate(repo: repo) {
            guard expected.isSetAside != setAside,
                  try load(repo: repo, slug: expected.slug) == expected else {
                throw SiteError("This chapter changed after review. Refresh review before changing its draft state.")
            }
            let slugs = Set(try SiteBuilder.manifest(from: SiteBuilder.readConfig(repo)).flattened().map(\.node.slug))
            try validateSources(repo: repo, slugs: slugs)
            guard try !hasHistory(repo: repo, slug: expected.slug) else {
                throw SiteError("This chapter appears in Git history or the index. Resolve that history before setting aside or restoring it.")
            }
            // New identity rejects editors/imports opened before either action,
            // including a round trip through set-aside and restore.
            let updated = Draft(version: 2, id: UUID().uuidString, slug: expected.slug,
                                title: expected.title, working: expected.working, setAside: setAside)
            try write(updated, repo: repo)
        }
    }

    /// Retain the record until both release files are written. If interrupted,
    /// build/upload fail closed and the same reviewed snapshot can be retried.
    static func include(repo: String, expected: Draft) throws {
        try SiteDrafts.mutate(repo: repo) {
            guard !expected.isSetAside else { throw SiteError("Restore this chapter as a draft before including it in publication.") }
            guard try load(repo: repo, slug: expected.slug) == expected else {
                throw SiteError("The chapter changed after review. Refresh review before including it.")
            }
            var config = try SiteBuilder.readConfig(repo)
            let existing = SiteBuilder.manifest(from: config).node(expected.slug)
            guard existing == nil || existing == expected.node else {
                throw SiteError("Another page uses this chapter's address. Resolve it before including the draft.")
            }
            let source = try SiteDrafts.sourceURL(repo: repo, slug: expected.slug)
            if FileManager.default.fileExists(atPath: source.path) {
                guard try Data(contentsOf: source) == expected.working else {
                    throw SiteError("Another file uses this chapter's address. Your local draft has been kept.")
                }
            }
            try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
            try expected.working.write(to: source, options: .atomic)
            if existing == nil {
                config.pages.append(expected.node)
                try SiteBuilder.writeConfig(config, to: repo)
            }
            guard let directory = try directory(repo: repo) else { throw SiteError("Unpublished chapter storage is unavailable.") }
            try FileManager.default.removeItem(at: directory.appendingPathComponent(expected.slug + ".json"))
        }
    }

    static func validateSources(repo: String, slugs: Set<String>) throws {
        for draft in try loadAll(repo: repo) {
            guard !slugs.contains(draft.slug),
                  !FileManager.default.fileExists(atPath: repo + "/" + SiteFiles.pagePath(draft.slug)) else {
                throw SiteError("An unpublished chapter also appears in release files. Finish including its reviewed draft, or recover those files before building.")
            }
        }
    }

    static func validateUpload(repo: String) throws {
        let slugs = Set(try SiteBuilder.manifest(from: SiteBuilder.readConfig(repo)).flattened().map(\.node.slug))
        try validateSources(repo: repo, slugs: slugs)
        for draft in try loadAll(repo: repo) {
            guard try !hasHistory(repo: repo, slug: draft.slug) else {
                throw SiteError("An unpublished chapter appears in local Git history or the index. Resolve that history before uploading; a local draft cannot hide committed text.")
            }
        }
    }
}
#endif
