import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

/// S-P0-3: a saved deck keeps its slide ids, sections, comments and rich notes.
final class SlideIdentityTests: XCTestCase {
    private func corpus(_ name: String) throws -> Data {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("\(name) not in the corpus cache") }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    private func roundTrip(_ d: DeckController) throws -> PptxPackage { PptxPackage(try Zip.read(try Pptx.write(d))) }
    private func presentation(_ p: PptxPackage) -> String { String(data: p.parts["ppt/presentation.xml"]!, encoding: .utf8)! }
    private func slideIds(_ pres: String) -> [Int] {
        pres.components(separatedBy: "<p:sldId id=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
    }
    private func sections(_ pres: String) -> [(name: String, ids: [Int])] {
        pres.components(separatedBy: "<p14:section name=\"").dropFirst().map { chunk in
            let name = String(chunk.prefix { $0 != "\"" })
            let ids = chunk.components(separatedBy: "<p14:sldId id=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
            return (name, ids)
        }
    }
    private func load(_ data: Data) throws -> DeckController {
        let (state, theme, package) = try Pptx.read(data)
        let d = DeckController()
        d.load(state, theme: theme, package: package)
        return d
    }

    func testSlidesKeepTheirIdsAndSectionsFollowAnAddedSlide() throws {
        let d = try load(try corpus("lo-slide-sections.pptx"))
        _ = d.addSlide()
        let pres = presentation(try roundTrip(d))
        XCTAssertEqual(slideIds(pres).prefix(7), [401, 405, 377, 366, 402, 403, 404])
        XCTAssertEqual(slideIds(pres).count, 8)
        XCTAssertTrue(slideIds(pres).contains(309))
        let s = sections(pres)
        XCTAssertEqual(s.map(\.name), ["Default Section", "section-demo"])
        XCTAssertEqual(s[0].ids, [401, 405, 377, 366])
        XCTAssertEqual(s[1].ids.count, 4, "the new slide joins the section of the slide before it")
        XCTAssertEqual(Set(s.flatMap(\.ids)), Set(slideIds(pres)))
    }

    func testSectionsFollowAMovedAndADeletedSlide() throws {
        let d = try load(try corpus("lo-slide-sections.pptx"))
        d.deleteSlide(0)          // 401 goes
        d.moveSlide(2, to: 0)     // 402 first: now a first-section slide
        let pres = presentation(try roundTrip(d))
        let ids = slideIds(pres)
        XCTAssertEqual(ids, [402, 377, 366, 403, 404, 309])
        let s = sections(pres)
        // A slide dragged to the top joins the first section, as in PowerPoint; the sections keep their order.
        XCTAssertEqual(s.map(\.name), ["Default Section", "section-demo"])
        XCTAssertEqual(s[0].ids, [402, 377, 366])
        XCTAssertEqual(s[1].ids, [403, 404, 309])
        XCTAssertEqual(Set(s.flatMap(\.ids)), Set(ids))
    }

    func testCommentsSurviveASave() throws {
        let d = try load(try corpus("45545_Comment.pptx"))
        _ = d.addSlide()
        let out = try roundTrip(d)
        let comments = out.parts.keys.filter { $0.hasPrefix("ppt/comments/") }
        XCTAssertEqual(comments.count, 2)
        XCTAssertNotNil(out.parts["ppt/commentAuthors.xml"])
        for part in comments {
            XCTAssertTrue(out.parts.keys.contains { $0.hasPrefix("ppt/slides/_rels/") && String(data: out.parts[$0]!, encoding: .utf8)!.contains((part as NSString).lastPathComponent) },
                          "a slide points at \(part)")
        }
        // A second save keeps them too.
        let again = try roundTrip(try load(try Pptx.write(d)))
        XCTAssertEqual(again.parts.keys.filter { $0.hasPrefix("ppt/comments/") }.count, 2)
    }

    /// Every internal relationship target exists, and no slide-owned part (an embedding, a drawing, a chart, comments) is named by two parts.
    private func assertWholeAndUnshared(_ p: PptxPackage, file: StaticString = #filePath, line: UInt = #line) {
        var owners: [String: String] = [:]
        for k in p.parts.keys.sorted() where k.hasSuffix(".rels") {
            let source = k.replacingOccurrences(of: "_rels/", with: "").replacingOccurrences(of: ".rels", with: "")
            for r in p.rels(source) where !r.external {
                XCTAssertNotNil(p.parts[r.target], "\(source) points at missing \(r.target)", file: file, line: line)
                if PptxWriterCopy.isOwned(r.target) {
                    if let o = owners[r.target], o != source { XCTFail("\(r.target) is shared by \(o) and \(source)", file: file, line: line) }
                    owners[r.target] = source
                }
            }
        }
    }

    func testADuplicatedCommentedSlideCarriesItsComments() throws {
        let d = try load(try corpus("45545_Comment.pptx"))
        let before = try roundTrip(d).parts.keys.filter { $0.hasPrefix("ppt/comments/") }.count
        XCTAssertGreaterThan(before, 0)
        d.duplicateSlide(0)
        let out = try roundTrip(d)
        let comments = out.parts.keys.filter { $0.hasPrefix("ppt/comments/") }
        XCTAssertGreaterThan(comments.count, before, "the copy owns a comments part of its own")
        assertWholeAndUnshared(out)
        let again = try roundTrip(try load(try Pptx.write(d)))
        XCTAssertEqual(again.parts.keys.filter { $0.hasPrefix("ppt/comments/") }.count, comments.count)
    }

    func testRichNotesKeepTheirLook() throws {
        let d = DeckController()
        d.newDeck()
        let slide = d.slides[0]
        var cs = CharStyle(); cs.bold = true; cs.italic = true
        slide.notes.load(RichDocument(paragraphs: [RichParagraph(text: "Say this loudly", runs: [Run(length: 15, style: cs)], style: RichParagraphStyle())]))
        let out = try roundTrip(d)
        let notes = String(data: out.parts["ppt/notesSlides/notesSlide1.xml"]!, encoding: .utf8)!
        XCTAssertTrue(notes.contains("b=\"1\"") && notes.contains("i=\"1\""), "bold and italic are written")
        let back = try load(try Pptx.write(d))
        XCTAssertTrue(back.slides[0].notes.document.paragraphs[0].runs.contains { $0.style.bold && $0.style.italic })
    }

    func testACroppedAndTurnedPictureKeepsItsRecolouring() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let part = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/slides/slide") && !$0.contains("_rels")
            && String(data: package.parts[$0]!, encoding: .utf8)!.contains("<p:pic>") })
        var xml = String(data: package.parts[part]!, encoding: .utf8)!
        let blip = try XCTUnwrap(xml.range(of: "<a:blip r:embed=\"[^\"]+\"/>", options: .regularExpression))
        let tag = String(xml[blip])
        xml.replaceSubrange(blip, with: String(tag.dropLast(2)) + "><a:duotone><a:srgbClr val=\"FF0000\"/><a:srgbClr val=\"0000FF\"/></a:duotone></a:blip>")
        package.parts[part] = Data(xml.utf8)
        let d = try load(try Zip.write(package.parts.keys.sorted().map { ZipEntry(name: $0, data: package.parts[$0]!) }) )
        let pic = try XCTUnwrap(d.slides.flatMap(\.shapes).first { $0.picture != nil })
        d.select(try XCTUnwrap(d.slides.firstIndex { $0.shapes.contains { $0 === pic } }))
        d.selectShapes([pic])
        d.cropPictures(aspect: 1)
        d.setRotationLive(pic, 90)
        let out = try roundTrip(d)
        let saved = out.parts.keys.compactMap { k -> String? in
            guard k.hasPrefix("ppt/slides/slide"), !k.contains("_rels") else { return nil }
            let t = String(data: out.parts[k]!, encoding: .utf8)!
            return t.contains("<p:pic>") ? t : nil
        }.first ?? ""
        XCTAssertTrue(saved.contains("<a:duotone>"), "the recolouring survives the crop and the turn")
        XCTAssertTrue(saved.contains("<a:srcRect"), "the crop is written")
        XCTAssertTrue(saved.contains("rot=\"5400000\""), "the turn is written")
    }
}
