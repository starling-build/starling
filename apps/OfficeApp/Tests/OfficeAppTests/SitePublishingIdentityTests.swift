// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SitePublishingIdentityTests: XCTestCase {
    private func withSite(_ body: (String) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = try SiteCreation.create(title: "Author setup", parent: parent.path)
        _ = LocalSiteStore.git(["config", "user.name", "Original author"], in: repo)
        _ = LocalSiteStore.git(["config", "user.email", "original@example.test"], in: repo)
        try body(repo)
    }

    func testSaveIsLocalPreservesOtherSettingsAndCreatesNoCommit() throws {
        try withSite { repo in
            _ = LocalSiteStore.git(["config", "publication.custom", "keep me"], in: repo)
            let snapshot = try SitePublishingIdentity.load(repo: repo)
            let config = try SiteHosting.load(repo: repo).bytes
            let globalName = LocalSiteStore.git(["config", "--global", "--get", "user.name"], in: repo).output
            let globalEmail = LocalSiteStore.git(["config", "--global", "--get", "user.email"], in: repo).output
            try SitePublishingIdentity.save(name: "  Zoë Writer  ", email: "123+zoe@users.noreply.github.com", repo: repo, expected: snapshot)
            let saved = try SitePublishingIdentity.load(repo: repo)
            XCTAssertEqual(saved.name, "Zoë Writer")
            XCTAssertEqual(saved.email, "123+zoe@users.noreply.github.com")
            XCTAssertEqual(LocalSiteStore.git(["config", "publication.custom"], in: repo).output.trimmingWhitespace(), "keep me")
            XCTAssertEqual(LocalSiteStore.git(["config", "--global", "--get", "user.name"], in: repo).output, globalName)
            XCTAssertEqual(LocalSiteStore.git(["config", "--global", "--get", "user.email"], in: repo).output, globalEmail)
            XCTAssertEqual(try SiteHosting.load(repo: repo).bytes, config)
            XCTAssertNotEqual(LocalSiteStore.git(["rev-parse", "--verify", "HEAD"], in: repo).status, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved.configURL.path + ".lock"))
        }
    }

    func testConnectingRepositoryWhileFormIsOpenPreservesConnection() throws {
        try withSite { repo in
            let before = try SitePublishingIdentity.load(repo: repo)
            _ = LocalSiteStore.git(["remote", "add", "origin", "https://github.com/author/book.git"], in: repo)
            try SitePublishingIdentity.save(name: "Writer", email: "writer@example.test", repo: repo, expected: before)
            XCTAssertEqual(LocalSiteStore.git(["remote", "get-url", "origin"], in: repo).output.trimmingWhitespace(), "https://github.com/author/book.git")
            XCTAssertEqual(try SitePublishingIdentity.load(repo: repo).name, "Writer")
        }
    }

    func testInvalidIdentityDoesNotChangeEitherField() throws {
        try withSite { repo in
            let before = try SitePublishingIdentity.load(repo: repo)
            for (name, email) in [("", "author@example.test"), ("A\nB", "author@example.test"),
                                  ("<Writer>", "author@example.test"), ("Writer", ""), ("Writer", "a@@example.test"),
                                  ("Writer", "a @example.test"), ("Writer", "@example.test"), ("Writer", "a@example.test\nuser.name=x")] {
                XCTAssertThrowsError(try SitePublishingIdentity.save(name: name, email: email, repo: repo, expected: before))
                XCTAssertEqual(try Data(contentsOf: before.configURL), before.configBytes)
            }
        }
    }

    func testStaleSnapshotAndExistingGitLockAreNotOverwritten() throws {
        try withSite { repo in
            let before = try SitePublishingIdentity.load(repo: repo)
            _ = LocalSiteStore.git(["config", "user.name", "Changed elsewhere"], in: repo)
            let current = try SitePublishingIdentity.load(repo: repo)
            XCTAssertThrowsError(try SitePublishingIdentity.save(name: "Writer", email: "writer@example.test", repo: repo, expected: before))
            XCTAssertEqual(try Data(contentsOf: current.configURL), current.configBytes)
            let lock = URL(fileURLWithPath: current.configURL.path + ".lock")
            let sentinel = Data("another operation".utf8)
            try sentinel.write(to: lock)
            XCTAssertThrowsError(try SitePublishingIdentity.save(name: "Writer", email: "writer@example.test", repo: repo, expected: current))
            XCTAssertEqual(try Data(contentsOf: lock), sentinel)
            XCTAssertEqual(try Data(contentsOf: current.configURL), current.configBytes)
        }
    }

    func testOverridingIncludeRollsBackBothChanges() throws {
        try withSite { repo in
            let config = try SitePublishingIdentity.load(repo: repo).configURL
            let extra = config.deletingLastPathComponent().appendingPathComponent("included-author")
            try Data("[user]\nname = Override\nemail = override@example.test\n".utf8).write(to: extra)
            _ = LocalSiteStore.git(["config", "include.path", extra.path], in: repo)
            let before = try SitePublishingIdentity.load(repo: repo)
            XCTAssertEqual(before.name, "Override")
            XCTAssertThrowsError(try SitePublishingIdentity.save(name: "Writer", email: "writer@example.test", repo: repo, expected: before))
            XCTAssertEqual(try Data(contentsOf: config), before.configBytes)
            XCTAssertEqual(try SitePublishingIdentity.load(repo: repo).email, "override@example.test")
        }
    }

    func testNestedFolderAndLinkedConfigAreNotModified() throws {
        try withSite { repo in
            XCTAssertThrowsError(try SitePublishingIdentity.load(repo: repo + "/pages"))
            let original = try SitePublishingIdentity.load(repo: repo)
            let alternate = original.configURL.deletingLastPathComponent().appendingPathComponent("linked-config")
            try FileManager.default.moveItem(at: original.configURL, to: alternate)
            try FileManager.default.createSymbolicLink(at: original.configURL, withDestinationURL: alternate)
            XCTAssertThrowsError(try SitePublishingIdentity.load(repo: repo))
            XCTAssertEqual(try Data(contentsOf: alternate), original.configBytes)
        }
    }

    func testPagesSetupUsesValidatedRepositoryAndActualTargetBranch() throws {
        XCTAssertEqual(try SiteHosting.pagesSettingsURL(repository: "https://github.com/author/book.git"), "https://github.com/author/book/settings/pages")
        XCTAssertThrowsError(try SiteHosting.pagesSettingsURL(repository: "https://secret@github.com/author/book"))
        try withSite { repo in
            XCTAssertTrue(try SiteHosting.pagesSource(repo: repo, out: "docs").contains("branch main"))
            _ = LocalSiteStore.git(["config", "branch.main.remote", "origin"], in: repo)
            _ = LocalSiteStore.git(["config", "branch.main.merge", "refs/heads/book-release"], in: repo)
            XCTAssertTrue(try SiteHosting.pagesSource(repo: repo, out: "docs").contains("branch book-release"))
            XCTAssertThrowsError(try SiteHosting.pagesSource(repo: repo, out: "public"))
        }
    }
}
