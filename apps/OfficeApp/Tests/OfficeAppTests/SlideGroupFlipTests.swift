import XCTest
import OfficeText
@testable import OfficeApp

/// A group turned or mirrored keeps its members' text the way PowerPoint turns it.
final class SlideGroupFlipTests: XCTestCase {
    /// vi-f6ecddd221's ruler: a group turned 180 and flipped both ways is drawn as it stands, numbers upright.
    /// A group mirrored top to bottom turns its members' text half round, as a mirrored shape does its own.
    func testAGroupTurnedAndFlippedBothWaysKeepsItsTextUpright() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let part = "ppt/slides/slide6.xml"
        var slide = try XCTUnwrap(String(data: try XCTUnwrap(package.parts[part]), encoding: .utf8))
        let group = "<p:grpSp><p:nvGrpSpPr><p:cNvPr id=\"76\" name=\"Ruler\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr>"
            + "<a:xfrm rot=\"10800000\" flipH=\"1\" flipV=\"1\"><a:off x=\"1000000\" y=\"4000000\"/><a:ext cx=\"4000000\" cy=\"400000\"/>"
            + "<a:chOff x=\"1000000\" y=\"4000000\"/><a:chExt cx=\"4000000\" cy=\"400000\"/></a:xfrm></p:grpSpPr>"
            + "<p:sp><p:nvSpPr><p:cNvPr id=\"77\" name=\"Text Box 62\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr>"
            + "<a:xfrm><a:off x=\"1000000\" y=\"4000000\"/><a:ext cx=\"300000\" cy=\"400000\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr>"
            + "<p:txBody><a:bodyPr wrap=\"none\"/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\"/><a:t>1</a:t></a:r></a:p></p:txBody></p:sp></p:grpSp>"
        slide = slide.replacingOccurrences(of: "</p:spTree>", with: group + "</p:spTree>")
        package.parts[part] = Data(slide.utf8)
        let state = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) })).0
        let members = state.slides[5].shapes.flatMap { s -> [ShapeState] in
            if case .opaque(let o) = s.kind { return o.rendering }
            return []
        }
        let one = try XCTUnwrap(members.first)
        let turn = (one.rotation + one.textSpin).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(abs(turn), 0, accuracy: 0.01, "text turned \(turn) degrees: rotation \(one.rotation), textSpin \(one.textSpin)")
    }
}
