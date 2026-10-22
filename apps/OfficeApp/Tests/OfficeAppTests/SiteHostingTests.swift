// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SiteHostingTests: XCTestCase {
    private func withSite(_ body: (String) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = try SiteCreation.create(title: "Handbook", parent: parent.path)
        try body(repo)
    }

    private func settings(url: String = "https://publisher.github.io/handbook/") throws -> SiteHosting.Settings {
        try SiteHosting.Settings(title: "Product handbook", repository: "https://github.com/publisher/handbook.git", url: url)
    }

    func testProjectAndUserPagesAddressesAndCustomBase() throws {
        XCTAssertEqual(try SiteHosting.suggestedURL(repository: "https://github.com/Publisher/handbook.git"), "https://publisher.github.io/handbook/")
        XCTAssertEqual(try SiteHosting.suggestedURL(repository: "https://github.com/Publisher/publisher.github.io"), "https://publisher.github.io/")
        XCTAssertEqual(try settings().base, "/handbook/")
        XCTAssertEqual(try settings(url: "https://manual.example.org/guides").url, "https://manual.example.org/guides/")
        XCTAssertEqual(try settings(url: "https://manual.example.org").base, "/")
    }

    func testInvalidAddressesAreRejectedWithoutEchoingSecrets() {
        for repository in ["https://token@github.com/owner/repo", "https://github.com/owner/repo/tree/main", "https://example.org/owner/repo", "https://github.com/owner/../repo", "https://github.com/owner/repo?token=secret"] {
            XCTAssertThrowsError(try SiteHosting.githubRepository(repository)) { error in
                XCTAssertFalse(String(describing: error).contains("secret"))
                XCTAssertFalse(String(describing: error).contains("token@"))
            }
        }
        for url in ["http://example.org", "https://example.org/../private", "https://example.org/%2e%2e/private", "https://example.org//manual", "https://example.org/manual?q=a", "https://person:secret@example.org", "javascript:alert(1)"] {
            XCTAssertThrowsError(try settings(url: url))
        }
    }

    func testSavePreservesTreeUnknownFieldsAndDoesNotConnect() throws {
        try withSite { repo in
            let path = URL(fileURLWithPath: repo + "/site.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            object["futureFeature"] = ["enabled": true]
            try JSONSerialization.data(withJSONObject: object).write(to: path)
            let before = try SiteHosting.load(repo: repo)
            let page = try Data(contentsOf: URL(fileURLWithPath: repo + "/pages/welcome.json"))
            try SiteHosting.save(settings(), repo: repo, expected: before)
            let after = try SiteHosting.load(repo: repo)
            XCTAssertEqual(after.config.pages, before.config.pages)
            XCTAssertEqual(after.config.base, "/handbook/")
            XCTAssertEqual(after.config.repository, "https://github.com/publisher/handbook")
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: after.bytes) as? [String: Any])
            XCTAssertEqual(saved["futureFeature"] as? [String: Bool], ["enabled": true])
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: repo + "/pages/welcome.json")), page)
            XCTAssertEqual(LocalSiteStore.git(["remote"], in: repo).output, "")
        }
    }

    func testStaleSettingsCannotOverwriteChangedTree() throws {
        try withSite { repo in
            let snapshot = try SiteHosting.load(repo: repo)
            var config = snapshot.config
            config.pages.append(SiteNode(slug: "new", title: "New page"))
            try SiteBuilder.writeConfig(config, to: repo)
            let changed = try SiteHosting.load(repo: repo).bytes
            XCTAssertThrowsError(try SiteHosting.save(settings(), repo: repo, expected: snapshot))
            XCTAssertEqual(try SiteHosting.load(repo: repo).bytes, changed)
        }
    }

    func testConnectIsLocalIdempotentAndPreservesMatchingSSH() throws {
        try withSite { repo in
            try SiteHosting.save(settings(), repo: repo, expected: SiteHosting.load(repo: repo))
            try SiteHosting.connect(repo: repo)
            try SiteHosting.connect(repo: repo)
            XCTAssertEqual(LocalSiteStore.git(["remote", "get-url", "origin"], in: repo).output.trimmingWhitespace(), "https://github.com/publisher/handbook.git")
            XCTAssertNotEqual(LocalSiteStore.git(["rev-parse", "--verify", "HEAD"], in: repo).status, 0)
            let ssh = "git@github.com:publisher/handbook.git"
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "origin", ssh], in: repo).status, 0)
            try SiteHosting.connect(repo: repo)
            XCTAssertEqual(LocalSiteStore.git(["remote", "get-url", "origin"], in: repo).output.trimmingWhitespace(), ssh)
        }
    }

    func testDifferentRemoteIsNeverReplaced() throws {
        try withSite { repo in
            try SiteHosting.save(settings(), repo: repo, expected: SiteHosting.load(repo: repo))
            let other = "https://github.com/someone/else.git"
            XCTAssertEqual(LocalSiteStore.git(["remote", "add", "origin", other], in: repo).status, 0)
            XCTAssertThrowsError(try SiteHosting.connect(repo: repo))
            XCTAssertEqual(LocalSiteStore.git(["remote", "get-url", "origin"], in: repo).output.trimmingWhitespace(), other)
            XCTAssertTrue(SiteHosting.readiness(repo: repo, web: nil).contains { $0.contains("push destination differs") })
        }
    }

    func testReadinessReportsMissingSetupThenPassesLocally() throws {
        try withSite { repo in
            let missing = SiteHosting.readiness(repo: repo, web: nil).joined(separator: " ")
            XCTAssertTrue(missing.contains("website address"))
            XCTAssertTrue(missing.contains("origin"))
            XCTAssertTrue(missing.contains("web reader"))
            try SiteHosting.save(settings(), repo: repo, expected: SiteHosting.load(repo: repo))
            try SiteHosting.connect(repo: repo)
            XCTAssertEqual(LocalSiteStore.git(["config", "user.name", "Test author"], in: repo).status, 0)
            XCTAssertEqual(LocalSiteStore.git(["config", "user.email", "author@example.test"], in: repo).status, 0)
            let web = repo + "/web"
            try FileManager.default.createDirectory(atPath: web, withIntermediateDirectories: false)
            try Data().write(to: URL(fileURLWithPath: web + "/index.html"))
            try Data().write(to: URL(fileURLWithPath: web + "/app.wasm"))
            XCTAssertEqual(SiteHosting.readiness(repo: repo, web: web), [])
            XCTAssertEqual(LocalSiteStore.git(["remote", "set-url", "--push", "origin", "https://github.com/another/repo.git"], in: repo).status, 0)
            XCTAssertTrue(SiteHosting.readiness(repo: repo, web: web).contains { $0.contains("push destination differs") })
        }
    }

    func testPushUsesExplicitSingleDestinationAndPreservesTargetBranch() throws {
        try withSite { repo in
            XCTAssertEqual(try SiteHosting.pushArguments(repo: repo), ["push", "--set-upstream", "--", "origin", "HEAD:refs/heads/main"])
            _ = LocalSiteStore.git(["config", "branch.main.remote", "origin"], in: repo)
            _ = LocalSiteStore.git(["config", "branch.main.merge", "refs/heads/publication"], in: repo)
            XCTAssertEqual(try SiteHosting.pushArguments(repo: repo).last, "HEAD:refs/heads/publication")
            _ = LocalSiteStore.git(["config", "branch.main.remote", "other"], in: repo)
            XCTAssertThrowsError(try SiteHosting.pushArguments(repo: repo))
        }
    }

    func testActiveMergeAndMultiplePushDestinationsBlockPublication() throws {
        try withSite { repo in
            try Data("in-progress".utf8).write(to: URL(fileURLWithPath: repo + "/.git/MERGE_HEAD"))
            XCTAssertTrue(SiteHosting.gitProblems(repo: repo).contains { $0.contains("Finish or abort") })
            _ = LocalSiteStore.git(["remote", "add", "origin", "https://github.com/publisher/handbook.git"], in: repo)
            _ = LocalSiteStore.git(["remote", "set-url", "--add", "--push", "origin", "https://github.com/publisher/handbook.git"], in: repo)
            _ = LocalSiteStore.git(["remote", "set-url", "--add", "--push", "origin", "https://github.com/other/handbook.git"], in: repo)
            XCTAssertThrowsError(try SiteHosting.pushArguments(repo: repo))
        }
    }
}
