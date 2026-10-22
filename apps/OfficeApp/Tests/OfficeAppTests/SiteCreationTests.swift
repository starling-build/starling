// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

final class SiteCreationTests: XCTestCase {
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    func testCreationProducesReadablePublicationWithLocalHistoryOnly() throws {
        try withFolder { parent in
            let path = try SiteCreation.create(title: "  Product handbook  ", parent: parent.path)
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, "product-handbook")
            let config = try SiteBuilder.readConfig(path)
            XCTAssertEqual(config.title, "Product handbook")
            XCTAssertEqual(config.pages, [SiteNode(slug: "welcome", title: "Product handbook")])
            XCTAssertNil(config.repository)
            XCTAssertNil(config.url)
            let data = try Data(contentsOf: URL(fileURLWithPath: path + "/pages/welcome.json"))
            let page = try XCTUnwrap(SiteFiles.decodePage(data))
            XCTAssertEqual(page.document.paragraphs.map(\.text), [""])
            XCTAssertEqual(page.pageSetup, .letter)
            XCTAssertTrue(page.document.paragraphIDsAreUnique)
            XCTAssertNotEqual(page.document.paragraphs.first?.id, 0)
            XCTAssertEqual(LocalSiteStore.git(["symbolic-ref", "--short", "HEAD"], in: path).output.trimmingWhitespace(), "main")
            XCTAssertEqual(LocalSiteStore.git(["remote"], in: path).output, "")
            XCTAssertNotEqual(LocalSiteStore.git(["rev-parse", "--verify", "HEAD"], in: path).status, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/PUBLISHING.md"))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["product-handbook"])
        }
    }

    func testStartingFromWordCopiesContentFormattingAndPageSetup() throws {
        try withFolder { parent in
            var paragraph = RichParagraph(text: "A writer's manuscript")
            paragraph.applyStyle(0 ..< 1) { $0.bold = true }
            var document = RichDocument(paragraphs: [paragraph, RichParagraph(text: "Second paragraph")])
            document.styles = OfficeStyles.sheet
            let source = parent.appendingPathComponent("manuscript.docx")
            try OfficeFormats.write(document, to: source.path, pageSetup: .letter)
            let original = try Data(contentsOf: source)
            let imported = try OfficeFormats.read(source.path)
            let path = try SiteCreation.create(title: "My publication", parent: parent.path, source: source.path)
            let config = try SiteBuilder.readConfig(path)
            XCTAssertEqual(config.pages.count, 1)
            let page = try XCTUnwrap(SiteFiles.decodePage(Data(contentsOf: URL(fileURLWithPath: path + "/pages/welcome.json"))))
            XCTAssertEqual(page.document.paragraphs.map(\.text), imported.document.paragraphs.map(\.text))
            XCTAssertTrue(page.document.paragraphs[0].runs[0].style.bold)
            XCTAssertEqual(page.pageSetup, imported.pageSetup)
            XCTAssertTrue(page.document.paragraphIDsAreUnique)
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(LocalSiteStore.git(["remote"], in: path).output, "")
        }
    }

    func testUnreadableManuscriptDoesNotCreatePartialPublication() throws {
        try withFolder { parent in
            let source = parent.appendingPathComponent("broken.docx")
            try Data("not a Word file".utf8).write(to: source)
            XCTAssertThrowsError(try SiteCreation.create(title: "My publication", parent: parent.path, source: source.path))
            XCTAssertThrowsError(try SiteCreation.create(title: "My publication", parent: parent.path, source: parent.path + "/missing.docx"))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["broken.docx"])
        }
    }

    func testExistingPublicationIsNeverOverwritten() throws {
        try withFolder { parent in
            let path = try SiteCreation.create(title: "Handbook", parent: parent.path)
            let source = URL(fileURLWithPath: path + "/pages/welcome.json")
            let original = try Data(contentsOf: source)
            XCTAssertThrowsError(try SiteCreation.create(title: "Handbook!", parent: parent.path))
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["handbook"])
        }
    }

    func testRejectsEmptyTitleMissingParentAndNestedRepository() throws {
        try withFolder { parent in
            XCTAssertThrowsError(try SiteCreation.create(title: " \n ", parent: parent.path))
            XCTAssertThrowsError(try SiteCreation.create(title: "Handbook", parent: parent.path + "/missing"))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
            XCTAssertEqual(LocalSiteStore.git(["init"], in: parent.path).status, 0)
            XCTAssertThrowsError(try SiteCreation.create(title: "Handbook", parent: parent.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), [".git"])
        }
    }

    func testInstallationFailureCleansUpStaging() throws {
        try withFolder { parent in
            XCTAssertThrowsError(try SiteCreation.create(title: String(repeating: "a", count: 300), parent: parent.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
        }
    }

    func testTitleCannotEscapeChosenFolderAndDanglingLinkIsNotReplaced() throws {
        try withFolder { parent in
            let path = try SiteCreation.create(title: "../Manual / 2026", parent: parent.path)
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, "manual-2026")
            let link = parent.appendingPathComponent("handbook")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: parent.path + "/absent")
            XCTAssertThrowsError(try SiteCreation.create(title: "Handbook", parent: parent.path))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), parent.path + "/absent")
        }
    }
}
