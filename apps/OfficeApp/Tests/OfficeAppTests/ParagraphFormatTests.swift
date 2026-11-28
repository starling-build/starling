// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// W-PA-1: one controller call sets a paragraph's whole format, undoes in one step,
/// and survives a save.
final class ParagraphFormatTests: XCTestCase {
    func testFormatAppliesUndoesAndSurvivesSave() throws {
        let c = RichDocumentController(plainText: "one\ntwo")
        c.selectAll()
        c.setParagraphFormat(.init(alignment: .justify, indentLeft: 36, indentRight: 18,
                                   firstLineIndent: -18, spaceBefore: 6, spaceAfter: 12,
                                   lineRule: .exactly(20)))
        let s = c.document.paragraphs[1].style
        XCTAssertEqual(s.alignment, .justify)
        XCTAssertEqual(s.indentLeft, 36); XCTAssertEqual(s.firstLineIndent, -18)
        XCTAssertEqual(s.lineHeightPoints, 20); XCTAssertFalse(s.lineHeightIsMinimum)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        let b = back.paragraphs[0].style
        XCTAssertEqual(b.alignment, .justify); XCTAssertEqual(b.indentRight, 18)
        XCTAssertEqual(b.firstLineIndent, -18); XCTAssertEqual(b.spaceAfter, 12)
        XCTAssertEqual(b.lineHeightPoints, 20); XCTAssertFalse(b.lineHeightIsMinimum)
        c.setParagraphFormat(.init(lineRule: .multiple(1.5)))
        XCTAssertNil(c.document.paragraphs[0].style.lineHeightPoints)
        XCTAssertEqual(c.document.paragraphs[0].style.lineSpacing, 1.5)
        c.setParagraphFormat(.init(lineRule: .atLeast(30)))
        XCTAssertTrue(c.document.paragraphs[0].style.lineHeightIsMinimum)
        c.undo(); c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.lineHeightPoints, 20)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.indentLeft, 0)
    }

    /// W-PA-3: tab stops (position, kind, leader) set through the controller undo in one step and survive a save.
    func testTabStopsApplyUndoAndSurviveSave() throws {
        let c = RichDocumentController(plainText: "a\tb")
        var ed = TabStopEditor(stops: [])
        ed.set(at: 144, kind: .right, leader: .dots)
        ed.set(at: 72, kind: .decimal, leader: .none)
        ed.set(at: 216, kind: .bar, leader: .none)
        ed.set(at: 72.2, kind: .center, leader: .dashes)   // the same stop again: replaced, not added
        XCTAssertEqual(ed.stops.map(\.position), [72.2, 144, 216])
        c.setParagraphFormat(.init(tabStops: ed.stops))
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].style.tabStops
        XCTAssertEqual(back.map(\.position), [72.2, 144, 216])
        XCTAssertEqual(back.map { TabKind($0) }, [.center, .right, .bar])
        XCTAssertEqual(back.map { TabLeader($0) }, [.dashes, .dots, .none])
        ed.clear(at: 144); XCTAssertEqual(ed.stops.count, 2)
        ed.clearAll(); XCTAssertTrue(ed.stops.isEmpty)
        c.setParagraphFormat(.init(tabStops: []))
        XCTAssertTrue(c.document.paragraphs[0].style.tabStops.isEmpty)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[0].style.tabStops.count, 3, "one undo restores the stops")
        c.undo()
        XCTAssertTrue(c.document.paragraphs[0].style.tabStops.isEmpty)
    }
}

/// W-CH-2: one call sets a selection's whole character format, undoes in one step, and survives a save.
final class CharFormatTests: XCTestCase {
    func testFontDialogFormatAppliesUndoesAndSurvivesSave() throws {
        let c = RichDocumentController(plainText: "hello world")
        c.selectAll()
        var f = RichDocumentController.CharFormat(c.currentCharStyle)
        f.family = "Georgia"; f.size = 15; f.bold = true; f.doubleStrike = true
        f.smallCaps = true; f.spacing = 2; f.scale = 1.5; f.raised = 3; f.kerningFrom = 12
        c.setCharFormat(f)
        let r = c.document.paragraphs[0].runs[0].style
        XCTAssertEqual(r.fontFamily, "Georgia"); XCTAssertEqual(r.fontSize, 15)
        XCTAssertTrue(r.bold); XCTAssertTrue(r.doubleStrike); XCTAssertTrue(r.smallCaps)
        XCTAssertEqual(r.letterSpacing, 2); XCTAssertEqual(r.horizontalScale, 1.5)
        XCTAssertEqual(r.raised, 3); XCTAssertEqual(r.kerningFrom, 12)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        let b = back.paragraphs[0].runs[0].style
        XCTAssertEqual(b.fontFamily, "Georgia"); XCTAssertEqual(b.fontSize, 15)
        XCTAssertTrue(b.doubleStrike); XCTAssertTrue(b.smallCaps)
        XCTAssertEqual(b.letterSpacing, 2); XCTAssertEqual(b.horizontalScale, 1.5); XCTAssertEqual(b.raised, 3)
        if let out = ProcessInfo.processInfo.environment["FONT_DIALOG_OUT"] {   // for a Word open check
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
        }
        c.undo()
        XCTAssertNil(c.document.paragraphs[0].runs[0].style.fontFamily)
        XCTAssertFalse(c.document.paragraphs[0].runs[0].style.bold)
    }
}

/// W-PA-1e: the Paragraph dialog's "Don't add space between paragraphs of the same style" (w:contextualSpacing).
final class ContextualSpacingTests: XCTestCase {
    func testDialogBoxAppliesUndoesAndSurvivesSave() throws {
        let c = RichDocumentController(plainText: "one\ntwo")
        c.selectAll()
        var v = ParagraphDialogValues(c.document.paragraphs[0].style)
        XCTAssertFalse(v.contextual)
        v.contextual = true
        c.setParagraphFormat(v.format)
        XCTAssertTrue(c.document.paragraphs[0].style.contextualSpacing)
        XCTAssertTrue(c.document.paragraphs[1].style.contextualSpacing)
        XCTAssertTrue(ParagraphDialogValues(c.document.paragraphs[1].style).contextual, "the dialog shows the box ticked")
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[1].style.contextualSpacing)
        c.undo()
        XCTAssertFalse(c.document.paragraphs[0].style.contextualSpacing, "one undo step")
        // A format that does not name the box leaves it alone.
        c.setParagraphFormat(.init(contextualSpacing: true))
        c.setParagraphFormat(.init(alignment: .center))
        XCTAssertTrue(c.document.paragraphs[0].style.contextualSpacing)
    }

    /// A paragraph whose style turns the spacing rule on, with the box cleared, keeps it off after a save.
    func testClearedUnderAStyleThatSetsItStaysOff() throws {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        func replace(_ n: String, _ f: (String) -> String) throws {
            let i = try XCTUnwrap(parts.firstIndex { $0.name == n })
            parts[i] = ZipEntry(name: n, data: Data(f(String(decoding: parts[i].data, as: UTF8.self)).utf8))
        }
        try replace("word/styles.xml") {
            $0.replacingOccurrences(of: "</w:styles>", with: "<w:style w:type=\"paragraph\" w:styleId=\"Tight\"><w:name w:val=\"Tight\"/>"
                + "<w:basedOn w:val=\"Normal\"/><w:pPr><w:contextualSpacing/></w:pPr></w:style></w:styles>")
        }
        try replace("word/document.xml") { s in
            var x = s
            x.insert(contentsOf: "<w:p><w:pPr><w:pStyle w:val=\"Tight\"/></w:pPr><w:r><w:t>one</w:t></w:r></w:p>",
                     at: x.range(of: "<w:body>")!.upperBound)
            return x
        }
        let read = try DocxFormat.read(try Zip.write(parts))
        let c = RichDocumentController(document: read.document)
        XCTAssertTrue(c.document.paragraphs[0].style.contextualSpacing, "the style's rule reaches the paragraph")
        var v = ParagraphDialogValues(c.document.paragraphs[0].style)
        XCTAssertTrue(v.contextual)
        v.contextual = false
        c.setParagraphFormat(v.format)
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertFalse(back.paragraphs[0].style.contextualSpacing)
    }
}

/// W-PA-2: the Line and Page Breaks settings survive a save, and an untouched box leaves each paragraph's own.
final class LineAndPageBreaksTests: XCTestCase {
    func testBreakSettingsSurviveSave() throws {
        let c = RichDocumentController(plainText: "one\ntwo\nthree")
        c.selectAll()
        c.setParagraphFormat(.init(widowControl: false, keepNext: true, keepLines: true, pageBreakBefore: true,
                                   suppressLineNumbers: true, noHyphenation: true))
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        if let out = ProcessInfo.processInfo.environment["PA2_OUT"] {   // the Word lab
            try data.write(to: URL(fileURLWithPath: out))
        }
        let xml = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        for tag in ["<w:keepNext/>", "<w:keepLines/>", "<w:pageBreakBefore/>", "<w:widowControl w:val=\"0\"/>",
                    "<w:suppressLineNumbers w:val=\"1\"/>", "<w:suppressAutoHyphens w:val=\"1\"/>"] {
            XCTAssertTrue(xml.contains(tag), tag)
        }
        let b = try DocxFormat.read(data).document.paragraphs[1].style
        XCTAssertFalse(b.widowControl); XCTAssertTrue(b.keepNext); XCTAssertTrue(b.keepLines); XCTAssertTrue(b.pageBreakBefore)
        XCTAssertEqual(b.eastAsian["w:suppressLineNumbers"], "1"); XCTAssertEqual(b.eastAsian["w:suppressAutoHyphens"], "1")
        // Cleared again: off, and said off where it had been said on.
        c.setParagraphFormat(.init(widowControl: true, keepNext: false, keepLines: false, pageBreakBefore: false,
                                   suppressLineNumbers: false, noHyphenation: false))
        let o = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[1].style
        XCTAssertTrue(o.widowControl); XCTAssertFalse(o.keepNext); XCTAssertFalse(o.pageBreakBefore)
        XCTAssertNotEqual(o.eastAsian["w:suppressAutoHyphens"], "1")
    }

    func testUntouchedBoxesLeaveEachParagraph() {
        var d = RichDocumentController(plainText: "one\ntwo").document
        d.paragraphs[1].style.pageBreakBefore = true
        let c = RichDocumentController(document: d)
        c.selectAll()
        let base = ParagraphDialogValues(c.document.paragraphs[0].style)
        var v = base
        v.keepLines = true
        c.setParagraphFormat(v.format(since: base))
        XCTAssertTrue(c.document.paragraphs[1].style.pageBreakBefore, "the second paragraph's page break stays")
        XCTAssertTrue(c.document.paragraphs[0].style.keepLines && c.document.paragraphs[1].style.keepLines)
    }

    /// A file whose style turns widow control off keeps it off through a save (no stray <w:widowControl/>);
    /// ticked in the dialog, the paragraph says it on over its style.
    func testWidowControlUnderAStyleThatTurnsItOff() throws {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        func replace(_ n: String, _ f: (String) -> String) throws {
            let i = try XCTUnwrap(parts.firstIndex { $0.name == n })
            parts[i] = ZipEntry(name: n, data: Data(f(String(decoding: parts[i].data, as: UTF8.self)).utf8))
        }
        try replace("word/styles.xml") {
            $0.replacingOccurrences(of: "</w:styles>", with: "<w:style w:type=\"paragraph\" w:styleId=\"Loose\"><w:name w:val=\"Loose\"/>"
                + "<w:basedOn w:val=\"Normal\"/><w:pPr><w:widowControl w:val=\"0\"/></w:pPr></w:style></w:styles>")
        }
        try replace("word/document.xml") { s in
            var x = s
            x.insert(contentsOf: "<w:p><w:pPr><w:pStyle w:val=\"Loose\"/></w:pPr><w:r><w:t>one</w:t></w:r></w:p>",
                     at: x.range(of: "<w:body>")!.upperBound)
            return x
        }
        let c = RichDocumentController(document: try DocxFormat.read(try Zip.write(parts)).document)
        XCTAssertFalse(c.document.paragraphs[0].style.widowControl, "the style's setting reaches the paragraph")
        func saved() throws -> String {
            String(decoding: try XCTUnwrap(Zip.read(DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        }
        XCTAssertFalse(try saved().contains("<w:widowControl/>"), "an untouched paragraph says nothing new")
        var v = ParagraphDialogValues(c.document.paragraphs[0].style)
        let base = v
        v.widow = true
        c.setParagraphFormat(v.format(since: base))
        XCTAssertTrue(try saved().contains("<w:widowControl/>"))
        XCTAssertTrue(try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document.paragraphs[0].style.widowControl)
    }
}
