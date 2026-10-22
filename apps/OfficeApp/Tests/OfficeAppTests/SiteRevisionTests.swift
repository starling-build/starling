// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

final class SiteRevisionTests: XCTestCase {
    private func page(_ entries: [(UInt32, String)]) -> SitePage {
        SitePage(document: RichDocument(paragraphs: entries.map { id, text in
            var paragraph = RichParagraph(text: text)
            paragraph.id = id
            return paragraph
        }), pageSetup: .letter)
    }

    private func revision(_ old: SitePage, _ new: SitePage) -> SiteRevision {
        SiteRevision(slug: "manual", original: old, incoming: new, originalBytes: Data())
    }

    func testWordIDsSurviveEditsAndReordering() {
        let result = revision(page([(11, "Heading"), (22, "Old wording"), (33, "Removed")]),
                              page([(22, "New wording"), (11, "Heading"), (44, "Added")]))
        XCTAssertEqual(result.replacement.document.paragraphs.map(\.id), [22, 11, 44])
        XCTAssertEqual(result.retained, 2)
        XCTAssertEqual(result.changed, 1)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertTrue(result.replacement.document.paragraphIDsAreUnique)
    }

    func testUniqueTextRecoversIDsWhenExporterDropsThem() {
        let result = revision(page([(11, "First"), (22, "Second")]), page([(0, "Second"), (0, "First")]))
        XCTAssertEqual(result.replacement.document.paragraphs.map(\.id), [22, 11])
        XCTAssertEqual(result.changed, 0)
    }

    func testAmbiguousTextAndDuplicateIDsNeverRetargetLinks() {
        let result = revision(page([(11, "Repeated"), (22, "Repeated"), (33, "")]),
                              page([(11, "Repeated"), (11, "Repeated"), (0, "")]))
        XCTAssertEqual(result.retained, 0)
        XCTAssertTrue(Set(result.replacement.document.paragraphs.map(\.id)).isDisjoint(with: [11, 22, 33]))
        XCTAssertTrue(result.replacement.document.paragraphIDsAreUnique)
    }

    func testChangedTextWithoutIdentityDoesNotGuessByPosition() {
        let result = revision(page([(11, "Old wording")]), page([(0, "New wording")]))
        XCTAssertEqual(result.retained, 0)
        XCTAssertNotEqual(result.replacement.document.paragraphs[0].id, 11)
    }

    func testFormattingAndPageSetupComeFromRevision() {
        let old = page([(11, "Same text")])
        var incoming = page([(0, "Same text")])
        incoming.document.paragraphs[0].applyStyle(0 ..< 4) { $0.bold = true }
        incoming.pageSetup = nil
        let result = revision(old, incoming)
        XCTAssertEqual(result.changed, 1)
        XCTAssertTrue(result.replacement.document.paragraphs[0].runs[0].style.bold)
        XCTAssertNil(result.replacement.pageSetup)
    }

    func testActualWordRoundTripKeepsAnchorsAfterUpdate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = page([(11, "Before"), (22, "Unchanged")])
        let incoming = page([(11, "After"), (22, "Unchanged")])
        let path = root.appendingPathComponent("revision.docx").path
        try OfficeFormats.write(incoming.document, to: path, pageSetup: .letter)
        let read = try OfficeFormats.read(path)
        let result = revision(old, SitePage(document: read.document, pageSetup: read.pageSetup))
        XCTAssertEqual(result.replacement.document.paragraphs.map(\.id), [11, 22])
        XCTAssertEqual(result.replacement.document.paragraphs.first?.text, "After")
    }

    func testPreviewDoesNotWriteAndApplyPreservesTree() throws {
        try withSite { root, source in
            let config = try Data(contentsOf: root.appendingPathComponent("site.json"))
            let before = try Data(contentsOf: source)
            let result = try LocalSiteStore.prepareUpdate(repo: root.path, slug: "manual", page: page([(11, "Revised")]))
            XCTAssertEqual(try Data(contentsOf: source), before)
            try LocalSiteStore.applyUpdate(repo: root.path, revision: result)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("site.json")), config)
            let saved = try XCTUnwrap(SiteFiles.decodePage(Data(contentsOf: source)))
            XCTAssertEqual(saved.document.paragraphs[0].text, "Revised")
            XCTAssertEqual(saved.document.paragraphs[0].id, 11)
        }
    }

    func testConcurrentEditAndDeletedPageRejectStalePreview() throws {
        try withSite { root, source in
            let result = try LocalSiteStore.prepareUpdate(repo: root.path, slug: "manual", page: page([(11, "Revised")]))
            let edited = try RichDocumentEnvelope.encode(page([(11, "Someone else's edit")]).document)
            try edited.write(to: source)
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: root.path, revision: result))
            XCTAssertEqual(try Data(contentsOf: source), edited)
            try FileManager.default.removeItem(at: source)
            XCTAssertThrowsError(try LocalSiteStore.applyUpdate(repo: root.path, revision: result))
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    private func withSite(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("pages"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try SiteBuilder.writeConfig(SiteConfig(title: "Site", pages: [SiteNode(slug: "manual", title: "My manual")]), to: root.path)
        let source = root.appendingPathComponent("pages/manual.json")
        try RichDocumentEnvelope.encode(page([(11, "Original")]).document).write(to: source)
        try body(root, source)
    }
}
