// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SiteRecentTests: XCTestCase {
    private func withHistory(_ body: (URL, SiteRecent) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root, SiteRecent(directory: root.appendingPathComponent("state").path))
    }

    private func publication(_ root: URL, _ name: String) throws -> String {
        let path = root.appendingPathComponent(name).path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        try SiteBuilder.writeConfig(SiteConfig(title: name, pages: [
            SiteNode(slug: "intro", title: "Introduction"), SiteNode(slug: "chapter", title: "Chapter one"),
        ]), to: path)
        return path
    }

    func testRemembersLastPageAcrossSessionsWithoutChangingPublication() throws {
        try withHistory { root, history in
            let repo = try publication(root, "Book")
            let original = try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json"))
            history.remember(repo: repo, slug: "chapter")
            let reopened = SiteRecent(directory: history.directory)
            XCTAssertEqual(reopened.items().first?.pageTitle, "Chapter one")
            XCTAssertEqual(reopened.route(for: repo), "/chapter/")
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/site.json")), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo), ["site.json"])
        }
    }

    func testCanonicalPathsDeduplicateAndMostRecentMovesToFront() throws {
        try withHistory { root, history in
            let book = try publication(root, "Book"), manual = try publication(root, "Manual")
            let link = root.appendingPathComponent("alias").path
            try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: book)
            history.remember(repo: book, slug: "intro")
            history.remember(repo: manual, slug: "intro")
            history.remember(repo: link + "/./", slug: "chapter")
            XCTAssertEqual(history.load().count, 2)
            XCTAssertEqual(history.load().map(\.title), ["Book", "Manual"])
            XCTAssertEqual(history.route(for: book), "/chapter/")
        }
    }

    func testRemovedPageFallsBackAndRenamedTitleRefreshes() throws {
        try withHistory { root, history in
            let repo = try publication(root, "Book")
            history.remember(repo: repo, slug: "chapter")
            var config = try SiteBuilder.readConfig(repo)
            config.pages.removeLast(); config.title = "Revised book"
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertEqual(history.route(for: repo), "/")
            XCTAssertEqual(history.items().first?.entry.title, "Revised book")
            XCTAssertEqual(history.items().first?.pageTitle, "Introduction")
        }
    }

    func testUnavailableFolderRemainsInHistoryAndInvalidOpenIsNotRemembered() throws {
        try withHistory { root, history in
            let repo = try publication(root, "Book")
            history.remember(repo: repo, slug: "chapter")
            history.remember(repo: repo, slug: "missing")
            XCTAssertEqual(history.load().first?.slug, "chapter")
            try FileManager.default.moveItem(atPath: repo, toPath: repo + "-moved")
            history.remember(repo: repo, slug: "chapter")
            XCTAssertEqual(history.items().first?.available, false)
            XCTAssertEqual(history.load().count, 1)
            XCTAssertEqual(history.route(for: repo), "/")
        }
    }

    func testHistoryIsBoundedAndMalformedHistoryDoesNotPreventOpening() throws {
        try withHistory { root, history in
            for i in 0..<22 {
                history.remember(repo: try publication(root, "Book \(i)"), slug: "intro")
            }
            XCTAssertEqual(history.load().count, 20)
            XCTAssertEqual(history.load().first?.title, "Book 21")
            try Data("broken".utf8).write(to: URL(fileURLWithPath: history.directory + "/office-publications.json"))
            XCTAssertTrue(history.load().isEmpty)
            XCTAssertEqual(history.route(for: root.appendingPathComponent("Book 21").path), "/")
        }
    }
}
