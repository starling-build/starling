// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class PictureTabLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func document(trailingTabs: Int) -> RichDocument {
        var p = RichParagraph(text: "")
        p.style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
        p.style.tabStops = [TabStop(position: 225, alignment: .center), TabStop(position: 450, alignment: .right)]
        p.runs = []
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        for (i, width) in [100.0, 110.0, 120.0].enumerated() {
            let picture = ImageAttachment(data: png, width: width, height: 80)
            var style = CharStyle(fontSize: 12)
            style.inlineImage = picture.id
            p.inlineImages[picture.id] = picture
            p.text += "\u{FFFC}"
            p.runs.append(Run(length: 1, style: style))
            let tabs = i < 2 ? 1 : trailingTabs
            if tabs > 0 {
                p.text += String(repeating: "\t", count: tabs)
                p.runs.append(Run(length: tabs, style: CharStyle(fontSize: 12)))
            }
        }
        var document = RichDocument(paragraphs: [p])
        document.compatibilityMode = 15
        return document
    }

    private func layout(trailingTabs: Int) -> RichLayout {
        let document = document(trailingTabs: trailingTabs)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 450 * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return layout
    }

    func testAPositionalTabGoesToTheMarginPastTheStopsBefore() throws {
        // bug57031's footer: "name <right ptab> Page 2 of 14" under the
        // Footer style's centre and right stops. The ptab is the line's
        // first tab, and Word ends the text at the right margin, not
        // centred on the centre stop.
        var p = RichParagraph(text: "Left\tPage 2")
        p.style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
        p.style.tabStops = [TabStop(position: 225, alignment: .center), TabStop(position: 450, alignment: .right)]
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let px = theme.pixelsPerPoint
        func end(_ p: RichParagraph) -> Double {
            let layout = RichLayout(theme: theme, paragraphCount: 1)
            layout.width = 450 * px
            layout.ensureLaidOut(RichDocument(paragraphs: [p]))
            let painter = layout.geometry(0).painter
            let n = painter.computeLineMetrics().isEmpty ? 0 : p.text.utf16.count
            return (painter.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: n)).map(\.right).max() ?? 0) / px
        }
        XCTAssertLessThan(end(p), 400)   // an ordinary tab: centred on 225
        p.style.positionalTabs = [0: .right]
        XCTAssertEqual(end(p), 450, accuracy: 0.5)
    }

    func testAFormCheckBoxIsADrawnSquareOfWordsAdvance() throws {
        // form_footnotes: Word draws a FORMCHECKBOX ("☐") as a 9.36pt
        // square with 1.06 before and 1.08 after it at 10pt — an 11.5pt
        // advance — standing 8.4 above the baseline.
        var p = RichParagraph(text: "x\u{2610} Yes")
        var formStyle = CharStyle(fontSize: 10)
        formStyle.formBox = true            // (a FORMCHECKBOX field's: a typed "☐" is a character)
        p.runs = [Run(length: p.text.utf16.count, style: formStyle)]
        p.style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let px = theme.pixelsPerPoint
        let document = RichDocument(paragraphs: [p])
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 450 * px
        layout.ensureLaidOut(document)
        let painter = layout.geometry(0).painter
        let boxes = try XCTUnwrap(painter.inlinePlaceholderBoxes).filter { $0.right - $0.left > 1 }
        XCTAssertEqual(boxes.count, 1)
        let box = try XCTUnwrap(boxes.first)
        XCTAssertEqual((box.right - box.left) / px, 11.5, accuracy: 0.05)
        let baseline = try XCTUnwrap(painter.computeLineMetrics().first).baseline
        XCTAssertEqual((baseline - box.top) / px, 8.4, accuracy: 0.3)
        // The box follows "x", and the space and "Yes" follow the box.
        let x = layout.caretRect(RichPosition(paragraph: 0, offset: 1), document).left
        XCTAssertEqual(box.left, x, accuracy: 0.3 * px)
        let space = layout.caretRect(RichPosition(paragraph: 0, offset: 2), document).left
        XCTAssertEqual(space, box.right, accuracy: 0.3 * px)
    }

    func testPicturePositionsFollowTheirTabStops() throws {
        let layout = layout(trailingTabs: 0)
        let boxes = try XCTUnwrap(layout.geometry(0).painter.inlinePlaceholderBoxes).filter { $0.bottom - $0.top > 1 }
        XCTAssertEqual(boxes.count, 3)
        let px = layout.theme.pixelsPerPoint
        XCTAssertEqual(boxes[0].left / px, 0, accuracy: 0.5)
        XCTAssertEqual((boxes[1].left + boxes[1].right) / 2 / px, 225, accuracy: 0.5)
        XCTAssertEqual(boxes[2].right / px, 450, accuracy: 0.5)
    }

    func testTrailingTabsDoNotAddAnEmptyPictureHeightLine() {
        let withoutTrailingTabs = layout(trailingTabs: 0)
        for tabs in [1, 2] {
            let layout = layout(trailingTabs: tabs)
            XCTAssertEqual(layout.geometry(0).painter.computeLineMetrics().count, 1)
            XCTAssertEqual(layout.totalHeight, withoutTrailingTabs.totalHeight, accuracy: 0.01)
        }
    }

    func testPictureBoxesFollowParagraphInsertionsAndRemovals() {
        let layout = layout(trailingTabs: 1)
        var doc = document(trailingTabs: 1)
        func paint() {
            layout.ensureLaidOut(doc)
            let rect = Rect.fromLTWH(0, 0, layout.width, layout.totalHeight)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: rect)
            layout.paint(canvas, visible: rect, document: doc, selection: nil, caret: nil)
            recorder.endRecording().dispose()
        }
        doc.paragraphs.insert(RichParagraph(text: "Before"), at: 0)
        layout.apply([.inserted(at: 0, count: 1)], paragraphCount: 2)
        paint()
        XCTAssertEqual(layout.geometry(1).painter.inlinePlaceholderBoxes?.filter { $0.bottom - $0.top > 1 }.count, 3)
        doc.paragraphs.remove(at: 0)
        layout.apply([.removed(at: 0, count: 1)], paragraphCount: 1)
        paint()
        XCTAssertEqual(layout.geometry(0).painter.inlinePlaceholderBoxes?.filter { $0.bottom - $0.top > 1 }.count, 3)
    }
}
