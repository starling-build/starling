// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class AbsentSymbolBulletLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// es-3b20b19c25: a ● bullet whose face is Noto Sans Symbols (absent on Windows) is drawn in the text's own face
    /// in Word's print; the absent face's taller ascent must not lift the item's first line (Word's bullets over
    /// Times 12 at 1.15 stood 12.03 apart; ours 21).
    func testAnAbsentSymbolFaceBulletDoesNotLiftItsLine() throws {
        _ = OfficeFonts.register()
        func firstBaseline(face: String?) throws -> Double {
            var p = RichParagraph(text: "item one of the list")
            p.style.list = .bullet; p.style.listId = "7"; p.style.listLevel = 0
            var doc = RichDocument(paragraphs: [p])
            var level = ListLevelFormat(text: "\u{25CF}", format: .bullet)
            if let face { level.numberRPrXML = "<w:rPr><w:rFonts w:ascii=\"\(face)\" w:hAnsi=\"\(face)\"/></w:rPr>" }
            doc.listFormats["7"] = [0: level]
            let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            // (The face is absent from the test fonts: stand it in with a taller one, as it stands taller than Times in Word's engine.)
            theme.faceResolver = { OfficeFonts.face(($0 ?? "").lowercased().hasPrefix("noto sans symbols") ? "Arial Black" : $0, eastAsian: $1) }
            let layout = RichLayout(theme: theme, paragraphCount: back.paragraphs.count)
            layout.width = 300
            layout.ensureLaidOut(back)
            let g = layout.geometry(0)
            return (g.painter.computeLineMetrics()[0].baseline + g.inkShift) / theme.pixelsPerPoint
        }
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        let plain = try firstBaseline(face: nil)
        let noto = try firstBaseline(face: "Noto Sans Symbols")
        XCTAssertEqual(noto, plain, accuracy: 0.3, "noto \(noto) plain \(plain)")
    }
}
