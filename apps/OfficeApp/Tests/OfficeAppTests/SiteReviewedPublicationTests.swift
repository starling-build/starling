// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

#if !os(WASI)
final class SiteReviewedPublicationTests: XCTestCase {
    private struct Fixture {
        let repo: String
        let web: String
        let remote: String
        var source: URL { URL(fileURLWithPath: repo + "/pages/welcome.json") }
        func review() throws -> SiteReviewedPublication {
            try SitePublishReview.load(repo: repo, out: "docs", web: web).reviewedPublication
        }
        func publish(_ review: SiteReviewedPublication? = nil, progress: ((SitePublishStage) -> Void)? = nil) -> SitePublishResult {
            LocalSiteStore.publishNow(repo: repo, out: "docs", web: web, message: "Release",
                control: SitePublishControl(reviewedPublication: review), progress: progress)
        }
        func changeText(_ text: String) throws {
            var page = try XCTUnwrap(SiteFiles.decodePage(Data(contentsOf: source)))
            page.document.paragraphs[0] = RichParagraph(text: text)
            try RichDocumentEnvelope.encode(page.document, pageSetup: page.pageSetup).write(to: source)
        }
        func remoteHead() -> String { LocalSiteStore.git(["rev-parse", "--verify", "refs/heads/main"], in: remote).output }
    }

    private func fixture(_ body: @escaping (Fixture) throws -> Void) throws {
        // Real layout/export needs the same stack allowance as the publisher.
        let finished = expectation(description: "Publication worker")
        var failure: Error?
        let worker = Thread {
            do {
                initializeHeadlessText()
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let repo = try SiteCreation.create(title: "Serial", parent: root.path)
                let web = root.appendingPathComponent("web")
                try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
                try Data("<html><head></head><body></body></html>".utf8).write(to: web.appendingPathComponent("index.html"))
                try Data([0, 97, 115, 109]).write(to: web.appendingPathComponent("app.wasm"))
                let remote = root.appendingPathComponent("remote.git").path
                XCTAssertEqual(LocalSiteStore.git(["init", "--bare", remote], in: root.path).status, 0)
                for args in [["config", "user.name", "Review Test"], ["config", "user.email", "review@example.test"],
                             ["remote", "add", "origin", remote]] {
                    XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
                }
                let fixture = Fixture(repo: repo, web: web.path, remote: remote)
                try fixture.changeText("Reviewed chapter")
                try body(fixture)
            } catch { failure = error }
            finished.fulfill()
        }
        worker.stackSize = 8 * 1024 * 1024
        worker.start()
        wait(for: [finished], timeout: 120)
        if let failure { throw failure }
    }

    func testReviewRejectsChangedSourcesTitlesUnlistedFilesAndRemovals() throws {
        try fixture { f in
            let review = try f.review(), original = try Data(contentsOf: f.source)
            try f.changeText("Saved in another window")
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: f.web))
            try original.write(to: f.source)
            var config = try SiteBuilder.readConfig(f.repo)
            config.pages[0].title = "Another title"
            try SiteBuilder.writeConfig(config, to: f.repo)
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: f.web))
            let current = try f.review()
            let unlisted = URL(fileURLWithPath: f.repo + "/pages/unlisted.bin")
            try Data([0, 255, 128, 10]).write(to: unlisted)
            XCTAssertThrowsError(try current.validate(repo: f.repo, out: "docs", web: f.web))
            let withExtra = try f.review()
            XCTAssertEqual(LocalSiteStore.git(["add", "site.json", "pages"], in: f.repo).status, 0)
            let tree = LocalSiteStore.git(["write-tree"], in: f.repo).output.trimmingWhitespace()
            XCTAssertNoThrow(try withExtra.input.validateTree(repo: f.repo, tree: tree))
            try FileManager.default.removeItem(at: unlisted)
            XCTAssertThrowsError(try withExtra.validate(repo: f.repo, out: "docs", web: f.web))
        }
    }

    func testPrivateWritingAndDatesDoNotInvalidateReviewButInclusionDoes() throws {
        try fixture { f in
            let review = try f.review()
            let page = try XCTUnwrap(SiteFiles.decodePage(Data(contentsOf: f.source)))
            let slug = try SiteUnpublishedDrafts.create(repo: f.repo, title: "Private chapter", page: page)
            try SiteUnpublishedDrafts.rename(repo: f.repo, slug: slug, title: "Private new title")
            try SiteReleasePlan.save(repo: f.repo, slug: slug, date: "2026-12-01", expected: SiteReleasePlan.load(repo: f.repo))
            XCTAssertNoThrow(try review.validate(repo: f.repo, out: "docs", web: f.web))
            try SiteUnpublishedDrafts.include(repo: f.repo, expected: XCTUnwrap(SiteUnpublishedDrafts.load(repo: f.repo, slug: slug)))
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: f.web))
        }
    }

    func testIgnoredUntrackedFilesDoNotBlockPublicationButTrackedFilesRemainReviewed() throws {
        try fixture { f in
            let excluded = URL(fileURLWithPath: f.repo + "/.git/info/exclude")
            try Data("*.scratch\n".utf8).write(to: excluded)
            let review = try f.review()
            let ignored = URL(fileURLWithPath: f.repo + "/pages/private.scratch")
            try Data("Private scratch notes".utf8).write(to: ignored)
            XCTAssertNoThrow(try review.validate(repo: f.repo, out: "docs", web: f.web))
            XCTAssertNil(f.publish(review).issue)
            XCTAssertNotEqual(LocalSiteStore.git(["cat-file", "-e", "HEAD:pages/private.scratch"], in: f.repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["add", "-f", "pages/private.scratch"], in: f.repo).status, 0)
            let tracked = try f.review()
            XCTAssertEqual(tracked.input.files["pages/private.scratch"], try Data(contentsOf: ignored))
            try Data("Changed tracked source".utf8).write(to: ignored)
            XCTAssertThrowsError(try tracked.validate(repo: f.repo, out: "docs", web: f.web))
        }
    }

    func testChangedDestinationTargetOutputAndHistoryRequireReview() throws {
        try fixture { f in
            let review = try f.review()
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "other", web: f.web))
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: nil))
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", f.remote + "-different"], in: f.repo).status, 0)
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: f.web))
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", f.remote], in: f.repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["config", "branch.main.remote", "origin"], in: f.repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["config", "branch.main.merge", "refs/heads/other"], in: f.repo).status, 0)
            XCTAssertThrowsError(try review.validate(repo: f.repo, out: "docs", web: f.web))
            let current = try f.review()
            XCTAssertEqual(LocalSiteStore.git(["commit", "--allow-empty", "-qm", "Unrelated local history"], in: f.repo).status, 0)
            XCTAssertThrowsError(try current.validate(repo: f.repo, out: "docs", web: f.web))
        }
    }

    func testStaleReviewStopsBeforeBuildAndFreshReviewPublishes() throws {
        try fixture { f in
            XCTAssertNil(try f.publish(f.review()).issue)
            let review = try f.review()
            let receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo))
            let output = try Data(contentsOf: URL(fileURLWithPath: f.repo + "/docs/pages/welcome.json"))
            let head = f.remoteHead()
            try f.changeText("Later saved revision")
            var stages: [SitePublishStage] = []
            let failed = f.publish(review) { stages.append($0) }
            XCTAssertEqual(failed.issue?.kind, .review)
            XCTAssertEqual(stages.count, 1)
            XCTAssertEqual(f.remoteHead(), head)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo)), receipt)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: f.repo + "/docs/pages/welcome.json")), output)
            XCTAssertNil(try f.publish(f.review()).issue)
            XCTAssertNotEqual(f.remoteHead(), head)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: f.repo + "/docs/pages/welcome.json")), try Data(contentsOf: f.source))
        }
    }

    func testBuildUsesCapturedDocumentsEvenIfSourceIsSavedLater() throws {
        try fixture { f in
            let input = try f.review().input
            try f.changeText("Unreviewed save")
            _ = try SiteBuilder.build(repo: f.repo, out: f.repo + "/docs", web: f.web, base: nil, snapshot: input)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: f.repo + "/docs/pages/welcome.json")), input.files["pages/welcome.json"])
            let html = try String(contentsOfFile: f.repo + "/docs/index.html", encoding: .utf8)
            XCTAssertTrue(html.contains("Reviewed chapter"))
            XCTAssertFalse(html.contains("Unreviewed save"))
            let word = try OfficeFormats.read(f.repo + "/docs/welcome/welcome.docx")
            XCTAssertEqual(word.document.paragraphs[0].text, "Reviewed chapter")
            XCTAssertTrue(try String(contentsOfFile: f.source.path, encoding: .utf8).contains("Unreviewed save"))
        }
    }

    func testEditsDuringBuildOrBeforeUploadKeepRemoteAndReceiptUnchanged() throws {
        try fixture { f in
            XCTAssertNil(try f.publish(f.review()).issue)
            for stage in [SitePublishStage.saving, .uploading] {
                let review = try f.review()
                let head = f.remoteHead(), receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo))
                var changed = false
                let result = f.publish(review) { current in
                    if current == stage {
                        do { try f.changeText(UUID().uuidString); changed = true }
                        catch { XCTFail("Could not inject save: \(error)") }
                    }
                }
                XCTAssertTrue(changed)
                XCTAssertEqual(result.issue?.kind, .review)
                XCTAssertEqual(f.remoteHead(), head)
                XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo)), receipt)
            }
        }
    }

    func testDestinationChangeBeforeUploadDoesNotSendOrRecord() throws {
        try fixture { f in
            let review = try f.review()
            var changed = false
            let result = f.publish(review) { stage in
                if stage == .uploading {
                    XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", f.remote + "-different"], in: f.repo).status, 0)
                    changed = true
                }
            }
            XCTAssertTrue(changed)
            XCTAssertEqual(result.issue?.kind, .review)
            XCTAssertNotEqual(LocalSiteStore.git(["rev-parse", "--verify", "refs/heads/main"], in: f.remote).status, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try SitePublicationState.receiptURL(repo: f.repo).path))
        }
    }

    func testCommitHookCannotReplacePreparedOutput() throws {
        try fixture { f in
            XCTAssertNil(try f.publish(f.review()).issue)
            let head = f.remoteHead(), receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo))
            let hook = URL(fileURLWithPath: f.repo + "/.git/hooks/pre-commit")
            try Data("#!/bin/sh\nprintf 'Changed by hook' > docs/index.html\ngit add docs/index.html\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let result = try f.publish(f.review())
            XCTAssertEqual(result.issue?.kind, .review)
            XCTAssertTrue(result.issue?.guidance.contains("commit hooks") == true)
            XCTAssertEqual(f.remoteHead(), head)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo)), receipt)
            XCTAssertTrue(LocalSiteStore.git(["show", "HEAD:docs/index.html"], in: f.repo).output.contains("Changed by hook"))
        }
    }

    func testCommitHookCannotAddFilesOutsidePublicationPaths() throws {
        try fixture { f in
            XCTAssertNil(try f.publish(f.review()).issue)
            let head = f.remoteHead(), receipt = try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo))
            let hook = URL(fileURLWithPath: f.repo + "/.git/hooks/pre-commit")
            try Data("#!/bin/sh\nprintf 'Not part of this publication' > private-notes.txt\ngit add private-notes.txt\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let result = try f.publish(f.review())
            XCTAssertEqual(result.issue?.kind, .review)
            XCTAssertEqual(f.remoteHead(), head)
            XCTAssertEqual(try Data(contentsOf: SitePublicationState.receiptURL(repo: f.repo)), receipt)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.repo + "/private-notes.txt"))
        }
    }
}
#endif
