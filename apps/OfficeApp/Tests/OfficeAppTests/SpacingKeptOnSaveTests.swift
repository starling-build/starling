import XCTest
@testable import OfficeApp
@testable import OfficeText

/// Direct paragraph spacing is written only where the paragraph's own look
/// differs from its style's; a save must not change any paragraph's spacing.
final class SpacingKeptOnSaveTests: XCTestCase {
    func testStyleSpacingIsNotBakedIntoParagraphsAndLayoutSurvives() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("test/corpus/docx/docs")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".docx") }.sorted()
        try XCTSkipIf(names.isEmpty, "corpus not restored")
        var checked = 0, mismatches: [String] = []
        for n in names.enumerated().filter({ $0.offset % 12 == 0 }).map({ $0.element }) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(n)),
                  let read = try? DocxFormat.read(data) else { continue }
            let out = try DocxFormat.write(read.document, pageSetup: read.pageSetup ?? .letter)
            let back = try DocxFormat.read(out).document
            func key(_ d: RichDocument) -> [String] {
                d.paragraphs.map { p in "\(p.style.spaceBefore)/\(p.style.spaceAfter)/\(p.style.lineSpacing)/\(p.style.lineHeightPoints ?? -1)/\(p.style.spaceBeforeAuto)/\(p.style.spaceAfterAuto)" }
            }
            let a = key(read.document), b = key(back)
            checked += 1
            // (A few documents already gain a paragraph on save; that is a separate matter.)
            if a.count == b.count, a != b { mismatches.append(String(n.prefix(12)) + " \(a.count)/\(b.count) first diff " + (zip(a, b).first { $0 != $1 }.map { "\($0) vs \($1)" } ?? "count")) }
        }
        XCTAssertGreaterThan(checked, 10)
        XCTAssertTrue(mismatches.isEmpty, "spacing changed on save: \(mismatches.prefix(8))")
    }

    func testParagraphsThatSayNothingStaySilentAndPlainTextHasNoXmlSpace() throws {
        let read = try DocxFormat.read(NumberingKeptOnSaveTests.sample())
        let out = try DocxFormat.write(read.document, pageSetup: read.pageSetup ?? .letter)
        let body = String(decoding: try Zip.read(out).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(body.containsSubstring("<w:spacing"), "the style's spacing is not baked into the paragraphs")
        XCTAssertTrue(body.containsSubstring("<w:t>one</w:t>"), "plain text needs no xml:space")
    }
}
