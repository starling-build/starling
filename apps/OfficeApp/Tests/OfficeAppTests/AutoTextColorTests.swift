// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Word's automatic text colour over a shaded cell: white or black, cut at luminance 59 (Word print of autocolor.docx, 40 cells).

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

final class AutoTextColorTests: XCTestCase {
    private func white(_ rgb: Int64) -> Bool { RichTextTheme.autoTextIsWhite(on: Color(0xFF000000 | rgb)) }

    func testWordsWhiteAndBlackCellsOfTheAutocolorPrint() {
        for rgb: Int64 in [0x000000, 0x333333, 0xB20000, 0x0000E6, 0x1F3864, 0x80007F, 0xC00000] {
            XCTAssertTrue(white(rgb), String(rgb, radix: 16))
        }
        for rgb: Int64 in [0x4C4C4C, 0xE60000, 0x7030A0, 0x2E74B5, 0x7300E6, 0xFFFFFF, 0x808080] {
            XCTAssertFalse(white(rgb), String(rgb, radix: 16))
        }
    }
}
