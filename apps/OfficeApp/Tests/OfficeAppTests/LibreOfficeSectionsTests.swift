// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Two LibreOffice files whose pages Word's print gives otherwise than ours did
/// (tdf149555, tdf108272): a page break kept before a continuous section that changes the
/// vertical margins, and a table placed against the page opening a header. (tdf146248's
/// right tab after a line break is not here: its test passed on the unfixed code in this
/// harness, so it proved nothing; the corpus score is its evidence.)
final class LibreOfficeSectionsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func laidOut(_ id: String) throws -> (RichLayout, RichDocument) {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/\(id).docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let parsed = try DocxFormat.read(data)
        // (As `--convert` sets its theme: the faces the layout measures in.)
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.drawn
        theme.faceResolver = OfficeFonts.face
        theme.complexFaceResolver = OfficeFonts.complexFace
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        theme.disablesLigatures = true
        let layout = RichLayout(theme: theme, paragraphCount: parsed.document.paragraphs.count)
        let setup = parsed.pageSetup ?? .letter
        layout.pageSetup = setup
        layout.width = setup.width * 96.0 / 72.0
        layout.ensureLaidOut(parsed.document)
        return (layout, parsed.document)
    }

    /// tdf149555: "Seriously" ends its section with a page break, and the continuous section
    /// after it has 1422 twips on top for 5982. Word's contents begin page 2 (four pages in
    /// all); with the same margins on both sides the break is still the section's own
    /// (zh-e2dc9dce), but here it stays.
    func testPageBreakBeforeAContinuousSectionOfOtherMarginsStays() throws {
        // (The rule that drops a section's own page break is Word for Windows' only: run
        // with OFFICE_WORD_FONTS=windows, as the corpus sweeps do, for this to bite.)
        try XCTSkipUnless(DocxFormat.wordOnWindows, "needs OFFICE_WORD_FONTS=windows")
        XCTAssertEqual(try laidOut("lo-abef832121138674").0.pageCount, 4)
    }

    /// tdf108272: the default header is a table placed against the page, 400 twips down,
    /// and Word opens it there (20pt), not at the header distance (36pt): the body below it
    /// starts 42pt down in its print, 16pt above where the header distance put it.
    func testHeaderTablePlacedAgainstThePageStandsThere() throws {
        let (layout, doc) = try laidOut("lo-198cd20047e25c50")
        let top = layout.canvasRects(layout.caretRect(RichPosition(paragraph: 0, offset: 0), doc))[0].top / 96.0 * 72.0
        XCTAssertEqual(top, 41.5, accuracy: 1.5)
    }
}
