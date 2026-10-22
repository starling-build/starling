// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if !os(WASI)
/// Separate working revisions live in Git's local metadata, outside the source
/// tree and every publication path. Builds continue using the released source.
/// This is device-local retention, not encrypted storage or a backup service.
enum SiteDrafts {
    struct Draft: Codable, Equatable {
        let version: Int
        let id: String
        let slug: String
        let revision: String
        let destination: String
        let target: String
        let out: String
        let released: Data
        var working: Data
    }

    private static func validSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private static func directory(repo: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: repo + "/.git") else { return nil }
        let git = try SitePublicationState.receiptURL(repo: repo).deletingLastPathComponent().resolvingSymlinksInPath()
        let directory = git.appendingPathComponent("starling-drafts")
        guard directory.resolvingSymlinksInPath().path == directory.path else {
            throw SiteError("The local draft folder must stay in this publication's Git metadata.")
        }
        return directory
    }

    static func loadAll(repo: String) throws -> [String: Draft] {
        guard let directory = try directory(repo: repo),
              FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        var drafts: [String: Draft] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            // Directory enumeration on macOS may use /private/var while the
            // resolved directory uses /var. Check file identity/type, not that
            // incidental spelling, while rejecting actual symbolic links.
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard file.pathExtension == "json", properties.isRegularFile == true, properties.isSymbolicLink != true,
                  file.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.path else {
                throw SiteError("An unexpected file was found in local draft storage. Keep the folder intact and recover it before publishing.")
            }
            let draft = try JSONDecoder().decode(Draft.self, from: Data(contentsOf: file))
            guard draft.version == 1, UUID(uuidString: draft.id) != nil, validSlug(draft.slug), file.lastPathComponent == draft.slug + ".json",
                  (40...64).contains(draft.revision.count), draft.revision.allSatisfy({ $0.isHexDigit }),
                  SiteFiles.decodePage(draft.released) != nil, SiteFiles.decodePage(draft.working) != nil else {
                throw SiteError("A local draft cannot be read by this version. Do not publish until it has been recovered.")
            }
            drafts[draft.slug] = draft
        }
        return drafts
    }

    static func load(repo: String, slug: String) throws -> Draft? {
        try loadAll(repo: repo)[slug]
    }

    static func sourceURL(repo: String, slug: String) throws -> URL {
        guard validSlug(slug) else { throw SiteError("Choose a valid publication page.") }
        let root = URL(fileURLWithPath: repo).standardizedFileURL.resolvingSymlinksInPath()
        let source = root.appendingPathComponent(SiteFiles.pagePath(slug)).resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/") else { throw SiteError("The page source is outside this publication.") }
        return source
    }

    static func workingData(repo: String, slug: String) throws -> Data {
        try workingSnapshot(repo: repo, slug: slug).data
    }

    static func workingSnapshot(repo: String, slug: String) throws -> (data: Data, storageID: String) {
        if let draft = try SiteUnpublishedDrafts.load(repo: repo, slug: slug) { return (draft.working, draft.id) }
        if let draft = try load(repo: repo, slug: slug) { return (draft.working, draft.id) }
        return (try Data(contentsOf: sourceURL(repo: repo, slug: slug)), "release")
    }

    private static let mutationLock = NSLock()
    static func mutate<T>(repo: String, _ body: () throws -> T) throws -> T {
        // Serialize the short local transitions, never a network upload.
        guard mutationLock.try() else { throw SiteError("Another draft operation is in progress. Try again after it finishes.") }
        defer { mutationLock.unlock() }
        #if canImport(Darwin) || canImport(Glibc)
        if let directory = try directory(repo: repo) {
            let file = directory.deletingLastPathComponent().appendingPathComponent("starling-drafts.lock")
            let descriptor = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw SiteError("Could not lock local draft storage. Check the publication folder permissions.") }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                throw SiteError("Another window is changing this draft. Try again after it finishes.")
            }
            defer { _ = flock(descriptor, LOCK_UN) }
            return try body()
        }
        #endif
        return try body()
    }

    private static func write(_ draft: Draft, repo: String) throws {
        guard let directory = try directory(repo: repo) else { throw SiteError("Local drafts require a publication repository.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(draft.slug + ".json")
        guard file.resolvingSymlinksInPath().path == file.path else { throw SiteError("The local draft file is outside its storage folder.") }
        try JSONEncoder().encode(draft).write(to: file, options: .atomic)
    }

    /// Start only from a fully uploaded local history and an unchanged released
    /// chapter. Moving already-committed draft text cannot make it private.
    static func start(repo: String, out: String, slug: String) throws {
        try mutate(repo: repo) { try startUnlocked(repo: repo, out: out, slug: slug) }
    }

    private static func startUnlocked(repo: String, out: String, slug: String) throws {
        guard try load(repo: repo, slug: slug) == nil else { throw SiteError("This page already has a separate draft.") }
        let receipt = try SitePublicationState.matchingReceipt(repo: repo, out: out)
        let head = LocalSiteStore.git(["rev-parse", "HEAD"], in: repo)
        guard head.status == 0, head.output.trimmingWhitespace() == receipt.revision else {
            throw SiteError("There are local history entries since the last upload. Resolve or publish them before starting a separate draft; committed text may travel with that history.")
        }
        let manifestResult = LocalSiteStore.git(["show", receipt.revision + ":" + out + "/" + SiteFiles.manifest], in: repo)
        guard manifestResult.status == 0,
              let manifest = try? JSONDecoder().decode(SiteManifest.self, from: Data(manifestResult.output.utf8)),
              manifest.node(slug) != nil,
              SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo)).node(slug) != nil else {
            throw SiteError("Publish this page before starting its next draft.")
        }
        let sent = LocalSiteStore.git(["show", receipt.revision + ":" + out + "/" + SiteFiles.pagePath(slug)], in: repo)
        let source = try Data(contentsOf: sourceURL(repo: repo, slug: slug))
        guard sent.status == 0, source == Data(sent.output.utf8) else {
            throw SiteError("This page has saved changes. Publish this revision first, then start a separate draft.")
        }
        let draft = Draft(version: 1, id: UUID().uuidString, slug: slug, revision: receipt.revision, destination: receipt.destination,
                          target: receipt.target, out: out, released: source, working: source)
        // Verify the committed source too: a publication artifact alone does
        // not prove that the repository source is safe to send.
        try validateHistory(draft, repo: repo)
        try write(draft, repo: repo)
    }

    static func save(_ data: Data, repo: String, slug: String, expectedStorageID: String? = nil) throws {
        try mutate(repo: repo) { try saveUnlocked(data, repo: repo, slug: slug, expectedStorageID: expectedStorageID) }
    }

    private static func saveUnlocked(_ data: Data, repo: String, slug: String, expectedStorageID: String?) throws {
        if let draft = try SiteUnpublishedDrafts.load(repo: repo, slug: slug) {
            try SiteUnpublishedDrafts.saveUnlocked(data, repo: repo, draft: draft, expectedStorageID: expectedStorageID)
            return
        }
        guard SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo)).node(slug) != nil else {
            throw SiteError("This page is no longer in the publication.")
        }
        let source = try sourceURL(repo: repo, slug: slug)
        let existing = try load(repo: repo, slug: slug)
        guard expectedStorageID == nil || expectedStorageID == (existing?.id ?? "release") else {
            throw SiteError("The draft's release choice changed in another window. Keep your edits open and save a separate copy before reopening the publication.")
        }
        if var draft = existing {
            guard try Data(contentsOf: source) == draft.released else {
                throw SiteError("The release file changed outside the draft. Keep your edits open and resolve that change before saving.")
            }
            draft.working = data
            try write(draft, repo: repo)
        } else {
            try data.write(to: source, options: .atomic)
        }
    }

    /// Opt into the next release without uploading. A failed removal leaves
    /// the draft intact and blocks builds; retrying the same promotion is safe.
    static func include(repo: String, expected: Draft) throws {
        try mutate(repo: repo) { try includeUnlocked(repo: repo, expected: expected) }
    }

    private static func includeUnlocked(repo: String, expected: Draft) throws {
        guard try load(repo: repo, slug: expected.slug) == expected else {
            throw SiteError("The draft changed after review. Refresh review before including it.")
        }
        guard SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo)).node(expected.slug) != nil else {
            throw SiteError("This page is no longer in the publication.")
        }
        let source = try sourceURL(repo: repo, slug: expected.slug)
        let current = try Data(contentsOf: source)
        guard current == expected.released || current == expected.working else {
            throw SiteError("The release file changed outside the draft. Resolve it before including this revision.")
        }
        try expected.working.write(to: source, options: .atomic)
        guard let directory = try directory(repo: repo) else { throw SiteError("Local draft storage is unavailable.") }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(expected.slug + ".json"))
    }

    static func validateSources(repo: String, slugs: Set<String>, drafts: [String: Draft]) throws {
        try SiteUnpublishedDrafts.validateSources(repo: repo, slugs: slugs)
        for draft in drafts.values {
            guard slugs.contains(draft.slug),
                  try Data(contentsOf: sourceURL(repo: repo, slug: draft.slug)) == draft.released else {
                throw SiteError("The release file for \(draft.slug) changed while its draft is held. Restore the release file or explicitly include the reviewed draft before building.")
            }
        }
    }

    private static func validateHistory(_ draft: Draft, repo: String) throws {
        let committed = LocalSiteStore.git(["show", draft.revision + ":" + SiteFiles.pagePath(draft.slug)], in: repo)
        let ancestor = LocalSiteStore.git(["merge-base", "--is-ancestor", draft.revision, "HEAD"], in: repo)
        let changes = LocalSiteStore.git(["--literal-pathspecs", "rev-list", "--full-history",
                                         draft.revision + "..HEAD", "--", SiteFiles.pagePath(draft.slug)], in: repo)
        guard committed.status == 0, Data(committed.output.utf8) == draft.released,
              ancestor.status == 0, changes.status == 0, changes.output.trimmingWhitespace().isEmpty else {
            throw SiteError("Publishing history changed for a held chapter. Resolve the local history before uploading; holding a draft cannot hide committed versions.")
        }
    }

    static func validateUpload(repo: String, out: String) throws {
        try SiteUnpublishedDrafts.validateUpload(repo: repo)
        let drafts = try loadAll(repo: repo)
        guard !drafts.isEmpty else { return }
        let receipt = try SitePublicationState.matchingReceipt(repo: repo, out: out)
        let slugs = Set(SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo)).flattened().map(\.node.slug))
        try validateSources(repo: repo, slugs: slugs, drafts: drafts)
        for draft in drafts.values {
            guard draft.out == out, draft.destination == receipt.destination, draft.target == receipt.target else {
                throw SiteError("Publishing destination changed while drafts are held. Restore the original publishing settings before uploading.")
            }
            try validateHistory(draft, repo: repo)
        }
    }
}
#endif
