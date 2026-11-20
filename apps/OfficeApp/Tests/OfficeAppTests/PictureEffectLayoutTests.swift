// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

final class PictureEffectLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func picture() -> ImageAttachment {
        var image = ImageAttachment(data: Data(), width: 100, height: 60)
        image.effectLeft = 12
        image.effectRight = 6
        image.sourceWidth = 100
        image.sourceHeight = 60
        return image
    }

    private func layout(_ p: RichParagraph) -> RichLayout {
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 450 * theme.pixelsPerPoint
        layout.ensureLaidOut(RichDocument(paragraphs: [p]))
        return layout
    }

    func testPictureAlignmentIncludesAsymmetricEffects() throws {
        // Word's frame-effects lab: 12pt left and 6pt right move the
        // picture, reserve both sides, and leave its own size unchanged.
        for alignment in [ParagraphAlignment.left, .center, .right] {
            var p = RichParagraph(image: picture())
            p.style.alignment = alignment
            let l = layout(p)
            let px = l.theme.pixelsPerPoint
            let box = try XCTUnwrap(l.imageRect(0))
            XCTAssertEqual(box.width / px, 100, accuracy: 0.5)
            switch alignment {
            case .left: XCTAssertEqual(box.left / px, 12, accuracy: 0.5)
            case .center: XCTAssertEqual(box.center.dx / px, 228, accuracy: 0.5)
            case .right: XCTAssertEqual(box.right / px, 444, accuracy: 0.5)
            default: XCTFail("unexpected alignment")
            }
        }
    }

    func testResizedPictureDoesNotKeepOldEffectSpacing() throws {
        var image = picture()
        image.width = 90
        let l = layout(RichParagraph(image: image))
        XCTAssertEqual(try XCTUnwrap(l.imageRect(0)).left, 0, accuracy: 0.01)
    }

    func testInlinePicturesReserveEffectsBeforeTheNextPicture() throws {
        let a = picture(), b = picture()
        var p = RichParagraph(text: "\u{FFFC}\u{FFFC}")
        p.inlineImages = [a.id: a, b.id: b]
        var sa = CharStyle(), sb = CharStyle()
        sa.inlineImage = a.id
        sb.inlineImage = b.id
        p.runs = [Run(length: 1, style: sa), Run(length: 1, style: sb)]
        let l = layout(p)
        let boxes = try XCTUnwrap(l.geometry(0).painter.inlinePlaceholderBoxes)
        XCTAssertEqual(boxes.count, 2)
        let px = l.theme.pixelsPerPoint
        XCTAssertEqual((boxes[0].right - boxes[0].left) / px, 118, accuracy: 0.5)
        XCTAssertEqual(boxes[1].left / px, 118, accuracy: 0.5)
    }
}
