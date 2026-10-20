// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SiteHomeTests: XCTestCase {
    private func withLegacy(_ body: (String) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("pages"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let json = """
        {"title":"Handbook","pages":[{"slug":"first","title":"Start","children":[{"slug":"child","title":"Nested"}]},{"slug":"second","title":"Chapter"}]}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("site.json"))
        for slug in ["first", "second", "child"] { try Data("{}".utf8).write(to: folder.appendingPathComponent("pages/\(slug).json")) }
        try body(folder.path)
    }

    func testLegacyReadDoesNotWriteAndMovePinsOriginalHome() throws {
        try withLegacy { repo in
            let path = URL(fileURLWithPath: repo + "/site.json")
            let original = try Data(contentsOf: path)
            XCTAssertEqual(try SiteBuilder.readConfig(repo).home, "first")
            XCTAssertEqual(try Data(contentsOf: path), original)
            XCTAssertTrue(try LocalSiteStore.movePage(repo: repo, slug: "first", by: 1))
            let config = try SiteBuilder.readConfig(repo)
            XCTAssertEqual(config.pages.map(\.slug), ["second", "first"])
            XCTAssertEqual(config.home, "first")
            let manifest = SiteBuilder.manifest(from: config)
            XCTAssertEqual(manifest.route("first"), "/")
            XCTAssertEqual(manifest.route("second"), "/second/")
            let saved = try JSONDecoder().decode(SiteConfig.self, from: Data(contentsOf: path))
            XCTAssertEqual(saved.home, "first")
        }
    }

    func testNestedPageCanBecomeHomeWithoutMovingIt() throws {
        try withLegacy { repo in
            let before = try SiteBuilder.readConfig(repo).pages
            try LocalSiteStore.chooseHome(repo: repo, slug: "child", replacing: "first")
            let after = try SiteBuilder.readConfig(repo)
            XCTAssertEqual(after.pages, before)
            XCTAssertEqual(after.home, "child")
            XCTAssertEqual(SiteBuilder.manifest(from: after).route("child"), "/")
            XCTAssertEqual(SiteBuilder.manifest(from: after).route("first"), "/first/")
            XCTAssertTrue(try LocalSiteStore.movePage(repo: repo, slug: "first", by: 1))
            XCTAssertEqual(try SiteBuilder.readConfig(repo).home, "child")
        }
    }

    func testStaleOrMissingSelectionCannotChangeConfig() throws {
        try withLegacy { repo in
            let path = URL(fileURLWithPath: repo + "/site.json")
            try LocalSiteStore.chooseHome(repo: repo, slug: "second", replacing: "first")
            let before = try Data(contentsOf: path)
            XCTAssertThrowsError(try LocalSiteStore.chooseHome(repo: repo, slug: "child", replacing: "first"))
            XCTAssertThrowsError(try LocalSiteStore.chooseHome(repo: repo, slug: "missing", replacing: "second"))
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }

    func testDeletingHomeRequiresExplicitReplacementAndNestedHomeSurvivesParentDeletion() throws {
        try withLegacy { repo in
            let store = LocalSiteStore(repo: repo)
            var problem: String?
            store.delete("first") { problem = $0 }
            XCTAssertTrue(problem?.contains("another home") == true)
            XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/pages/first.json"))
            try LocalSiteStore.chooseHome(repo: repo, slug: "child", replacing: "first")
            store.delete("first") { problem = $0 }
            XCTAssertNil(problem)
            let config = try SiteBuilder.readConfig(repo)
            XCTAssertEqual(config.home, "child")
            XCTAssertEqual(config.pages.map(\.slug), ["child", "second"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/pages/first.json"))
        }
    }

    func testInvalidExplicitHomeFailsSourceValidation() throws {
        try withLegacy { repo in
            var config = try SiteBuilder.readConfig(repo)
            for home in ["missing", "", "../first"] {
                config.home = home
                XCTAssertThrowsError(try SiteBuilder.validatedSources(repo: repo, config: config, web: nil))
            }
        }
    }

    func testRenameAndHostingSavePreserveLegacyHome() throws {
        try withLegacy { repo in
            let expected = try SiteHosting.load(repo: repo)
            try SiteHosting.save(.init(title: "New handbook", repository: "", url: ""), repo: repo, expected: expected)
            let raw = try JSONDecoder().decode(SiteConfig.self, from: Data(contentsOf: URL(fileURLWithPath: repo + "/site.json")))
            XCTAssertEqual(raw.home, "first")
            var problem: String?
            LocalSiteStore(repo: repo).rename("first", to: "Introduction") { problem = $0 }
            XCTAssertNil(problem)
            let config = try SiteBuilder.readConfig(repo)
            XCTAssertEqual(config.home, "first")
            XCTAssertEqual(config.pages.first?.title, "Introduction")
        }
    }

    func testPassageLinksKeepTheirPageWhenHomeChanges() throws {
        try withLegacy { repo in
            let before = SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo), base: "/manual/")
            let link = before.paragraphRoute("first", id: 42)
            XCTAssertEqual(link, "/manual/first/#p=42")
            try LocalSiteStore.chooseHome(repo: repo, slug: "second", replacing: "first")
            let after = SiteBuilder.manifest(from: try SiteBuilder.readConfig(repo), base: "/manual/")
            XCTAssertEqual(after.paragraphRoute("first", id: 42), link)
            XCTAssertEqual(SiteFiles.slug(ofRoute: link, base: after.base), "first")
            XCTAssertEqual(after.route("second"), "/manual/")
        }
    }
}
