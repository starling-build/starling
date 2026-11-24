// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A PDF waits for the document's pictures to decode before it paints them: until they have, a picture is a
/// grey box. The wait spins the run loop, which cannot drain the main queue while the caller is itself running a
/// block of it (a driven tap on the iPad is one): the wait ran out its eight seconds and the pictures printed as
/// grey boxes. The decoded pictures now reach the layout through a mailbox the wait drains itself.
final class PdfExportPictureTests: XCTestCase {
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    private func theme() -> RichTextTheme {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        return theme
    }

    /// The picture objects in the PDF (a grey box is a rectangle: none).
    private func imageObjects(inBlock: Bool) throws -> Int {
        let document = RichDocument(paragraphs: [RichParagraph(text: "above"),
                                                 RichParagraph(image: ImageAttachment(data: Self.png, width: 100, height: 80)),
                                                 RichParagraph(text: "below")])
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("pic-\(UUID().uuidString).pdf").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var written = false
        if inBlock {
            let done = expectation(description: "written from inside a main-queue block")
            DispatchQueue.main.async {
                written = PdfExport.write(document, pageSetup: .a4, theme: self.theme(), to: path, title: "t")
                done.fulfill()
            }
            wait(for: [done], timeout: 60)
        } else {
            written = PdfExport.write(document, pageSetup: .a4, theme: theme(), to: path, title: "t")
        }
        XCTAssertTrue(written)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        let needle = Data("/Subtype /Image".utf8)
        var count = 0
        var from = bytes.startIndex
        while let r = bytes.range(of: needle, in: from ..< bytes.endIndex) { count += 1; from = r.upperBound }
        return count
    }

    func testAPictureIsInThePdfWrittenFromTheRunLoop() throws {
        XCTAssertGreaterThanOrEqual(try imageObjects(inBlock: false), 1)
    }

    func testAPictureIsInThePdfWrittenFromInsideAMainQueueBlock() throws {
        XCTAssertGreaterThanOrEqual(try imageObjects(inBlock: true), 1)
    }
}
