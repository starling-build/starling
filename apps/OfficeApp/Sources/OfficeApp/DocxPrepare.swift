// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// .docx — WordprocessingML in a zip. The reader covers what the document
// model can hold: paragraphs with runs (bold, italic, underline, strike,
// size, colour, highlight, font, sub/superscript, hyperlinks), paragraph
// alignment, indents, spacing, headings via the style table, lists via the
// numbering table, page breaks, tables (cells as cell-tagged paragraphs,
// column widths from the grid), inline pictures, headers and footers, and
// the section's paper size and margins. The writer emits a minimal package
// (document, styles, numbering, relationships, media) that Word,
// LibreOffice and macOS all open.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation
#if canImport(FoundationXML) && !os(WASI)
import FoundationXML
#endif

// Part of the .docx reader (split from Docx.swift, members unchanged).

extension DocxFormat {
    // MARK: Reading

    /// Word keeps paragraph indents and spacing, line and row heights in
    /// 16 bits, a border's width in 8 and its gap in 5, and a run's text
    /// scale in 16, and a file's value past that range is read wrapped
    /// (xa dx4j's probe, in Word's print: indent 66256 is 720, space
    /// before 65537 is 1, a 65535 first line is a 1-twip hanging, an
    /// exact 65535 line is at least 1 twip, an exact 65537 row is 1 twip
    /// tall and hides its text, a border of sz 256 and space 32 is a
    /// hairline on the text, a 65636% scale is 100%). An exact height is
    /// held negated before it wraps, so it can come back as "at least".
    /// The values are rewritten in the markup before it is read, so every
    /// reader of them agrees; values in range are left alone.
    static func _wrapWordWidths(_ node: XNode, parent: String = "") {
        func wrap16(_ v: Int) -> Int { ((v + 32768) & 0xFFFF) - 32768 }
        func big(_ key: String) -> Int? {
            guard let s = node.attrs[key], let v = Int(s), v > 32767 || v < -32768 else { return nil }
            return v
        }
        let before = node.attrs
        defer { if node.attrs != before { RuleTrace.hit("word-wraps-values-past-16-bits") } }
        switch node.name {
        case "w:ind":
            for key in ["w:left", "w:right", "w:start", "w:end"] { if let v = big(key) { node.attrs[key] = String(wrap16(v)) } }
            if let v = big("w:firstLine") {
                let w = wrap16(v)
                if w < 0 { node.attrs["w:firstLine"] = nil; node.attrs["w:hanging"] = String(-w) } else { node.attrs["w:firstLine"] = String(w) }
            } else if let v = big("w:hanging") {
                let w = wrap16(v)
                if w < 0 { node.attrs["w:hanging"] = nil; node.attrs["w:firstLine"] = String(-w) } else { node.attrs["w:hanging"] = String(w) }
            }
        case "w:spacing" where parent == "w:pPr":
            for key in ["w:before", "w:after"] { if let v = big(key) { node.attrs[key] = String(max(0, wrap16(v))) } }
            if let v = big("w:line") {
                switch node.attrs["w:lineRule"] ?? "auto" {
                case "exact":
                    let w = wrap16(-v)
                    node.attrs["w:line"] = String(abs(w))
                    if w > 0 { node.attrs["w:lineRule"] = "atLeast" }
                case "atLeast": node.attrs["w:line"] = String(max(0, wrap16(v)))
                default: break
                }
            }
        case "w:trHeight":
            if let v = big("w:val") {
                if node.attrs["w:hRule"] == "exact" {
                    let w = wrap16(-v)
                    node.attrs["w:val"] = String(abs(w))
                    if w > 0 { node.attrs["w:hRule"] = "atLeast" }
                } else {
                    node.attrs["w:val"] = String(max(0, wrap16(v)))
                }
            }
        case "w:w" where parent == "w:rPr":
            if let s = node.attrs["w:val"], let v = Int(s), v > 0xFFFF { node.attrs["w:val"] = String(v & 0xFFFF) }
        default:
            if node.name == "w:bdr" || ["w:pBdr", "w:tblBorders", "w:tcBorders", "w:pgBorders"].contains(parent) {
                if let s = node.attrs["w:sz"], let v = Int(s), v > 0xFF { node.attrs["w:sz"] = String(v & 0xFF) }
                if let s = node.attrs["w:space"], let v = Int(s), v > 31 { node.attrs["w:space"] = String(v & 31) }
            }
        }
        for child in node.children { _wrapWordWidths(child, parent: node.name) }
    }

    /// A width that is a share of the page's or margins' (`wp14:sizeRelH`,
    /// `pctWidth` in thousandths of a percent) is that share of the section's
    /// page or text area in Word, whatever extent the file also states:
    /// LibreOffice's tdf92724 pull quote says 2360930 EMU (185.9pt) and 40% of
    /// the margins (180.5pt), and Word sets its text in the 166.1pt the share
    /// leaves; ours took the extent's 171.5 and ran a word longer on five of
    /// its lines. The extent is rewritten in the markup, before the drawing is
    /// read, so every reader of it agrees. Each section's own page.
    static func _applyShareWidths(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        var pending: [XNode] = []
        for child in body.children {
            if child.name == "w:sectPr" { _resolveShareWidths(pending, child); pending = []; continue }
            pending += child.descendants("wp:anchor")
            if child.name == "w:p", let sect = child.first("w:pPr")?.first("w:sectPr") { _resolveShareWidths(pending, sect); pending = [] }
        }
    }

    /// Ids of the footnotes that open a section whose footnotePr says
    /// numRestart eachSect: Word numbers that section's notes from 1 again
    /// (471e57de: the second section's note prints "1", ours "2").
    @inline(never)
    /// A section whose own footnotePr names no numRestart takes the settings' (`settingsRestart`).
    static func _footnoteRestartIDs(_ body: XNode, settingsRestart: String? = nil) -> Set<Int> {
        var out: Set<Int> = []
        var first: Int? = nil
        func close(_ sect: XNode?) {
            guard sect != nil else { return }
            if let f = first, (sect?.first("w:footnotePr")?.first("w:numRestart")?["w:val"] ?? settingsRestart) == "eachSect" { out.insert(f) }
            first = nil
        }
        func walk(_ n: XNode) {
            if n.name == "w:footnoteReference", first == nil, let id = Int(n["w:id"] ?? "") { first = id }
            if n.name == "w:p" {
                for c in n.children where c.name != "w:pPr" { walk(c) }
                close(n.first("w:pPr")?.first("w:sectPr"))
                return
            }
            for c in n.children { walk(c) }
        }
        for c in body.children {
            if c.name == "w:sectPr" { close(c); continue }
            walk(c)
        }
        return out
    }

    /// The share widths of `anchors`, on `sect`'s page. A header's or footer's
    /// are on the last section's (lo-9c6cc479's footer rule, 100% of the margins:
    /// 446.6pt in Word's print, the 468pt extent here).
    static func _resolveShareWidths(_ anchors: [XNode], _ sect: XNode?) {
        guard !anchors.isEmpty, let sect, let sz = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
              let w = Double(sz["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") else { return }
        let gutter = Double(mar["w:gutter"] ?? "") ?? 0
        for anchor in anchors {
            guard let rel = anchor.first("wp14:sizeRelH"), let pct = Double(rel.first("wp14:pctWidth")?.text ?? ""), pct > 0,
                  let extent = anchor.first("wp:extent"), let cx = extent["cx"], Double(cx) != nil else { continue }
            let span: Double
            switch rel["relativeFrom"] ?? "" {
            case "margin": span = w - l - r - gutter
            case "page": span = w
            default: continue
            }
            let emu = String(Int((span / 20 * 12700 * pct / 100_000).rounded()))
            extent.attrs["cx"] = emu
            for ext in anchor.descendants("a:ext") where ext["cx"] == cx { ext.attrs["cx"] = emu }
        }
    }

    /// Word's drop caps. A paragraph holding only `w:framePr w:dropCap="drop"`
    /// (`w:lines` of them) and the letters it drops, on an exact line of
    /// the lines' height, goes before the paragraph it is the first of; the
    /// drop is a box at that paragraph's left, the letters in it at the size
    /// Word sets them in (the lines' height over the text's, by the face's
    /// cap height) and on the last of those lines' baseline, the text round
    /// it as round a square-wrapped box. Here the box is written into
    /// the paragraph after it — the reader reads it as any anchored text
    /// box — and the paragraph itself is dropped from the body. (lo
    /// tdf150438: Word's print sets 53pt "“" in 11pt text three lines
    /// deep, its baseline the third line's, the lines beside it 23.5pt in;
    /// ours set it on a line of its own.)
    static func _foldDropCaps(_ root: XNode) {
        // (The text's room: the section's page less its margins, in points.)
        var column = 451.0
        if let sect = root.first("w:body")?.descendants("w:sectPr").last, let sz = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
           let w = Double(sz["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") {
            column = (w - l - r - (Double(mar["w:gutter"] ?? "") ?? 0)) / 20
        }
        /// The em-widths of a text in Times-like faces, roughly (the
        /// drop's own width and whether its paragraph is all beside it).
        func em(_ text: String) -> Double {
            text.unicodeScalars.reduce(0) { total, c in
                switch c.value {
                case 0x20: return total + 0.25
                case 0x201C, 0x201D: return total + 0.444
                case 0x2018, 0x2019: return total + 0.333
                case 0x2D, 0x2013, 0x2012: return total + (c.value == 0x2D ? 0.333 : 0.5)
                case 0x2014: return total + 1
                case 0x2E80...: return total + 1
                case 0x41...0x5A: return total + 0.7
                default: return total + 0.46
                }
            }
        }
        func fold(_ parent: XNode, top: Bool) {
            var out: [XNode] = []
            var i = 0
            let kids = parent.children
            while i < kids.count {
                let p = kids[i]
                // (A drop cap held in a content control, tdf109308: the control
                // is Word's own bracket round the letter, and the paragraph is
                // a drop cap all the same.)
                if p.name == "w:p", p.first("w:pPr")?.first("w:framePr")?["w:dropCap"] == "drop", p.children.contains(where: { $0.name == "w:sdt" }) {
                    RuleTrace.hit("dropcap-in-content-control")
                    p.children = p.children.flatMap { $0.name == "w:sdt" ? ($0.first("w:sdtContent")?.children ?? []) : [$0] }
                }
                if p.name == "w:p", i + 1 < kids.count, kids[i + 1].name == "w:p",
                   let pPr = p.first("w:pPr"), let frame = pPr.first("w:framePr"), ["drop", "margin"].contains(frame["w:dropCap"] ?? ""),
                   let lines = Double(frame["w:lines"] ?? ""), lines >= 2,
                   let spacing = pPr.first("w:spacing"), spacing["w:lineRule"] == "exact", let line = Double(spacing["w:line"] ?? ""), line > 0,
                   // (More than one run is one cap word where they are all of one look:
                   // tdf109316_dropCaps' "L" and "liquam", 77pt.)
                   p.children.filter({ $0.name != "w:pPr" && $0.name != "w:r" }).isEmpty,
                   case let capRuns = p.children.filter({ $0.name == "w:r" }), !capRuns.isEmpty,
                   capRuns.allSatisfy({ r in r.children.filter { $0.name != "w:rPr" && $0.name != "w:t" }.isEmpty && r.all("w:t").count == 1
                       && r.first("w:rPr").map(PptxXML.serialize) == capRuns[0].first("w:rPr").map(PptxXML.serialize) }),
                   let run = capRuns.first, case let capText = capRuns.compactMap({ $0.first("w:t")?.text }).joined(), !capText.isEmpty,
                   case let host = kids[i + 1], host.first("w:pPr")?.first("w:framePr") == nil {
                    let height = line / 20                      // points: the lines' height
                    let pitch = height / lines
                    // (Word's size: the lines above the last, over the face's
                    // cap height, and the text's own cap height on top.)
                    let capHeight = 0.655
                    var hostSize = 11.0
                    if let r = host.children.first(where: { $0.name == "w:r" }),
                       let sz = r.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init) { hostSize = sz / 2 }
                    // (The cap run's own size wins: lo tdf150200's dash caps say
                    // 130 and 137.5pt, and Word's print has them so; the lines'
                    // size is for a cap that names none.)
                    let ownSize = run.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init).map { $0 / 2 }
                    let size = ownSize ?? hostSize + (lines - 1) * pitch / capHeight
                    let capWidth = em(capText) * size
                    let halfPoints = Int((size * 2).rounded())
                    // (Word for Windows sets a cap that names its own size a point lower: lab dropcap, hyphen,
                    // en dash, figure dash and "L" at 130 and 137.5pt, and a hyphen at 50 and 80, a 39.9pt exact
                    // line raised -5.5pt — every baseline 37.58 from the paragraph's top where this had 36.6.)
                    let lowered = DocxFormat.wordOnWindows && ownSize != nil
                    if lowered { RuleTrace.hit("dropcap-with-its-own-size-sits-a-point-lower") }
                    let baseline = height - 0.25 * pitch + (lowered ? 1.0 : 0)        // the last line's baseline, from the box's top
                    let exact = Int((baseline / 0.8 * 20).rounded())
                    let rPrInner = (run.first("w:rPr")?.children ?? []).filter { $0.name != "w:sz" && $0.name != "w:szCs" && !(ownSize != nil && $0.name == "w:position") }
                        .map { PptxXML.serialize($0) }.joined()
                    let esc = capText.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;")
                    // (A drop "in the margin" hangs outside the column, its right
                    // edge a space short of it, no text beside it: lo
                    // tdf109316_dropCaps' "I", 3 lines of 41pt, stands at x 23
                    // in a column from 57 in Word's print.)
                    let inMargin = frame["w:dropCap"] == "margin"
                    let marginWidth = capText.unicodeScalars.reduce(0.0) { $0 + ($1.value == 0x49 ? 0.333 : em(String($1))) } * size
                    let emu = Int(height * 12700)
                    // (One capital letter in Times is its own advance wide: tdf109308's "L" at 57.5pt, 35.1.)
                    let timesCaps: [Double] = [0.722, 0.667, 0.667, 0.722, 0.611, 0.556, 0.722, 0.722, 0.333, 0.389, 0.722, 0.611, 0.889, 0.722, 0.722, 0.556, 0.722, 0.667, 0.556, 0.611, 0.722, 0.722, 0.944, 0.722, 0.722, 0.611]
                    let exactCap: Double? = capText.unicodeScalars.count == 1 && (0x41...0x5A).contains(capText.unicodeScalars.first!.value)
                        ? timesCaps[Int(capText.unicodeScalars.first!.value) - 0x41] * size : nil
                    if exactCap != nil { RuleTrace.hit("dropcap-box-is-the-capital-wide") }
                    let emuW = exactCap.map { Int($0 * 12700) } ?? max(emu, Int(capWidth * (capText.count > 1 ? 1.05 : 1.5) * 12700))   // (room for the cap's own width: the box takes the text's, no more than its extent)
                    let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
                    let hSpacePoints: Double = (Double(frame["w:hSpace"] ?? "") ?? 0) / 20
                    let distRight: Int = Int(hSpacePoints * 12700)
                    let xml = "<w:r \(ns)><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"\(distRight)\" simplePos=\"0\" relativeHeight=\"0\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>\(inMargin ? -Int((marginWidth + hSpacePoints) * 12700) : 0)</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx=\"\(emuW)\" cy=\"\(emu)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/><wp:wrapSquare wrapText=\"bothSides\"/><wp:docPr id=\"1\" name=\"Drop cap\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(emuW)\" cy=\"\(emu)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent><w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(exact)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:rPr>\(rPrInner)<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/></w:rPr><w:t xml:space=\"preserve\">\(esc)</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"><a:spAutoFit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
                    if let drawing = XNode.parse(Data(xml.utf8)) {
                        let at = host.children.firstIndex(where: { $0.name != "w:pPr" }) ?? host.children.count
                        host.children.insert(drawing, at: at)
                        out.append(host)
                        i += 2
                        continue
                    }
                }
                out.append(p)
                i += 1
            }
            parent.children = out
        }
        if let body = root.first("w:body") { fold(body, top: true) }
    }

    /// Word's text frames. A run of paragraphs holding one `w:framePr` that is
    /// anchored to the text (`w:vAnchor="text"`), with a width, a height and a
    /// place below its paragraph (`w:y`), is a box that stands there and has
    /// the paragraph after it set round it (`w:wrap` "around") or clear of it
    /// ("notBeside"): an anchored text box. Here it is written into the
    /// paragraph after the run as one — read as any anchored text box, and
    /// laid out beside it by the layout's wrapping — and the frame's own
    /// paragraphs go. (lo tdf133924: Word's print sets "Around" 71pt and
    /// "notBeside" 273pt under the text's top, the text round the one and over
    /// and under the other; ours set both frames before the text.)
    /// A table whose every cell paragraph carries the one frame, of the text's
    /// anchor and "auto" wrap, an offset down and nothing else: Word floats it as
    /// a table placed by the text, `w:tblpY` down from the paragraph after it,
    /// and sets that text first, at the top (LibreOffice's tdf164474: "Some text"
    /// at 30.5 over the table's row at 59.4; ours set the row first and the text
    /// under it). The frame is written as the table's own floating position, and
    /// taken off the paragraphs (the table's, and the one after it that carries
    /// the same frame).
    static func _floatFramedTables(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        func cellParagraphs(_ tbl: XNode) -> [XNode] {
            tbl.all("w:tr").flatMap { $0.all("w:tc") }.flatMap { $0.all("w:p") }
        }
        var i = 0
        while i < body.children.count {
            defer { i += 1 }
            let tbl = body.children[i]
            guard tbl.name == "w:tbl", let pr = tbl.first("w:tblPr"), pr.first("w:tblpPr") == nil else { continue }
            let paragraphs = cellParagraphs(tbl)
            guard !paragraphs.isEmpty else { continue }
            let frames = paragraphs.map { $0.first("w:pPr")?.first("w:framePr") }
            guard let frame = frames[0], frames.allSatisfy({ $0 != nil }),
                  Set(frames.map { PptxXML.serialize($0!) }).count == 1,
                  [nil, "text", "page", "margin"].contains(frame["w:vAnchor"]),
                  [nil, "text", "page", "margin"].contains(frame["w:hAnchor"]),
                  frame["w:wrap"] == nil || frame["w:wrap"] == "auto" || frame["w:wrap"] == "around",
                  frame["w:x"] == nil, frame["w:xAlign"] == nil || frame["w:xAlign"] == "center", frame["w:yAlign"] == nil, frame["w:w"] == nil, frame["w:h"] == nil,
                  frame["w:dropCap"] == nil, let y = Int(frame["w:y"] ?? ""), y > 0 else { continue }
            let signature = PptxXML.serialize(frame)
            for p in paragraphs { p.first("w:pPr")?.children.removeAll { $0.name == "w:framePr" } }
            if i + 1 < body.children.count, body.children[i + 1].name == "w:p",
               let f = body.children[i + 1].first("w:pPr")?.first("w:framePr"), PptxXML.serialize(f) == signature {
                body.children[i + 1].first("w:pPr")?.children.removeAll { $0.name == "w:framePr" }
            }
            let pos = XNode(name: "w:tblpPr", attrs: ["w:vertAnchor": frame["w:vAnchor"] ?? "text", "w:horzAnchor": frame["w:hAnchor"] ?? "text", "w:tblpY": String(y)])
            if let xa = frame["w:xAlign"] { pos.attrs["w:tblpXSpec"] = xa }
            pr.children.insert(pos, at: 0)
        }
    }

    static func _foldFrames(_ root: XNode) {
        // (A frame whose text runs turned, `w:textDirection` btLr or tbRl, on
        // the page or margin: a box of the size it says, the text in it
        // turned, where the layout set it across a narrow column — lo
        // frame-direction's two 44pt-wide frames, 820pt tall, and
        // tdf154703_framePrTextDirection's 21.6 by 116 one centred on the page.)
        func turned(_ p: XNode) -> String? {
            guard let d = p.first("w:pPr")?.first("w:textDirection")?["w:val"] else { return nil }
            return ["btLr": "vert270", "tbRl": "vert"][d]
        }
        let _columnTwips: Double = {
            guard let sect = root.first("w:body")?.descendants("w:sectPr").last, let sz = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
                  let w = Double(sz["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") else { return 0 }
            return w - l - r
        }()
        func frameOf(_ p: XNode) -> XNode? {
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, turned(p) != nil || f["w:yAlign"] != nil,
               ["page", "margin"].contains(f["w:vAnchor"] ?? ""), Double(f["w:w"] ?? "").map({ $0 > 0 }) == true,
               Double(f["w:h"] ?? "").map({ $0 > 0 }) == true, f["w:y"] != nil || f["w:yAlign"] != nil,
               f["w:wrap"] == "around", p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (A frame of no stated size, set by the text at the page's outer or inner
            // edge: a page-margin note, LibreOffice's CT-with-frame "0123" — in Word's
            // print it stands at the right of the page, level with the next paragraph's
            // top, in the margin beside no text, and that paragraph keeps its place; ours
            // set it as a line of the text and the paragraph under it, 11pt low.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "page", f["w:xAlign"] == "outside" || f["w:xAlign"] == "inside",
               f["w:wrap"] == "around", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (A frame of no stated size that text does not go round, set at the
            // margin's right edge: a page number in LibreOffice's sdt+framePr —
            // Word's print has its "1" at the right margin on the next paragraph's
            // line, taking no line of its own; ours set it at the left on a line
            // of its own and pushed the text down.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "margin", f["w:xAlign"] == "right",
               f["w:wrap"] == "none" || f["w:wrap"] == "around", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            // (Wrap "around" the same, sa2 d72074ba: a page number as the body's first paragraph, in Word's print at the
            // right margin on the first line of the next paragraph, taking no line of its own.)
            // (A frame of no stated size, at an x on the page beside the text: its
            // box stands at that x whatever column the text is in, as wide as the
            // column — LibreOffice's tdf135035, in a column section of three.)
            if p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil, f["w:w"] == nil, f["w:h"] == nil,
               f["w:vAnchor"] == "text", f["w:hAnchor"] == "page", f["w:xAlign"] == nil, Double(f["w:x"] ?? "") != nil,
               f["w:wrap"] == "around", f["w:y"] != nil, f["w:yAlign"] == nil, p.descendant("w:ins") == nil, p.descendant("w:del") == nil { return f }
            guard p.name == "w:p", let f = p.first("w:pPr")?.first("w:framePr"), f["w:dropCap"] == nil,
                  (f["w:vAnchor"] ?? "text") == "text", Double(f["w:w"] ?? "").map({ $0 > 0 }) == true,
                  // (A frame of no stated vAnchor is anchored to the text only when it leaves room beside it, at most half the
                  // column: sa1 b0e39b18's 324 pt frame in a 504 pt column, with another frame at the right, left a gap too
                  // narrow for a word, and the paragraphs below it were set in that gap instead of under the frame.)
                  f["w:vAnchor"] != nil || Double(f["w:w"] ?? "").map({ $0 * 2 <= _columnTwips }) == true,
                  Double(f["w:h"] ?? "").map({ $0 > 0 }) == true, f["w:y"] != nil, f["w:yAlign"] == nil,
                  f["w:wrap"] == "around" || f["w:wrap"] == "notBeside" else { return nil }
            // (Not a frame whose text is tracked: lo tdf125894's inserted and deleted
            // paragraphs stand in Word's print as one line from the margin, not in
            // the frame's width. And "notBeside" only among frames that text goes
            // round, below: one set at the foot of a paragraph's own line —
            // tdf105035_framePrC's, 28pt down — is set right by the flow's own
            // offset; it is the frames that text goes round that the flow gets
            // wrong, and the ones set beside them tdf133924's.)
            if p.descendant("w:ins") != nil || p.descendant("w:del") != nil { return nil }
            return f
        }
        func signature(_ f: XNode) -> String { PptxXML.serialize(f) }
        guard let body = root.first("w:body") else { return }
        // (A one-cell table whose paragraph carries the frame its neighbours carry is part
        // of that frame: lo fdo60957-2's "G", between the frame's "F" and "H", is set in the
        // frame at x 317 in Word's print; ours left the table in the body at x 65. Set as
        // the frame's paragraph, which loses the table's rules and shading.)
        if RichTextTheme.wordWindowsPages {
            func sig(_ n: XNode?) -> String? { n?.name == "w:p" ? n?.first("w:pPr")?.first("w:framePr").map { signature($0) } : nil }
            for (k, n) in body.children.enumerated() where n.name == "w:tbl" && k > 0 && k + 1 < body.children.count {
                let rows = n.children.filter { $0.name == "w:tr" }
                guard rows.count == 1, case let cells = rows[0].children.filter({ $0.name == "w:tc" }), cells.count == 1,
                      case let ps = cells[0].children.filter({ $0.name == "w:p" }), ps.count == 1,
                      cells[0].children.filter({ $0.name == "w:tbl" }).isEmpty,
                      let mine = sig(ps[0]), sig(body.children[k - 1]) == mine, sig(body.children[k + 1]) == mine else { continue }
                RuleTrace.hit("docx-one-cell-table-in-a-frame-is-the-frame's-paragraph")
                body.children[k] = ps[0]
            }
        }
        // (A framed page number in a content control, LibreOffice's sdt+framePr: the
        // control brackets the paragraph and is no part of its frame.)
        body.children = body.children.flatMap { n -> [XNode] in
            guard n.name == "w:sdt", let content = n.first("w:sdtContent"), !content.children.isEmpty,
                  content.children.allSatisfy({ $0.name == "w:p" && frameOf($0)?["w:wrap"] == "none" }) else { return [n] }
            RuleTrace.hit("docx-frame-in-content-control")
            return content.children
        }
        // (Tables with no paragraph between them are ONE table in Word: dx2 8afcc2c4's TARIFAS,
        // Impuestos and SUPLEMENTOS, whose price column is cut down and whose header row repeats as
        // one table's. Joined when their properties and grids are the same.)
        if RichTextTheme.wordWindowsPages {
            var joined: [XNode] = []
            for n in body.children {
                if n.name == "w:tbl", let prev = joined.last, prev.name == "w:tbl",
                   let pr = prev.first("w:tblPr"), let pn = n.first("w:tblPr"), pr.first("w:tblpPr") == nil, pn.first("w:tblpPr") == nil,
                   let gp = prev.first("w:tblGrid"), let gn = n.first("w:tblGrid"),
                   signature(pr) == signature(pn), signature(gp) == signature(gn) {
                    RuleTrace.hit("docx-adjacent-tables-are-one-table")
                    prev.children.append(contentsOf: n.children.filter { $0.name == "w:tr" })
                    continue
                }
                joined.append(n)
            }
            body.children = joined
        }
        var out: [XNode] = []
        let kids = body.children
        var i = 0
        while i < kids.count {
            guard frameOf(kids[i]) != nil else { out.append(kids[i]); i += 1; continue }
            // (Every run of frames before one paragraph is anchored to it: runs of
            // paragraphs of one frame, one after another.)
            var runs: [(frame: XNode, range: Range<Int>)] = []
            var j = i
            while j < kids.count, let frame = frameOf(kids[j]) {
                var k = j
                while k < kids.count, let f = frameOf(kids[k]), signature(f) == signature(frame) { k += 1 }
                runs.append((frame, j ..< k)); j = k
            }
            // (A bookmark's end between the frame and its paragraph is no paragraph: LibreOffice's
            // tdf107119, "This is a frame" and the text round it, has one.)
            var h = j
            while h < kids.count, kids[h].name == "w:bookmarkStart" || kids[h].name == "w:bookmarkEnd" { h += 1 }
            guard runs.contains(where: { $0.frame["w:wrap"] == "around" || $0.frame["w:wrap"] == "none" }),
                  h < kids.count, kids[h].name == "w:p", kids[h].first("w:pPr")?.first("w:framePr") == nil else {
                out.append(contentsOf: kids[i ..< j]); i = j; continue
            }
            let host = kids[h]
            var drawings: [XNode] = []
            var kept: [XNode] = []
            for (frame, range) in runs {
                var w = Int((Double(frame["w:w"] ?? "") ?? 0) * 635), h = Int((Double(frame["w:h"] ?? "") ?? 0) * 635)
                let sizedByColumn = w == 0 && h == 0 && frame["w:hAnchor"] == "page" && frame["w:x"] != nil && frame["w:xAlign"] == nil
                    && frame["w:vAnchor"] == "text" && kids[range.lowerBound].descendant("w:t") != nil
                var columnPoints = 0.0
                if sizedByColumn {
                    // (The column the section sets: the page less its margins, less the
                    // gaps, over the columns — the section that ends at or after the frame.)
                    var sect: XNode? = nil
                    var q = range.lowerBound
                    while q < kids.count, sect == nil { sect = kids[q].first("w:pPr")?.first("w:sectPr") ?? (kids[q].name == "w:sectPr" ? kids[q] : nil); q += 1 }
                    if let sect, let size = sect.first("w:pgSz"), let mar = sect.first("w:pgMar"),
                       let pw = Double(size["w:w"] ?? ""), let l = Double(mar["w:left"] ?? ""), let r = Double(mar["w:right"] ?? "") {
                        let n = max(1, Double(sect.first("w:cols")?["w:num"] ?? "") ?? 1)
                        let gap = Double(sect.first("w:cols")?["w:space"] ?? "") ?? 720
                        columnPoints = ((pw - l - r - gap * (n - 1)) / n) / 20
                    }
                }
                if sizedByColumn, columnPoints > 0 {
                    // (Its lines wrap at the column, its borders outside the text.)
                    RuleTrace.hit("docx-frame-without-size-is-a-column-wide-box")
                    w = Int((columnPoints + 3.5) * 12700); h = Int(14 * 12700)
                } else if w == 0, h == 0 {
                    // (Sized by its text: the characters at the run's size, and the exact line.)
                    let pPr = kids[range.lowerBound].first("w:pPr")
                    let chars = kids[range.lowerBound].descendants("w:t").reduce(0) { $0 + ($1.text.count) }
                    let size = (Double(kids[range.lowerBound].descendant("w:sz")?["w:val"] ?? "") ?? 20) / 2
                    let line = pPr?.first("w:spacing").flatMap { $0["w:lineRule"] == "exact" ? Double($0["w:line"] ?? "") : nil }.map { $0 / 20 } ?? size * 1.2
                    w = Int(Double(max(1, chars)) * size * 0.6 * 12700); h = Int(line * 12700)
                }
                let y = Int((Double(frame["w:y"] ?? "") ?? 0) * 635)
                let direction = turned(kids[range.lowerBound])
                // (Or aligned on the page, text not turned: lo tdf36117_verticalAdjustment's
                // 116pt by 450pt frame, centred on the page at x 360, which the
                // body goes round in Word's print and the layout sets in the flow.)
                let onPage = ["page", "margin"].contains(frame["w:vAnchor"] ?? "")
                let relV = onPage ? (frame["w:vAnchor"] ?? "page") : "paragraph"
                let vertical = onPage && frame["w:yAlign"] != nil && frame["w:yAlign"] != "inline"
                    ? "<wp:align>\(frame["w:yAlign"]!)</wp:align>" : "<wp:posOffset>\(y)</wp:posOffset>"
                // (A border on a side of the frame takes its `w:space` and twice its
                // width, and a little more, off the room beside it, on top of
                // `w:hSpace`: lab fr2 (Word for Windows, tdf154703's frame,
                // sz 6 / 12 and space 7 / 14 over hSpace 0, 1000 and 2552) ends
                // the lines 9.1, 11.0 and 16.2pt short of where hSpace alone puts
                // them: space + 2 x width + 0.6.)
                func borderGive(_ side: String) -> Double {
                    guard let b = kids[range.lowerBound].first("w:pPr")?.first("w:pBdr")?.first(side), (b["w:val"] ?? "none") != "none",
                          (b["w:val"] ?? "nil") != "nil" else { return 0 }
                    return (Double(b["w:space"] ?? "") ?? 0) + 2 * (Double(b["w:sz"] ?? "") ?? 0) / 8 + 0.6
                }
                let hSpaceL = Int(((Double(frame["w:hSpace"] ?? "") ?? 0) / 20 + borderGive("w:left")) * 12700)
                let hSpaceR = Int(((Double(frame["w:hSpace"] ?? "") ?? 0) / 20 + borderGive("w:right")) * 12700)
                let vSpace = Int((Double(frame["w:vSpace"] ?? "") ?? 0) * 635)
                let relH = ["page": "page", "margin": "margin"][frame["w:hAnchor"] ?? ""] ?? "column"
                let horizontal: String
                if let a = frame["w:xAlign"] { horizontal = "<wp:align>\(a)</wp:align>" }
                else {
                    // (The text, not its border, is at the x.)
                    let inset = 0.0
                    horizontal = "<wp:posOffset>\(Int(((Double(frame["w:x"] ?? "") ?? 0) / 20 - inset) * 12700))</wp:posOffset>"
                }
                let wrap = frame["w:wrap"] == "none" ? "<wp:wrapNone/>" : frame["w:wrap"] == "notBeside" ? "<wp:wrapTopAndBottom/>" : "<wp:wrapSquare wrapText=\"bothSides\"/>"
                let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\""
                let xml = "<w:r \(ns)><w:drawing><wp:anchor distT=\"\(vSpace)\" distB=\"\(vSpace)\" distL=\"\(hSpaceL)\" distR=\"\(hSpaceR)\" simplePos=\"0\" relativeHeight=\"0\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"\(relH)\">\(horizontal)</wp:positionH><wp:positionV relativeFrom=\"\(relV)\">\(vertical)</wp:positionV><wp:extent cx=\"\(w)\" cy=\"\(h)\"/><wp:effectExtent l=\"0\" t=\"0\" r=\"0\" b=\"0\"/>\(wrap)<wp:docPr id=\"1\" name=\"Frame\"/><wp:cNvGraphicFramePr/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp><wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(w)\" cy=\"\(h)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></wps:spPr><wps:txbx><w:txbxContent/></wps:txbx><wps:bodyPr wrap=\"square\"\(direction.map { " vert=\"\($0)\"" } ?? "") lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\">\(sizedByColumn && columnPoints > 0 ? "<a:spAutoFit/>" : "<a:noAutofit/>")</wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
                guard let drawing = XNode.parse(Data(xml.utf8)), let content = drawing.descendant("w:txbxContent") else {
                    kept.append(contentsOf: kids[range]); continue
                }
                for k in range {
                    let p = kids[k]
                    p.first("w:pPr")?.children.removeAll { $0.name == "w:framePr" || (direction != nil && $0.name == "w:textDirection") }
                    content.children.append(p)
                }
                // (A lone empty paragraph with a border, in a frame of stated height: Word
                // draws the box the frame's height, and an empty paragraph here is no
                // taller than a line, or nothing at all: lo-dd3d953e. A line of the frame's
                // height makes the box that tall.)
                if range.count == 1, let p = content.children.first, p.descendant("w:r") == nil,
                   let pPr = p.first("w:pPr"), pPr.first("w:pBdr") != nil, pPr.first("w:spacing") == nil,
                   let fh = Double(frame["w:h"] ?? ""), fh > 0, frame["w:hRule"] != "auto" {
                    // (The box is the line plus each side's width and space, so they come off it;
                    // and a paragraph with no run paints no border in a text box, so it gets a space.)
                    func give(_ side: String) -> Double {
                        guard let b = pPr.first("w:pBdr")?.first(side), (b["w:val"] ?? "none") != "none", (b["w:val"] ?? "nil") != "nil" else { return 0 }
                        return (Double(b["w:space"] ?? "") ?? 0) + (Double(b["w:sz"] ?? "") ?? 0) / 8
                    }
                    let line = Int(max(20, fh - 20 * (give("w:top") + give("w:bottom"))))
                    let w = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
                    if let sp = XNode.parse(Data("<w:spacing \(w) w:line=\"\(line)\" w:lineRule=\"exact\" w:before=\"0\" w:after=\"0\"/>".utf8)),
                       let run = XNode.parse(Data("<w:r \(w)><w:t xml:space=\"preserve\"> </w:t></w:r>".utf8)) {
                        pPr.children.append(sp)
                        p.children.append(run)
                    }
                }
                drawings.append(drawing)
            }
            out.append(contentsOf: kept)
            out.append(contentsOf: kids[j ..< h])
            var at = host.children.firstIndex(where: { $0.name != "w:pPr" }) ?? host.children.count
            for d in drawings { host.children.insert(d, at: at); at += 1 }
            out.append(host)
            i = h + 1
        }
        body.children = out
    }

    /// The chart a drawing is itself: its `c:chart` outside any text box's content
    /// and outside an alternate content's fallback. A chart in a text box's
    /// paragraph is that paragraph's inline object (the text box is the drawing, its
    /// insets and all), and the fallback holds the same chart again: lo fdo78474's
    /// chart drew over the whole frame and chart-size's twice.
    static func _ownChartRid(_ node: XNode) -> String? {
        for child in node.children {
            if child.name == "w:txbxContent" || child.name == "mc:Fallback" { continue }
            if child.name == "c:chart", let rid = child["r:id"] { return rid }
            if let found = _ownChartRid(child) { return found }
        }
        return nil
    }

    /// A section break whose paragraph mark stands while a field's CODE is still open — the field has begun and
    /// not yet separated — is not one: Word keeps the text running, lo-8928a1e9's IF fields wrapped round two of
    /// them, 1 page in its print where ours had 3. (One in a field's result stands: lo-9bb072ca's continuous
    /// breaks inside fields keep their sections.) The break is taken out of the markup, before anything reads
    /// the sections.
    static func _dropSectionBreaksInsideFields(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        var open: [Bool] = []   // each open field: still in its code
        for p in body.descendants("w:p") {
            for mark in p.descendants("w:fldChar") {
                switch mark["w:fldCharType"] {
                case "begin": open.append(true)
                case "separate": if !open.isEmpty { open[open.count - 1] = false }
                case "end": if !open.isEmpty { open.removeLast() }
                default: break
                }
            }
            if open.contains(true), let pPr = p.first("w:pPr"), let at = pPr.children.firstIndex(where: { $0.name == "w:sectPr" }) {
                RuleTrace.hit("section-break-inside-a-field-code-is-ignored")
                pPr.children.remove(at: at)
            }
        }
    }

    /// An IF field that spans body blocks (paragraphs, tables) and shows nothing: Word works out the condition and
    /// shows the true or the false text; when that text is empty, everything the field wraps is gone, the table
    /// inside it too (lo-8928a1e9: `IF ="BASEDMAFAC" "Garantie` + a table + `"""` has no left operand, so the
    /// comparison is false and the false text is empty; 1 page and no table in Word's print). Only a top-level IF
    /// with literal operands whose code never separates; a nested field or any text inside a string counts as
    /// something shown, so a field that might show something stays as it is.
    static func _hideEmptyIfFields(_ root: XNode) {
        guard let body = root.first("w:body") else { return }
        func evaluate(_ code: String) -> Bool? {   // true = the field shows nothing
            let c = Array(code)
            var i = 0
            func skip() { while i < c.count, c[i] == " " || c[i] == "\n" || c[i] == "\t" { i += 1 } }
            func quoted() -> String? {
                guard i < c.count, c[i] == "\"" else { return nil }
                i += 1
                var out = ""
                while i < c.count, c[i] != "\"" { out.append(c[i]); i += 1 }
                guard i < c.count else { return nil }
                i += 1
                return out
            }
            let ops: Set<Character> = ["=", "<", ">"]
            func operand() -> String? {
                skip()
                if let q = quoted() { return q }
                var out = ""
                while i < c.count, c[i] != " ", !ops.contains(c[i]), c[i] != "\"" { out.append(c[i]); i += 1 }
                return out
            }
            skip()
            guard i + 2 <= c.count, String(c[i ..< i + 2]).uppercased() == "IF" else { return nil }
            i += 2
            guard let left = operand() else { return nil }
            skip()
            var op = ""
            while i < c.count, ops.contains(c[i]) { op.append(c[i]); i += 1 }
            guard ["=", "<>", "<", ">", "<=", ">="].contains(op), let right = operand() else { return nil }
            skip()
            guard let yes = quoted() else { return nil }
            skip()
            let no = i < c.count ? quoted() : ""
            guard let no else { return nil }
            let marker: Character = "\u{1}"
            guard !left.contains(marker), !right.contains(marker) else { return nil }
            let cmp: Bool
            if let a = Double(left), let b = Double(right) {
                switch op { case "=": cmp = a == b; case "<>": cmp = a != b; case "<": cmp = a < b; case ">": cmp = a > b; case "<=": cmp = a <= b; default: cmp = a >= b }
            } else {
                let a = left.lowercased(), b = right.lowercased()
                switch op { case "=": cmp = a == b; case "<>": cmp = a != b; case "<": cmp = a < b; case ">": cmp = a > b; case "<=": cmp = a <= b; default: cmp = a >= b }
            }
            return (cmp ? yes : no).isEmpty
        }
        var depth = 0
        var begin: (block: Int, run: XNode)?
        var code = ""
        var separated = false
        var found: [(from: (block: Int, run: XNode), to: (block: Int, run: XNode))] = []
        for (bi, block) in body.children.enumerated() {
            if block.name == "w:tbl" { if depth == 1 { code += "\u{1}" }; continue }
            guard block.name == "w:p" else { continue }
            for run in block.children where run.name == "w:r" {
                for c in run.children {
                    if c.name == "w:fldChar" {
                        switch c["w:fldCharType"] {
                        case "begin":
                            depth += 1
                            if depth == 1 { begin = (bi, run); code = ""; separated = false } else if depth == 2 { code += "\u{1}" }
                        case "separate": if depth == 1 { separated = true }
                        case "end":
                            if depth == 1, let b = begin, !separated, b.block != bi, evaluate(code) == true { found.append((b, (bi, run))) }
                            depth = max(0, depth - 1)
                        default: break
                        }
                    } else if depth == 1, !separated {
                        if c.name == "w:instrText" { code += c.text }
                        else if c.name == "w:t" || c.name == "w:drawing" || c.name == "w:tab" || c.name == "w:br" { code += "\u{1}" }
                    }
                }
            }
            if depth == 1, !separated { code += "\u{1}" }   // (a paragraph mark inside the code is text too)
        }
        // Back to front, so the indexes of the earlier fields stay true.
        for (from, to) in found.reversed() {
            guard let first = body.children[from.block...].first, let last = body.children.indices.contains(to.block) ? body.children[to.block] : nil,
                  first.name == "w:p", last.name == "w:p",
                  let a = first.children.firstIndex(where: { $0 === from.run }), let z = last.children.firstIndex(where: { $0 === to.run }) else { continue }
            RuleTrace.hit("empty-if-field-hides-what-it-wraps")
            let head = Array(first.children[..<a].filter { $0.name != "w:pPr" })
            let tail = Array(last.children[(z + 1)...])
            last.children = last.children.filter { $0.name == "w:pPr" } + head + tail
            body.children.removeSubrange(from.block ..< to.block)
        }
    }

    /// A package whose main part is not named `word/document.xml`: the root
    /// relationships say which it is (LibreOffice's tdf104713_undefinedStyles
    /// names `word/trial.xml`), and it and its relationships file are read
    /// under the usual names. Only a main part in `word/`, whose relative
    /// targets are then the same; any other package is left as it is.
    static func _withStandardMainPart(_ entries: [ZipEntry]) -> [ZipEntry] {
        guard !entries.contains(where: { $0.name == "word/document.xml" }),
              let root = entries.first(where: { $0.name == "_rels/.rels" }).flatMap({ XNode.parse($0.data) }),
              let rel = root.relationships().first(where: { ($0["Type"] ?? "").hasSuffix("/officeDocument") && $0["TargetMode"] != "External" }),
              var main = rel["Target"] else { return entries }
        if main.hasPrefix("/") { main.removeFirst() }
        let parts = main.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "word", entries.contains(where: { $0.name == main }) else { return entries }
        return entries.map { e in
            if e.name == main { return ZipEntry(name: "word/document.xml", data: e.data) }
            if e.name == "word/_rels/\(parts[1]).rels" { return ZipEntry(name: "word/_rels/document.xml.rels", data: e.data) }
            return e
        }
    }
}
