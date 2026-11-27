import XCTest
@testable import OfficeApp
@testable import OfficeText

final class VerticalSaveProbeTests: XCTestCase {
    func testProbe() throws {
        let mar = "<w:pgMar w:top=\"1000\" w:right=\"1100\" w:bottom=\"1200\" w:left=\"1300\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        let sz = "<w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
        let mid = "<w:p><w:pPr><w:sectPr>\(sz)\(mar)<w:textDirection w:val=\"tbRl\"/></w:sectPr></w:pPr><w:r><w:t>一</w:t></w:r></w:p>"
        let body = "<w:body>\(mid)<w:p><w:r><w:t>二</w:t></w:r></w:p><w:sectPr>\(sz)\(mar)<w:textDirection w:val=\"tbRl\"/></w:sectPr></w:body>"
        var entries = try Zip.read(try DocxFormat.write(RichDocument(plainText: "a"), pageSetup: .letter))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let a = s.rangeOfSubstring("<w:body>")!, b = s.rangeOfSubstring("</w:body>")!
        s.replaceSubrange(a.lowerBound ..< b.upperBound, with: body)
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        let read = try DocxFormat.read(try Zip.write(entries))
        let p = read.pageSetup!
        print("PROBE last", p.vertical, p.width, p.height, p.marginTop, p.marginRight, p.marginBottom, p.marginLeft)
        let m = read.document.paragraphs[0].style.sectionPage!
        print("PROBE mid", m.vertical, m.width, m.height, m.marginTop, m.marginRight, m.marginBottom, m.marginLeft)
        func sects(_ d: RichDocument, _ p: PageSetup) throws -> String {
            let out = String(decoding: try Zip.read(try DocxFormat.write(d, pageSetup: p)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
            var r = ""; var rest = Substring(out)
            while let x = rest.range(of: "<w:sectPr"), let y = rest.range(of: "</w:sectPr>") { r += rest[x.lowerBound ..< y.upperBound] + "\n"; rest = rest[y.upperBound...] }
            return r
        }
        print("PROBE untouched\n" + (try sects(read.document, p)))
        var d = read.document; var m2 = m; m2.marginTop += 10; d.paragraphs[0].style.sectionPage = m2
        var p2 = p; p2.marginTop += 10
        print("PROBE changed (flow top +10)\n" + (try sects(d, p2)))
    }
}
