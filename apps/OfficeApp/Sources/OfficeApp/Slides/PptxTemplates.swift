// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The parts a new deck is written with: our theme (colours and fonts from
// DeckTheme, a plain format scheme), one master whose text styles match the
// layouts in Deck.swift, the seven layouts bound by PowerPoint's own
// placeholder type/idx pairs, a notes master, and the package's small
// support parts. Written by hand to the PresentationML schema; nothing here
// is copied from a Microsoft template.

import Flutter
import FlutterSwiftBridge
import Foundation

struct PptxTemplates {
    let theme: DeckTheme
    let slideSize: Size

    static let namespaces = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" "
        + "xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" "
        + "xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
    private static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    private func _emu(_ v: Double) -> Int { Int((v * Pptx.emu).rounded()) }
    private func _hex(_ c: Color) -> String { PptxText.hex(c) }

    // MARK: Theme

    func themeXML() -> String {
        let a = theme.accents + Array(repeating: Color(0xFF808080), count: max(0, 6 - theme.accents.count))
        func clr(_ name: String, _ c: Color) -> String { "<a:\(name)><a:srgbClr val=\"\(_hex(c))\"/></a:\(name)>" }
        let fonts = { (f: String) in "<a:latin typeface=\"\(PptxXML.escape(f, attribute: true))\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>" }
        let solid = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let ln = { (w: Int) in "<a:ln w=\"\(w)\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln>" }
        return Self.head + """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="\(PptxXML.escape(theme.name, attribute: true))"><a:themeElements>\
        <a:clrScheme name="\(PptxXML.escape(theme.name, attribute: true))">\
        \(clr("dk1", theme.text))\(clr("lt1", theme.background))\(clr("dk2", Color(0xFF1F2A44)))\(clr("lt2", Color(0xFFE8EBF0)))\
        \(clr("accent1", a[0]))\(clr("accent2", a[1]))\(clr("accent3", a[2]))\(clr("accent4", a[3]))\(clr("accent5", a[4]))\(clr("accent6", a[5]))\
        \(clr("hlink", Color(0xFF0563C1)))\(clr("folHlink", Color(0xFF954F72)))</a:clrScheme>\
        <a:fontScheme name="\(PptxXML.escape(theme.name, attribute: true))"><a:majorFont>\(fonts(theme.headingFont))</a:majorFont>\
        <a:minorFont>\(fonts(theme.bodyFont))</a:minorFont></a:fontScheme>\
        <a:fmtScheme name="\(PptxXML.escape(theme.name, attribute: true))">\
        <a:fillStyleLst>\(solid)\(solid)\(solid)</a:fillStyleLst>\
        <a:lnStyleLst>\(ln(6350))\(ln(12700))\(ln(19050))</a:lnStyleLst>\
        <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>\
        <a:bgFillStyleLst>\(solid)\(solid)\(solid)</a:bgFillStyleLst>\
        </a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
        """
    }

    // MARK: Placeholders

    private func _frame(_ r: Rect) -> Rect {
        let sx = slideSize.width / 960, sy = slideSize.height / 540
        return Rect.fromLTWH(r.left * sx, r.top * sy, r.width * sx, r.height * sy)
    }

    private func _xfrm(_ r: Rect) -> String {
        "<a:xfrm><a:off x=\"\(_emu(r.left))\" y=\"\(_emu(r.top))\"/><a:ext cx=\"\(_emu(r.width))\" cy=\"\(_emu(r.height))\"/></a:xfrm>"
    }

    /// A layout or master placeholder: geometry, body settings and, on a
    /// layout, its own level-1 look and prompt text.
    private func _placeholder(_ id: Int, _ spec: PlaceholderSpec, onLayout: Bool) -> String {
        var ph = ""
        // A master's placeholders are title, body, date, footer and number:
        // no "obj" (an untyped one) — PowerPoint repairs a master that has
        // one. A layout's content placeholder stays untyped.
        let type = spec.phType ?? (onLayout ? nil : (spec.role == .title || spec.role == .ctrTitle ? "title" : "body"))
        if let t = type { ph += " type=\"\(t)\"" }
        if let i = spec.phIdx { ph += " idx=\"\(i)\"" }
        let anchor = spec.anchor.rawValue
        var lst = "<a:lstStyle/>"
        if onLayout {
            var pPr = spec.alignment == .center ? " algn=\"ctr\"" : ""
            if !spec.bullets { pPr += " marL=\"0\" indent=\"0\"" }
            let bu = spec.bullets ? "" : "<a:buNone/>"
            let color = spec.subtle ? "<a:solidFill><a:schemeClr val=\"tx1\"><a:lumMod val=\"65000\"/><a:lumOff val=\"35000\"/></a:schemeClr></a:solidFill>" : ""
            lst = "<a:lstStyle><a:lvl1pPr\(pPr)>\(bu)<a:defRPr sz=\"\(Int(spec.fontSize * 100))\"\(spec.bold ? " b=\"1\"" : "")>\(color)</a:defRPr></a:lvl1pPr></a:lstStyle>"
        }
        let prompt = onLayout ? "<a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\(spec.prompt)</a:t></a:r></a:p>" : "<a:p><a:endParaRPr lang=\"en-US\"/></a:p>"
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(spec.name) Placeholder \(id - 1)\"/>"
            + "<p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph\(ph)/></p:nvPr></p:nvSpPr>"
            + "<p:spPr>\(_xfrm(_frame(spec.frame)))</p:spPr>"
            + "<p:txBody><a:bodyPr anchor=\"\(anchor)\"><a:normAutofit/></a:bodyPr>\(lst)\(prompt)</p:txBody></p:sp>"
    }

    /// The date, footer and slide number as PowerPoint's master and layouts
    /// carry them (type and idx as PowerPoint's), so a slide's own — and
    /// PowerPoint's Header & Footer dialog — have something to bind to.
    private func _footers(startId: Int) -> String {
        let specs: [(type: String, idx: String, left: Double, width: Double, algn: String, name: String)] = [
            ("dt", "10", 66, 216, "l", "Date Placeholder"),
            ("ftr", "11", 318, 324, "ctr", "Footer Placeholder"),
            ("sldNum", "12", 678, 216, "r", "Slide Number Placeholder"),
        ]
        var out = ""
        for (i, f) in specs.enumerated() {
            let id = startId + i
            let content: String
            switch f.type {
            case "dt": content = "<a:fld id=\"{8F3A1C55-2B7E-4C1D-9A60-3E5B7D2C4F10}\" type=\"datetime1\"><a:rPr lang=\"en-US\"/><a:t>1/1/2026</a:t></a:fld>"
            case "sldNum": content = "<a:fld id=\"{2C6E9B71-4D3A-4E8F-B5C2-7A1D0F3E6B24}\" type=\"slidenum\"><a:rPr lang=\"en-US\"/><a:t>‹#›</a:t></a:fld>"
            default: content = "<a:endParaRPr lang=\"en-US\"/>"
            }
            out += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(f.name) \(id - 1)\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr>"
                + "<p:nvPr><p:ph type=\"\(f.type)\" sz=\"quarter\" idx=\"\(f.idx)\"/></p:nvPr></p:nvSpPr>"
                + "<p:spPr>\(_xfrm(_frame(Rect.fromLTWH(f.left, 500.5, f.width, 28.75))))</p:spPr>"
                + "<p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\" anchor=\"ctr\"/>"
                + "<a:lstStyle><a:lvl1pPr algn=\"\(f.algn)\"><a:defRPr sz=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"><a:tint val=\"75000\"/></a:schemeClr></a:solidFill></a:defRPr></a:lvl1pPr></a:lstStyle>"
                + "<a:p>\(content)</a:p></p:txBody></p:sp>"
        }
        return out
    }

    private static let groupHead = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"

    // MARK: Master and layouts

    private func _level(_ n: Int, size: Double, bullet: Bool, before: Double, font: String) -> String {
        let marL = bullet ? Int(Double(n + 1) * 18 * Pptx.emu) : 0
        let indent = bullet ? -Int(18 * Pptx.emu) : 0
        let bu = bullet ? "<a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>" : "<a:buNone/>"
        return "<a:lvl\(n + 1)pPr marL=\"\(marL)\" indent=\"\(indent)\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\">"
            + "<a:lnSpc><a:spcPct val=\"90000\"/></a:lnSpc><a:spcBef><a:spcPts val=\"\(Int(before * 100))\"/></a:spcBef>\(bu)"
            + "<a:defRPr sz=\"\(Int(size * 100))\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill>"
            + "<a:latin typeface=\"\(font)\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl\(n + 1)pPr>"
    }

    func master() -> String {
        let specs = SlideLayoutKind.titleAndContent.placeholders
        var tree = ""
        for (i, s) in specs.enumerated() { tree += _placeholder(i + 2, s, onLayout: false) }
        tree += _footers(startId: specs.count + 2)
        var layouts = ""
        for i in 0 ..< SlideLayoutKind.allCases.count {
            layouts += "<p:sldLayoutId id=\"\(Int64(2_147_483_649) + Int64(i))\" r:id=\"rIdL\(i + 1)\"/>"
        }
        let body = (0 ..< 9).map { n in
            _level(n, size: [28, 24, 20, 18, 18, 18, 18, 18, 18][n], bullet: true, before: 10, font: "+mn-lt")
        }.joined()
        let other = (0 ..< 9).map { n in _level(n, size: 18, bullet: false, before: 0, font: "+mn-lt") }.joined()
        let title = _level(0, size: 44, bullet: false, before: 0, font: "+mj-lt")
        return Self.head + """
        <p:sldMaster \(Self.namespaces)><p:cSld>\(_masterBackground())<p:spTree>\(Self.groupHead)\(tree)</p:spTree></p:cSld>\
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
        <p:sldLayoutIdLst>\(layouts)</p:sldLayoutIdLst>\
        <p:txStyles><p:titleStyle>\(title)</p:titleStyle><p:bodyStyle>\(body)</p:bodyStyle><p:otherStyle>\(other)</p:otherStyle></p:txStyles></p:sldMaster>
        """
    }

    /// The theme's background: its colour by reference, or its gradient.
    private func _masterBackground() -> String {
        let f = theme.backgroundFill
        guard f.stops.count >= 2 else {
            return "<p:bg><p:bgRef idx=\"1001\"><a:schemeClr val=\"bg1\"/></p:bgRef></p:bg>"
        }
        let stops = f.stops.map { "<a:gs pos=\"\(Int(($0.position * 100000).rounded()))\"><a:srgbClr val=\"\(_hex($0.color))\"/></a:gs>" }.joined()
        return "<p:bg><p:bgPr><a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(Int(f.angle * 60000))\" scaled=\"0\"/></a:gradFill><a:effectLst/></p:bgPr></p:bg>"
    }

    func layout(_ kind: SlideLayoutKind) -> String {
        let type: String
        switch kind {
        case .titleSlide: type = "title"
        case .titleAndContent: type = "obj"
        case .sectionHeader: type = "secHead"
        case .twoContent: type = "twoObj"
        case .comparison: type = "twoTxTwoObj"
        case .titleOnly: type = "titleOnly"
        case .blank: type = "blank"
        }
        var tree = ""
        for (i, s) in kind.placeholders.enumerated() { tree += _placeholder(i + 2, s, onLayout: true) }
        tree += _footers(startId: kind.placeholders.count + 2)
        return Self.head + """
        <p:sldLayout \(Self.namespaces) type="\(type)" preserve="1"><p:cSld name="\(kind.name)"><p:spTree>\(Self.groupHead)\(tree)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """
    }

    // MARK: Notes

    func notesMaster() -> String {
        let img = "<p:sp><p:nvSpPr><p:cNvPr id=\"2\" name=\"Slide Image Placeholder 1\"/><p:cNvSpPr><a:spLocks noGrp=\"1\" noRot=\"1\" noChangeAspect=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"sldImg\" idx=\"2\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"1143000\"/><a:ext cx=\"5486400\" cy=\"3086100\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr></p:sp>"
        let body = "<p:sp><p:nvSpPr><p:cNvPr id=\"3\" name=\"Notes Placeholder 2\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph type=\"body\" sz=\"quarter\" idx=\"3\"/></p:nvPr></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"685800\" y=\"4400550\"/><a:ext cx=\"5486400\" cy=\"3600450\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr><p:txBody><a:bodyPr vert=\"horz\" lIns=\"91440\" tIns=\"45720\" rIns=\"91440\" bIns=\"45720\" rtlCol=\"0\"/><a:lstStyle/><a:p><a:pPr lvl=\"0\"/><a:r><a:rPr lang=\"en-US\"/><a:t>Notes</a:t></a:r></a:p></p:txBody></p:sp>"
        let level = "<a:lvl1pPr marL=\"0\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\"><a:defRPr sz=\"1200\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl1pPr>"
        return Self.head + """
        <p:notesMaster \(Self.namespaces)><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\(Self.groupHead)\(img)\(body)</p:spTree></p:cSld>\
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
        <p:notesStyle>\(level)</p:notesStyle></p:notesMaster>
        """
    }

    static func notesSlide(_ paragraphs: String) -> String {
        head + """
        <p:notes \(namespaces)><p:cSld><p:spTree>\(groupHead)\
        <p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>\
        <p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>\
        </p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>
        """
    }

    // MARK: Presentation and support parts

    func presentation(slideIds: String) -> String {
        let cx = _emu(slideSize.width), cy = _emu(slideSize.height)
        let four3 = abs(slideSize.width / slideSize.height - 4.0 / 3.0) < 0.01 ? " type=\"screen4x3\"" : ""
        let levels = (0 ..< 9).map { n in
            "<a:lvl\(n + 1)pPr marL=\"\(n * 457200)\" algn=\"l\" defTabSz=\"914400\" rtl=\"0\" eaLnBrk=\"1\" latinLnBrk=\"0\" hangingPunct=\"1\"><a:defRPr sz=\"1800\" kern=\"1200\"><a:solidFill><a:schemeClr val=\"tx1\"/></a:solidFill><a:latin typeface=\"+mn-lt\"/><a:ea typeface=\"+mn-ea\"/><a:cs typeface=\"+mn-cs\"/></a:defRPr></a:lvl\(n + 1)pPr>"
        }.joined()
        return Self.head + """
        <p:presentation \(Self.namespaces) saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rIdM"/></p:sldMasterIdLst>\
        <p:notesMasterIdLst><p:notesMasterId r:id="rIdNM"/></p:notesMasterIdLst><p:sldIdLst>\(slideIds)</p:sldIdLst>\
        <p:sldSz cx="\(cx)" cy="\(cy)"\(four3)/><p:notesSz cx="6858000" cy="9144000"/>\
        <p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr>\(levels)</p:defaultTextStyle></p:presentation>
        """
    }

    static let presProps = head + "<p:presentationPr \(namespaces)/>"
    static let viewProps = head + "<p:viewPr \(namespaces)><p:normalViewPr><p:restoredLeft sz=\"15620\"/><p:restoredTop sz=\"94660\"/></p:normalViewPr><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"
    static let tableStyles = head + "<a:tblStyleLst xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\"/>"

    static func core() -> String {
        let now = OfficeDates.iso8601(Date())
        return head + """
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>Presentation</dc:title><dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified></cp:coreProperties>
        """
    }

    static func app(slides: Int) -> String {
        head + """
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Starling Slides</Application><Slides>\(slides)</Slides><PresentationFormat>On-screen Show</PresentationFormat></Properties>
        """
    }
}
