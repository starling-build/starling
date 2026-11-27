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
        var f = try PptFile(currentUser: user, document: doc)
        f.pictures = cf.stream("Pictures") ?? []
        return PptxPackage(parts(f))
    }

    /// One master (with its theme and one layout) per master of the file and colour scheme in use: a slide
    /// that does not follow its master's scheme gets a clone of the master with its own theme.
    private struct Variant: Hashable { var master: Int; var scheme: [Int] }

    private static func hex(_ rgb: Int) -> String {
        let d = Array("0123456789ABCDEF")
        return String((0 ..< 6).map { d[rgb >> (20 - 4 * $0) & 15] })
    }

    static func parts(_ f: PptFile) -> [ZipEntry] {
        var out: [ZipEntry] = []
        func add(_ name: String, _ xml: String) { out.append(ZipEntry(name: name, data: Data((head + xml).utf8))) }
        func rels(_ items: [(String, String, String)]) -> String {
            "<Relationships xmlns=\"\(relNS)\">" + items.map { "<Relationship Id=\"\($0.0)\" Type=\"\($0.1.containsSubstring("://") ? $0.1 : rel + $0.1)\" Target=\"\($0.2)\"/>" }.joined() + "</Relationships>"
        }
        let defaultScheme = [0xFFFFFF, 0, 0x808080, 0, 0x808080, 0x808080, 0x0000FF, 0x800080]
        func masterIndex(_ s: PptFile.Page) -> Int { f.masters.firstIndex { $0.slideId == s.masterRef } ?? 0 }
        var variants: [Variant] = []
        func variant(_ v: Variant) -> Int {
            if let i = variants.firstIndex(of: v) { return i }
            variants.append(v); return variants.count - 1
        }
        var slideVariant: [Int] = []
        for s in f.slides {
            let m = masterIndex(s)
            slideVariant.append(variant(Variant(master: m, scheme: f.scheme(of: s) ?? defaultScheme)))
        }
        if variants.isEmpty { _ = variant(Variant(master: 0, scheme: f.masters.first?.scheme ?? defaultScheme)) }
        let n = f.slides.count, nm = variants.count
        let pml = "application/vnd.openxmlformats-officedocument.presentationml."
        var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
            + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"\(pml)presentation.main+xml\"/>"
        for k in 1 ... nm {
            types += "<Override PartName=\"/ppt/slideMasters/slideMaster\(k).xml\" ContentType=\"\(pml)slideMaster+xml\"/>"
            types += "<Override PartName=\"/ppt/slideLayouts/slideLayout\(k).xml\" ContentType=\"\(pml)slideLayout+xml\"/>"
            types += "<Override PartName=\"/ppt/theme/theme\(k).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"
        }
        for k in 1 ... max(n, 1) where k <= n {
            types += "<Override PartName=\"/ppt/slides/slide\(k).xml\" ContentType=\"\(pml)slide+xml\"/>"
        }
        add("_rels/.rels", rels([("rId1", "officeDocument", "ppt/presentation.xml")]))

        var presRels: [(String, String, String)] = []
        var masterIds = ""
        for k in 1 ... nm {
            presRels.append(("rIdM\(k)", "slideMaster", "slideMasters/slideMaster\(k).xml"))
            masterIds += "<p:sldMasterId id=\"\(Int64(2147483648) + Int64(2 * (k - 1)))\" r:id=\"rIdM\(k)\"/>"
        }
        var ids = ""
        for k in 1 ... max(n, 1) where k <= n {
            presRels.append(("rIdS\(k)", "slide", "slides/slide\(k).xml"))
            ids += "<p:sldId id=\"\(255 + k)\" r:id=\"rIdS\(k)\"/>"
        }
        let first = f.firstSlideNumber == 1 ? "" : " firstSlideNum=\"\(f.firstSlideNumber)\""
        add("ppt/presentation.xml", "<p:presentation \(ns)\(first)><p:sldMasterIdLst>\(masterIds)</p:sldMasterIdLst>"
            + "<p:sldIdLst>\(ids)</p:sldIdLst><p:sldSz cx=\"\(emu(f.slideWidth))\" cy=\"\(emu(f.slideHeight))\"/>"
            + "<p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>")
        add("ppt/_rels/presentation.xml.rels", rels(presRels))

        let treeHead = "<p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>"
            + "<p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
        let tree = treeHead + "</p:spTree>"
        // Pictures: one media part per store entry used, one relationship per part that shows it.
        var mediaName: [Int: String] = [:]
        var mediaExts = Set<String>()
        var embeds = PptEmbeds()
        func partPictures(_ firstRid: Int) -> (rid: (Int) -> String?, rels: () -> [(String, String, String)], relate: (String, String) -> String) {
            var mine: [(Int, String)] = []
            var extra: [(String, String, String)] = []
            func relate(_ type: String, _ target: String) -> String {
                extra.append(("rIdE\(extra.count + 1)", type, target))
                return extra[extra.count - 1].0
            }
            func rid(_ index: Int) -> String? {
                if let k = mine.firstIndex(where: { $0.0 == index }) { return "rId\(firstRid + k)" }
                if mediaName[index] == nil {
                    guard let b = f.blip(index), !b.data.isEmpty else { return nil }
                    let name = "image\(mediaName.count + 1).\(b.ext)"
                    mediaName[index] = name
                    mediaExts.insert(b.ext)
                    out.append(ZipEntry(name: "ppt/media/" + name, data: Data(b.data)))
                }
                guard let name = mediaName[index] else { return nil }
                mine.append((index, name))
                return "rId\(firstRid + mine.count - 1)"
            }
            return (rid, { mine.enumerated().map { ("rId\(firstRid + $0.offset)", "image", "../media/" + $0.element.1) } + extra }, relate)
        }
        func slideTree(_ shapes: String) -> String { treeHead + shapes + "</p:spTree>" }
        func background(_ rgb: Int?) -> String {
            guard let rgb else { return "" }
            return "<p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"\(hex(rgb))\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>"
        }
        for (i, v) in variants.enumerated() {
            let k = i + 1
            let m = v.master < f.masters.count ? f.masters[v.master] : nil
            let mp = partPictures(3)
            let masterShapes = m.map { f.shapeXML(of: $0, master: true, picture: mp.rid, embed: { embeds.frame($0, id: $1, xfrm: $2, relate: mp.relate) }) } ?? ""
            add("ppt/slideMasters/slideMaster\(k).xml", "<p:sldMaster \(ns)><p:cSld>\(m.flatMap { f.backgroundXML(of: $0, picture: mp.rid) } ?? background(m?.background))\(slideTree(masterShapes))</p:cSld>"
                + "<p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/>"
                + "<p:sldLayoutIdLst><p:sldLayoutId id=\"\(Int64(2147483649) + Int64(2 * i))\" r:id=\"rId1\"/></p:sldLayoutIdLst>\(m.map { f.textStylesXML(of: $0) } ?? "")</p:sldMaster>")
            add("ppt/slideMasters/_rels/slideMaster\(k).xml.rels", rels([("rId1", "slideLayout", "../slideLayouts/slideLayout\(k).xml"), ("rId2", "theme", "../theme/theme\(k).xml")] + mp.rels()))
            let layoutShapes = m.map { f.shapeXML(of: $0, master: true, placeholdersOnly: true) } ?? ""
            add("ppt/slideLayouts/slideLayout\(k).xml", "<p:sldLayout \(ns) type=\"blank\"><p:cSld>\(slideTree(layoutShapes))</p:cSld></p:sldLayout>")
            add("ppt/slideLayouts/_rels/slideLayout\(k).xml.rels", rels([("rId1", "slideMaster", "../slideMasters/slideMaster\(k).xml")]))
            add("ppt/theme/theme\(k).xml", theme(v.scheme))
        }
        for (i, s) in f.slides.enumerated() {
            let k = i + 1
            let attrs = (s.followsMasterObjects ? "" : " showMasterSp=\"0\"") + (s.hidden ? " show=\"0\"" : "")
            let own = s.followsMasterBackground ? nil : s.background
            let sp = partPictures(2)
            let bg = s.followsMasterBackground ? "" : (f.backgroundXML(of: s, picture: sp.rid) ?? background(own))
            add("ppt/slides/slide\(k).xml", "<p:sld \(ns)\(attrs)><p:cSld>\(bg)\(slideTree(f.shapeXML(of: s, picture: sp.rid, embed: { embeds.frame($0, id: $1, xfrm: $2, relate: sp.relate) })))</p:cSld></p:sld>")
            add("ppt/slides/_rels/slide\(k).xml.rels", rels([("rId1", "slideLayout", "../slideLayouts/slideLayout\(slideVariant[i] + 1).xml")] + sp.rels()))
        }
        let mimes = ["png": "image/png", "jpeg": "image/jpeg", "bmp": "image/bmp", "tiff": "image/tiff", "emf": "image/x-emf", "wmf": "image/x-wmf", "pict": "image/x-pict"]
        for e in mediaExts.sorted() { types += "<Default Extension=\"\(e)\" ContentType=\"\(mimes[e] ?? "application/octet-stream")\"/>" }
        for (e, t) in embeds.defaults.sorted(by: { $0.key < $1.key }) where !mediaExts.contains(e) { types += "<Default Extension=\"\(e)\" ContentType=\"\(t)\"/>" }
        for (p, t) in embeds.overrides { types += "<Override PartName=\"\(p)\" ContentType=\"\(t)\"/>" }
        out += embeds.parts
        add("[Content_Types].xml", types + "</Types>")
        return out
    }

    /// A theme whose twelve colours come from a .ppt colour scheme (background, text, shadow, title text,
    /// fill, accent, accent and hyperlink, accent and followed hyperlink): PowerPoint's own conversion puts
    /// them in lt1, dk1, lt2, dk2, accent1, accent2, hlink, folHlink, and repeats background and text in accent3 and 4.
    private static func theme(_ s: [Int]) -> String {
        func c(_ i: Int) -> String { hex(i < s.count ? s[i] : 0) }
        func clr(_ n: String, _ v: String) -> String { "<a:\(n)><a:srgbClr val=\"\(v)\"/></a:\(n)>" }
        let solid = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let ln = "<a:ln w=\"12700\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill></a:ln>"
        return "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Ppt\"><a:themeElements>"
            + "<a:clrScheme name=\"Ppt\">" + clr("dk1", c(1)) + clr("lt1", c(0)) + clr("dk2", c(3)) + clr("lt2", c(2))
            + clr("accent1", c(4)) + clr("accent2", c(5)) + clr("accent3", c(0)) + clr("accent4", c(1))
            + clr("accent5", c(4)) + clr("accent6", c(5)) + clr("hlink", c(6)) + clr("folHlink", c(7)) + "</a:clrScheme>"
            + "<a:fontScheme name=\"Ppt\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont>"
            + "<a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme>"
            + "<a:fmtScheme name=\"Ppt\"><a:fillStyleLst>\(solid)\(solid)\(solid)</a:fillStyleLst>"
            + "<a:lnStyleLst>\(ln)\(ln)\(ln)</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + "<a:bgFillStyleLst>\(solid)\(solid)\(solid)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
    }
}
