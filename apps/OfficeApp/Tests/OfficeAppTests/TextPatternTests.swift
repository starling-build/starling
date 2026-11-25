// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeText

final class TextPatternTests: XCTestCase {
    private func hits(_ q: String, _ text: String, _ o: FindOptions = FindOptions()) throws -> [String] {
        let p = try TextPattern(q, o)
        return p.matches(in: text).map { String(text[$0.range]) }
    }

    func testPlainIgnoresCaseUnlessAsked() throws {
        XCTAssertEqual(try hits("cat", "Cat cat CAT"), ["Cat", "cat", "CAT"])
        XCTAssertEqual(try hits("cat", "Cat cat CAT", FindOptions(matchCase: true)), ["cat"])
    }

    func testWholeWordSkipsInsideWords() throws {
        let o = FindOptions(wholeWord: true)
        XCTAssertEqual(try hits("cat", "cat concat cats cat.", o).count, 2)
    }

    func testEntireCellNeedsTheWholeText() throws {
        let o = FindOptions(entireCell: true)
        XCTAssertEqual(try hits("abc", "abc", o), ["abc"])
        XCTAssertEqual(try hits("abc", "abcd", o), [])
        XCTAssertEqual(try hits("abc", "xabc", o), [])
    }

    func testWildcards() throws {
        let o = FindOptions(mode: .wildcards)
        XCTAssertEqual(try hits("c?t", "cat cot cut cart", o), ["cat", "cot", "cut"])
        XCTAssertEqual(try hits("c*t", "cat cart", o), ["cat", "cart"])
        XCTAssertEqual(try hits("[bc]at", "bat cat rat", o), ["bat", "cat"])
        XCTAssertEqual(try hits("[!b]at", "bat cat rat", o), ["cat", "rat"])
        XCTAssertEqual(try hits("\\?", "what? yes", o), ["?"])
        XCTAssertEqual(try hits("<an", "an and band", o), ["an", "an"])
    }

    func testRegex() throws {
        let o = FindOptions(mode: .regex)
        XCTAssertEqual(try hits("\\d+", "a12 b345", o), ["12", "345"])
        XCTAssertEqual(try hits("(ab|cd)+", "abcdab x", o), ["abcdab"])
        XCTAssertEqual(try hits("a{2,3}", "a aa aaaa", o), ["aa", "aaa"])
        XCTAssertEqual(try hits("<.+?>", "<a><b>", o), ["<a>", "<b>"])
        XCTAssertEqual(try hits("\\bfoo\\b", "foo food foo", o), ["foo", "foo"])
        XCTAssertEqual(try hits("^x", "x\nx\ny", o), ["x", "x"])
    }

    func testRegexReplacementUsesGroups() throws {
        let o = FindOptions(mode: .regex)
        let text = "2026-11-25"
        let p = try TextPattern("(\\d+)-(\\d+)-(\\d+)", o)
        let m = try XCTUnwrap(p.matches(in: text).first)
        XCTAssertEqual(p.replacement("$3/$2/$1 ($&) $$", for: m, in: text), "25/11/2026 (2026-11-25) $")
    }

    func testBadPatternsExplainThemselves() {
        let o = FindOptions(mode: .regex)
        XCTAssertNotNil(TextPattern.problem("(ab", o))
        XCTAssertNotNil(TextPattern.problem("*a", o))
        XCTAssertNotNil(TextPattern.problem("[a", o))
        XCTAssertNil(TextPattern.problem("a(b)c", o))
        XCTAssertNotNil(TextPattern.problem("", FindOptions()))
    }

    func testBackwardsFindsTheLastMatchBeforeThePoint() throws {
        let text = "ab ab ab"
        let p = try TextPattern("ab", FindOptions())
        let from = text.index(text.startIndex, offsetBy: 6)
        let m = try XCTUnwrap(p.firstMatch(in: text, from: from, backwards: true))
        XCTAssertEqual(text.distance(from: text.startIndex, to: m.range.lowerBound), 3)
        let f = try XCTUnwrap(p.firstMatch(in: text, from: text.index(after: text.startIndex)))
        XCTAssertEqual(text.distance(from: text.startIndex, to: f.range.lowerBound), 3)
    }

    func testCombiningMarksStayWithTheirLetter() throws {
        XCTAssertEqual(try hits("e", "e\u{301} e").count, 1)   // é is not an e
    }

    func testRunawayPatternGivesUpInsteadOfHanging() throws {
        let o = FindOptions(mode: .regex)
        _ = try hits("(a+)+b", String(repeating: "a", count: 40), o)
    }
}
