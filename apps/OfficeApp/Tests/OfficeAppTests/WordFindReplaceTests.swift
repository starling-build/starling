// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeText

/// W-ED-2: Word's Find and Replace — ^ codes, wildcard groups and counts, the prefix/suffix and
/// ignore options, and Format on both sides.
final class WordFindReplaceTests: XCTestCase {
    private func hits(_ q: String, _ text: String, _ o: FindOptions = FindOptions()) throws -> [String] {
        let p = try TextPattern(q, o)
        return p.matches(in: text).map { String(text[$0.range]) }
    }

    private func texts(_ c: RichDocumentController) -> [String] { c.document.paragraphs.map(\.text) }

    func testSpecialCharacters() throws {
        XCTAssertEqual(try hits("a^tb", "a\tb ab"), ["a\tb"])
        XCTAssertEqual(try hits("^#^#", "x 12 y 3"), ["12"])
        XCTAssertEqual(try hits("^$^$", "ab 1 c"), ["ab"])
        XCTAssertEqual(try hits("a^?c", "abc a1c ac"), ["abc", "a1c"])
        XCTAssertEqual(try hits("a^wb", "a   b ab a\tb"), ["a   b", "a\tb"])
        XCTAssertEqual(try hits("^s", "a\u{00A0}b"), ["\u{00A0}"])
        XCTAssertEqual(try hits("^^", "a^b"), ["^"])
        XCTAssertEqual(try hits("^0101", "Tea"), ["e"])
        XCTAssertTrue(try TextPattern("a^pb", FindOptions()).spansParagraphs)
        XCTAssertFalse(try TextPattern("a^tb", FindOptions()).spansParagraphs)
        XCTAssertThrowsError(try TextPattern("a^p", FindOptions(mode: .wildcards)))
    }

    func testWildcardGroupsAndCounts() throws {
        let o = FindOptions(mode: .wildcards)
        XCTAssertEqual(try hits("lo@t", "lot loot lt", o), ["lot", "loot"])
        XCTAssertEqual(try hits("[0-9]{3}", "12 345 6789", o), ["345", "678"])
        XCTAssertEqual(try hits("[0-9]{2,}", "1 22 333", o), ["22", "333"])
        XCTAssertEqual(try hits("x{1,2}y", "y xy xxy", o), ["xy", "xxy"])
        let p = try TextPattern("(<[A-Z][a-z]@) (<[A-Z][a-z]@)", FindOptions(matchCase: true, mode: .wildcards))
        let text = "Ada Lovelace"
        let m = try XCTUnwrap(p.matches(in: text).first)
        XCTAssertEqual(p.replacement("\\2, \\1", for: m, in: text), "Lovelace, Ada")
        XCTAssertThrowsError(try TextPattern("(ab", o))
    }

    func testReplacementCodes() throws {
        let p = try TextPattern("cat", FindOptions())
        let text = "cat"
        let m = try XCTUnwrap(p.matches(in: text).first)
        XCTAssertEqual(p.replacement("[^&]^t", for: m, in: text), "[cat]\t")
        XCTAssertEqual(p.replacement("a^pb", for: m, in: text), "a\u{2029}b")
        XCTAssertEqual(p.replacement("^m", for: m, in: text), "\u{000C}")
        XCTAssertNotNil(TextPattern.replacementProblem("^w", .plain))
        XCTAssertNil(TextPattern.replacementProblem("^p^t^&", .plain))
    }

    func testPrefixSuffixAndIgnore() throws {
        XCTAssertEqual(try hits("pre", "prefix spree pre", FindOptions(matchPrefix: true)).count, 2)
        XCTAssertEqual(try hits("ing", "sing ingot ring", FindOptions(matchSuffix: true)).count, 2)
        XCTAssertEqual(try hits("dont", "don't dont", FindOptions(ignorePunctuation: true)), ["don't", "dont"])
        XCTAssertEqual(try hits("ab", "a b ab", FindOptions(ignoreSpace: true)), ["a b", "ab"])
    }

    /// ^p^p to ^p takes out the empty paragraphs between paragraphs; one undo step.
    func testReplaceParagraphMarks() throws {
        let c = RichDocumentController(plainText: "one\n\ntwo\n\nthree")
        let before = c.document
        let p = try TextPattern("^p^p", FindOptions())
        XCTAssertEqual(c.countMatches(p), 2)
        XCTAssertEqual(c.replaceAll(p, with: "^p"), 2)
        XCTAssertEqual(texts(c), ["one", "two", "three"])
        c.undo()
        XCTAssertEqual(c.document, before)
        // And a tab between words becomes a paragraph break.
        let d = RichDocumentController(plainText: "a\tb")
        XCTAssertEqual(d.replaceAll(try TextPattern("^t", FindOptions()), with: "^p"), 1)
        XCTAssertEqual(texts(d), ["a", "b"])
    }

    /// Find Next across a paragraph mark selects into the next paragraph.
    func testFindAcrossParagraphs() throws {
        let c = RichDocumentController(plainText: "end\nstart")
        let s = try XCTUnwrap(c.find(try TextPattern("d^ps", FindOptions())))
        XCTAssertEqual(s.start, RichPosition(paragraph: 0, offset: 2))
        XCTAssertEqual(s.end, RichPosition(paragraph: 1, offset: 1))
    }

    /// Format: find only the bold "cat", replace it with plain-italic "dog"; and find any bold
    /// text (no words) to make it underlined.
    func testFindAndReplaceFormat() throws {
        let c = RichDocumentController(plainText: "cat cat cat")
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: false); c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: true)
        c.toggleBold()
        let p = try TextPattern("cat", FindOptions())
        let bold = FindFormat(bold: true)
        XCTAssertEqual(c.countMatches(p), 3)
        XCTAssertEqual(c.countMatches(p, format: bold), 1)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        let s = try XCTUnwrap(c.find(p, format: bold))
        XCTAssertEqual(s.start.offset, 4)
        XCTAssertEqual(c.replaceAll(p, with: "dog", format: bold, replaceFormat: FindFormat(bold: false, italic: true)), 1)
        XCTAssertEqual(texts(c), ["cat dog cat"])
        XCTAssertEqual(c.document.paragraphs[0].style(at: 5).italic, true)
        XCTAssertEqual(c.document.paragraphs[0].style(at: 5).bold, false)
        XCTAssertEqual(c.document.paragraphs[0].style(at: 1).italic, false)

        let d = RichDocumentController(plainText: "plain bold plain")
        d.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false); d.moveTo(RichPosition(paragraph: 0, offset: 10), extend: true)
        d.toggleBold()
        let any = TextPattern.anyText(FindOptions())
        XCTAssertEqual(d.countMatches(any, format: bold), 1)
        XCTAssertEqual(d.replaceAll(any, with: "", format: bold, replaceFormat: FindFormat(underline: true)), 1)
        XCTAssertEqual(texts(d), ["plain bold plain"], "an empty Replace with and a format only reformats")
        XCTAssertEqual(d.document.paragraphs[0].style(at: 7).underline, true)
        XCTAssertEqual(d.document.paragraphs[0].style(at: 2).underline, false)
    }

    /// A paragraph style on Find narrows to paragraphs of that style.
    func testFindParagraphStyle() throws {
        let c = RichDocumentController(plainText: "Title x\nbody x")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.setNamedStyle(RichNamedStyle.headingId(1))
        let p = try TextPattern("x", FindOptions())
        XCTAssertEqual(c.countMatches(p, format: FindFormat(paragraphStyle: RichNamedStyle.headingId(1))), 1)
        XCTAssertEqual(FindFormat(bold: true, italic: false, fontSize: 12, paragraphStyle: "H").describe(),
                       "Font: 12 pt, Bold, Not Italic; Style: H")
    }
}
