// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SitePublishReviewTests: XCTestCase {
    private func withPublication(_ body: (String) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = try SiteCreation.create(title: "Handbook", parent: parent.path)
        for args in [["config", "user.name", "Review Test"], ["config", "user.email", "review@example.test"],
                     ["remote", "add", "origin", parent.path + "/hosting.git"]] {
            XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
        }
        try body(repo)
    }

    private func read(_ repo: String) throws -> SitePublishReview {
        try SitePublishReview.load(repo: repo, out: "docs", web: nil)
    }

    /// Materialize the public files a previous build sent, without rendering
    /// PDFs or using a network. Record that exact commit as the upload baseline.
    private func recordUpload(_ repo: String) throws {
        let config = try SiteBuilder.readConfig(repo)
        let output = URL(fileURLWithPath: repo + "/docs")
        try FileManager.default.createDirectory(at: output.appendingPathComponent("pages"), withIntermediateDirectories: true)
        try JSONEncoder().encode(SiteBuilder.manifest(from: config)).write(to: output.appendingPathComponent(SiteFiles.manifest))
        for (node, _) in SiteBuilder.manifest(from: config).flattened() {
            try Data(contentsOf: URL(fileURLWithPath: repo + "/" + SiteFiles.pagePath(node.slug)))
                .write(to: output.appendingPathComponent(SiteFiles.pagePath(node.slug)))
        }
        XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
        XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Sent publication"], in: repo).status, 0)
        try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                        destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
    }

    private func addPage(_ slug: String, repo: String) throws {
        try Data(contentsOf: URL(fileURLWithPath: repo + "/pages/welcome.json"))
            .write(to: URL(fileURLWithPath: repo + "/pages/" + slug + ".json"))
    }

    func testFirstReviewIncludesAllPagesWithoutClaimingTheyAreNewOrMutatingFiles() throws {
        try withPublication { repo in
            var config = try SiteBuilder.readConfig(repo)
            config.base = "/handbook/"
            config.pages[0].children = [SiteNode(slug: "chapter", title: "Chapter")]
            try addPage("chapter", repo: repo)
            try SiteBuilder.writeConfig(config, to: repo)
            let before = LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output
            let review = try read(repo)
            XCTAssertFalse(review.compared)
            XCTAssertTrue(review.pages.allSatisfy { $0.comparison == nil })
            XCTAssertEqual(review.pages.map(\.change), [.included, .included])
            XCTAssertEqual(review.pages.map(\.route), ["/handbook/", "/handbook/chapter/"])
            XCTAssertEqual(review.pages.map(\.depth), [0, 1])
            XCTAssertTrue(review.pages[0].isHome)
            XCTAssertTrue(review.removed.isEmpty)
            XCTAssertEqual(before, LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output)
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/docs"))
            XCTAssertFalse(FileManager.default.fileExists(atPath: try SitePublicationState.receiptURL(repo: repo).path))
        }
    }

    func testAddedEditedRemovedAndUnchangedPagesUseSentVersionNotLocalHead() throws {
        try withPublication { repo in
            var config = try SiteBuilder.readConfig(repo)
            for slug in ["removed", "kept"] {
                try addPage(slug, repo: repo)
                config.pages.append(SiteNode(slug: slug, title: slug))
            }
            try SiteBuilder.writeConfig(config, to: repo)
            try recordUpload(repo)
            XCTAssertEqual(try read(repo).pages.map(\.change), [.unchanged, .unchanged, .unchanged])
            // Change document bytes, remove a configured page and add a new one.
            try Data("{}".utf8).write(to: URL(fileURLWithPath: repo + "/pages/welcome.json"))
            config.pages.remove(at: 1)
            try addPage("new", repo: repo)
            config.pages.append(SiteNode(slug: "new", title: "New chapter"))
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Not uploaded"], in: repo).status, 0)
            let review = try read(repo)
            XCTAssertTrue(review.compared)
            XCTAssertEqual(review.pages.map(\.change), [.updated, .unchanged, .added])
            XCTAssertEqual(review.removed.map(\.title), ["removed"])
            XCTAssertEqual(review.removed.map(\.route), ["/removed/"])
            XCTAssertTrue(review.summary.contains("1 added, 1 updated, 1 removed"))
            // The old generated output remains unchanged; the review uses saved source.
            XCTAssertNotEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/docs/pages/welcome.json")), Data("{}".utf8))
        }
    }

    func testReorderingHomeAndChangingBaseExposesPreviousRoutes() throws {
        try withPublication { repo in
            var config = try SiteBuilder.readConfig(repo)
            try addPage("chapter", repo: repo)
            config.pages.append(SiteNode(slug: "chapter", title: "Chapter"))
            try SiteBuilder.writeConfig(config, to: repo)
            try recordUpload(repo)
            config.pages.reverse()
            config.home = "chapter"
            try SiteBuilder.writeConfig(config, to: repo)
            let moved = try read(repo)
            XCTAssertEqual(moved.pages.map(\.route), ["/", "/welcome/"])
            XCTAssertEqual(moved.pages.map(\.previousRoute), ["/chapter/", "/"])
            XCTAssertEqual(moved.pages.map(\.change), [.updated, .updated])
            XCTAssertTrue(moved.settingsChanged)
            config.base = "/manual/"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertEqual(try read(repo).pages.map(\.route), ["/manual/", "/manual/welcome/"])
        }
    }

    func testTitleEditIsVisibleEvenWhenDocumentBytesAreUnchanged() throws {
        try withPublication { repo in
            try recordUpload(repo)
            var config = try SiteBuilder.readConfig(repo)
            config.pages[0].title = "Reader handbook"
            try SiteBuilder.writeConfig(config, to: repo)
            let review = try read(repo)
            XCTAssertEqual(review.pages[0].change, .updated)
            XCTAssertNil(review.pages[0].previousRoute)
            XCTAssertTrue(review.settingsChanged)
            XCTAssertTrue(try XCTUnwrap(review.pages[0].comparison).passages.isEmpty)
        }
    }

    func testRenamingAnEmptyLegacyPageDoesNotInventParagraphEdits() throws {
        try withPublication { repo in
            try Data("{}".utf8).write(to: URL(fileURLWithPath: repo + "/pages/welcome.json"))
            try recordUpload(repo)
            var config = try SiteBuilder.readConfig(repo)
            config.pages[0].title = "Renamed empty chapter"
            try SiteBuilder.writeConfig(config, to: repo)
            let comparison = try XCTUnwrap(read(repo).pages[0].comparison)
            XCTAssertTrue(comparison.passages.isEmpty)
            XCTAssertNotEqual(comparison.previousTitle, comparison.currentTitle)
        }
    }

    func testReferenceGuidanceUsesSavedContentAndClearsWhenTheAuthorFixesIt() throws {
        try withPublication { repo in
            let path = URL(fileURLWithPath: repo + "/pages/welcome.json")
            var style = CharStyle.plain; style.link = "appendix.docx"
            var document = RichDocument(paragraphs: [RichParagraph(text: "Read the appendix", charStyle: style)])
            try RichDocumentEnvelope.encode(document).write(to: path)
            try recordUpload(repo)
            let before = try Data(contentsOf: path)
            let status = LocalSiteStore.git(["status", "--porcelain=v1"], in: repo).output
            let review = try read(repo)
            XCTAssertEqual(review.referenceCount, 1)
            XCTAssertEqual(review.pages[0].change, .unchanged)
            XCTAssertEqual(review.pages[0].references[0].target, "appendix.docx")
            XCTAssertEqual(try Data(contentsOf: path), before)
            XCTAssertEqual(LocalSiteStore.git(["status", "--porcelain=v1"], in: repo).output, status)
            document.paragraphs[0].runs[0].style.link = "https://example.org/appendix/"
            try RichDocumentEnvelope.encode(document).write(to: path)
            let fixed = try read(repo)
            XCTAssertEqual(fixed.referenceCount, 0)
            XCTAssertEqual(fixed.pages[0].change, .updated)
        }
    }

    func testChangedDestinationAndCorruptBaselineDoNotInventAComparison() throws {
        try withPublication { repo in
            try recordUpload(repo)
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", "/different.git"], in: repo).status, 0)
            XCTAssertFalse(try read(repo).compared)
            // A malformed public manifest in an otherwise matching receipt.
            let config = try SiteBuilder.readConfig(repo)
            let invalid = SiteManifest(title: config.title, base: "/", home: "welcome", pages: [config.pages[0], config.pages[0]])
            try JSONEncoder().encode(invalid).write(to: URL(fileURLWithPath: repo + "/docs/manifest.json"))
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Malformed old manifest"], in: repo).status, 0)
            try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                            destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
            XCTAssertFalse(try read(repo).compared)
            XCTAssertEqual(try read(repo).pages[0].change, .included)
        }
    }

    func testMissingOldPublicPageMakesBaselineUnknown() throws {
        try withPublication { repo in
            try recordUpload(repo)
            XCTAssertEqual(LocalSiteStore.git(["rm", "docs/pages/welcome.json"], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Incomplete old build"], in: repo).status, 0)
            try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                            destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
            XCTAssertFalse(try read(repo).compared)
        }
    }

    func testComparisonUsesUploadedArtifactAndRetainsReviewSnapshotAfterLaterEdits() throws {
        try withPublication { repo in
            let source = URL(fileURLWithPath: repo + "/pages/welcome.json")
            var paragraph = RichParagraph(text: "Readers received this.")
            paragraph.id = 123
            let uploaded = RichDocument(paragraphs: [paragraph])
            try RichDocumentEnvelope.encode(uploaded).write(to: source)
            try recordUpload(repo)
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: repo))
            // A later local commit and build must not replace the sent baseline.
            paragraph = RichParagraph(text: "Saved revision."); paragraph.id = 123
            let draft = try RichDocumentEnvelope.encode(RichDocument(paragraphs: [paragraph]))
            try draft.write(to: source)
            try draft.write(to: URL(fileURLWithPath: repo + "/docs/pages/welcome.json"))
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Unsent local rebuild"], in: repo).status, 0)
            let beforeStatus = LocalSiteStore.git(["status", "--porcelain=v1"], in: repo).output
            let review = try read(repo)
            let comparison = try XCTUnwrap(review.pages[0].comparison)
            XCTAssertEqual(comparison.passages.count, 1)
            XCTAssertEqual(comparison.passages[0].before, "Readers received this.")
            XCTAssertEqual(comparison.passages[0].after, "Saved revision.")
            XCTAssertEqual(comparison.passages[0].paragraphID, 123)
            XCTAssertEqual(try Data(contentsOf: source), draft)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: repo)), receipt)
            XCTAssertEqual(LocalSiteStore.git(["status", "--porcelain=v1"], in: repo).output, beforeStatus)
            paragraph = RichParagraph(text: "A still newer draft."); paragraph.id = 123
            try RichDocumentEnvelope.encode(RichDocument(paragraphs: [paragraph])).write(to: source)
            XCTAssertEqual(comparison.passages[0].after, "Saved revision.")
            XCTAssertEqual(try read(repo).pages[0].comparison?.passages[0].after, "A still newer draft.")
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", "/another.git"], in: repo).status, 0)
            XCTAssertNil(try read(repo).pages[0].comparison)
        }
    }

    func testRemovedTextRemainsReviewableAfterSourceAndLocalOutputAreDeleted() throws {
        try withPublication { repo in
            var config = try SiteBuilder.readConfig(repo)
            let path = URL(fileURLWithPath: repo + "/pages/chapter.json")
            try RichDocumentEnvelope.encode(RichDocument(paragraphs: [RichParagraph(text: "Old chapter ending")])).write(to: path)
            config.pages.append(SiteNode(slug: "chapter", title: "Chapter"))
            try SiteBuilder.writeConfig(config, to: repo)
            try recordUpload(repo)
            config.pages.removeLast()
            try SiteBuilder.writeConfig(config, to: repo)
            try FileManager.default.removeItem(at: path)
            try FileManager.default.removeItem(atPath: repo + "/docs/pages/chapter.json")
            let removed = try XCTUnwrap(read(repo).removed.first)
            XCTAssertEqual(removed.comparison.passages.map(\.before), ["Old chapter ending"])
            XCTAssertEqual(removed.comparison.passages.map(\.kind), [.removed])
            XCTAssertNil(removed.comparison.currentTitle)
        }
    }

    func testInvalidMissingDuplicateAndEscapingSourcesCannotLookReady() throws {
        try withPublication { repo in
            let original = try SiteBuilder.readConfig(repo)
            var config = original
            for slug in ["../outside", "pages"] {
                config.pages = [SiteNode(slug: slug, title: "Invalid")]
                try SiteBuilder.writeConfig(config, to: repo)
                XCTAssertThrowsError(try read(repo))
            }
            config.pages = [original.pages[0], original.pages[0]]
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try read(repo))
            try SiteBuilder.writeConfig(original, to: repo)
            let path = repo + "/pages/welcome.json"
            try FileManager.default.removeItem(atPath: path)
            XCTAssertThrowsError(try read(repo))
            let outside = URL(fileURLWithPath: repo).deletingLastPathComponent().appendingPathComponent("outside.json")
            try Data("{}".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: outside.path)
            XCTAssertThrowsError(try read(repo))
        }
    }
}
#endif
