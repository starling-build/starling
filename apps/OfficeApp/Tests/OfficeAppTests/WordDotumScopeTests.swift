// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

/// The Dotum and Gulim advance tables are Excel's own: a face Word's machine lacks whose font table names Dotum as its alternate keeps the
/// Word path's widths and is not given the Sheets table (dx2 0b3859a7 went 100 to 50 with it).
final class WordDotumScopeTests: XCTestCase {
    func testAlternateDotumDoesNotTakeTheSheetsTableInWord() throws {
        let was = OfficeFonts.wordOnWindows
        OfficeFonts.wordOnWindows = true
        OfficeFonts.noteFontEntries(["starling absent face": OfficeFonts.FontEntry(alt: "Dotum", family: "swiss", panoseZero: false)])
        defer { OfficeFonts.noteFontEntries([:]); OfficeFonts.wordOnWindows = was }
        let f = try XCTUnwrap(OfficeFonts.face("Starling Absent Face", eastAsian: false))
        var tabled = f
        OfficeFonts.applyTabled("Dotum", to: &tabled)
        XCTAssertNotEqual(f.advances, tabled.advances, "the face was given Excel's Dotum widths")
    }
}
