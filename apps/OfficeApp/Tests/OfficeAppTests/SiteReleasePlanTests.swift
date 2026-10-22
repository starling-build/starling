// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SiteReleasePlanTests: XCTestCase {
    private func fixture(_ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try SiteCreation.create(title: "Serial", parent: root.path)
        for args in [["config", "user.name", "Plan Test"], ["config", "user.email", "plan@example.test"],
                     ["remote", "add", "origin", root.path + "/hosting.git"]] {
            XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
        }
        try body(repo)
    }

    private func newDraft(_ repo: String) throws -> String {
        try SiteUnpublishedDrafts.create(repo: repo, title: "Secret ending",
            page: SitePage(document: RichDocument(paragraphs: [RichParagraph(text: "Private final scene")]), pageSetup: nil))
    }

    private func review(_ repo: String) throws -> SitePublishReview {
        try SitePublishReview.load(repo: repo, out: "docs", web: nil)
    }

    private func entries(_ repo: String) throws -> [SiteReleasePlan.Entry] {
        try SiteReleasePlan.entries(review: review(repo), plan: SiteReleasePlan.load(repo: repo))
    }

    @discardableResult
    private func recordUpload(_ repo: String) throws -> String {
        let manifest = SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo))
        let output = URL(fileURLWithPath: repo + "/docs")
        try FileManager.default.createDirectory(at: output.appendingPathComponent("pages"), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: output.appendingPathComponent(SiteFiles.manifest))
        for (node, _) in manifest.flattened() {
            try Data(contentsOf: SiteDrafts.sourceURL(repo: repo, slug: node.slug))
                .write(to: output.appendingPathComponent(SiteFiles.pagePath(node.slug)))
        }
        XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
        XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Upload snapshot"], in: repo).status, 0)
        let revision = LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace()
        try SitePublicationState.record(repo: repo, revision: revision, destination: SitePublicationState.destination(repo: repo),
                                        target: "refs/heads/main", out: "docs")
        return revision
    }

    func testCalendarValidationIsStrictAndIndependentOfTimeZones() {
        for value in ["2028-02-29", "2000-02-29", "2026-10-21", "0001-01-01", "9999-12-31"] {
            XCTAssertTrue(SiteReleasePlan.validDate(value), value)
        }
        for value in ["", "2026-02-29", "1900-02-29", "2026-04-31", "0000-01-01", "2026-00-10", "2026-13-01",
                      "2026-01-00", "2026-01-32", "2026-1-01", " 2026-01-01", "２０２６-01-01", "2026-01-01T10:00Z"] {
            XCTAssertFalse(SiteReleasePlan.validDate(value), value)
        }
    }

    func testWritingReserveSeparatesUnpublishedSetAsideAndIncludedDocuments() throws {
        try fixture { repo in
            let unpublished = try newDraft(repo) // Three saved words.
            let empty = try SiteUnpublishedDrafts.create(repo: repo, title: "Untitled scene",
                page: SitePage(document: RichDocument(), pageSetup: nil))
            let parked = try SiteUnpublishedDrafts.create(repo: repo, title: "Alternate scene",
                page: SitePage(document: RichDocument(paragraphs: [RichParagraph(text: "Another ending")]), pageSetup: nil))
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: parked)))
            let before = LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output
            let snapshot = try review(repo)
            let progress = SiteWritingProgress(review: snapshot)
            XCTAssertEqual(progress.unpublished, .init(documents: 2, words: 3))
            XCTAssertEqual(progress.held, .init(documents: 0, words: 0))
            XCTAssertEqual(progress.setAside, .init(documents: 1, words: 2))
            XCTAssertEqual(progress.included, .init(documents: 1, words: 0))
            XCTAssertEqual(snapshot.wordCounts[unpublished], .init(saved: 3, included: nil, uploaded: nil))
            XCTAssertEqual(snapshot.wordCounts[empty]?.saved, 0)
            XCTAssertNil(snapshot.wordCounts["welcome"]?.uploaded) // Unknown is not an empty upload.
            let plan = try SiteReleasePlan.load(repo: repo)
            XCTAssertEqual(SiteReleasePlan.entries(review: snapshot, plan: plan).first { $0.slug == parked }?.words?.saved, 2)
            XCTAssertEqual(before, LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output)

            try SiteUnpublishedDrafts.include(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: unpublished)))
            let included = SiteWritingProgress(review: try review(repo))
            XCTAssertEqual(included.unpublished, .init(documents: 1, words: 0))
            XCTAssertEqual(included.included, .init(documents: 2, words: 3))
            XCTAssertEqual(SiteWritingProgress(review: snapshot).unpublished, progress.unpublished)
        }
    }

    func testHeldRevisionCountsStaySeparateFromIncludedAndUploadedWords() throws {
        try fixture { repo in
            func content(_ text: String) throws -> Data {
                try RichDocumentEnvelope.encode(RichDocument(paragraphs: [RichParagraph(text: text)]))
            }
            try content("Original chapter").write(to: SiteDrafts.sourceURL(repo: repo, slug: "welcome"))
            try recordUpload(repo)
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: repo))
            try SiteDrafts.start(repo: repo, out: "docs", slug: "welcome")
            try SiteDrafts.save(content("Original chapter with a correction"), repo: repo, slug: "welcome")
            let snapshot = try review(repo)
            XCTAssertEqual(snapshot.wordCounts["welcome"], .init(saved: 5, included: 2, uploaded: 2))
            let progress = SiteWritingProgress(review: snapshot)
            XCTAssertEqual(progress.held, .init(documents: 1, words: 5))
            XCTAssertEqual(progress.included, .init(documents: 1, words: 2))
            XCTAssertEqual(progress.unpublished.documents, 0)
            // Saving again does not change the already displayed snapshot.
            try SiteDrafts.save(content("A shorter correction"), repo: repo, slug: "welcome")
            XCTAssertEqual(snapshot.wordCounts["welcome"]?.saved, 5)
            XCTAssertEqual(try review(repo).wordCounts["welcome"]?.saved, 3)
            try SiteDrafts.include(repo: repo, expected: XCTUnwrap(SiteDrafts.load(repo: repo, slug: "welcome")))
            let refreshed = try review(repo)
            XCTAssertEqual(refreshed.wordCounts["welcome"], .init(saved: 3, included: 3, uploaded: 2))
            XCTAssertEqual(SiteWritingProgress(review: refreshed).held.documents, 0)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: repo)), receipt)
        }
    }

    func testWordCountsUseRecordedUploadIncludingRemovedPagesAndUnknownEvidence() throws {
        try fixture { repo in
            let slug = try newDraft(repo)
            try SiteUnpublishedDrafts.include(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            try recordUpload(repo)
            try RichDocumentEnvelope.encode(RichDocument(paragraphs: [RichParagraph(text: "Revised final scene with more detail")]))
                .write(to: SiteDrafts.sourceURL(repo: repo, slug: slug))
            XCTAssertEqual(LocalSiteStore.git(["add", "."], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Not uploaded"], in: repo).status, 0)
            XCTAssertEqual(try review(repo).wordCounts[slug], .init(saved: 6, included: 6, uploaded: 3))
            var config = try SiteBuilder.readConfig(repo)
            config.pages.removeAll { $0.slug == slug }
            try SiteBuilder.writeConfig(config, to: repo)
            let removed = try review(repo)
            XCTAssertEqual(removed.wordCounts[slug], .init(saved: nil, included: nil, uploaded: 3))
            XCTAssertEqual(SiteWritingProgress(review: removed).included, .init(documents: 1, words: 0))
            let plan = try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-11-01", expected: SiteReleasePlan.load(repo: repo))
            XCTAssertEqual(SiteReleasePlan.entries(review: removed, plan: plan).first { $0.slug == slug }?.words?.uploaded, 3)
            try FileManager.default.removeItem(at: SitePublicationState.receiptURL(repo: repo))
            let unknown = try review(repo)
            XCTAssertNil(unknown.wordCounts[slug])
            XCTAssertNil(unknown.wordCounts["welcome"]?.uploaded)
        }
    }

    func testChapterCountsUseWriterCountingRulesAndIgnoreNavigationTitles() throws {
        try fixture { repo in
            let document = RichDocument(paragraphs: [
                RichParagraph(text: "one\ttwo\nthree"), RichParagraph(text: "你好 世界"), RichParagraph(text: "")
            ])
            XCTAssertEqual(document.wordCount, 7)
            try RichDocumentEnvelope.encode(document).write(to: SiteDrafts.sourceURL(repo: repo, slug: "welcome"))
            var config = try SiteBuilder.readConfig(repo)
            config.pages[0].title = "A long navigation title that is not manuscript text"
            try SiteBuilder.writeConfig(config, to: repo)
            try recordUpload(repo)
            XCTAssertEqual(try review(repo).wordCounts["welcome"], .init(saved: 7, included: 7, uploaded: 7))
            XCTAssertEqual(SiteWritingProgress(review: try review(repo)).included.words, document.wordCount)
        }
    }

    func testDatesAreLocalAndDoNotChangeReleaseFilesOrUploadEvidence() throws {
        try fixture { repo in
            let revision = try recordUpload(repo)
            let slug = try newDraft(repo)
            let paths = ["site.json", "pages/welcome.json", "docs/manifest.json", "docs/pages/welcome.json"]
            let before = try paths.map { try Data(contentsOf: URL(fileURLWithPath: repo + "/" + $0)) }
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: repo))
            let draft = try SiteUnpublishedDrafts.load(repo: repo, slug: slug)
            let empty = try SiteReleasePlan.load(repo: repo)
            XCTAssertNil(empty.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try SiteReleasePlan.storageURL(repo: repo).path))
            let saved = try SiteReleasePlan.save(repo: repo, slug: slug, date: "2099-12-31", expected: empty)
            XCTAssertEqual(try SiteReleasePlan.load(repo: repo), saved)
            XCTAssertEqual(try paths.map { try Data(contentsOf: URL(fileURLWithPath: repo + "/" + $0)) }, before)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: repo)), receipt)
            XCTAssertEqual(try SiteUnpublishedDrafts.load(repo: repo, slug: slug), draft)
            XCTAssertEqual(LocalSiteStore.git(["status", "--porcelain=v1", "--untracked-files=all"], in: repo).output, "")
            XCTAssertEqual(LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(), revision)
            XCTAssertEqual(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil).count, 1)
            XCTAssertNil(try entries(repo).first { $0.slug == slug }?.uploadedRevision)
        }
    }

    func testStalePlanCannotOverwriteAnotherWindowIncludingClearAndReadd() throws {
        try fixture { repo in
            let old = try SiteReleasePlan.load(repo: repo)
            let first = try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-11-01", expected: old)
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-11-02", expected: old))
            let cleared = try SiteReleasePlan.save(repo: repo, slug: "welcome", date: nil, expected: first)
            XCTAssertTrue(cleared.dates.isEmpty)
            XCTAssertNotEqual(cleared.id, old.id)
            let sameDate = try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-11-01", expected: cleared)
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: nil, expected: first))
            XCTAssertEqual(try SiteReleasePlan.load(repo: repo), sameDate)
        }
    }

    func testDateSurvivesRenameSetAsideRestoreAndInclusionWithoutScheduling() throws {
        try fixture { repo in
            let slug = try newDraft(repo)
            let saved = try SiteReleasePlan.save(repo: repo, slug: slug, date: "2099-12-31", expected: SiteReleasePlan.load(repo: repo))
            try SiteUnpublishedDrafts.rename(repo: repo, slug: slug, title: "Revised ending")
            try SiteUnpublishedDrafts.setAside(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            var entry = try XCTUnwrap(entries(repo).first { $0.slug == slug })
            XCTAssertEqual(entry.title, "Revised ending")
            XCTAssertEqual(entry.date, "2099-12-31")
            XCTAssertFalse(entry.canPreview)
            XCTAssertTrue(entry.nextPublication.contains("set aside"))
            try SiteUnpublishedDrafts.restore(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            try SiteUnpublishedDrafts.include(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            entry = try XCTUnwrap(entries(repo).first { $0.slug == slug })
            XCTAssertTrue(entry.canPreview)
            XCTAssertTrue(entry.nextPublication.hasPrefix("Included"))
            XCTAssertEqual(try SiteReleasePlan.load(repo: repo), saved)
            XCTAssertEqual(try SiteBuilder.validatedSources(repo: repo, config: SiteBuilder.readConfig(repo), web: nil).count, 2)
            let revision = try recordUpload(repo)
            XCTAssertEqual(try entries(repo).first { $0.slug == slug }?.uploadedRevision, revision)
            XCTAssertEqual(try SiteReleasePlan.load(repo: repo), saved) // Upload does not erase intent.
        }
    }

    func testOverviewUsesMatchingUploadNotLocalHeadAndDistinguishesHeldDrafts() throws {
        try fixture { repo in
            let revision = try recordUpload(repo)
            try SiteDrafts.start(repo: repo, out: "docs", slug: "welcome")
            let slug = try newDraft(repo)
            var all = try entries(repo)
            XCTAssertEqual(all.first { $0.slug == "welcome" }?.uploadedRevision, revision)
            XCTAssertTrue(try XCTUnwrap(all.first { $0.slug == "welcome" }).nextPublication.contains("next draft stays local"))
            XCTAssertNil(all.first { $0.slug == slug }?.uploadedRevision)
            // An unrelated local commit cannot become upload evidence.
            try Data("note".utf8).write(to: URL(fileURLWithPath: repo + "/note.txt"))
            XCTAssertEqual(LocalSiteStore.git(["add", "note.txt"], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["commit", "-qm", "Only local"], in: repo).status, 0)
            XCTAssertEqual(try review(repo).uploadedRevision, revision)
            // A changed hosting destination invalidates the receipt. Clear the
            // held draft first because its release guard correctly blocks review.
            try SiteDrafts.include(repo: repo, expected: XCTUnwrap(SiteDrafts.load(repo: repo, slug: "welcome")))
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", repo + "/elsewhere.git"], in: repo).status, 0)
            all = try entries(repo)
            XCTAssertTrue(all.allSatisfy { $0.uploadedRevision == nil })
            XCTAssertFalse(try review(repo).compared)
        }
    }

    func testDatesSortAndRemovedOrMissingChaptersKeepClearablePlans() throws {
        try fixture { repo in
            let slug = try newDraft(repo)
            try SiteUnpublishedDrafts.include(repo: repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: repo, slug: slug)))
            let revision = try recordUpload(repo)
            var plan = try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-12-01", expected: SiteReleasePlan.load(repo: repo))
            plan = try SiteReleasePlan.save(repo: repo, slug: slug, date: "2026-11-01", expected: plan)
            XCTAssertEqual(try entries(repo).map(\.slug), [slug, "welcome"])
            var config = try SiteBuilder.readConfig(repo)
            config.pages.removeAll { $0.slug == slug }
            try SiteBuilder.writeConfig(config, to: repo)
            var missing = try XCTUnwrap(entries(repo).first { $0.slug == slug })
            XCTAssertEqual(missing.uploadedRevision, revision)
            XCTAssertFalse(missing.canPlan)
            XCTAssertTrue(missing.nextPublication.hasPrefix("Removed"))
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: slug, date: "2026-12-02", expected: plan))
            // Losing the receipt does not silently lose the old plan.
            try FileManager.default.removeItem(at: SitePublicationState.receiptURL(repo: repo))
            missing = try XCTUnwrap(entries(repo).first { $0.slug == slug })
            XCTAssertFalse(missing.canPlan)
            XCTAssertNil(missing.uploadedRevision)
            XCTAssertTrue(missing.nextPublication.hasPrefix("Chapter unavailable"))
            plan = try SiteReleasePlan.save(repo: repo, slug: slug, date: nil, expected: plan)
            XCTAssertNil(plan.dates[slug])
            XCTAssertEqual(try entries(repo).map(\.slug), ["welcome"])
        }
    }

    func testCorruptUnsupportedAndInvalidRecordsArePreserved() throws {
        try fixture { repo in
            let old = try SiteReleasePlan.load(repo: repo)
            let file = try SiteReleasePlan.storageURL(repo: repo)
            let invalid: [Data] = [Data("not json".utf8)] + (try [
                ["version": 2, "id": UUID().uuidString, "dates": ["welcome": "2026-01-01"]],
                ["version": 1, "id": UUID().uuidString, "dates": ["welcome": "2026-02-30"]],
                ["version": 1, "id": UUID().uuidString, "dates": ["../outside": "2026-01-01"]],
            ].map { try JSONSerialization.data(withJSONObject: $0) })
            for data in invalid {
                try data.write(to: file)
                XCTAssertThrowsError(try SiteReleasePlan.load(repo: repo))
                XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: nil, expected: old))
                XCTAssertEqual(try Data(contentsOf: file), data)
                // A broken reminder cannot block reviewing or publishing writing.
                XCTAssertEqual(try review(repo).pages.count, 1)
            }
        }
    }

    func testSymlinkAndInvalidDateCannotWriteOutsideLocalPlan() throws {
        try fixture { repo in
            let empty = try SiteReleasePlan.load(repo: repo)
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-02-30", expected: empty))
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "missing", date: "2026-01-01", expected: empty))
            let file = try SiteReleasePlan.storageURL(repo: repo)
            let target = URL(fileURLWithPath: repo + "/private-plan.json")
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
            XCTAssertThrowsError(try SiteReleasePlan.load(repo: repo))
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-01-01", expected: empty))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            try Data("unchanged".utf8).write(to: target)
            XCTAssertThrowsError(try SiteReleasePlan.load(repo: repo))
            XCTAssertThrowsError(try SiteReleasePlan.save(repo: repo, slug: "welcome", date: "2026-01-01", expected: empty))
            XCTAssertEqual(try Data(contentsOf: target), Data("unchanged".utf8))
        }
    }
}
#endif
