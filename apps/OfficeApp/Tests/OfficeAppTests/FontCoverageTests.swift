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

    private func cut(_ s: String) -> [(text: String, kind: Int)]? { RichLayout._variationPieces(Substring(s)) }

    /// A ZWJ sequence after a text-style emoji and U+FE0F is one piece with it: the rainbow flag
    /// (U+1F3F3 U+FE0F U+200D U+1F308) drew as a white flag and a rainbow when the cut fell after FE0F.
    func testAZWJSequenceAfterTheSelectorStaysInItsPiece() throws {
        let flag = "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}"
        let pieces = try XCTUnwrap(cut("a\(flag)b"))
        XCTAssertEqual(pieces.map(\.text), ["a", flag, "b"])
        XCTAssertEqual(pieces.map(\.kind), [0, 1, 0])
        // A heart on fire (U+2764 U+FE0F U+200D U+1F525), and a joined character with a selector of its own
        // (U+2640 U+FE0F after the ZWJ): each stays whole.
        let fire = "\u{2764}\u{FE0F}\u{200D}\u{1F525}"
        XCTAssertEqual(try XCTUnwrap(cut(fire)).map(\.text), [fire])
        let both = "\u{2764}\u{FE0F}\u{200D}\u{2640}\u{FE0F}x"
        XCTAssertEqual(try XCTUnwrap(cut(both)).map(\.text), ["\u{2764}\u{FE0F}\u{200D}\u{2640}\u{FE0F}", "x"])
        // A selector pair with no ZWJ after it is still cut off alone.
        XCTAssertEqual(try XCTUnwrap(cut("\u{2764}\u{FE0F}x")).map(\.text), ["\u{2764}\u{FE0F}", "x"])
    }
}
