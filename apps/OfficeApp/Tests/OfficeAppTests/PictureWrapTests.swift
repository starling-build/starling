// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-OB-3: the wrap choice and the nudge of a floating picture, read from a file, changed, undone and saved.
final class PictureWrapTests: XCTestCase {
    /// Line breaking needs ICU's data in the text engine; without it a whole paragraph lays out as one line. Loaded before
    /// every test (once per process; later calls are free), since a run filtered to these classes may not start with
    /// `AAATextSetupTests`, and a text engine first used without it keeps breaking
    /// nothing (a filtered run on macOS: PictureWrapTests then ShapeSelectTests).
    override func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    /// A document whose second paragraph holds a picture floating square, 20pt in and 30pt down.
    func floatingDocument(inText: Bool = false) throws -> Data {
        let base = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "text"), RichParagraph(image: ImageAttachment(data: png, width: 100, height: 50))]), pageSetup: .letter)
        var entries = try Zip.read(base)
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let start = try XCTUnwrap(xml.rangeOfSubstring("<w:drawing>")), end = try XCTUnwrap(xml.rangeOfSubstring("</w:drawing>"))
        let embed = try XCTUnwrap(xml.rangeOfSubstring("r:embed=\""))
        let id = String(xml[embed.upperBound...].prefix { $0 != "\"" })
        let drawing = "<w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"114300\" distR=\"114300\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>254000</wp:posOffset></wp:positionH>"
            + "<wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>381000</wp:posOffset></wp:positionV><wp:extent cx=\"1270000\" cy=\"635000\"/>"
            + "<wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"5\" name=\"Picture 5\"/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:nvPicPr><pic:cNvPr id=\"0\" name=\"p\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(id)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"1270000\" cy=\"635000\"/></a:xfrm><a:prstGeom prst=\"rect\"/></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor>"
        xml.replaceSubrange(start.lowerBound ..< end.lowerBound, with: drawing)
        if inText, let r = xml.rangeOfSubstring("<w:r><w:drawing>") { xml.replaceSubrange(r, with: "<w:r><w:t>hello</w:t></w:r><w:r><w:drawing>") }
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        return try Zip.write(entries)
    }

    private func reopened(_ c: RichDocumentController) throws -> RichDocumentController {
        RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document)
    }

    private func floatIndex(_ c: RichDocumentController) throws -> Int {
        try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.float != nil || $0.inlineImages.values.contains { $0.float != nil } })
    }

    func testWrapChoiceChangesTheFloatUndoesAndSaves() throws {
        let c = RichDocumentController(document: try DocxFormat.read(try floatingDocument()).document)
        let i = try floatIndex(c)
        let inline = c.document.paragraphs[i].image == nil ? c.document.paragraphs[i].inlineImages.first { $0.value.float != nil }?.key : nil
        XCTAssertEqual(c.pictureWrap(at: i, inline: inline), .square)
        XCTAssertFalse(c.setPictureWrap(at: i, inline: inline, .square), "already so")
        for wrap in PictureWrap.allCases where wrap != .square {
            XCTAssertTrue(c.setPictureWrap(at: i, inline: inline, wrap))
            XCTAssertEqual(c.pictureWrap(at: i, inline: inline), wrap)
            XCTAssertEqual(try reopened(c).pictureWrap(at: i, inline: inline), wrap, "\(wrap) survives a save")
        }
        // Behind and in front differ only in behindDoc; top and bottom reads as a band of the page for a picture set from its paragraph.
        XCTAssertTrue(c.setPictureWrap(at: i, inline: inline, .behindText))
        let f = try XCTUnwrap((inline.map { c.document.paragraphs[i].inlineImages[$0] } ?? c.document.paragraphs[i].image)?.float)
        XCTAssertFalse(f.wraps)
        c.undo()
        XCTAssertEqual(c.pictureWrap(at: i, inline: inline), .inFrontOfText)
    }

    func testNudgeMovesTheOffsetsAndSaves() throws {
        let c = RichDocumentController(document: try DocxFormat.read(try floatingDocument()).document)
        let i = try floatIndex(c)
        let inline = c.document.paragraphs[i].image == nil ? c.document.paragraphs[i].inlineImages.first { $0.value.float != nil }?.key : nil
        XCTAssertTrue(c.movePicture(at: i, inline: inline, dx: 10, dy: -5))
        let back = try reopened(c)
        let f = try XCTUnwrap((inline.map { back.document.paragraphs[i].inlineImages[$0] } ?? back.document.paragraphs[i].image)?.float)
        XCTAssertEqual(f.x, 30, accuracy: 0.01)
        XCTAssertEqual(f.y, 25, accuracy: 0.01)
        c.undo()
        let was = try XCTUnwrap((inline.map { c.document.paragraphs[i].inlineImages[$0] } ?? c.document.paragraphs[i].image)?.float)
        XCTAssertEqual(was.x, 20, accuracy: 0.01)
    }

    /// The Picture Format tab shows the wrap choices and nudges of a selected floating picture, each one undo step.
    func testPictureFormatTabChoosesWrapAndNudges() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        c.load(try DocxFormat.read(try floatingDocument()).document)
        let i = try floatIndex(c)
        XCTAssertNotNil(c.document.paragraphs[i].image, "a picture alone in its paragraph")
        c.selectImage(at: i)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Behind Text"))
        XCTAssertEqual(c.pictureWrap(at: i), .behindText)
        // (At 1280 the tab is tight and the small buttons show their icons alone: the tip names the button.)
        XCTAssertTrue(ui.tap(tip: "Nudge Right"))
        XCTAssertEqual(c.document.paragraphs[i].image?.float?.x ?? 0, 26, accuracy: 0.01)
        c.undo()
        c.undo()
        XCTAssertEqual(c.pictureWrap(at: i), .square)
    }

    /// The Picture Format tab of a floating shape has Select Multiple, which a finger needs for picking shapes to group.
    func testPictureFormatTabHasSelectMultiple() throws {
        // (2000 wide: the Picture Format ribbon is 1615 pt on macOS, over the 1240 a 1280 window gives it, so it would be folded.)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        c.load(try DocxFormat.read(try floatingDocument()).document)
        c.selectImage(at: try floatIndex(c))
        ui.pump()
        XCTAssertFalse(c.selectMultiple)
        XCTAssertTrue(ui.tap(text: "Select Multiple"))
        XCTAssertTrue(c.selectMultiple)
        XCTAssertTrue(ui.tap(text: "Select Multiple"))
        XCTAssertFalse(c.selectMultiple)
    }

    /// A picture anchored in a line of text has a drawn box the click test can use.
    func testFloatAnchoredInTextHasADrawnBox() throws {
        let doc = try DocxFormat.read(try floatingDocument(inText: true)).document
        let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.inlineImages.values.contains { $0.float != nil } })
        let id = try XCTUnwrap(doc.paragraphs[k].inlineImages.first { $0.value.float != nil }?.key)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        l.width = 450 * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let box = try XCTUnwrap(l.inlineFloatRect(k, id: id))
        XCTAssertEqual(box.width / px, 100, accuracy: 0.5)
        XCTAssertEqual(box.height / px, 50, accuracy: 0.5)
    }

    /// A float anchored in text moves, undoes and saves like one in its own paragraph.
    func testFloatAnchoredInTextMoves() throws {
        let c = RichDocumentController(document: try DocxFormat.read(try floatingDocument(inText: true)).document)
        let k = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.inlineImages.values.contains { $0.float != nil } })
        let id = try XCTUnwrap(c.document.paragraphs[k].inlineImages.first { $0.value.float != nil }?.key)
        XCTAssertTrue(c.movePicture(at: k, inline: id, dx: 10, dy: -5))
        XCTAssertEqual(try XCTUnwrap(c.document.paragraphs[k].inlineImages[id]?.float).x, 30, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(try reopened(c).document.paragraphs[k].inlineImages.values.first { $0.float != nil }?.float).y, 25, accuracy: 0.01)
        c.undo()
        XCTAssertEqual(try XCTUnwrap(c.document.paragraphs[k].inlineImages[id]?.float).x, 20, accuracy: 0.01)
    }
}

/// W-OB-4: a text box made by Insert → Text Box.
final class TextBoxInsertTests: XCTestCase {
    /// Line breaking needs ICU's data in the text engine; without it a whole paragraph lays out as one line. Loaded before
    /// every test (once per process; later calls are free), since a run filtered to these classes may not start with
    /// `AAATextSetupTests`, and a text engine first used without it keeps breaking
    /// nothing (a filtered run on macOS: PictureWrapTests then ShapeSelectTests).
    override func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    func testNewTextBoxFloatsHoldsItsTextAndSurvivesASave() throws {
        let box = try XCTUnwrap(TextBoxInsert.make(text: "Hello & <you>"))
        XCTAssertNotNil(box.float)
        XCTAssertEqual(box.width, 144, accuracy: 0.1)
        XCTAssertEqual(box.textBox?.paragraphs.first?.text, "Hello & <you>")
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(box)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let kept = back.paragraphs.compactMap { $0.image ?? $0.inlineImages.values.first }.first { $0.textBox != nil }
        XCTAssertEqual(kept?.textBox?.paragraphs.first?.text, "Hello & <you>")
        XCTAssertEqual(kept?.width ?? 0, 144, accuracy: 0.1)
        c.undo()
        XCTAssertFalse(c.document.paragraphs.contains { $0.image?.textBox != nil })
    }

    func testEditTextChangesTheWordsUndoesAndSaves() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertEqual(c.textBoxText(at: i), "one")
        XCTAssertTrue(c.setTextBoxText(at: i, "two & <three>\nfour"))
        XCTAssertEqual(c.textBoxText(at: i), "two & <three>\nfour")
        XCTAssertFalse(c.setTextBoxText(at: i, "two & <three>\nfour"), "same words")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let kept = try XCTUnwrap(back.paragraphs.compactMap { $0.image }.first { $0.textBox != nil })
        XCTAssertEqual(kept.textBox?.paragraphs.map(\.text), ["two & <three>", "four"])
        c.undo()
        XCTAssertEqual(c.textBoxText(at: i), "one")
    }

    /// W-TB-6: a table made inside a text box stays a table when the box is left, saved and read again, and a box that
    /// already holds one can be edited in place.
    func testATableInsideATextBoxIsKeptWhenTheBoxIsLeftAndSaved() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        let box = RichDocumentController(document: try XCTUnwrap(c.textBoxDocument(at: i)))
        box.insertTable(rows: 2, columns: 2)
        let first = try XCTUnwrap(box.document.paragraphs.firstIndex { $0.cell != nil })
        box.moveTo(RichPosition(paragraph: first, offset: 0), extend: false)
        box.insertText("cell")
        let xml = try XCTUnwrap(TextBoxInsert.contentXML(box.document))
        XCTAssertTrue(xml.containsSubstring("<w:tbl>"))
        XCTAssertTrue(c.setTextBoxContent(at: i, document: box.document, contentXML: xml))
        let inBox = try XCTUnwrap(c.document.paragraphs[i].image?.textBox)
        XCTAssertEqual(inBox.paragraphs.compactMap(\.cell).count, 4)
        XCTAssertEqual(inBox.paragraphs.first?.cell != nil, true, "no empty paragraph before the table")
        XCTAssertEqual(inBox.paragraphs.last?.text, "one")
        // A box that holds a table is editable in place, and saves.
        let again = try XCTUnwrap(c.textBoxDocument(at: i))
        XCTAssertEqual(again.paragraphs.compactMap(\.cell).count, 4)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let kept = try XCTUnwrap(back.paragraphs.compactMap { $0.image }.first { $0.textBox != nil }?.textBox)
        XCTAssertEqual(kept.paragraphs.compactMap(\.cell).count, 4)
        XCTAssertTrue(kept.paragraphs.contains { $0.text == "cell" && $0.cell != nil })
        c.undo()
        XCTAssertEqual(c.document.paragraphs[i].image?.textBox?.paragraphs.compactMap(\.cell).count, 0)
    }

    func testTypingInTheBoxIsOneUndoStepWithFormattingAndSaves() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        // What the shell does: a controller over the box's paragraphs, then the words back as one change.
        let box = RichDocumentController(document: RichDocument(paragraphs: try XCTUnwrap(c.textBoxParagraphs(at: i))))
        box.selectAll()
        box.insertText("two & <three>")
        box.selectAll()
        box.toggleBold()
        let xml = try XCTUnwrap(TextBoxInsert.contentXML(box.document.paragraphs))
        XCTAssertFalse(xml.containsSubstring("<w:sectPr"))
        XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: box.document.paragraphs, contentXML: xml))
        XCTAssertEqual(c.textBoxText(at: i) ?? c.document.paragraphs[i].image?.textBox?.paragraphs.map(\.text).joined(), "two & <three>")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let kept = try XCTUnwrap(back.paragraphs.compactMap { $0.image }.first { $0.textBox != nil })
        XCTAssertEqual(kept.textBox?.paragraphs.map(\.text), ["two & <three>"])
        XCTAssertEqual(kept.textBox?.paragraphs.first?.runs.first?.style.bold, true)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[i].image?.textBox?.paragraphs.map(\.text), ["one"])
    }

    func testBoxWithAFieldAndATrackedInsertionIsEditedInPlace() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        // A box whose words hold a page field and a tracked insertion, as a file would carry them.
        var field = RichParagraph(text: "Page 7")
        field.runs = [Run(length: 5, style: .plain), Run(length: 1, style: { var s = CharStyle.plain; s.field = "PAGE"; s.fieldResult = 7; return s }())]
        var ins = RichParagraph(text: "added")
        ins.runs = [Run(length: 5, style: { var s = CharStyle.plain; s.revision = RevisionMark(kind: .inserted, author: "A", date: ""); return s }())]
        let paragraphs = [field, ins]
        let xml = try XCTUnwrap(TextBoxInsert.contentXML(paragraphs))
        XCTAssertTrue(xml.containsSubstring("PAGE"))
        XCTAssertTrue(xml.containsSubstring("<w:ins "))
        XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: paragraphs, contentXML: xml))
        XCTAssertNotNil(c.textBoxParagraphs(at: i), "a field and a tracked change are no bar to editing in place")
        let box = RichDocumentController(document: RichDocument(paragraphs: try XCTUnwrap(c.textBoxParagraphs(at: i))))
        box.selectAll()
        box.insertText("x")
        let again = try XCTUnwrap(TextBoxInsert.contentXML(box.document.paragraphs))
        XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: box.document.paragraphs, contentXML: again))
        c.undo()
        XCTAssertTrue(c.document.paragraphs[i].image?.sourceXML?.containsSubstring("PAGE") == true)
    }

    func testRevisionIdsOfTwoEditedBoxesNeverRepeat() throws {
        var ins = RichParagraph(text: "added")
        ins.runs = [Run(length: 5, style: { var s = CharStyle.plain; s.revision = RevisionMark(kind: .inserted, author: "A", date: ""); return s }())]
        let xml = try XCTUnwrap(TextBoxInsert.contentXML([ins]))
        // A body with its own tracked changes and a bookmark whose id came from the file.
        var bodyP = RichParagraph(text: "kept gone")
        bodyP.runs = [Run(length: 5, style: .plain), Run(length: 4, style: { var s = CharStyle.plain; s.revision = RevisionMark(kind: .deleted, author: "A", date: ""); return s }())]
        let c = RichDocumentController(document: RichDocument(paragraphs: [bodyP]))
        var ids: [Int] = []
        for n in 0..<2 {
            c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "box \(n)")))
            let i = try XCTUnwrap(c.document.paragraphs.lastIndex { $0.image?.textBox != nil })
            XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: [ins], contentXML: xml))
            ids.append(RichDocumentController._highestRevisionId(in: try XCTUnwrap(c.document.paragraphs[i].image?.sourceXML)))
        }
        XCTAssertEqual(Set(ids).count, 2, "each box's revisions get their own ids")
        let bodyIds = RichDocumentController._highestRevisionId(in: String(decoding: try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [bodyP]), pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self))
        XCTAssertGreaterThan(ids.min() ?? 0, bodyIds, "box ids sit above the body's")
    }

    func testAnnotationIdsNeverRepeatAcrossBodyHeaderAndBox() throws {
        var bodyP = RichParagraph(text: "kept gone")
        bodyP.runs = [Run(length: 5, style: .plain), Run(length: 4, style: { var s = CharStyle.plain; s.revision = RevisionMark(kind: .deleted, author: "A", date: ""); return s }())]
        var d = RichDocument(paragraphs: [bodyP])
        d.header = "Head"
        var entries = try Zip.read(try DocxFormat.write(d, pageSetup: .letter))
        let hi = try XCTUnwrap(entries.firstIndex { $0.name.hasPrefix("word/header") && $0.name.hasSuffix(".xml") })
        var h = String(decoding: entries[hi].data, as: UTF8.self)
        let close = try XCTUnwrap(h.rangeOfSubstring("</w:p>"))
        h.replaceSubrange(close.lowerBound ..< close.lowerBound, with: "<w:ins w:id=\"1\" w:author=\"B\"><w:r><w:t>hi</w:t></w:r></w:ins>")
        entries[hi] = ZipEntry(name: entries[hi].name, data: Data(h.utf8))
        let c = RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "box")))
        let out = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        var seen: [Int] = []
        for e in out where e.name.hasPrefix("word/") && e.name.hasSuffix(".xml") && (e.name == "word/document.xml" || e.name.hasPrefix("word/header")) {
            seen += RichDocumentController._annotationIds(in: String(decoding: e.data, as: UTF8.self))
        }
        XCTAssertTrue(seen.count >= 2, "header and body both carry a revision")
        XCTAssertEqual(Set(seen).count, seen.count, "no id names two annotations: \(seen)")
    }

    func testLeftoverRelationshipIsDroppedButOneTheMarkupNamesStays() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var img = ImageAttachment(data: png, width: 40, height: 40)
        img.sourceXML = "<w:drawing><wp:inline><wp:extent cx=\"508000\" cy=\"508000\"/><a:blip r:embed=\"rId7\"/><x:thing o:relid=\"rId8\"/></wp:inline></w:drawing>"
        let img2rel = KeptRel(id: "rId7", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", target: "media/a.png", external: false)
        let named = KeptRel(id: "rId8", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", target: "media/b.png", external: false)
        let stale = KeptRel(id: "rId9", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", target: "media/c.png", external: false)
        let tpl = KeptRel(id: "rId10", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate", target: "file:///C:/t.dotm", external: true)
        let glossary = KeptRel(id: "rId11", type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/glossaryDocument", target: "glossary/document.xml", external: false)
        img.sourceRels = [img2rel, named, stale, tpl, glossary]
        let out = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: img)]), pageSetup: .letter))
        let rels = String(decoding: try XCTUnwrap(out.first { $0.name == "word/_rels/document.xml.rels" }).data, as: UTF8.self)
        XCTAssertTrue(rels.containsSubstring("media/a.png"))
        XCTAssertTrue(rels.containsSubstring("media/b.png"), "named by an attribute we do not read: kept")
        XCTAssertFalse(rels.containsSubstring("media/c.png"), "named nowhere: dropped")
        XCTAssertTrue(rels.containsSubstring("t.dotm"), "a template rel is never dropped")
        XCTAssertTrue(rels.containsSubstring("glossary/document.xml"), "a glossary rel is never dropped")
    }

    func testBoxWithAnExternalLinkIsEditedInPlaceAndKeepsItsLink() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        var p = RichParagraph(text: "see site")
        p.runs = [Run(length: 4, style: .plain), Run(length: 4, style: { var s = CharStyle.plain; s.link = "https://example.com/a?b=1&c=2"; return s }())]
        let (xml, rels) = try XCTUnwrap(TextBoxInsert.content([p]))
        XCTAssertEqual(rels.map(\.target), ["https://example.com/a?b=1&c=2"])
        XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: [p], contentXML: xml, rels: rels))
        XCTAssertNotNil(c.textBoxParagraphs(at: i), "an external link is no bar to editing in place")
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let box = try XCTUnwrap(back.paragraphs.first { $0.image?.textBox != nil }?.image?.textBox)
        XCTAssertEqual(box.paragraphs.first?.runs.last?.style.link, "https://example.com/a?b=1&c=2")
    }

    func testBoxHoldingAPictureIsEditedInPlaceAndKeepsThePicture() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        let box0 = try XCTUnwrap(TextBoxInsert.make(text: "one"))
        let base = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: box0), RichParagraph(image: ImageAttachment(data: png, width: 40, height: 40))]), pageSetup: .letter)
        var entries = try Zip.read(base)
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        var ds: Range<String.Index>?, de: Range<String.Index>?
        var from = xml.startIndex
        while let r = xml.rangeOfSubstring("<w:drawing>", in: from ..< xml.endIndex) { ds = r; from = r.upperBound }
        de = xml.rangeOfSubstring("</w:drawing>", in: (ds?.upperBound ?? xml.startIndex) ..< xml.endIndex)
        let (ds0, de0) = (try XCTUnwrap(ds), try XCTUnwrap(de))
        let pic = String(xml[ds0.lowerBound ..< de0.upperBound])
        xml.replaceSubrange(ds0.lowerBound ..< de0.upperBound, with: "")
        let open = try XCTUnwrap(xml.rangeOfSubstring("<w:txbxContent>")), close = try XCTUnwrap(xml.rangeOfSubstring("</w:txbxContent>"))
        xml.replaceSubrange(open.upperBound ..< close.lowerBound, with: "<w:p><w:r>" + pic + "</w:r><w:r><w:t>caption</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let c = RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        var inside = try XCTUnwrap(c.textBoxDocument(at: i), "a picture the file carried is no bar to editing in place")
        XCTAssertEqual(inside.paragraphs.flatMap { [$0.image].compactMap { $0 } + Array($0.inlineImages.values) }.count, 1)
        inside.paragraphs[0].insert("X", at: inside.paragraphs[0].length)
        let (out, rels) = try XCTUnwrap(TextBoxInsert.content(inside))
        XCTAssertTrue(rels.contains { $0.target.hasPrefix("media/") }, "the picture's file is named")
        XCTAssertTrue(c.setTextBoxContent(at: i, document: inside, contentXML: out, rels: rels))
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let back = try DocxFormat.read(saved).document
        let boxBack = try XCTUnwrap(back.paragraphs.first { $0.image?.textBox != nil }?.image?.textBox)
        let images = boxBack.paragraphs.flatMap { [$0.image].compactMap { $0 } + Array($0.inlineImages.values) }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.data, png, "the picture still has its file")
        XCTAssertTrue(boxBack.paragraphs.map(\.text).joined().contains("captionX"))
    }

    func testNewTextBoxFitsItsTextAndGrowsWithTyping() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        XCTAssertTrue(c.textBoxAutoHeight(at: i))
        let h0 = try XCTUnwrap(c.document.paragraphs[i].image?.height)
        let box = RichDocumentController(document: RichDocument(paragraphs: try XCTUnwrap(c.textBoxParagraphs(at: i))))
        box.selectAll()
        box.insertText("two")
        let xml = try XCTUnwrap(TextBoxInsert.contentXML(box.document.paragraphs))
        XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: box.document.paragraphs, contentXML: xml, height: h0 + 40))
        XCTAssertEqual(c.document.paragraphs[i].image?.height, h0 + 40)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let kept = try XCTUnwrap(back.paragraphs.compactMap { $0.image }.first { $0.textBox != nil })
        XCTAssertEqual(kept.height, h0 + 40, accuracy: 0.6)
        c.undo()
        XCTAssertEqual(c.document.paragraphs[i].image?.height, h0)
        XCTAssertEqual(c.document.paragraphs[i].image?.textBox?.paragraphs.map(\.text), ["one"])
    }

    // (2000 wide: at 1280 the Picture Format tab gives way, and the Text Box group is icons by then, without the caption this taps.)
    func testEditTextOnThePictureFormatTab() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(2000, 800))
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        c.selectImage(at: i)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Edit Text"))
        ui.pump()
        XCTAssertNotNil(ui.state(OfficeShellState.self))
        XCTAssertTrue(ui.tap(id: "box-text"))
    }
}

final class ShapeInsertTests: XCTestCase {
    /// Line breaking needs ICU's data in the text engine; without it a whole paragraph lays out as one line. Loaded before
    /// every test (once per process; later calls are free), since a run filtered to these classes may not start with
    /// `AAATextSetupTests`, and a text engine first used without it keeps breaking
    /// nothing (a filtered run on macOS: PictureWrapTests then ShapeSelectTests).
    override func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    func testNewShapeReadsBackAndSaves() throws {
        for preset in ["rect", "roundRect", "ellipse", "triangle", "rightArrow"] {
            let shape = try XCTUnwrap(TextBoxInsert.makeShape(preset: preset), preset)
            XCTAssertNotNil(shape.float)
            XCTAssertNil(shape.textBox)
            let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
            c.insertImage(shape)
            let xml = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
            XCTAssertTrue(xml.containsSubstring("prst=\"\(preset)\""), preset)
            XCTAssertFalse(xml.containsSubstring("txBox"))   // (a shape, not a text box)
        }
    }

    func testShapesAreNamedLikeWordAndStandWhereTheyWerePlaced() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.pendingShape = { x, y, w, h in
            TextBoxInsert.makeShape(preset: "ellipse", width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y))
        }
        XCTAssertTrue(c.placePendingShape(x: 100, y: 200, width: 50, height: 40, at: RichPosition(paragraph: 0, offset: 4)))
        XCTAssertNil(c.pendingShape)
        XCTAssertNotNil(c.selectedImageIndex)
        c.pendingShape = { x, y, w, h in
            TextBoxInsert.makeShape(preset: "rect", width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y))
        }
        XCTAssertTrue(c.placePendingShape(x: 10, y: 20, width: 96, height: 72, at: RichPosition(paragraph: 0, offset: 0)))
        let xml = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("name=\"Oval 1\""))
        XCTAssertTrue(xml.containsSubstring("name=\"Rectangle 2\""))
        XCTAssertTrue(xml.containsSubstring("<wp:posOffset>1270000</wp:posOffset>"))   // 100 pt
        XCTAssertTrue(xml.containsSubstring("relativeFrom=\"page\""))
    }

    /// Set SHAPE_LAB2 to a file path to get shapes with typed text, other fills and outlines, for a Word check.
    func testWriteShapeStyleLab() throws {
        guard let path = ProcessInfo.processInfo.environment["SHAPE_LAB2"] else { return }
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Shapes with text and styles follow."), RichParagraph(text: "Second paragraph.")]))
        var n = 0
        for (preset, text, fill, line) in [("rect", "Hello", Color?.some(Color(0xFFFF0000)), Color?.some(Color(0xFF00AA00))),
                                           ("ellipse", "Oval text", Color?.none, Color?.some(Color(0xFF0000FF))),
                                           ("roundRect", "Rounded", Color?.some(Color(0xFFFFC000)), Color?.none),
                                           ("triangle", "", Color?.some(Color(0xFF7030A0)), Color?.some(Color(0xFF000000)))] {
            n += 1
            c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: preset, width: 120, height: 90, number: n, page: (x, y)) }
            XCTAssertTrue(c.placePendingShape(x: 60 + Double(n - 1) * 130, y: 200, width: 120, height: 90, at: RichPosition(paragraph: 0, offset: 0)))
            let i = try XCTUnwrap(c.selectedImageIndex)
            _ = c.setShapeFill(at: i, fill); _ = c.setShapeOutline(at: i, line)
            if !text.isEmpty {
                XCTAssertTrue(c.giveShapeText(at: i))
                var doc = try XCTUnwrap(c.textBoxDocument(at: i))
                doc.paragraphs[0] = RichParagraph(text: text, style: doc.paragraphs[0].style)
                let (xml, rels) = try XCTUnwrap(TextBoxInsert.content(doc))
                XCTAssertTrue(c.setTextBoxContent(at: i, document: doc, contentXML: xml, rels: rels))
            }
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
    }

    /// Set SHAPE_LAB to a file path to get a document with every menu shape, for a Word check.
    func testWriteShapeLab() throws {
        guard let path = ProcessInfo.processInfo.environment["SHAPE_LAB"] else { return }
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Shapes inserted from the menu follow."), RichParagraph(text: "Second paragraph.")]))
        for preset in ["rect", "roundRect", "ellipse", "triangle", "rightArrow"] {
            c.insertImage(try XCTUnwrap(TextBoxInsert.makeShape(preset: preset, number: TextBoxInsert.nextShapeNumber(in: c.document))))
        }
        try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
    }
}

final class ShapeSelectTests: XCTestCase {
    /// Line breaking needs ICU's data in the text engine; without it a whole paragraph lays out as one line. Loaded before
    /// every test (once per process; later calls are free), since a run filtered to these classes may not start with
    /// `AAATextSetupTests`, and a text engine first used without it keeps breaking
    /// nothing (a filtered run on macOS: PictureWrapTests then ShapeSelectTests).
    override func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    func testSelectedShapeMovesAndDeletes() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "before"), RichParagraph(text: "after")]))
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "rect", width: w, height: h, number: 1, page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 100, y: 200, width: 96, height: 72, at: RichPosition(paragraph: 1, offset: 0)))
        let i = try XCTUnwrap(c.selectedImageIndex)
        XCTAssertTrue(c.movePicture(at: i, dx: 10, dy: -20))
        let f = try XCTUnwrap(c.document.paragraphs[i].image?.float)
        XCTAssertEqual(f.x, 110); XCTAssertEqual(f.y, 180)
        let before = c.document.paragraphs.count
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.count, before - 1)
        XCTAssertFalse(c.document.paragraphs.contains { $0.image != nil })
        c.undo()
        XCTAssertTrue(c.document.paragraphs.contains { $0.image != nil })
    }

    func testTypingIntoAShapeKeepsItsGeometryAndCentresTheText() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "ellipse", width: w, height: h, number: 1, page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 50, y: 60, width: 96, height: 72, at: RichPosition(paragraph: 0, offset: 0)))
        let i = try XCTUnwrap(c.selectedImageIndex)
        XCTAssertNil(c.textBoxDocument(at: i))
        XCTAssertTrue(c.giveShapeText(at: i))
        XCTAssertFalse(c.giveShapeText(at: i))
        let inside = try XCTUnwrap(c.textBoxDocument(at: i))
        XCTAssertEqual(inside.paragraphs.count, 1)
        var typed = inside
        typed.paragraphs[0] = RichParagraph(text: "Hello", style: typed.paragraphs[0].style)
        let (xml, rels) = try XCTUnwrap(TextBoxInsert.content(typed))
        XCTAssertTrue(c.setTextBoxContent(at: i, document: typed, contentXML: xml, rels: rels))
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("Hello"))
        XCTAssertTrue(out.containsSubstring("prst=\"ellipse\""))
        XCTAssertTrue(out.containsSubstring("w:jc w:val=\"center\""))
    }

    func testShapeFillAndOutlineChangeTheMarkupAndTheDrawnShape() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "body")]))
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "rect", width: w, height: h, number: 1, page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 5, y: 5, width: 96, height: 72, at: RichPosition(paragraph: 0, offset: 0)))
        let i = try XCTUnwrap(c.selectedImageIndex)
        XCTAssertTrue(c.setShapeFill(at: i, Color(0xFFFF0000)))
        XCTAssertTrue(c.setShapeOutline(at: i, Color(0xFF00FF00)))
        XCTAssertEqual(c.document.paragraphs[i].image?.outline?.fill?.value, 0xFFFF0000)
        XCTAssertTrue(c.setShapeFill(at: i, nil))
        XCTAssertNil(c.document.paragraphs[i].image?.outline?.fill)
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("</a:prstGeom><a:noFill/><a:ln w=\"9525\"><a:solidFill><a:srgbClr val=\"00FF00\"/>"))
        XCTAssertFalse(out.containsSubstring("4472C4"))
        c.undo()
        XCTAssertNotNil(c.document.paragraphs[i].image?.outline?.fill)
    }

    func testThemePicksStayLinkedToTheThemeSlot() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "x", style: .init())]))
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "ellipse", width: w, height: h, number: 1, page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 5, y: 5, width: 96, height: 72, at: RichPosition(paragraph: 0, offset: 0)))
        let i = try XCTUnwrap(c.selectedImageIndex)
        // Accent 2, Lighter 40 percent; Accent 1, Darker 25 percent (outline); plain Text 1 is not touched here.
        XCTAssertTrue(c.setShapeFill(at: i, Color(0xFFF4B183), theme: (5, 60, 40)))
        XCTAssertTrue(c.setShapeOutline(at: i, Color(0xFF2F5597), theme: (4, 75, 0)))
        let xml = try XCTUnwrap(c.document.paragraphs[i].image?.sourceXML)
        XCTAssertTrue(xml.containsSubstring("<a:solidFill><a:schemeClr val=\"accent2\"><a:lumMod val=\"60000\"/><a:lumOff val=\"40000\"/></a:schemeClr></a:solidFill>"))
        XCTAssertTrue(xml.containsSubstring("<a:ln w=\"9525\"><a:solidFill><a:schemeClr val=\"accent1\"><a:lumMod val=\"75000\"/></a:schemeClr></a:solidFill>"))
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("<a:schemeClr val=\"accent2\">"))
        XCTAssertFalse(out.containsSubstring("4472C4"))
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB3"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
    }

    func testShapesGroupAndUngroupAndKeepTheirPlaceAndNames() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "x", style: .init())]))
        for (n, preset) in ["rect", "ellipse", "triangle"].enumerated() {
            c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: preset, width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y)) }
            XCTAssertTrue(c.placePendingShape(x: 50 + Double(n) * 100, y: 200 + Double(n) * 20, width: 80, height: 60, at: RichPosition(paragraph: 0, offset: 0)))
        }
        let shapes = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].image != nil }
        XCTAssertEqual(shapes.count, 3)
        c.selectImage(at: shapes[0])
        c.toggleShapePick(at: shapes[2])
        XCTAssertEqual(c.pickedShapeIndexes, [shapes[0], shapes[2]])
        let members = c.pickedShapeIndexes.compactMap { c.document.paragraphs[$0].image }
        let group = try XCTUnwrap(ShapeGroups.group(members, number: 9))
        XCTAssertTrue(ShapeGroups.isGroup(group))
        XCTAssertTrue(c.replaceImageParagraphs(c.pickedShapeIndexes, with: [group]))
        XCTAssertEqual(c.document.paragraphs.filter { $0.image != nil }.count, 2)
        XCTAssertTrue(c.document.paragraphs[c.selectedImageIndex!].image!.sourceXML!.containsSubstring("name=\"Group 9\""))
        // The file keeps the group and reads back as one.
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs.compactMap(\.image).filter { $0.sourceXML?.containsSubstring("<wpg:wgp") == true }.count, 1)
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB4"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
        // A click into the selected group picks the child under it; a fill then paints that child alone.
        let gi = try XCTUnwrap(c.selectedImageIndex)
        let boxes = try XCTUnwrap(c.groupChildBoxes(at: gi))
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0], Rect.fromLTWH(100, 20, 80, 60))
        XCTAssertEqual(boxes[1], Rect.fromLTWH(0, 0, 80, 60))
        XCTAssertFalse(c.pickGroupChild(at: gi, point: Offset(90, 70)), "between the children there is nothing to pick")
        XCTAssertTrue(c.pickGroupChild(at: gi, point: Offset(40, 30)))
        XCTAssertEqual(c.groupChild, 1)
        XCTAssertTrue(c.setShapeFill(at: gi, Color(0xFFFF0000)))
        let painted = try XCTUnwrap(c.document.paragraphs[gi].image?.sourceXML)
        XCTAssertEqual(painted.components(separatedBy: "<a:srgbClr val=\"FF0000\"/>").count - 1, 1, "only the picked child took the fill")
        let spPr = painted.components(separatedBy: "<wps:spPr>")
        XCTAssertFalse(spPr[1].components(separatedBy: "</wps:spPr>")[0].contains("FF0000"), "the first child keeps its fill")
        XCTAssertTrue(spPr[2].components(separatedBy: "</wps:spPr>")[0].contains("FF0000"))
        // The picked child moves (one undo step); the group keeps both children and the pick.
        RichDocumentController.groupChildEditor = { ShapeGroups.editChild($0, child: $1, $2, parts: $3) }
        XCTAssertTrue(c.editGroupChild(.move(dx: 12700 * 10, dy: 12700 * 5)))
        XCTAssertEqual(c.groupChild, 1)
        var moved = try XCTUnwrap(c.groupChildBoxes(at: gi))
        XCTAssertEqual(moved[0].width, boxes[0].width, accuracy: 0.5, "the other child stays")
        // (Boxes run from the group's own corner, which follows the children: the other one now sits 10 left and 5 up from it.)
        XCTAssertEqual(boxes[0].left - moved[0].left, 10, accuracy: 0.5)
        XCTAssertEqual(boxes[0].top - moved[0].top, 5, accuracy: 0.5)
        c.undo()
        XCTAssertEqual(try XCTUnwrap(c.groupChildBoxes(at: c.selectedImageIndex ?? gi))[1], boxes[1], "one undo puts it back")
        c.selectImage(at: c.selectedImageIndex ?? gi)
        XCTAssertTrue(c.pickGroupChild(at: c.selectedImageIndex ?? gi, point: Offset(40, 30)))
        XCTAssertTrue(c.editGroupChild(.resize(cx: 12700 * 40, cy: 12700 * 30)))
        moved = try XCTUnwrap(c.groupChildBoxes(at: c.selectedImageIndex ?? gi))
        XCTAssertEqual(moved[1].width, 40, accuracy: 0.5)
        XCTAssertEqual(moved[1].height, 30, accuracy: 0.5)
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB5"] {   // a group whose child was moved up-left and resized
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
        XCTAssertTrue(c.editGroupChild(.delete))
        XCTAssertEqual(try XCTUnwrap(c.groupChildBoxes(at: c.selectedImageIndex ?? gi)).count, 1, "the child is gone, the other stays")
        c.undo()   // the delete
        c.undo()   // the resize
        XCTAssertEqual(try XCTUnwrap(c.groupChildBoxes(at: c.selectedImageIndex ?? gi)), boxes, "each edit was one undo step")
        // Words typed into the picked child stay in the group: it keeps both children, and undo takes them out.
        c.selectImage(at: c.selectedImageIndex ?? gi)
        XCTAssertTrue(c.pickGroupChild(at: c.selectedImageIndex ?? gi, point: Offset(40, 30)))
        var typed = try XCTUnwrap(c.groupChildTextDocument())
        typed.paragraphs = [RichParagraph(text: "typed in a child")]
        let (body, rels) = try XCTUnwrap(TextBoxInsert.content(typed))
        XCTAssertTrue(c.setGroupChildText(document: typed, contentXML: body, rels: rels))
        XCTAssertEqual(c.groupChild, 1)
        XCTAssertEqual(try XCTUnwrap(c.groupChildBoxes(at: c.selectedImageIndex ?? gi)).count, 2)
        XCTAssertTrue(c.document.paragraphs[c.selectedImageIndex ?? gi].image!.sourceXML!.containsSubstring("typed in a child"))
        XCTAssertEqual(c.groupChildTextDocument()?.paragraphs.first?.text, "typed in a child", "the child reads back what was typed")
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB6"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
        c.undo()
        XCTAssertFalse(c.document.paragraphs[c.selectedImageIndex ?? gi].image!.sourceXML!.containsSubstring("typed in a child"))
        // Ungroup gives the two shapes back, by name and size.
        let g = try XCTUnwrap(c.document.paragraphs[c.selectedImageIndex!].image)
        let parts = try XCTUnwrap(ShapeGroups.ungroup(g, number: 20))
        XCTAssertEqual(parts.count, 2)
        let oval = try XCTUnwrap(parts.first { $0.sourceXML!.containsSubstring("name=\"Oval 2\"") })
        XCTAssertTrue(oval.sourceXML!.containsSubstring("<wp:posOffset>\(150 * 12700)</wp:posOffset></wp:positionH>"))
        XCTAssertTrue(parts.contains { $0.sourceXML!.containsSubstring("name=\"Rectangle 1\"") })
        c.undo()   // the fill
        c.undo()   // the group
        XCTAssertEqual(c.document.paragraphs.filter { $0.image != nil }.count, 3)
    }

    /// A saved document for the Word check of what the Shape Format tab writes: fills, outlines, wraps and text.
    /// A tight ellipse placed from the page, in the middle of the column: the text goes round it on both sides, left piece
    /// and right piece on one line, and keeps off the ellipse (Word's print of lab shape-format; before, the lines ran through).
    func testTightEllipseFromThePageWrapsOnBothSides() throws {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: String(repeating: "Body text of the page, long enough to flow past the shape. ", count: 60))]))
        c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: "ellipse", width: w, height: h, number: 1, page: (x, y)) }
        XCTAssertTrue(c.placePendingShape(x: 200, y: 200, width: 100, height: 70, at: RichPosition(paragraph: 0, offset: 0)))
        let i = try XCTUnwrap(c.selectedImageIndex)
        _ = c.setPictureWrap(at: i, .tight)
        let parsed = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter))
        let doc = parsed.document
        let setup = parsed.pageSetup ?? .letter
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = setup
        layout.width = setup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let body = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("Body text") })
        let px = theme.pixelsPerPoint
        var rows: [Double: [Double]] = [:]
        for off in stride(from: 0, to: 2400, by: 3) {
            let r = layout.caretRect(RichPosition(paragraph: body, offset: off), doc)
            rows[(r.top / px).rounded(), default: []].append(r.left / px)
        }
        // (The ellipse stands at 128...228 across the column, rows 128...198 down; its widest rows are the middle ones.)
        // (A caret in a left piece reports the row of the piece before it, so the rows are taken together.)
        let lefts = rows.filter { $0.key > 120 && $0.key < 200 }.flatMap(\.value)
        XCTAssertFalse(lefts.isEmpty)
        // At its widest rows the ellipse reaches 228 across; Word sets the text a further 9 pt out (its wrap distance: lab
        // shape-format's print starts the right piece 9.0 pt past the outline at the row through the centre). How far into
        // that strip this layout's outline lets a word come differs with the host's line heights, so the bound is the outline.
        XCTAssertFalse(rows.filter { $0.key > 150 && $0.key < 176 }.flatMap(\.value).contains { $0 > 125 && $0 < 228 }, "no text inside the ellipse's widest rows")
        XCTAssertTrue(lefts.contains { $0 < 119 }, "a left piece")
        XCTAssertTrue(lefts.contains { $0 > 236 }, "a right piece")
    }

    /// Word's print of lab shape-format: a square at the margin, a tight ellipse 9pt from it on the same rows, and a top-and-bottom
    /// box lower down, all set from the page, in one long paragraph.
    /// Lays out with the faces this app ships, loaded here, and those only: a machine's own faces (a Mac's Times) or what
    /// an earlier test left loaded must not move the lines these tests measure. Gives back the undo.
    static func pinBundledFonts() -> () -> Void {
        _ = OfficeFonts.register()
        let env = ProcessInfo.processInfo.environment["OFFICE_FONT_SOURCE"]
        setenv("OFFICE_FONT_SOURCE", "bundled", 1)
        OfficeFonts.fontSourceChanged()
        return {
            if let env { setenv("OFFICE_FONT_SOURCE", env, 1) } else { unsetenv("OFFICE_FONT_SOURCE") }
            OfficeFonts.fontSourceChanged()
        }
    }

    func testSquareBesideATightEllipseFromThePageAsWordSetsThem() throws {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        let unpin = Self.pinBundledFonts()
        defer { unpin() }
        /// Lays the page out with the fourth shape wrapped `last`; the caret rows by row top (column points) and the foot of the text.
        func lay(_ last: PictureWrap) throws -> (rows: [Double: [Double]], foot: Double) {
            let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: String(repeating: "Body text of the page, long enough to flow past every one of the four shapes so the wrap of each can be seen acting on it. ", count: 14))]))
            let specs: [(String, PictureWrap)] = [("rect", .square), ("ellipse", .tight), ("rect", .behindText), ("roundRect", last)]
            for (n, spec) in specs.enumerated() {
                c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: spec.0, width: w, height: h, number: n + 1, page: (x, y)) }
                XCTAssertTrue(c.placePendingShape(x: 60 + Double(n) * 110, y: 150 + Double(n) * 40, width: 100, height: 70, at: RichPosition(paragraph: 0, offset: 0)))
                _ = c.setPictureWrap(at: try XCTUnwrap(c.selectedImageIndex), spec.1)
            }
            let parsed = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter))
            let doc = parsed.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = parsed.pageSetup ?? .letter
            layout.width = layout.pageSetup!.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let body = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("Body text") })
            let px = theme.pixelsPerPoint
            var rows: [Double: [Double]] = [:]
            for off in stride(from: 0, to: 3600, by: 2) {
                let r = layout.caretRect(RichPosition(paragraph: body, offset: off), doc)
                rows[(r.top / px * 100).rounded() / 100, default: []].append(r.left / px)
            }
            return (rows, layout.totalHeight / px)
        }
        let (rows, foot) = try lay(.topAndBottom)
        // Rows are down the column (page y - 72), carets across it (page x - 72). Square 60...160 x 150...220 on the page: -12...88 across,
        // 78...148 down. Ellipse 170...270 x 190...260: 98...198 across, 118...188 down. Top-and-bottom box 390...490 x 270...340.
        // Beside the ellipse above the square's foot, no word sits in the 9pt strip or under the ellipse; the first starts at its outline
        // (Word's print: 260.6 / 275.6 / 279.0 on the page, 188.6 / 203.6 / 207.0 across the column; the rows here are a little further right).
        let beside = rows.filter { $0.key > 118 && $0.key < 148 }.flatMap(\.value)
        XCTAssertFalse(beside.isEmpty)
        XCTAssertFalse(beside.contains { $0 > 30 && $0 < 196 }, "no text in the strip or the ellipse: \(rows.keys.sorted())")
        XCTAssertTrue(beside.contains { $0 > 196 && $0 < 216 }, "the first line beside the ellipse starts at its outline")
        // Each line meets the outline over its TEXT, not its spacing: the 1.08 multiple's extra goes below the text and does not count
        // (Word's print: 260.6 / 275.6 are the oval's edge plus 9pt over the 13.4pt Calibri text, not over the 14.5pt line). Here the
        // rows are 13pt, the text 13 / 1.08 = 12.04pt: the row at 120 meets the oval (centre 148, 153; half axes 50, 35) at 132.04,
        // where its edge is 188.1 across, so the text starts at 197.1 (198.2 before, over the whole line); the row at 133 meets it at 145.04: 196.7, text at 205.7.
        // The first two lines whose top is at or below the ellipse's (118) and that have a piece right of it, by their measured
        // tops: the row height is the spacing between them, the text height that over 1.08 (the host's faces set both).
        let near = rows.filter { $0.key >= 118 && $0.key < 148 && $0.value.contains { $0 > 150 } }.sorted { $0.key < $1.key }
        XCTAssertGreaterThanOrEqual(near.count, 2, "lines beside the ellipse: \(rows.keys.sorted())")
        guard near.count >= 2 else { return }
        let text = (near[1].key - near[0].key) / 1.0791666
        for line in near.prefix(2) {
            let edge = 148 + 50 * (1 - pow((153 - (line.key + text)) / 35, 2)).squareRoot()
            XCTAssertEqual(try XCTUnwrap(line.value.filter { $0 > 150 }.min()), edge + 9, accuracy: 0.4, "the line at \(line.key)")
        }
        // Below the square the left piece is back at the margin.
        XCTAssertTrue(rows.filter { $0.key > 150 && $0.key < 188 }.flatMap(\.value).contains { $0 < 8 })
        // The top-and-bottom box takes its rows out of the text: the lines that would stand in them go under it, so the page is
        // taller than with the same box behind the text (the push is the box's 70pt less the lines that fell above it).
        let (_, behind) = try lay(.behindText)
        XCTAssertGreaterThan(foot, behind + 40, "the top-and-bottom box pushes the lines under it: \(foot) against \(behind)")
    }

    /// The same four shapes at the same places on the page, but anchored to the margin or the column instead of the page, lay the
    /// text out the same way: where a shape is measured from changes only the numbers, not what the text does around it.
    func testShapesLayTheTextTheSameWhateverTheyAreMeasuredFrom() throws {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        func lay(_ from: (h: String, v: String)) throws -> (rows: [Double: [Double]], height: Double) {
            let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: String(repeating: "Body text of the page, long enough to flow past every one of the four shapes so the wrap of each can be seen acting on it. ", count: 14))]))
            let specs: [(String, PictureWrap)] = [("rect", .square), ("ellipse", .tight), ("rect", .behindText), ("roundRect", .topAndBottom)]
            for (n, spec) in specs.enumerated() {
                c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: spec.0, width: w, height: h, number: n + 1, page: (x, y)) }
                XCTAssertTrue(c.placePendingShape(x: 60 + Double(n) * 110, y: 150 + Double(n) * 40, width: 100, height: 70, at: RichPosition(paragraph: 0, offset: 0)))
                _ = c.setPictureWrap(at: try XCTUnwrap(c.selectedImageIndex), spec.1)
            }
            let parsed = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter))
            var doc = parsed.document
            let setup = parsed.pageSetup ?? .letter
            // (Where each paragraph starts down the column, from the file as it stands: a paragraph's offset is from its top.)
            let flat = { let t = RichTextTheme(fontFamily: OfficeFonts.serif); t.wordRules = true; return t }()
            let probe = RichLayout(theme: flat, paragraphCount: doc.paragraphs.count)
            probe.pageSetup = setup
            probe.width = setup.columnWidth * flat.pixelsPerPoint
            probe.ensureLaidOut(doc)
            for n in doc.paragraphs.indices {
                guard var image = doc.paragraphs[n].image, var float = image.float, float.verticalFrom == "page", float.horizontalFrom == "page" else { continue }
                if from.h == "leftMargin" || from.h == "insideMargin" { float.horizontalFrom = from.h }
                else if from.h == "rightMargin" || from.h == "outsideMargin" { float.x -= setup.width - setup.marginRight; float.horizontalFrom = from.h }
                else if from.h != "page" { float.x -= setup.marginLeft; float.horizontalFrom = from.h }
                if from.v == "paragraph", float.wraps || float.takesRoom || float.bandsPage { float.y -= setup.marginTop + probe._tops[n] / flat.pixelsPerPoint; float.verticalFrom = "paragraph" }
                else if from.v != "page" { float.y -= setup.marginTop; float.verticalFrom = from.v == "paragraph" ? "margin" : from.v }
                image.float = float
                doc.paragraphs[n].image = image
            }
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = setup
            layout.width = setup.columnWidth * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            let body = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("Body text") })
            let px = theme.pixelsPerPoint
            var rows: [Double: [Double]] = [:]
            for off in stride(from: 0, to: 1800, by: 2) {
                let r = layout.caretRect(RichPosition(paragraph: body, offset: off), doc)
                rows[(r.top / px).rounded(), default: []].append((r.left / px * 2).rounded() / 2)
            }
            return (rows, layout.totalHeight / px)
        }
        let page = try lay(("page", "page"))
        for from in [("margin", "margin"), ("column", "margin"), ("margin", "page"), ("page", "margin"), ("column", "paragraph"), ("margin", "paragraph"), ("page", "paragraph"), ("leftMargin", "page"), ("rightMargin", "page"), ("insideMargin", "page"), ("outsideMargin", "page")] {
            let other = try lay(from)
            XCTAssertEqual(other.height, page.height, accuracy: 0.6, "page height measured from \(from)")
            XCTAssertEqual(other.rows.keys.sorted(), page.rows.keys.sorted(), "rows measured from \(from)")
            for k in page.rows.keys {
                XCTAssertEqual(other.rows[k]?.min() ?? -1, page.rows[k]!.min() ?? -2, accuracy: 0.6, "row \(k) start measured from \(from)")
            }
        }
    }

    func testShapeFormatChoicesSaveForTheWordCheck() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: String(repeating: "Body text of the page, long enough to flow past every one of the four shapes so the wrap of each can be seen acting on it. ", count: 40), style: .init())]))
        let specs: [(String, PictureWrap, Color?, Color?, String?)] = [
            ("rect", .square, Color(0xFFFF0000), Color(0xFF0000FF), "square"),
            ("ellipse", .tight, Color(0xFF00AA00), nil, "tight"),
            ("rect", .behindText, Color(0xFFFFFF00), Color(0xFF000000), "behind"),
            ("roundRect", .topAndBottom, nil, Color(0xFFCC0000), "top and bottom"),
        ]
        for (n, spec) in specs.enumerated() {
            c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: spec.0, width: w, height: h, number: n + 1, page: (x, y)) }
            XCTAssertTrue(c.placePendingShape(x: 60 + Double(n) * 110, y: 150 + Double(n) * 40, width: 100, height: 70, at: RichPosition(paragraph: 0, offset: 0)))
            let i = try XCTUnwrap(c.selectedImageIndex)
            _ = c.setPictureWrap(at: i, spec.1)
            XCTAssertTrue(c.setShapeFill(at: i, spec.2))
            _ = c.setShapeOutline(at: i, spec.3)
            XCTAssertTrue(c.giveShapeText(at: i))
            var para = RichParagraph(text: spec.4 ?? "")
            para.style.alignment = .center
            XCTAssertTrue(c.setTextBoxContent(at: i, paragraphs: [para], contentXML: "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>\(spec.4 ?? "")</w:t></w:r></w:p>"))
        }
        let ellipse = try XCTUnwrap(c.document.paragraphs.compactMap(\.image).first { $0.sourceXML?.containsSubstring("prst=\"ellipse\"") == true })
        let xml = try XCTUnwrap(ellipse.sourceXML)
        XCTAssertEqual(xml.components(separatedBy: "<wp:lineTo").count - 1, 36, "a smooth ellipse: 36 points, closed")
        XCTAssertFalse(xml.containsSubstring("<wp:lineTo x=\"21600\" y=\"21600\"/><wp:lineTo x=\"21600\" y=\"0\"/>"), "not the full rectangle")
        let poly = try XCTUnwrap(ellipse.float).wrapPolygon
        XCTAssertGreaterThan(poly.count, 20)
        XCTAssertTrue(poly.contains { abs($0.x - 0.5) < 0.01 && $0.y < 0.01 }, "reaches the top middle")
        XCTAssertFalse(poly.contains { $0.x < 0.05 && $0.y < 0.05 }, "the corner of the box is not in it")
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB7"] {
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
    }

    func testTurnedShapesGroupByTheBoxTheirTurnSweeps() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "x", style: .init())]))
        for (n, preset) in ["rect", "ellipse"].enumerated() {
            c.pendingShape = { x, y, w, h in TextBoxInsert.makeShape(preset: preset, width: w, height: h, number: TextBoxInsert.nextShapeNumber(in: c.document), page: (x, y)) }
            XCTAssertTrue(c.placePendingShape(x: 50 + Double(n) * 200, y: 200, width: 80, height: 60, at: RichPosition(paragraph: 0, offset: 0)))
        }
        var shapes = c.document.paragraphs.compactMap(\.image).filter { $0.float != nil }
        XCTAssertEqual(shapes.count, 2)
        let r = try XCTUnwrap(shapes.firstIndex { $0.sourceXML!.containsSubstring("name=\"Rectangle") })
        shapes[r].sourceXML = shapes[r].sourceXML!.replacingAll("<a:xfrm>", with: "<a:xfrm rot=\"5400000\">").replacingAll("<a:xfrm ", with: "<a:xfrm rot=\"5400000\" ")
        XCTAssertTrue(shapes[r].sourceXML!.containsSubstring("rot=\"5400000\""))
        let g = try XCTUnwrap(ShapeGroups.group(shapes, number: 5))
        let xml = try XCTUnwrap(g.sourceXML)
        // Turned a quarter, the 80 x 60 box fills 60 x 80 about its centre: 60..120 across, 190..270 down; the group ends at 330.
        XCTAssertTrue(xml.containsSubstring("<wp:posOffset>\(60 * 12700)</wp:posOffset></wp:positionH>"))
        XCTAssertTrue(xml.containsSubstring("<wp:posOffset>\(190 * 12700)</wp:posOffset></wp:positionV>"))
        XCTAssertTrue(xml.containsSubstring("<wp:extent cx=\"\(270 * 12700)\" cy=\"\(80 * 12700)\"/>"))
        if let path = ProcessInfo.processInfo.environment["SHAPE_LAB5"] {
            let idx = c.document.paragraphs.indices.filter { c.document.paragraphs[$0].image?.float != nil }
            XCTAssertTrue(c.replaceImageParagraphs(idx, with: [g]))
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: path))
        }
        let parts = try XCTUnwrap(ShapeGroups.ungroup(g, number: 9))
        XCTAssertTrue(parts.contains { $0.sourceXML!.containsSubstring("rot=\"5400000\"") })
    }
}
