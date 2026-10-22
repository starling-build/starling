// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SiteUnpublishedDraftTests: XCTestCase {
    private func page(_ text: String) -> SitePage {
        SitePage(document: RichDocument(paragraphs: [RichParagraph(text: text)]), pageSetup: nil)
    }

    private func fixture(_ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try SiteCreation.create(title: "Serial", parent: root.path)
        try body(repo)
    }

    func testNewChapterBeforeFirstUploadHasPrivateTitleAndSource() throws {
        try fixture { repo in
            let config = try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json"))
            let store = LocalSiteStore(repo: repo)
            var slug = ""
            store.createPage(title: "Secret finale", under: "welcome") { slug = (try? $0.get()) ?? "" }
            XCTAssertEqual(slug, "secret-finale")
            store.page(slug) { XCTAssertNotNil(try? $0.get()) }
            store.save(slug, page("The murderer is the captain.")) { XCTAssertNil($0) }
            store.rename(slug, to: "The captain's secret") { XCTAssertNil($0) }
            let loaded = expectation(description: "Author contents loaded")
            store.manifest {
                XCTAssertEqual(try? $0.get().node(slug)?.title, "The captain's secret")
                loaded.fulfill()
            }
            wait(for: [loaded], timeout: 10)
            store.search { XCTAssertTrue((try? $0.get().contains { $0.slug == slug && $0.text.contains("murderer") }) == true) }
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json")), config)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/pages/" + slug + ".json"))
            XCTAssertEqual(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil).count, 1)
            let review = try SitePublishReview.load(repo: repo, out: "docs", web: nil)
            XCTAssertEqual(review.pages.count, 1)
            XCTAssertEqual(review.unpublished.map(\.title), ["The captain's secret"])
            XCTAssertFalse(review.compared)
            try SiteDrafts.validateUpload(repo: repo, out: "docs") // No receipt needed.
        }
    }

    func testImportAndStaleEditorCannotWriteThroughInclusion() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Initial"))
            let store = LocalSiteStore(repo: repo)
            store.page(slug) { XCTAssertNotNil(try? $0.get()) }
            let update = try LocalSiteStore.prepareUpdate(repo: repo, slug: slug, page: page("Revised"))
            try LocalSiteStore.applyUpdate(repo: repo, revision: update)
            let draft = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            let stale = try LocalSiteStore.prepareUpdate(repo: repo, slug: slug, page: page("More edits"))
            try SiteUnpublishedDrafts.include(repo: repo, expected: draft)
            XCTAssertNil(try SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertEqual(try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: slug)), draft.working)
            XCTAssertEqual(try SiteBuilder.readConfig(repo).resolvedHome, "welcome")
            XCTAssertEqual(try SiteBuilder.readConfig(repo).pages.last, draft.node)
            store.save(slug, page("Open editor must not overwrite")) { XCTAssertNotNil($0) }
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: repo, revision: stale))
            store.page(slug) { XCTAssertNotNil(try? $0.get()) }
            store.save(slug, page("Freshly reopened")) { XCTAssertNil($0) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/docs"))
        }
    }

    func testChangedReviewRejectsInclusionAndConflictsKeepDraft() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Draft"))
            let old = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.rename(repo: repo, slug: slug, title: "Changed title")
            XCTAssertThrowsError(try SiteUnpublishedDrafts.include(repo: repo, expected: old))
            let current = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            let source = try SiteDrafts.sourceURL(repo: repo, slug: slug)
            try Data("unrelated file".utf8).write(to: source)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.include(repo: repo, expected: current))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), current)
            XCTAssertEqual(try Data(contentsOf: source), Data("unrelated file".utf8))
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
        }
    }

    func testInterruptedInclusionBlocksBuildAndCanBeRetried() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Draft"))
            let draft = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            // Crash after source write, then after navigation write.
            try draft.working.write(to: SiteDrafts.sourceURL(repo: repo, slug: slug))
            XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil))
            var config = try SiteBuilder.readConfig(repo)
            config.pages.append(draft.node)
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertThrowsError(try SiteDrafts.save(draft.working, repo: repo, slug: slug, expectedStorageID: draft.id))
            try SiteUnpublishedDrafts.include(repo: repo, expected: draft)
            XCTAssertEqual(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil).count, 2)
            XCTAssertEqual(try SiteBuilder.readConfig(repo).pages.filter { $0.slug == slug }.count, 1)
        }
    }

    func testNamesAvoidPublishedPrivateReservedAndHistoricalPaths() throws {
        try fixture { repo in
            XCTAssertEqual(try SiteUnpublishedDrafts.create(repo: repo, title: "Welcome", page: page("Draft")), "welcome-2")
            XCTAssertEqual(try SiteUnpublishedDrafts.create(repo: repo, title: "Welcome", page: page("Draft")), "welcome-3")
            XCTAssertEqual(try LocalSiteStore.addPage(repo: repo, title: "Welcome", page: page("Release"), under: nil), "welcome-4")
            XCTAssertEqual(try SiteUnpublishedDrafts.create(repo: repo, title: "Pages", page: page("Draft")), "pages-2")
            let source = URL(fileURLWithPath: repo + "/pages/removed.json")
            try RichDocumentEnvelope.encode(page("Old version").document).write(to: source)
            for args in [["config", "user.name", "Test"], ["config", "user.email", "test@example.test"],
                         ["add", "."], ["commit", "-qm", "Old chapter"], ["rm", "pages/removed.json"], ["commit", "-qm", "Remove"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            XCTAssertEqual(try SiteUnpublishedDrafts.create(repo: repo, title: "Removed", page: page("Draft")), "removed-2")
        }
    }

    func testStagedOrCommittedThenDeletedDraftSourceBlocksUpload() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Secret"))
            let draft = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            let source = try SiteDrafts.sourceURL(repo: repo, slug: slug)
            try draft.working.write(to: source)
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            try FileManager.default.removeItem(at: source)
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            for args in [["config", "user.name", "Test"], ["config", "user.email", "test@example.test"],
                         ["commit", "-qm", "Mistaken source"], ["add", "-u"], ["commit", "-qm", "Remove source"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), draft)
        }
    }

    func testMergedThenDeletedDraftHistoryCannotDisappearThroughSimplification() throws {
        try fixture { repo in
            for args in [["config", "user.name", "Test"], ["config", "user.email", "test@example.test"],
                         ["add", "."], ["commit", "-qm", "Initial"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Secret", page: page("Secret ending"))
            let draft = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertEqual(LocalSiteStore.git(["checkout", "-qb", "side"], in: repo).status, 0)
            try draft.working.write(to: SiteDrafts.sourceURL(repo: repo, slug: slug))
            for args in [["add", "."], ["commit", "-qm", "Accidental source"],
                         ["rm", SiteFiles.pagePath(slug)], ["commit", "-qm", "Remove"],
                         ["checkout", "main"], ["merge", "--no-ff", "side", "-m", "Merge"], ["branch", "-d", "side"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), draft)
        }
    }

    func testSetAsideAndRestoreRetainTitleAndBytesWithoutReleaseChanges() throws {
        try fixture { repo in
            let config = try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json"))
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Alternative ending", page: page("The captain survives."))
            let original = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertEqual(original.version, 1) // Existing records remain readable.
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: original)
            let kept = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertEqual(kept.version, 2)
            XCTAssertTrue(kept.isSetAside)
            XCTAssertNotEqual(kept.id, original.id)
            XCTAssertEqual(kept.working, original.working)
            XCTAssertEqual(kept.title, original.title)
            XCTAssertNil(try SiteUnpublishedDrafts.authorManifest(repo: repo).node(slug))
            let store = LocalSiteStore(repo: repo)
            store.search { XCTAssertFalse((try? $0.get().contains { $0.slug == slug }) ?? true) }
            let review = try SitePublishReview.load(repo: repo, out: "docs", web: nil)
            XCTAssertTrue(review.unpublished.isEmpty)
            XCTAssertEqual(review.setAside, [kept])
            XCTAssertThrowsError(try SiteDrafts.workingSnapshot(repo: repo, slug: slug))
            XCTAssertThrowsError(try SiteUnpublishedDrafts.include(repo: repo, expected: kept))
            XCTAssertThrowsError(try SiteUnpublishedDrafts.rename(repo: repo, slug: slug, title: "Hidden edit"))
            XCTAssertThrowsError(try SiteDrafts.save(original.working, repo: repo, slug: slug))
            try SiteDrafts.validateUpload(repo: repo, out: "docs")
            try SiteUnpublishedDrafts.restore(repo: repo, expected: kept)
            let restored = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertFalse(restored.isSetAside)
            XCTAssertNotEqual(restored.id, kept.id)
            XCTAssertNotEqual(restored.id, original.id)
            XCTAssertEqual(restored.working, original.working)
            XCTAssertEqual(restored.title, original.title)
            XCTAssertEqual(try SiteUnpublishedDrafts.authorManifest(repo: repo).node(slug), original.node)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json")), config)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/pages/" + slug + ".json"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/docs"))
        }
    }

    func testStaleReviewCannotSetAsideNewEditsOrRestoreAnotherSnapshot() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("First"))
            let before = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteDrafts.save(RichDocumentEnvelope.encode(page("Second").document), repo: repo, slug: slug)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.setAside(repo: repo, expected: before))
            let latest = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: latest)
            let aside = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            XCTAssertThrowsError(try SiteUnpublishedDrafts.setAside(repo: repo, expected: latest))
            try SiteUnpublishedDrafts.restore(repo: repo, expected: aside)
            let restored = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: restored)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.restore(repo: repo, expected: aside))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug)?.working, latest.working)
        }
    }

    func testOpenWriterAndImportCannotCrossSetAsideRestoreRoundTrip() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Original"))
            let store = LocalSiteStore(repo: repo)
            store.page(slug) { XCTAssertNotNil(try? $0.get()) }
            let imported = try LocalSiteStore.prepareUpdate(repo: repo, slug: slug, page: page("Import"))
            let original = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: original)
            store.save(slug, page("Stale editor")) { XCTAssertNotNil($0) }
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: repo, revision: imported))
            try SiteUnpublishedDrafts.restore(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            store.save(slug, page("Still stale")) { XCTAssertNotNil($0) }
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: repo, revision: imported))
            XCTAssertEqual(try SiteDrafts.workingData(repo: repo, slug: slug), original.working)
            store.page(slug) { XCTAssertNotNil(try? $0.get()) }
            store.save(slug, page("Reopened safely")) { XCTAssertNil($0) }
        }
    }

    func testSetAsideAddressStaysReservedForDraftAndLegacyImports() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Kept"))
            let original = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: original)
            XCTAssertEqual(try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("New")), "next-2")
            XCTAssertEqual(try LocalSiteStore.addPage(repo: repo, title: "Next", page: page("Legacy"), under: nil), "next-3")
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug)?.working, original.working)
            try SiteUnpublishedDrafts.restore(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            XCTAssertEqual(try SiteUnpublishedDrafts.authorManifest(repo: repo).node(slug)?.title, "Next")
        }
    }

    func testPartialInclusionAndConflictingFilesCannotBeHiddenBySetAside() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Draft"))
            let original = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            let source = try SiteDrafts.sourceURL(repo: repo, slug: slug)
            try original.working.write(to: source)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.setAside(repo: repo, expected: original))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), original)
            try FileManager.default.removeItem(at: source)
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: original)
            let kept = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try original.working.write(to: source)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.restore(repo: repo, expected: kept))
            XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil))
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), kept)
        }
    }

    func testSetAsideHistoryStillBlocksUploadAndRestoration() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Secret", page: page("Private ending"))
            let original = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: original)
            let kept = try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug))
            try kept.working.write(to: SiteDrafts.sourceURL(repo: repo, slug: slug))
            for args in [["config", "user.name", "Test"], ["config", "user.email", "test@example.test"],
                         ["add", "."], ["commit", "-qm", "Accidental source"],
                         ["rm", SiteFiles.pagePath(slug)], ["commit", "-qm", "Remove"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertThrowsError(try SiteUnpublishedDrafts.restore(repo: repo, expected: kept))
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), kept)
        }
    }

    func testMissingSetAsideStateInNewRecordVersionFailsClosed() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Kept"))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            let path = URL(fileURLWithPath: repo + "/.git/starling-unpublished/" + slug + ".json")
            let original = try Data(contentsOf: path)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            object.removeValue(forKey: "setAside")
            try JSONSerialization.data(withJSONObject: object).write(to: path)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.loadAll(repo: repo))
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            try original.write(to: path)
            XCTAssertTrue(try XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)).isSetAside)
        }
    }

    func testCorruptAndSymlinkedRecordsBlockBuildAndUpload() throws {
        try fixture { repo in
            let slug = try SiteUnpublishedDrafts.create(repo: repo, title: "Next", page: page("Secret"))
            let path = URL(fileURLWithPath: repo + "/.git/starling-unpublished/" + slug + ".json")
            let record = try Data(contentsOf: path)
            try Data("{}".utf8).write(to: path)
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil))
            try FileManager.default.removeItem(at: path)
            let outside = URL(fileURLWithPath: repo).deletingLastPathComponent().appendingPathComponent("private.json")
            try record.write(to: outside)
            try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
            XCTAssertThrowsError(try SiteUnpublishedDrafts.loadAll(repo: repo))
            XCTAssertEqual(try Data(contentsOf: outside), record)
        }
    }
}
#endif
