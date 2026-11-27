import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A slide's tags (`p:custDataLst` naming ppt/tags parts, where add-ins keep their own data) survive a save, with the tag
/// part and its content type. The edit-loss sweep found them dropped on every save (aascu 5864 slides 24 and 25, lo-tdf141058-1).
final class PptxSlideTagsKeptTests: XCTestCase {
    private let tag = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:tagLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:tag name="THINKCELLPRESENTATIONDONOTDELETE" val="slide-marker-42"/></p:tagLst>
        """

    func testPlainSaveKeepsTheSlideTags() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let slide = "ppt/slides/slide1.xml"
        let rels = Pptx.relsPath(slide)
        var xml = String(decoding: try XCTUnwrap(package.parts[slide]), as: UTF8.self)
        xml = xml.replacingOccurrences(of: "</p:spTree>", with: "</p:spTree><p:custDataLst><p:tags r:id=\"rIdTag9\"/></p:custDataLst>")
        package.parts[slide] = Data(xml.utf8)
        var r = String(decoding: try XCTUnwrap(package.parts[rels]), as: UTF8.self)
        r = r.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rIdTag9\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/tags\" Target=\"../tags/tag1.xml\"/></Relationships>")
        package.parts[rels] = Data(r.utf8)
        package.parts["ppt/tags/tag1.xml"] = Data(tag.utf8)
        var ct = String(decoding: try XCTUnwrap(package.parts["[Content_Types].xml"]), as: UTF8.self)
        ct = ct.replacingOccurrences(of: "</Types>", with: "<Override PartName=\"/ppt/tags/tag1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.tags+xml\"/></Types>")
        package.parts["[Content_Types].xml"] = Data(ct.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))

        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let saved = String(decoding: try XCTUnwrap(out.parts[slide]), as: UTF8.self)
        XCTAssertTrue(saved.containsSubstring("<p:custDataLst><p:tags r:id="), saved)
        let rel = try XCTUnwrap(out.rels(slide).first { $0.kind == "tags" })
        let part = try XCTUnwrap(out.parts[rel.target])
        XCTAssertTrue(String(decoding: part, as: UTF8.self).containsSubstring("slide-marker-42"))
        XCTAssertEqual(out.overrides[rel.target], "application/vnd.openxmlformats-officedocument.presentationml.tags+xml")
        XCTAssertTrue(saved.containsSubstring("r:id=\"\(rel.id)\""), saved)
    }

    func testPlainSaveKeepsTheSlidesThemeOverride() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let slide = "ppt/slides/slide1.xml"
        let rels = Pptx.relsPath(slide)
        var r = String(decoding: try XCTUnwrap(package.parts[rels]), as: UTF8.self)
        r = r.replacingOccurrences(of: "</Relationships>", with: "<Relationship Id=\"rId77\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/themeOverride\" Target=\"../theme/themeOverride1.xml\"/></Relationships>")
        package.parts[rels] = Data(r.utf8)
        package.parts["ppt/theme/themeOverride1.xml"] = Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:themeOverride xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:clrScheme name=\"Marker77\"/></a:themeOverride>".utf8)
        var ct = String(decoding: try XCTUnwrap(package.parts["[Content_Types].xml"]), as: UTF8.self)
        ct = ct.replacingOccurrences(of: "</Types>", with: "<Override PartName=\"/ppt/theme/themeOverride1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.themeOverride+xml\"/></Types>")
        package.parts["[Content_Types].xml"] = Data(ct.utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        let (state, theme, pkg) = try Pptx.read(try Zip.write(entries))

        let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let rel = try XCTUnwrap(out.rels(slide).first { $0.kind == "themeOverride" })
        XCTAssertTrue(String(decoding: try XCTUnwrap(out.parts[rel.target]), as: UTF8.self).containsSubstring("Marker77"))
        XCTAssertEqual(out.overrides[rel.target], "application/vnd.openxmlformats-officedocument.themeOverride+xml")
    }
}
