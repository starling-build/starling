// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// Guard: layout rules taken from binary .doc prints (a header taller than its
/// margin pushes margin-anchored header pictures down) must not reach .docx.
final class DocxHeaderGateTests: XCTestCase {
    func testDocxIsNotMarkedBinaryDoc() throws {
        let data = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter)
        let opened = try OfficeFormats.read(data, named: "a.docx")
        XCTAssertFalse(opened.document.fromBinaryDoc)
    }
}
