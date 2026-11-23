// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// A cell's paragraph direction: its reading order, or with "context" the first strong letter. ar-1cbfc66b64's headers are
/// "فبراير\n.Feb" with no reading order, and Excel prints the second line "Feb." (right to left), not ".Feb".
final class SheetsReadingOrderTests: XCTestCase {
    func testContextTakesTheFirstStrongLetter() {
        let st = CellStyle()
        XCTAssertTrue(_cellIsRTL(st, "فبراير\n.Feb"))
        XCTAssertTrue(_cellIsRTL(st, "12 שלום"))
        XCTAssertFalse(_cellIsRTL(st, "Jan. يناير"))
        XCTAssertFalse(_cellIsRTL(st, "123"))
    }
    func testExplicitOrderWins() {
        var st = CellStyle(); st.readingOrder = 1
        XCTAssertFalse(_cellIsRTL(st, "يناير"))
        st.readingOrder = 2
        XCTAssertTrue(_cellIsRTL(st, "Jan."))
    }
}
