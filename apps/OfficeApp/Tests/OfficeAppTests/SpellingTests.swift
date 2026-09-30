// The Mac checker behind the red underline: it flags, it guesses, and
// what the user ignores stops being flagged.

import XCTest
import Flutter
@testable import OfficeApp

#if canImport(AppKit)
final class SpellingTests: XCTestCase {
    func testCocoaCheckerFlagsAndGuesses() {
        let checker = CocoaSpellChecker()
        XCTAssertEqual(checker.misspelledRanges(in: "teh cat sat"), [0 ..< 3])
        XCTAssertEqual(checker.misspelledRanges(in: "the cat sat"), [])
        XCTAssertTrue(checker.suggestions(for: "teh").contains("the"))
        let v = checker.version
        checker.ignore("teh")
        XCTAssertEqual(checker.misspelledRanges(in: "teh cat sat"), [])
        XCTAssertGreaterThan(checker.version, v)
    }
}
#endif
