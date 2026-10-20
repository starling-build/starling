// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SitePublicationDetailsTests: XCTestCase {
    private func withPublication(_ body: (String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(SiteCreation.create(title: "Handbook", parent: root.path))
    }

    func testLegacyPublicationHasNoDetailsAndReadingDoesNotRewriteIt() throws {
        try withPublication { repo in
            let path = URL(fileURLWithPath: repo + "/site.json")
            let before = try Data(contentsOf: path)
            XCTAssertNil(try SitePublicationDetailsStore.load(repo: repo).config.details)
            XCTAssertNil(try SiteBuilder.readConfig(repo).details)
            XCTAssertEqual(before, try Data(contentsOf: path))
        }
    }

    func testSaveTrimsOptionalFieldsAndPreservesDocumentsAndUnknownSettings() throws {
        try withPublication { repo in
            let path = URL(fileURLWithPath: repo + "/site.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            object["futureSetting"] = "keep"
            object["details"] = ["version": 1, "futureDetail": "keep too"]
            try JSONSerialization.data(withJSONObject: object).write(to: path)
            let source = try Data(contentsOf: URL(fileURLWithPath: repo + "/pages/welcome.json"))
            let expected = try SitePublicationDetailsStore.load(repo: repo)
            let details = SitePublicationDetails(byline: "  An Author  ", summary: "A short description",
                                                edition: "Second edition", language: "en-GB", rights: "  ")
            try SitePublicationDetailsStore.save(details, repo: repo, expected: expected)
            let saved = try SiteBuilder.readConfig(repo)
            XCTAssertEqual(saved.details?.byline, "An Author")
            XCTAssertNil(saved.details?.rights)
            XCTAssertEqual(saved.details?.language, "en-GB")
            XCTAssertEqual(saved.pages, expected.config.pages)
            XCTAssertEqual(saved.home, expected.config.resolvedHome)
            XCTAssertEqual(source, try Data(contentsOf: URL(fileURLWithPath: repo + "/pages/welcome.json")))
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            XCTAssertEqual(raw["futureSetting"] as? String, "keep")
            XCTAssertEqual((raw["details"] as? [String: Any])?["futureDetail"] as? String, "keep too")
        }
    }

    func testStaleSaveRejectsNewerPageOrSettingsEdits() throws {
        try withPublication { repo in
            let expected = try SitePublicationDetailsStore.load(repo: repo)
            var config = try SiteBuilder.readConfig(repo)
            config.title = "Edited elsewhere"
            try SiteBuilder.writeConfig(config, to: repo)
            let path = URL(fileURLWithPath: repo + "/site.json")
            let changed = try Data(contentsOf: path)
            XCTAssertThrowsError(try SitePublicationDetailsStore.save(.init(byline: "Author"), repo: repo, expected: expected))
            XCTAssertEqual(try Data(contentsOf: path), changed)
        }
    }

    func testClearingFieldsRemovesPublishedValues() throws {
        try withPublication { repo in
            try SitePublicationDetailsStore.save(.init(byline: "Author", edition: "First"), repo: repo,
                                                 expected: SitePublicationDetailsStore.load(repo: repo))
            try SitePublicationDetailsStore.save(.init(), repo: repo, expected: SitePublicationDetailsStore.load(repo: repo))
            let details = try XCTUnwrap(SiteBuilder.readConfig(repo).details)
            XCTAssertFalse(details.hasContent)
            XCTAssertNil(details.byline)
            XCTAssertNil(details.edition)
        }
    }

    func testUnsupportedVersionInvalidLanguageAndOversizedFieldsAreRejected() throws {
        XCTAssertThrowsError(try SitePublicationDetails(version: 2).validated())
        XCTAssertThrowsError(try SitePublicationDetails(summary: String(repeating: "x", count: 301)).validated())
        XCTAssertThrowsError(try SitePublicationDetails(byline: "Author\nAnother").validated())
        for language in ["English language", "en--GB", "en<script>", "-en", "e", "en_XX"] {
            XCTAssertThrowsError(try SitePublicationDetails(language: language).validated(), language)
        }
        for language in ["en", "en-GB", "zh-Hant", "es-419"] {
            XCTAssertEqual(try SitePublicationDetails(language: language).validated().language, language)
        }
        try withPublication { repo in
            var config = try SiteBuilder.readConfig(repo)
            config.details = .init(version: 2)
            try SiteBuilder.writeConfig(config, to: repo)
            XCTAssertThrowsError(try SiteBuilder.readConfig(repo))
            XCTAssertThrowsError(try SitePublicationDetailsStore.load(repo: repo))
        }
    }

    func testPublicManifestIncludesDetailsAndOldManifestsStillDecode() throws {
        let legacy = Data(#"{"title":"Legacy","base":"/","home":"index","pages":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(SiteManifest.self, from: legacy).details)
        let details = SitePublicationDetails(byline: "Author", summary: "A handbook", edition: "Second", language: "fr", rights: "Rights statement")
        let config = SiteConfig(title: "Handbook", pages: [SiteNode(slug: "home", title: "Start")], details: details)
        let manifest = SiteBuilder.manifest(from: config)
        XCTAssertEqual(try JSONDecoder().decode(SiteManifest.self, from: JSONEncoder().encode(manifest)).details, details)
    }

    func testShellEscapesDetailsAndKeepsLanguageAlongsideOtherHTMLAttributes() {
        let payload = #""/><script>alert(1)</script>&"#
        let details = SitePublicationDetails(byline: payload, summary: payload, edition: payload, language: "fr-CA", rights: payload)
        let html = SiteShellPage.render(template: #"<html lang="en" dir="ltr"><head><title>Old</title></head><body></body></html>"#,
                                        base: "/", route: "/", title: "Page", siteTitle: "Publication", description: payload, text: "",
                                        details: details)
        XCTAssertTrue(html.contains(#"<html lang="fr-CA" dir="ltr">"#))
        XCTAssertTrue(html.contains(#"<meta name="author" content="&quot;/&gt;&lt;script&gt;"#))
        XCTAssertTrue(html.contains(#"aria-label="About this publication""#))
        XCTAssertFalse(html.contains("<script>alert(1)"))
        XCTAssertTrue(html.contains("starling-edition"))
        XCTAssertTrue(html.contains(#"name="copyright""#))
        let noLanguage = SiteShellPage.render(template: "<html dir=\"ltr\"><head></head><body></body></html>",
                                              base: "/", route: "/", title: "Page", siteTitle: "Publication", description: "", text: "",
                                              details: .init(language: "zh-Hant"))
        XCTAssertTrue(noLanguage.contains(#"<html dir="ltr" lang="zh-Hant">"#))
    }
}
