import XCTest
@testable import OfficeApp
@testable import OfficeText

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

    /// An embedded Arabic face (dx2 7e49187f: DecoType Naskh) must not load as a "Latin" stand-in
    /// (text in it shaped with no glyphs and Skia's cluster() trapped); garbage and truncated data never load.
    func testOnlyAFaceMappingTheLatinLettersIsALatinFace() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../sdk/Sources/FluentSystemIcons/Resources/Selawik-Regular.ttf").standardizedFileURL
        let latin = try Data(contentsOf: file)
        XCTAssertTrue(OfficeFonts.coversLatinLetters(latin))
        XCTAssertFalse(OfficeFonts.coversLatinLetters(Data(latin.prefix(200))), "truncated")
        XCTAssertFalse(OfficeFonts.coversLatinLetters(Data(repeating: 0xAB, count: 4000)), "garbage")
        XCTAssertFalse(OfficeFonts.coversLatinLetters(Data()))
        if let arabic = ["/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf", "/usr/share/fonts/truetype/noto/NotoKufiArabic-Regular.ttf"]
            .compactMap({ try? Data(contentsOf: URL(fileURLWithPath: $0)) }).first {
            XCTAssertFalse(OfficeFonts.coversLatinLetters(arabic), "an Arabic face is not a Latin one")
        }
    }
}

/// U+FE0F turns a text-style emoji to colour and U+FE0E a colour one to an outline, as Word and PowerPoint draw them.
final class EmojiVariationTests: XCTestCase {
    func testVariationSelectorsCutTheTextAtTheirBase() throws {
        // ❤ + FE0F: colour; a bare ❤ is not cut; ⌚ + FE0E: outline; a base that is not an emoji is not cut.
        let pieces = try XCTUnwrap(RichLayout._variationPieces("a\u{2764}\u{FE0F}b\u{2764}\u{231A}\u{FE0E}c"))
        XCTAssertEqual(pieces.map(\.kind), [0, 1, 0, 2, 0])
        XCTAssertEqual(pieces.map(\.text), ["a", "\u{2764}\u{FE0F}", "b\u{2764}", "\u{231A}\u{FE0E}", "c"])
        XCTAssertNil(RichLayout._variationPieces("a\u{2764}b"), "no selector, no cut")
        XCTAssertNil(RichLayout._variationPieces("a\u{FE0F}"), "a letter takes no colour")
        XCTAssertNil(RichLayout._variationPieces("a\u{A9}\u{FE0F} \u{2122}\u{FE0F} \u{203C}\u{FE0F}"), "(c) (tm) !! stay text in Word and PowerPoint")
        XCTAssertNil(RichLayout._variationPieces("\u{231A}\u{FE0F}"), "a colour emoji needs nothing from FE0F")
    }
}
