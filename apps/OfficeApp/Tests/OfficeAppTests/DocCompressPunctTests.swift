import XCTest
@testable import OfficeApp

/// A binary file's document properties say whether East Asian punctuation is compressed (the first bit of the
/// typography block at byte 90). ja-d68afa9ee6 sets it; Word closes up 、 before kana and a justified line holds one more mark.
final class DocCompressPunctTests: XCTestCase {
    func testTypographyBitReachesTheSettings() {
        var dop = [UInt8](repeating: 0, count: 120)
        XCTAssertFalse(DocRead.compressesPunctuation(dop: dop))
        dop[90] = 3
        XCTAssertTrue(DocRead.compressesPunctuation(dop: dop))
        XCTAssertTrue(DocRead.settingsXML(facing: false, compressPunct: true).contains("<w:characterSpacingControl w:val=\"compressPunctuation\"/>"))
        XCTAssertFalse(DocRead.settingsXML(facing: false).contains("characterSpacingControl"))
        XCTAssertFalse(DocRead.compressesPunctuation(dop: [UInt8](repeating: 1, count: 60)))
    }
}
