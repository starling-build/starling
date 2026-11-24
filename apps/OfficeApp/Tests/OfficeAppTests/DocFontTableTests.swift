// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// The .doc font table (SttbfFfn) written to word/fontTable.xml: a Hangul face keeps its charset and family
/// (the layout prints an absent Korean serif in Batang from it); a Latin-named face with a blank PANOSE and a
/// Western charset (Word's own "TimesNewRoman, Arial,Bold" artefact) is left out.
final class DocFontTableTests: XCTestCase {
    /// One FFN: length byte, family in the high bits of byte 1, charset at 4, PANOSE at 6..15, name (UTF-16, NUL) at 40.
    private func ffn(_ name: String, charset: UInt8, family: UInt8, panose: [UInt8]) -> [UInt8] {
        let units = Array(name.utf16) + [0]
        var b = [UInt8](repeating: 0, count: 40)   // index 0 is the length byte
        b[1] = family << 4
        b[4] = charset
        b[5] = 1
        for (i, v) in panose.enumerated() { b[6 + i] = v }
        for u in units { b.append(UInt8(u & 0xFF)); b.append(UInt8(u >> 8)) }
        b[0] = UInt8(b.count - 1)
        return b
    }

    private func table(_ faces: [[UInt8]]) -> [UInt8] {
        [0, 0, 0, 0] + faces.flatMap { $0 }
    }

    func testHangulFaceKeepsCharsetAndFamily() throws {
        let t = table([ffn("한컴바탕", charset: 0x81, family: 1, panose: [2, 3, 6, 0, 0, 1, 1, 1, 1, 1])])
        let xml = try XCTUnwrap(DocProps.fontTable(t, at: 0, count: t.count, ns: "xmlns:w=\"w\""))
        XCTAssertTrue(xml.contains("w:name=\"한컴바탕\""), xml)
        XCTAssertTrue(xml.contains("<w:charset w:val=\"81\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:family w:val=\"roman\"/>"), xml)
    }

    func testLatinNamedFaceWithBlankPanoseAndWesternCharsetIsLeftOut() throws {
        let t = table([
            ffn("TimesNewRoman,Bold", charset: 0, family: 0, panose: [UInt8](repeating: 0, count: 10)),
            ffn("Arial", charset: 0, family: 2, panose: [2, 11, 6, 4, 2, 2, 2, 2, 2, 4]),
        ])
        let xml = try XCTUnwrap(DocProps.fontTable(t, at: 0, count: t.count, ns: "xmlns:w=\"w\""))
        XCTAssertFalse(xml.contains("TimesNewRoman"), xml)
        XCTAssertTrue(xml.contains("w:name=\"Arial\""), xml)
    }

    func testLatinNamedFaceWithShiftJisCharsetIsLeftOut() throws {
        let t = table([
            ffn("Arial Unicode MS", charset: 0x80, family: 2, panose: [2, 11, 6, 4, 2, 2, 2, 2, 2, 4]),
            ffn("MS-Mincho", charset: 0x80, family: 1, panose: [2, 2, 6, 9, 4, 2, 5, 8, 3, 4]),
        ])
        let xml = try XCTUnwrap(DocProps.fontTable(t, at: 0, count: t.count, ns: "xmlns:w=\"w\""))
        XCTAssertFalse(xml.contains("Arial Unicode"), xml)
        XCTAssertTrue(xml.contains("MS-Mincho"), xml)
    }
}
