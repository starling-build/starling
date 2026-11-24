// A legacy .ppt written out as the PresentationML parts the pptx reader opens
// (the way DocRead writes a .doc as .docx parts). Step 2: the package skeleton,
// one master with its theme and layout, and one empty slide per slide of the
// show, at the deck's size. Slide content comes in later steps.
//
// Shared code (also built for the web).

import Foundation

enum PptBuild {
    private static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
    private static let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

    /// Master units (576 to the inch) to EMU, rounded once.
    static func emu(_ units: Int) -> Int { (units * 3175 + 1) / 2 }

    /// The file's own bytes as a pptx package, or nil when it is not a readable .ppt.
    static func package(_ bytes: [UInt8]) throws -> PptxPackage {
        guard let cf = try? CompoundFile(bytes), let user = cf.stream("Current User"),
              let doc = cf.stream("PowerPoint Document") else {
            throw OfficeFormats.FormatError.unsupported("a PowerPoint file older than PowerPoint 97, or not a PowerPoint file")
        }
        return PptxPackage(parts(try PptFile(currentUser: user, document: doc)))
    }

    static func parts(_ f: PptFile) -> [ZipEntry] {
        var out: [ZipEntry] = []
        func add(_ name: String, _ xml: String) { out.append(ZipEntry(name: name, data: Data((head + xml).utf8))) }
        func rels(_ items: [(String, String, String)]) -> String {
            "<Relationships xmlns=\"\(relNS)\">" + items.map { "<Relationship Id=\"\($0.0)\" Type=\"\(rel)\($0.1)\" Target=\"\($0.2)\"/>" }.joined() + "</Relationships>"
        }
        let n = f.slideIds.count
        var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        let pml = "application/vnd.openxmlformats-officedocument.presentationml."
        types += "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(pml)presentation.main+xml\"/>"
        types += "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"\(pml)slideMaster+xml\"/>"
        types += "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"\(pml)slideLayout+xml\"/>"
        types += "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        for k in 1 ... max(n, 1) where k <= n {
            types += "<Override PartName=\"/ppt/slides/slide\(k).xml\" ContentType=\"\(pml)slide+xml\"/>"
        }
        add("[Content_Types].xml", types + "</Types>")
        add("_rels/.rels", rels([("rId1", "officeDocument", "ppt/presentation.xml")]))

        var presRels: [(String, String, String)] = [("rIdM", "slideMaster", "slideMasters/slideMaster1.xml")]
        var ids = ""
        for k in 1 ... max(n, 1) where k <= n {
            presRels.append(("rIdS\(k)", "slide", "slides/slide\(k).xml"))
            ids += "<p:sldId id=\"\(255 + k)\" r:id=\"rIdS\(k)\"/>"
        }
        let first = f.firstSlideNumber == 1 ? "" : " firstSlideNum=\"\(f.firstSlideNumber)\""
        add("ppt/presentation.xml", "<p:presentation \(ns)\(first)><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rIdM\"/></p:sldMasterIdLst>"
            + "<p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"\(emu(f.slideWidth))\" cy=\"\(emu(f.slideHeight))\"/>"
            + "<p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        add("ppt/_rels/presentation.xml.rels", rels(presRels))

        let tree = "<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
        add("ppt/slideMasters/slideMaster1.xml", "<p:sldMaster \(ns)>\(tree)</p:spTree></p:cSld>"
            + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
            + "<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rId1\"/></p:sldLayoutIdLst></p:sldMaster>")
        add("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", "theme", "../theme/theme1.xml")]))
        add("ppt/slideLayouts/slideLayout1.xml", "<p:sldLayout \(ns) type=\"blank\">\(tree)</p:spTree></p:cSld></p:sldLayout>")
        add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels([("rId1", "slideMaster", "../slideMasters/slideMaster1.xml")]))
        add("ppt/theme/theme1.xml", theme)
        for k in 1 ... max(n, 1) where k <= n {
            add("ppt/slides/slide\(k).xml", "<p:sld \(ns)>\(tree)</p:spTree></p:cSld></p:sld>")
            add("ppt/slides/_rels/slide\(k).xml.rels", rels([("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml")]))
        }
        return out
    }

    private static var theme: String {
        func clr(_ n: String, _ v: String) -> String { "<a:\(n)><a:srgbClr val=\"\(v)\"/></a:\(n)>" }
        let solid = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let ln = "<a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        return "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Ppt\"><a:themeElements>"
            + "<a:clrScheme name=\"Ppt\">" + clr("dk1", "000000") + clr("lt1", "FFFFFF") + clr("dk2", "000000") + clr("lt2", "FFFFFF")
            + clr("accent1", "808080") + clr("accent2", "808080") + clr("accent3", "808080") + clr("accent4", "808080")
            + clr("accent5", "808080") + clr("accent6", "808080") + clr("hlink", "0000FF") + clr("folHlink", "800080") + "</a:clrScheme>"
            + "<a:fontScheme name=\"Ppt\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont>"
            + "<a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"Ppt\"><a:fillStyleLst>\(solid)\(solid)\(solid)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(ln)\(ln)\(ln)</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(solid)\(solid)\(solid)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
    }
}
