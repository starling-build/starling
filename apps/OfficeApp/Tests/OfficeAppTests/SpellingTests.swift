// The Mac checker behind the red underline: it flags, it guesses, and
// what the user ignores stops being flagged.

import XCTest
import Flutter
@testable import OfficeApp
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
final class SpellingTests: XCTestCase {
    func testCocoaCheckerFlagsAndGuesses() throws {
        let checker = CocoaSpellChecker()
        try XCTSkipUnless(NSSpellChecker.shared.language().hasPrefix("en"), "needs an English spelling language")
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
