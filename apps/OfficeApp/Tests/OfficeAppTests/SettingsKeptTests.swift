// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

final class SettingsKeptTests: XCTestCase {
    private let original = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\">"
        + "<w:zoom w:percent=\"120\"/><w:rsids><w:rsidRoot w:val=\"00ABCDEF\"/><w:rsid w:val=\"00ABCDEF\"/></w:rsids><m:mathPr><m:brkBin m:val=\"before\"/></m:mathPr>"
        + "<w:defaultTabStop w:val=\"720\"/><w:characterSpacingControl w:val=\"doNotCompress\"/><w:footnotePr><w:footnote w:id=\"-1\"/><w:footnote w:id=\"0\"/></w:footnotePr>"
        + "<w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"14\"/></w:compat>"
        + "<w:clrSchemeMapping w:bg1=\"light1\" w:t1=\"dark1\" w:bg2=\"light2\" w:t2=\"dark2\" w:accent1=\"accent1\" w:accent2=\"accent2\" w:accent3=\"accent3\" w:accent4=\"accent4\" w:accent5=\"accent5\" w:accent6=\"accent6\" w:hyperlink=\"hyperlink\" w:followedHyperlink=\"followedHyperlink\"/></w:settings>"

    private func settings(of data: Data) throws -> String {
        let e = try XCTUnwrap(try Zip.read(data).first { $0.name == "word/settings.xml" })
        return String(decoding: e.data, as: UTF8.self)
    }

    /// A save keeps the file's settings (zoom, revision ids, math, note and colour settings) as they were.
    func testASaveKeepsTheFilesSettingsWhole() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        entries.removeAll { $0.name == "word/settings.xml" }
        entries.append(ZipEntry(name: "word/settings.xml", data: Data(original.utf8)))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let saved = try settings(of: try DocxFormat.write(doc, pageSetup: .letter))
        XCTAssertEqual(saved, original)
    }

    /// Only what the app sets changes: the default tab stop here.
    func testOnlyTheTabStopChanges() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        entries.removeAll { $0.name == "word/settings.xml" }
        entries.append(ZipEntry(name: "word/settings.xml", data: Data(original.utf8)))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.defaultTabStop = 18
        let saved = try settings(of: try DocxFormat.write(doc, pageSetup: .letter))
        XCTAssertEqual(saved, original.replacingAll("w:defaultTabStop w:val=\"720\"", with: "w:defaultTabStop w:val=\"360\""))
    }
}
