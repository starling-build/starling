import XCTest
@testable import OfficeApp

/// `OfficeFonts.coverage`: the characters an embedded face's cmap maps
/// (formats 4 and 12) — the subset of zh-92373179's 仿宋_GB2312 holds 为
/// but not 规, and what it lacks Word sets in YaHei.
final class FontCoverageTests: XCTestCase {
    func testAFacesCmapIsReadAndABlobIsNot() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../sdk/Sources/FluentSystemIcons/Resources/Selawik-Regular.ttf").standardizedFileURL
        let covered = try XCTUnwrap(OfficeFonts.coverage(try Data(contentsOf: file)))
        XCTAssertTrue(covered.contains(0x41), "A")
        XCTAssertTrue(covered.contains(0x7A), "z")
        XCTAssertFalse(covered.contains(0x4E00), "一: a Latin face has no ideographs")
        XCTAssertNil(OfficeFonts.coverage(Data([0, 1, 0, 0])), "no table directory, no coverage")
    }
}
