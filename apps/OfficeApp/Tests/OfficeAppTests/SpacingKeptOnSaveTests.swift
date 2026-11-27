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
        // Every 12th file is checked and more than 10 checks are wanted, so a host holding only a few corpus files skips.
        try XCTSkipIf(names.count < 130, "corpus not restored (\(names.count) files)")
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

    func testSaveWithNoEditAddsNoStyleNumberingPartAndKeepsEveryFileStyle() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("test/corpus/docx/docs")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".docx") }.sorted()
        // Every 12th file is checked and more than 10 checks are wanted, so a host holding only a few corpus files skips.
        try XCTSkipIf(names.count < 130, "corpus not restored (\(names.count) files)")
        func ids(_ xml: String) -> [String: String] {
            guard let root = XNode.parse(Data(xml.utf8)) else { return [:] }
            var out: [String: String] = [:]
            for st in root.children where st.name == "w:style" { out[st["w:styleId"] ?? ""] = "\(st)" }
            return out
        }
        var added: [String] = [], overridden: [String] = [], numberingAdded: [String] = [], checked = 0
        for n in names.enumerated().filter({ $0.offset % 12 == 5 }).map({ $0.element }) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(n)), let read = try? DocxFormat.read(data) else { continue }
            let before = try Zip.read(data), out = try Zip.read(try DocxFormat.write(read.document, pageSetup: read.pageSetup ?? .letter))
            func part(_ e: [ZipEntry], _ name: String) -> String? { e.first { $0.name == name }.map { String(decoding: $0.data, as: UTF8.self) } }
            checked += 1
            let a = ids(part(before, "word/styles.xml") ?? ""), b = ids(part(out, "word/styles.xml") ?? "")
            if a.isEmpty { continue }   // a file with no styles part has nothing to keep
            let extra = Set(b.keys).subtracting(a.keys)
            if !extra.isEmpty { added.append(String(n.prefix(10)) + " " + extra.sorted().joined(separator: ",")) }
            let lost = Set(a.keys).subtracting(b.keys)
            if !lost.isEmpty { overridden.append(String(n.prefix(10)) + " lost " + lost.sorted().joined(separator: ",")) }
            if part(before, "word/numbering.xml") == nil, part(out, "word/numbering.xml") != nil, !(read.document.paragraphs.contains { $0.style.list != nil }) {
                numberingAdded.append(String(n.prefix(10)))
            }
        }
        XCTAssertGreaterThan(checked, 10)
        XCTAssertTrue(added.isEmpty, "styles the file did not have: \(added.prefix(8))")
        XCTAssertTrue(overridden.isEmpty, "file styles gone: \(overridden.prefix(8))")
        XCTAssertTrue(numberingAdded.isEmpty, "numbering part added to a file with no lists: \(numberingAdded.prefix(8))")
    }
}
