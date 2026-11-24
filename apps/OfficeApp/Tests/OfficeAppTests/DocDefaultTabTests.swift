// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

final class DocDefaultTabTests: XCTestCase {
    /// The .doc reader writes the DOP's default tab stop into a settings part that holds nothing else.
    /// That part is read for its tab distance (708 twips = 35.4 pt) and still counts as "no settings" for
    /// the East Asian rules, as a .doc without one did.
    func testABareTabOnlySettingsPartSetsTheTabDistanceAndKeepsTheLegacyRules() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        entries.removeAll { $0.name == "word/settings.xml" }
        let settings = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:defaultTabStop w:val=\"708\"/></w:settings>"
        entries.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(try XCTUnwrap(doc.defaultTabStop), 35.4, accuracy: 0.01)
        XCTAssertTrue(doc.usesEastAsianLayout)
    }
}
