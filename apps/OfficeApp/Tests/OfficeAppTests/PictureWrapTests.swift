// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-OB-3: the wrap choice and the nudge of a floating picture, read from a file, changed, undone and saved.
final class PictureWrapTests: XCTestCase {
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
        XCTAssertTrue(ui.tap(text: "Nudge Right"))
        XCTAssertEqual(c.document.paragraphs[i].image?.float?.x ?? 0, 26, accuracy: 0.01)
        c.undo()
        c.undo()
        XCTAssertEqual(c.pictureWrap(at: i), .square)
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

    func testEditTextOnThePictureFormatTab() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
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
