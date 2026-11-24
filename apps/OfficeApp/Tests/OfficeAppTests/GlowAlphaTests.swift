// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// w14:alpha on a text glow is TRANSPARENCY (Word: Glow.Transparency 0.4 for 40000), unlike a:alpha.
final class GlowAlphaTests: XCTestCase {
    private func read(_ alpha: Int) throws -> CharStyle {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let i = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        parts[i] = ZipEntry(name: "word/document.xml", data: Data((
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\"><w:body><w:p><w:r><w:rPr><w:rPr/>"
            + "<w14:glow w14:rad=\"63500\"><w14:srgbClr w14:val=\"FFC000\"><w14:alpha w14:val=\"\(alpha)\"/></w14:srgbClr></w14:glow>"
            + "</w:rPr><w:t>glow</w:t></w:r></w:p></w:body></w:document>").utf8))
        return try DocxFormat.read(Zip.write(parts)).document.paragraphs[0].runs[0].style
    }

    func testGlowAlphaIsTransparency() throws {
        let s = try XCTUnwrap(read(40000).shadow)
        XCTAssertEqual(Double(s.color.alpha) / 255, 0.6, accuracy: 0.01)
        XCTAssertNil(try read(100000).shadow)
    }
}
