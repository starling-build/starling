// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

final class SitePublishedLinkTests: XCTestCase {
    // The caller supplies a previously checked snapshot. HTTPS marker checking
    // is tested separately with URLProtocol; these fixtures never use a host.
    private func withUploaded(duplicateParagraphID: Bool = false, _ body: (String, SiteLivePublication.Snapshot, UInt32) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try SiteCreation.create(title: "Handbook", parent: root.path)
        var config = try SiteBuilder.readConfig(repo)
        config.url = "https://author.example/manual/"
        config.base = "/manual/"
        try SiteBuilder.writeConfig(config, to: repo)
        let source = URL(fileURLWithPath: repo + "/pages/welcome.json")
        var data = try Data(contentsOf: source)
        var page = try XCTUnwrap(SiteFiles.decodePage(data))
        let id = try XCTUnwrap(page.document.paragraphs.first?.id)
        if duplicateParagraphID {
            page.document.paragraphs.append(page.document.paragraphs[0])
            data = try RichDocumentEnvelope.encode(page.document, pageSetup: page.pageSetup)
            try data.write(to: source)
        }
        let out = URL(fileURLWithPath: repo + "/docs")
        try FileManager.default.createDirectory(at: out.appendingPathComponent("pages"), withIntermediateDirectories: true)
        try data.write(to: out.appendingPathComponent("pages/welcome.json"))
        try JSONEncoder().encode(SiteBuilder.manifest(from: config)).write(to: out.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(SiteLivePublication.Marker(version: 1, build: UUID().uuidString))
            .write(to: out.appendingPathComponent(SiteLivePublication.markerFile))
        for args in [["config", "user.name", "Test Author"], ["config", "user.email", "author@example.test"],
                     ["remote", "add", "origin", root.path + "/hosting.git"], ["add", "."], ["commit", "-qm", "Uploaded"]] {
            XCTAssertEqual(LocalSiteStore.git(args, in: repo).status, 0)
        }
        try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                        destination: SitePublicationState.destination(repo: repo), target: "refs/heads/main", out: "docs")
        try body(repo, SiteLivePublication.snapshot(repo: repo, out: "docs"), id)
    }

    func testPageAndParagraphLinksUseStableAliasAndProjectPathExactlyOnce() throws {
        try withUploaded { repo, verified, id in
            let page = try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome")
            XCTAssertEqual(page.absoluteString, "https://author.example/manual/welcome/")
            let paragraph = try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: id)
            XCTAssertEqual(paragraph.absoluteString, "https://author.example/manual/welcome/#p=\(id)")
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: 0))
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: id == 1 ? 2 : 1))
        }
    }

    func testUnsentContentAndTitleChangesDoNotProduceLinks() throws {
        try withUploaded { repo, verified, _ in
            let path = URL(fileURLWithPath: repo + "/pages/welcome.json")
            let original = try Data(contentsOf: path)
            try Data("{}".utf8).write(to: path)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome")) {
                XCTAssertTrue(String(describing: $0).contains("saved changes"))
            }
            try original.write(to: path)
            var config = try SiteBuilder.readConfig(repo)
            config.pages[0].title = "New title"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
        }
    }

    func testHeldDraftCannotBeSharedAsThoughItIsTheVerifiedRelease() throws {
        try withUploaded { repo, verified, id in
            try SiteDrafts.start(repo: repo, out: "docs", slug: "welcome")
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: id)) {
                XCTAssertTrue(String(describing: $0).contains("separate local draft"))
            }
        }
    }

    func testNewAndDeletedLocalPagesCannotBeSharedAsPublished() throws {
        try withUploaded { repo, verified, _ in
            var config = try SiteBuilder.readConfig(repo)
            config.pages.append(SiteNode(slug: "new", title: "New page"))
            try Data("{}".utf8).write(to: URL(fileURLWithPath: repo + "/pages/new.json"))
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "new"))
            config.pages.removeFirst()
            config.home = "new"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
        }
    }

    func testNewHomeAndOtherPagesDoNotRetargetUnchangedPublishedPassage() throws {
        try withUploaded { repo, verified, id in
            var config = try SiteBuilder.readConfig(repo)
            config.pages.insert(SiteNode(slug: "new", title: "New page"), at: 0)
            config.home = "new"
            try Data("{}".utf8).write(to: URL(fileURLWithPath: repo + "/pages/new.json"))
            try SiteBuilder.writeConfig(config, to: repo)
            let url = try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: id)
            XCTAssertEqual(url.path, "/manual/welcome")
            XCTAssertEqual(url.fragment, "p=\(id)")
        }
    }

    func testChangedWebsiteOrUploadRecordInvalidatesVerifiedSnapshot() throws {
        try withUploaded { repo, verified, _ in
            var config = try SiteBuilder.readConfig(repo)
            config.url = "https://author.example/elsewhere/"
            config.base = "/elsewhere/"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
            config.url = "https://author.example/manual/"; config.base = "/manual/"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertEqual(LocalSiteStore.git(["commit", "--allow-empty", "-qm", "Another upload"], in: repo).status, 0)
            try SitePublicationState.record(repo: repo, revision: LocalSiteStore.git(["rev-parse", "HEAD"], in: repo).output.trimmingWhitespace(),
                                            destination: verified.receipt.destination, target: verified.receipt.target, out: "docs")
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
        }
    }

    func testMissingOrEscapingSourceAndInvalidSlugAreRejected() throws {
        try withUploaded { repo, verified, _ in
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "../welcome"))
            let path = repo + "/pages/welcome.json"
            let original = try Data(contentsOf: URL(fileURLWithPath: path))
            try FileManager.default.removeItem(atPath: path)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
            let outside = URL(fileURLWithPath: repo).deletingLastPathComponent().appendingPathComponent("outside.json")
            try original.write(to: outside)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: outside.path)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
        }
    }

    func testUnsentPublicationDetailsRequirePublishingBeforeSharing() throws {
        try withUploaded { repo, verified, _ in
            var config = try SiteBuilder.readConfig(repo)
            config.details = .init(byline: "A newly credited author")
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome")) {
                XCTAssertTrue(String(describing: $0).contains("saved changes"))
            }
        }
    }

    func testAmbiguousPassageIdentityCannotProduceAMisleadingSharedLink() throws {
        try withUploaded(duplicateParagraphID: true) { repo, verified, id in
            XCTAssertNoThrow(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome"))
            XCTAssertThrowsError(try SitePublishedLink.prepare(repo: repo, out: "docs", verified: verified, slug: "welcome", paragraph: id)) {
                XCTAssertTrue(String(describing: $0).contains("single passage"))
            }
        }
    }
}
