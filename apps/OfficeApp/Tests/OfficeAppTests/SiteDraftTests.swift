// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SiteDraftTests: XCTestCase {
    private func bytes(_ text: String) throws -> Data {
        var paragraph = RichParagraph(text: text)
        paragraph.id = 123
        return try RichDocumentEnvelope.encode(RichDocument(paragraphs: [paragraph]))
    }

    private func fixture(_ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try SiteCreation.create(title: "Serial", parent: root.path)
        var config = try SiteBuilder.readConfig(repo)
        config.pages.append(SiteNode(slug: "chapter", title: "Chapter"))
        config.url = "https://author.example/"
        try SiteBuilder.writeConfig(config, to: repo)
        try FileManager.default.createDirectory(atPath: repo + "/docs/pages", withIntermediateDirectories: true)
        for slug in ["welcome", "chapter"] {
            let data = try bytes("Released " + slug)
            try data.write(to: URL(fileURLWithPath: repo + "/pages/" + slug + ".json"))
            try data.write(to: URL(fileURLWithPath: repo + "/docs/pages/" + slug + ".json"))
        }
        try JSONEncoder().encode(SiteBuilder.manifest(from: config)).write(to: URL(fileURLWithPath: repo + "/docs/manifest.json"))
        try JSONEncoder().encode(SiteLivePublication.Marker(version: 1, build: UUID().uuidString))
            .write(to: URL(fileURLWithPath: repo + "/docs/" + SiteLivePublication.markerFile))
        for args in [["config", "user.name", "Draft Test"], ["config", "user.email", "draft@example.test"],
                     ["remote", "add", "origin", root.path + "/hosting.git"], ["add", "."], ["commit", "-qm", "Uploaded"]] {
            XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
        }
        try record(repo)
        try body(repo)
    }

    private func record(_ repo: String) throws {
        try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                        destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
    }

    func testSavedDraftStaysOutOfSourcesIndexAndReviewRelease() throws {
        try fixture { repo in
            let original = try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: "chapter"))
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: repo))
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let working = try bytes("Unreleased ending")
            try SiteDrafts.save(working, repo: repo, slug: "chapter")
            XCTAssertEqual(try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: "chapter")), original)
            XCTAssertEqual(try SiteDrafts.workingData(repo: repo, slug: "chapter"), working)
            XCTAssertEqual(try SiteDrafts.load(repo: repo, slug: "chapter")?.working, working)
            XCTAssertEqual(LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output, "")
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: repo)), receipt)
            XCTAssertEqual(SitePublicationState.status(repo: repo), .held)
            let review = try SitePublishReview.load(repo: repo, out: "docs", web: nil)
            let chapter = try XCTUnwrap(review.pages.first { $0.slug == "chapter" })
            XCTAssertEqual(chapter.change, .unchanged)
            XCTAssertNotNil(chapter.heldDraft)
            XCTAssertEqual(chapter.comparison?.passages.first?.after, "Unreleased ending")
            try SiteDrafts.validateUpload(repo: repo, out: "docs")
        }
    }

    func testWriterSaveAndWordUpdateBothUseHeldDraft() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let store = LocalSiteStore(repo: repo)
            let page = try XCTUnwrap(SiteFiles.decodePage(bytes("Writer revision")))
            store.save("chapter", page) { XCTAssertNil($0) }
            store.page("chapter") { result in
                XCTAssertEqual(try? result.get().document.paragraphs[0].text, "Writer revision")
            }
            let incoming = try XCTUnwrap(SiteFiles.decodePage(bytes("Word revision")))
            let revision = try LocalSiteStore.prepareUpdate(repo: repo, slug: "chapter", page: incoming)
            XCTAssertEqual(revision.original.document.paragraphs[0].text, "Writer revision")
            try LocalSiteStore.applyUpdate(repo: repo, revision: revision)
            XCTAssertEqual(try SiteDrafts.workingData(repo: repo, slug: "chapter"), try SiteDrafts.load(repo: repo, slug: "chapter")?.working)
            XCTAssertEqual(try SiteFiles.decodePage(Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: "chapter")))?.document.paragraphs[0].text, "Released chapter")
            store.delete("chapter") { XCTAssertTrue($0?.contains("separate local draft") == true) }
        }
    }

    func testIncludingDraftRequiresCurrentReviewAndDoesNotUpload() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let earlier = try XCTUnwrap(SiteDrafts.load(repo: repo, slug: "chapter"))
            let new = try bytes("Ready for readers")
            try SiteDrafts.save(new, repo: repo, slug: "chapter")
            XCTAssertThrowsError(try SiteDrafts.include(repo: repo, expected: earlier))
            let reviewed = try XCTUnwrap(SiteDrafts.load(repo: repo, slug: "chapter"))
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: repo))
            let output = try Data(contentsOf: URL(fileURLWithPath: repo + "/docs/pages/chapter.json"))
            try SiteDrafts.include(repo: repo, expected: reviewed)
            XCTAssertNil(try SiteDrafts.load(repo: repo, slug: "chapter"))
            XCTAssertEqual(try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: "chapter")), new)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/docs/pages/chapter.json")), output)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: repo)), receipt)
            XCTAssertEqual(SitePublicationState.status(repo: repo), .pending)
        }
    }

    func testOpenWriterAndPreparedImportCannotCrossAChangedReleaseChoice() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let store = LocalSiteStore(repo: repo)
            store.page("chapter") { XCTAssertNotNil(try? $0.get()) }
            let incoming = try XCTUnwrap(SiteFiles.decodePage(bytes("Still writing")))
            let revision = try LocalSiteStore.prepareUpdate(repo: repo, slug: "chapter", page: incoming)
            let reviewed = try XCTUnwrap(SiteDrafts.load(repo: repo, slug: "chapter"))
            try SiteDrafts.include(repo: repo, expected: reviewed)
            store.save("chapter", incoming) { XCTAssertTrue($0?.contains("release choice changed") == true) }
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: repo, revision: revision))
            XCTAssertEqual(try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: "chapter")), reviewed.released)
            // A new draft from the same release has a different identity.
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            XCTAssertNotEqual(try SiteDrafts.load(repo: repo, slug: "chapter")?.id, reviewed.id)
            store.save("chapter", incoming) { XCTAssertNotNil($0) }
            XCTAssertEqual(try SiteDrafts.workingData(repo: repo, slug: "chapter"), reviewed.released)
        }
    }

    func testChangedReleaseSourceBlocksBuildAndUploadWithoutLosingDraft() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            try SiteDrafts.save(bytes("Held text"), repo: repo, slug: "chapter")
            let held = try XCTUnwrap(SiteDrafts.load(repo: repo, slug: "chapter"))
            try bytes("External edit").write(to: SiteDrafts.sourceURL(repo: repo, slug: "chapter"))
            XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil))
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertThrowsError(try SiteDrafts.save(bytes("Another edit"), repo: repo, slug: "chapter"))
            XCTAssertThrowsError(try SiteDrafts.include(repo: repo, expected: held))
            XCTAssertEqual(try SiteDrafts.load(repo: repo, slug: "chapter"), held)
            // Recover a promotion interrupted after the source write.
            try held.working.write(to: SiteDrafts.sourceURL(repo: repo, slug: "chapter"))
            try SiteDrafts.include(repo: repo, expected: held)
            XCTAssertNil(try SiteDrafts.load(repo: repo, slug: "chapter"))
        }
    }

    func testUnsentSavedOrCommittedTextCannotBeMadePrivateByHolding() throws {
        try fixture { repo in
            let source = try SiteDrafts.sourceURL(repo: repo, slug: "chapter")
            try bytes("Not yet sent").write(to: source)
            XCTAssertThrowsError(try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter"))
            XCTAssertNil(try SiteDrafts.load(repo: repo, slug: "chapter"))
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Local draft history"], in: repo).status, 0)
            // Even an unchanged different chapter cannot start while the
            // checkout has unuploaded history.
            XCTAssertThrowsError(try SiteDrafts.start(repo: repo, out: "docs", slug: "welcome"))
            XCTAssertTrue(try SiteDrafts.loadAll(repo: repo).isEmpty)
        }
    }

    func testNewChapterAndMissingReceiptDoNotCreateHeldState() throws {
        try fixture { repo in
            _ = try LocalSiteStore.addPage(repo: repo, title: "New", page: SiteFiles.decodePage(bytes("New chapter"))!, under: nil)
            XCTAssertThrowsError(try SiteDrafts.start(repo: repo, out: "docs", slug: "new"))
            try FileManager.default.removeItem(at: SitePublicationState.receiptURL(repo: repo))
            XCTAssertThrowsError(try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter"))
            XCTAssertTrue(try SiteDrafts.loadAll(repo: repo).isEmpty)
        }
    }

    func testOtherChapterUploadCanAdvanceWhileDraftStaysHeld() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            try SiteDrafts.save(bytes("Future chapter"), repo: repo, slug: "chapter")
            try bytes("Welcome update").write(to: SiteDrafts.sourceURL(repo: repo, slug: "welcome"))
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Other chapter"], in: repo).status, 0)
            try SiteDrafts.validateUpload(repo: repo, out: "docs")
            try record(repo)
            try SiteDrafts.validateUpload(repo: repo, out: "docs")
            XCTAssertNotNil(try SiteDrafts.load(repo: repo, slug: "chapter"))
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", "/another.git"], in: repo).status, 0)
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
        }
    }

    func testCommittedThenRevertedHeldSourceIsStillRejected() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let draft = try XCTUnwrap(SiteDrafts.load(repo: repo, slug: "chapter"))
            try bytes("Leaked into local history").write(to: SiteDrafts.sourceURL(repo: repo, slug: "chapter"))
            for args in [["add", "."], ["commit", "-qm", "Mistaken source commit"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            try draft.released.write(to: SiteDrafts.sourceURL(repo: repo, slug: "chapter"))
            for args in [["add", "."], ["commit", "-qm", "Restored source"]] {
                XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
            }
            XCTAssertThrowsError(try SiteDrafts.validateUpload(repo: repo, out: "docs"))
            XCTAssertEqual(try SiteDrafts.load(repo: repo, slug: "chapter"), draft)
        }
    }

    func testCorruptAndEscapingDraftStorageFailsClosed() throws {
        try fixture { repo in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "chapter")
            let path = URL(fileURLWithPath: repo + "/.git/starling-drafts/chapter.json")
            let data = try Data(contentsOf: path)
            try Data("{}".utf8).write(to: path)
            XCTAssertThrowsError(try SiteDrafts.loadAll(repo: repo))
            XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil))
            XCTAssertEqual(SitePublicationState.status(repo: repo), .unknown)
            try FileManager.default.removeItem(at: path)
            let outside = URL(fileURLWithPath: repo).deletingLastPathComponent().appendingPathComponent("draft.json")
            try data.write(to: outside)
            try FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
            XCTAssertThrowsError(try SiteDrafts.loadAll(repo: repo))
            XCTAssertEqual(try Data(contentsOf: outside), data)
        }
    }
}
#endif
