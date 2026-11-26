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


enum DocxFormat {
    enum DocxError: Error { case noDocumentPart, badXML(String) }


    static func read(_ archive: Data) throws -> DocxDocument {
        try BigStack.run { try _read(archive) }
    }

    private static func _read(_ archive: Data) throws -> DocxDocument {
        let entries = _withStandardMainPart(try Zip.read(archive))
        func part(_ name: String) -> Data? { entries.first { $0.name == name }?.data }
        /// The styles part as Word reads it: a document with `w:linkStyles` ("automatically
        /// update document styles") and an attached template Word cannot find takes Word's
        /// built-in Normal over its own (dx2 70b475ea: Arial in the file, Cambria in Word's print).
        func styleTree() -> XNode? {
            guard let styles = part("word/styles.xml").flatMap(XNode.parse) else { return nil }
            if let settings = part("word/settings.xml").flatMap(XNode.parse),
               let link = settings.first("w:linkStyles"), !_isOff(link), let attached = settings.first("w:attachedTemplate"),
               let rid = attached["r:id"],
               let relRoot = part("word/_rels/settings.xml.rels").flatMap(XNode.parse),
               let target = relRoot.relationships().first(where: { $0["Id"] == rid })?["Target"],
               // Only an HFS target ("Volume:dir:file", colon-separated, no URL scheme) makes Word
               // replace Normal from Normal.dotm; a file URL, drive path or relative target keeps the
               // file's own Normal (Word COM, lab linkstyles: 70b475ea with a file:/// or relative
               // target kept Arial; 0c15d329 and 62034d67 with an HFS target were replaced).
               target.containsSubstring(":") && !target.hasPrefix("file:") && !target.hasPrefix("\\\\") && !target.hasPrefix("/")
                && !(target.count > 1 && target.dropFirst().hasPrefix(":") && target.dropFirst(2).first.map { $0 == "\\" || $0 == "/" } == true) {
                _applyBuiltinStyles(styles)
            }
            return styles
        }
        guard let docData = part("word/document.xml") else { throw DocxError.noDocumentPart }
        guard let root = XNode.parse(docData) else { throw DocxError.badXML("word/document.xml") }
        _hoistTablesOutOfParagraphs(root)
        _dropSectionBreaksInsideFields(root)
        _hideEmptyIfFields(root)
        _renumberSequences(root)
        _refreshReferences(root)
        let kept = _keptParts(entries, part)
        // Relationships: hyperlink targets and media parts.
        var rels: [String: String] = [:]
        var relInfo: [String: KeptRel] = [:]
        if let relData = part("word/_rels/document.xml.rels"), let relRoot = XNode.parse(relData) {
            for r in relRoot.relationships() {
                if let id = r["Id"], let target = r["Target"] {
                    rels[id] = target
                    relInfo[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
        }
        // Content types, for the parts kept verbatim.
        var typeByExt: [String: String] = [:], typeByPart: [String: String] = [:]
        if let ct = part("[Content_Types].xml").flatMap(XNode.parse) {
            for d in ct.all("Default") { if let e = d["Extension"], let t = d["ContentType"] { typeByExt[e.lowercased()] = t } }
            for o in ct.all("Override") { if let n = o["PartName"], let t = o["ContentType"] { typeByPart[n.hasPrefix("/") ? String(n.dropFirst()) : n] = t } }
        }
        let contentType: (String) -> String? = { path in
            typeByPart[path] ?? typeByExt[(path.split(separator: ".").last.map(String.init) ?? "").lowercased()]
        }
        let rootNS = root.attrs.filter { $0.key.hasPrefix("xmlns:") }

        let media: (String) -> Data? = { target in
            let name = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            return part(name)
        }
        guard let body = root.first("w:body") else { throw DocxError.badXML("no w:body") }
        _inheritSpace(root)
        WriterMath.heldGridLines = body.first("w:sectPr")?.first("w:docGrid")?["w:type"] == "lines"
        Self._foldDropCaps(root)
        Self._foldFrames(root)
        Self._floatFramedTables(root)
        // A Word document as an alt-chunk: its blocks stand where the chunk
        // does, and its section breaks with them, on paper of Word's default
        // (Letter, an inch all round) whatever the chunk's own pgSz says;
        // its closing section is the outer document's. (lo alt-chunk: Word
        // prints "inner doc, first para" under the outer text on a Letter
        // page and "inner doc, last para" on the A4 page after it; the chunk
        // is read before the section breaks are told how the next starts.)
        for (i, node) in body.children.enumerated().reversed() where node.name == "w:altChunk" {
            guard let id = node["r:id"], let rel = relInfo[id], !rel.external, rel.target.lowercased().hasSuffix(".docx"),
                  let data = part(_resolvePath("word", rel.target)), let inner = Self._innerBody(data) else { continue }
            RuleTrace.hit("docx-alt-chunk-is-blocks")
            let blocks = inner.children.filter { $0.name != "w:sectPr" }
            for sect in blocks.flatMap({ $0.descendants("w:sectPr") }) {
                sect.children.removeAll { $0.name == "w:pgSz" || $0.name == "w:pgMar" }
                sect.children.insert(XNode(name: "w:pgSz", attrs: ["w:w": "12240", "w:h": "15840"]), at: 0)
                sect.children.insert(XNode(name: "w:pgMar", attrs: ["w:top": "1440", "w:right": "1440", "w:bottom": "1440", "w:left": "1440", "w:header": "720", "w:footer": "720", "w:gutter": "0"]), at: 1)
            }
            body.children.replaceSubrange(i ... i, with: blocks)
        }
        Self._applyShareWidths(root)
        // A document with several bodies: Word shows them all, one after
        // the other (MultipleBodyBug came back with the first alone).
        // Each section break in the text, told how the section after it
        // starts (see `_paragraphs`).
        do {
            var sects: [XNode] = []
            var stack = Array(body.children.reversed())
            while let n = stack.popLast() {
                if n.name == "w:sectPr" { sects.append(n) } else if n.name != "w:tbl" { stack.append(contentsOf: n.children.reversed()) }
            }
            // (A continuous section on paper of another size or the other
            // way round starts a page all the same: zh-3ab8a2fb's landscape
            // "附件2" table, continuous after a portrait section, opens page
            // 22 in Word's print; ours set its label at page 21's foot, and
            // the document ran a page long.)
            func paper(_ s: XNode) -> String {
                let size = s.first("w:pgSz")
                return "\(size?["w:w"] ?? "")x\(size?["w:h"] ?? "")"
            }
            for (i, sect) in sects.enumerated().dropLast() {
                let next = sects[i + 1]
                let breaks = (next.first("w:type")?["w:val"] ?? "nextPage") != "continuous" || paper(next) != paper(sect)
                sect.attrs["x-next-breaks"] = breaks ? "1" : "0"
                func vertical(_ s: XNode) -> String { "\(s.first("w:pgMar")?["w:top"] ?? "")/\(s.first("w:pgMar")?["w:bottom"] ?? "")" }
                if !breaks, vertical(next) != vertical(sect) { sect.attrs["x-next-vmargins"] = "1" }
            }
        }
        // (A section of columns that a continuous section follows, and that has
        // no paragraph of its own after it: the body ends on the paragraph that
        // closes the columns. Word has a last paragraph mark there all the same,
        // and the columns are balanced above it: LibreOffice's tdf103931, six
        // lines of text in three columns of two in Word's print, in one column
        // in ours, which had no paragraph for the break to be at.)
        if let last = body.children.last, last.name == "w:sectPr", (last.first("w:type")?["w:val"] ?? "") == "continuous",
           body.children.count >= 2, case let before = body.children[body.children.count - 2], before.name == "w:p",
           let closing = before.first("w:pPr")?.first("w:sectPr"), Int(closing.first("w:cols")?["w:num"] ?? "") ?? 1 > 1,
           closing.first("w:pgSz")?["w:w"] == last.first("w:pgSz")?["w:w"], closing.first("w:pgSz")?["w:h"] == last.first("w:pgSz")?["w:h"] {
            RuleTrace.hit("docx-last-paragraph-after-the-columns")
            body.children.insert(XNode(name: "w:p", attrs: [:]), at: body.children.count - 1)
        }
        for extra in root.all("w:body").dropFirst() {
            let at = body.children.lastIndex { $0.name == "w:sectPr" } ?? body.children.count
            body.children.insert(contentsOf: extra.children.filter { $0.name != "w:sectPr" }, at: at)
        }
        _reuseInlinePlaceholders(body)
        _bindCoreProperties(body, part: part)
        let notes = _Shared(kept: kept, rels: relInfo, rootNS: rootNS, part: part, contentType: contentType)
        notes.footnoteRestarts = Self._footnoteRestartIDs(body)
        notes.bookmarkNames = Set(body.descendants("w:bookmarkStart").compactMap { $0["w:name"]?.lowercased() })
        // (Those of the other parts too, by their text: a reference into a
        // note or a header finds its name there.)
        var otherParts = ""
        for (name, data) in kept where name.hasPrefix("word/") && name.hasSuffix(".xml") && name != "word/document.xml" && !name.containsSubstring("/_rels/") {
            if name.containsSubstring("header") || name.containsSubstring("footer") || name.containsSubstring("notes") {
                otherParts += String(decoding: data, as: UTF8.self)
            }
        }
        notes.keptBookmarkText = otherParts
        // How note marks are numbered: Word's endnotes count "i, ii, iii"
        // unless the settings say otherwise, its footnotes "1, 2, 3"
        // (endnotes.docx and Bug54849 show "i" in Word's print).
        _mathDefaultJc = nil
        _exactAtAscent = false
        if let settings = part("word/settings.xml").flatMap(XNode.parse) {
            _mathDefaultJc = settings.first("m:mathPr")?.first("m:defJc")?["m:val"]
            _exactAtAscent = settings.first("w:compat")?.first("w:noExtraLineSpacing").map { !_isOff($0) } ?? false
            if let f = settings.first("w:endnotePr")?.first("w:numFmt")?["w:val"] { notes.endnoteFormat = f }
            if let f = settings.first("w:footnotePr")?.first("w:numFmt")?["w:val"] { notes.footnoteFormat = f }
        }
        notes.hasColumns = body.descendants("w:cols").contains { (Int($0["w:num"] ?? "") ?? 1) > 1 }
        if let compat = part("word/settings.xml").flatMap(XNode.parse)?.first("w:compat") {
            let mode = compat.all("w:compatSetting").first { $0["w:name"] == "compatibilityMode" }.flatMap { Int($0["w:val"] ?? "") } ?? 12
            notes.compatMode = mode
            notes.marksFollowBreaks = mode < 15 && (compat.first("w:splitPgBreakAndParaMark").map { !_isOff($0) } ?? false)
        }

        // Kept header and footer parts, before the styles are read: the
        // styles they name must be written too (issue_51265_3's header
        // paragraphs are "Kopfzeile", which fell back to Normal).
        var keptHeaderFooters: [KeptHeaderFooter] = []
        var titlePage = false
        var sectionChange: FormatChange? = nil
        var evenAndOddHeaders = false
        var footerFramed = false
        var keptCompat: String? = nil
        // The default tab distance: 35.4pt in a third of the corpus (metric
        // Word's 1.25cm), and every typed "4.2.8.<tab>text" lands
        // elsewhere under our 36 — bug65649's first lines.
        // (A settings part that holds nothing but the tab distance, as the .doc reader writes it, is read as no settings at all.)
        let _settingsBare = part("word/settings.xml").flatMap(XNode.parse).map { $0.children.allSatisfy { $0.name == "w:defaultTabStop" } } ?? false
        let defaultTabStop = part("word/settings.xml").flatMap(XNode.parse)?.first("w:defaultTabStop")
            .flatMap { Double($0["w:val"] ?? "") }.flatMap { $0 >= 0 ? $0 / 20 : nil }
        if let sect = body.first("w:sectPr") {
            // A header or footer with a picture, a table or a text box
            // (a logo, 60329's banner) is more than its text: the part is
            // kept whole and written back unless the text was edited; the
            // first-page and even-page ones, which the editor has no
            // field for, are kept always.
            titlePage = _on(sect.first("w:titlePg"))
            if let ch = sect.first("w:sectPrChange") {
                sectionChange = FormatChange(author: ch["w:author"] ?? "", date: ch["w:date"] ?? "", oldRPrXML: Self._sectionChangeSaid(sect, was: ch.first("w:sectPr")))
            }
            // The file's compatibility block, as it stands — including an
            // EMPTY one, which is Word's legacy (2003) layout mode and lays
            // text out measurably differently: drawing.docx wrapped tighter
            // under mode 15 and ran two lines ahead by page 7 (13% -> 1.4%
            // with its empty block put back). An earlier reading dropped
            // the empty block over a form_footnotes page that has since
            // turned out to be a one-point knife edge.
            if let settings = part("word/settings.xml").flatMap(XNode.parse), let compat = settings.first("w:compat") {
                if compat.children.isEmpty {
                    keptCompat = "<w:compat/>"
                } else if compat.children.allSatisfy({ $0.name.hasPrefix("w:") }) {
                    keptCompat = PptxXML.serialize(compat)
                }
            }
            // (An on/off element: w:val="false" or "0" or "off" is off; 5ff3d0's
            // settings say so, and every even page lost its header.)
            evenAndOddHeaders = part("word/settings.xml").map { data -> Bool in
                let xml = String(decoding: data, as: UTF8.self)
                guard let at = xml.rangeOfSubstring("<w:evenAndOddHeaders") else { return false }
                let rest = xml[at.upperBound...]
                let tag = rest[..<(rest.firstIndex(of: ">") ?? rest.endIndex)]
                return !["w:val=\"false\"", "w:val=\"0\"", "w:val=\"off\""].contains(where: { String(tag).containsSubstring($0) })
            } ?? false
            for ref in sect.children where ref.name == "w:headerReference" || ref.name == "w:footerReference" {
                // ("odd", which the format does not have, is the default
                // to Word: 60293's "ODD_PAGE_HEADER" on its page 3.)
                let type = ref["w:type"].map { $0 == "odd" ? "default" : $0 } ?? "default"
                guard ["default", "first", "even"].contains(type), let rid = ref["r:id"], let target = relInfo[rid]?.target,
                      let data = media(target), _wellFormed(data), let node = XNode.parse(data) else { continue }
                // Every part is kept, the plainest included, and written back
                // while the editor's text for it is still the file's: the
                // generated form is one line, centred or tabbed into thirds,
                // and says none of a part's border, font, alignment tab,
                // second paragraph or left-set footer (WordWithAttachments'
                // three-line header, form_footnotes' blank footer that still
                // reserves its height, FancyFoot's ruled Cambria line,
                // headerFooter's footer at the left margin).
                // (A framed paragraph in a footer raised over the footer's
                // top — `w:framePr` with a negative `w:y`, so it stands up
                // into the body's room — and Word for Mac lets the body's
                // lines part with no widow control: lab wc2 (Word 16, mode
                // 14); its w:y set to 0 or 1 (lab wc3), the lines stay
                // together again. Not a frame at or under the footer's top:
                // the 36 references whose page numbers stand 1 to 8 twips
                // down keep widow control in Word's prints.)
                func raisedFrame(_ n: XNode) -> Bool {
                    if n.name == "w:framePr", let y = n["w:y"].flatMap(Double.init), y < 0 { return true }
                    return n.children.contains(where: raisedFrame)
                }
                if ref.name == "w:footerReference", raisedFrame(node) { footerFramed = true }
                let path = _resolvePath("word", target)
                notes.keep(path)
                guard notes.kept[path] != nil else { continue }
                keptHeaderFooters.append(KeptHeaderFooter(kind: ref.name == "w:headerReference" ? .header : .footer,
                                                                   type: type, part: path, text: _fieldText(node)))
            }
        }
        // Comments: the part (and Word's extended parts) kept whole; the
        // ranges ride on the runs. Word prints them as balloons, which
        // scale the page (WordWithAttachments, delins, testComment).
        for p in ["word/comments.xml", "word/commentsExtended.xml", "word/commentsIds.xml", "word/commentsExtensible.xml"] {
            if let data = part(p), _wellFormed(data) { notes.keep(p) }
        }
        // Theme fonts: "minorHAnsi" in a run or style means the theme's
        // minor Latin face — Calibri only in Word's default theme. Resolved
        // in the trees before anything reads a font, so a Cambria or Aptos
        // document lays out (and saves) in Cambria or Aptos; the theme part
        // itself rides along in keptParts.
        let theme = _themeFonts(entries)
        notes.themeFonts = theme
        _themeColors = _themePalette(entries)
        _resolveThemeFonts(root, theme)
        let thaiAlternates = _thaiAlternates(entries)
        _followThaiAlternates(root, thaiAlternates)

        // Styles: which paragraph styles are ours (headings, Title, Quote…),
        // and what they look like in this package — Word's Heading 1 is
        // not our Heading 1, so the sheet takes the file's word for it.
        // Spacing is Word's hierarchy: the document defaults (0 after and
        // single lines when the file states none), Normal on top, a
        // table's style on top of that inside its cells, then the named
        // style, then the paragraph's own — every paragraph comes out
        // with the absolute values the layout draws.
        var styleByDocx: [String: String] = [:]
        var styleSourceIds: [String: String] = [:]
        var sheet = RichStyleSheet.word
        var base = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
        // A package with no styles part at all is laid out by Word's own
        // Normal of the day — 12pt, 8pt after, lines of 1.16 (measured off
        // Word 16's print of Bug66263-paragraph) — not by the bare
        // defaults a styles part that says nothing leaves.
        let noStyles = part("word/styles.xml") == nil
        if noStyles { base = RichParagraphStyle(spaceAfter: 8, lineSpacing: 278.0 / 240) }
        var tableBases: [String: RichParagraphStyle] = [:]
        // The same over the document defaults alone, for a cell paragraph
        // whose style chain does not reach Normal.
        var tableRootBases: [String: RichParagraphStyle] = [:]
        // The same with the style's first-row paragraph look on top.
        var headerBases: [String: RichParagraphStyle] = [:]
        var headerRootBases: [String: RichParagraphStyle] = [:]
        var docBase = base
        // Cell margins by table style, each side from the style's chain
        // down to the default table style, then Word's own (0, 5.4pt).
        var tableMargins: [String: _Margins] = [:]
        var defaultMargins = _Margins()
        var noDefaultTableStyle = false
        // Whether a table style draws borders (Table Grid does, Normal Table
        // does not): a table that says nothing itself takes its style's word.
        var tableBorders: [String: _Borders] = [:]
        // A table style's own indent (twips), down its w:basedOn chain.
        var tableIndents: [String: Double] = [:]
        var tableEdges: [String: BorderEdges?] = [:]
        var tableSides: [String: XNode] = [:]
        var defaultBorders: _Borders? = nil
        // A table style's conditional parts: the first row's fill and run
        // look, the body rows' bands.
        var tableConds: [String: _Cond] = [:]
        // A table style's own text size, by its chain, where the Normal style
        // says none of its own (`tableSizes`).
        var tableSizes: [String: Double] = [:]
        var tableSpacings: [String: Double] = [:]
        var normalStatesSize = false
        // A table style's other run properties, by its chain (its own over
        // its parent's), and what the Normal style states of its own: the
        // table's stand under the paragraph's style, over the defaults.
        var tableChars: [String: CharStyle] = [:]
        var normalStatedChar = CharStyle()
        // Table styles (and the default one) that fix the layout: a table
        // that says nothing itself is then not autofitted.
        var fixedTableStyles = Set<String>()
        var defaultTableFixed = false
        // Numbering a paragraph style carries itself (a numbered heading
        // style): the paragraphs of that style number without a numPr.
        var styleNums: [String: (numId: String, ilvl: Int, left: Double?, first: Double?)] = [:]
        var paragraphStyles: [String: XNode] = [:]
        var styleAliases: [String: String] = [:]
        var keptCharacterStyles: [String: String] = [:]
        var keptTableStyles: [String: String] = [:]
        var keptCharacterStyleIds: [String: String] = [:]
        if let styles = styleTree() {
            _resolveThemeFonts(styles, theme)
            _followThaiAlternates(styles, thaiAlternates)
            _normaliseStyleIds(styles)
            // A styles part with NO w:pPrDefault at all (WPS writes them
            // so: six of a sample of 68 Chinese government documents, every
            // one 6-37% off) is spaced by Word's own Normal — 8pt after,
            // lines of 278/240, the same as a package with no styles part.
            // An EMPTY w:pPrDefault is a statement, and means none.
            if styles.first("w:docDefaults")?.first("w:pPrDefault") == nil {
                base = RichParagraphStyle(spaceAfter: 8, lineSpacing: 278.0 / 240)
            }
            if let defaults = styles.first("w:docDefaults")?.first("w:pPrDefault")?.first("w:pPr") {
                _paragraphProps(defaults, into: &base)
                // (A frame in the document defaults of no width and no height, as
                // a Pages export writes: Word sets no frame from it. Inherited here
                // it took a header's or footer's picture paragraph out of the flow,
                // and the body stood 56pt above Word's: dx2 es 335fbcf8.)
                if let fp = defaults.first("w:framePr"), (Double(fp["w:w"] ?? "") ?? 0) == 0, (Double(fp["w:h"] ?? "") ?? 0) == 0 {
                    base.frame = nil
                    base.frameXML = nil
                }
            }
            // What a style with no w:basedOn starts from: the document
            // defaults alone. Only a style based on Normal takes Normal's
            // look (Bug54771b's No Spacing names no parent, and came back
            // with Normal's 10pt after and 1.15 lines in every cell).
            docBase = base
            _latinLangKorean = {
                let own = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }?.first("w:rPr")?.first("w:lang")?["w:val"]
                let def = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:lang")?["w:val"]
                return (own ?? def ?? "").lowercased().hasPrefix("ko")
            }()
            // (The document's complex-script language, w:bidi: Hebrew gates the rtl-digit-run rules below. An Arabic doc's header and footer page numbers, a run with only w:rtl, stay complex script.)
            _bidiLangHebrew = {
                let own = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }?.first("w:rPr")?.first("w:lang")?["w:bidi"]
                let def = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:lang")?["w:bidi"]
                return (own ?? def ?? "").lowercased().hasPrefix("he")
            }()
            var docChar = CharStyle()
            if let rPr = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr") { docChar = _charStyle(rPr, base: docChar) }
            var normalChar = docChar
            for style in styles.all("w:style") where style["w:type"] == "paragraph"
                && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                if let rPr = style.first("w:rPr") { normalChar = _charStyle(rPr, base: normalChar) }
            }
            // (A style's look is kept as what it says over Normal's, so
            // only where the defaults differ from Normal are they stated.)
            var rootChar = CharStyle()
            if docChar.fontSize != normalChar.fontSize { rootChar.fontSize = docChar.fontSize }
            // docDefaults with no size: Word draws 10pt, for a style with no parent as
            // much as for Normal (dx2 590766b4's Tabellenstil cells drew 12pt).
            if docChar.fontSize == nil,
               styles.first("w:docDefaults")?.first("w:rPrDefault") != nil { rootChar.fontSize = 10 }
            if docChar.fontFamily != normalChar.fontFamily { rootChar.fontFamily = docChar.fontFamily }
            // Kerning too, said as none where only Normal kerns: Word
            // closes up 》《 only where it kerns, and a Zhejiang plan's
            // body, in a style that is not Normal's child, took a
            // character more a line under Normal's.
            if docChar.kerningFrom != normalChar.kerningFrom { rootChar.kerningFrom = docChar.kerningFrom ?? 0 }
            // And the language: zh-fec5fa30's Normal says East Asian
            // en-US, its defaults zh-TW, and its body style "內文2" is
            // no child of Normal — Word keeps "，" off a line's start
            // there, carrying "目" down with it; ours read Normal's
            // en-US, which has no such rules.
            let docLang = _keptRunProperties(docChar.keptXML)["w:lang"]
            if let docLang, docLang != _keptRunProperties(normalChar.keptXML)["w:lang"] { rootChar.keptXML = docLang }
            for style in styles.all("w:style") where style["w:type"] == "paragraph"
                && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &base) }
            }
            var tableNodes: [String: XNode] = [:]
            var allTableStyles: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "table" {
                if let id = style["w:styleId"] { allTableStyles[id] = style; keptTableStyles[id] = PptxXML.serialize(_standaloneW(style)) }
            }
            for style in styles.all("w:style") where style["w:type"] == "table" {
                guard let id = style["w:styleId"] else { continue }
                // (A table style says its paragraph look over the style it is
                // based on: ECC Table - red header has none of its own and
                // takes "before 3 pt" from ECC Table - clean. Word's rows in
                // 2179cebe stand 2.3 pt apart, ours 8.9 with the defaults.)
                var chain: [XNode] = [], seenT = Set<String>(), curT: String? = id
                while let c = curT, !seenT.contains(c), let n = allTableStyles[c] {
                    seenT.insert(c)
                    chain.insert(n, at: 0)
                    curT = n.first("w:basedOn")?["w:val"]
                }
                var ps = base
                var rootPs = docBase
                for n in chain {
                    if let pPr = n.first("w:pPr") { _paragraphProps(pPr, into: &ps); _paragraphProps(pPr, into: &rootPs) }
                }
                tableBases[id] = ps
                tableRootBases[id] = rootPs
                var hps = ps, hroot = rootPs, hasHeaderPPr = false
                for n in chain {
                    for part in n.all("w:tblStylePr") where part["w:type"] == "firstRow" {
                        if let pPr = part.first("w:pPr") { _paragraphProps(pPr, into: &hps); _paragraphProps(pPr, into: &hroot); hasHeaderPPr = true }
                    }
                }
                if hasHeaderPPr { headerBases[id] = hps; headerRootBases[id] = hroot }
                tableNodes[id] = style
                tableEdges[id] = _edges(style.first("w:tblPr"), "w:tblBorders")
                tableSides[id] = style.first("w:tblPr")?.first("w:tblBorders")
                if style.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed" {
                    fixedTableStyles.insert(id)
                    if Self._isDefaultTableStyle(style) { defaultTableFixed = true }
                }
                if Self._isDefaultTableStyle(style) {
                    defaultMargins = _defaultStyleMargins(style)
                    defaultBorders = _borders(style.first("w:tblPr"), "w:tblBorders")
                }
            }
            // (A styles part with no default table style leaves a table no cell
            // margin: Word's 5.4pt is Normal Table's, which a file saved by
            // Word carries and some exporters' do not. Lab tableorigin (Word
            // for Windows): with no table style at all the letters stand
            // 0.5pt from the rule and the left rule on the margin, in every
            // mode — a table is set out by its left cell margin, here 0.)
            if !tableNodes.values.contains(where: { Self._isDefaultTableStyle($0) }) {
                RuleTrace.hit("no-default-table-style-no-margin")
                noDefaultTableStyle = true
                defaultMargins = _Margins(top: 0, left: 0, bottom: 0, right: 0)
            }
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let b = _borders(node.first("w:tblPr"), "w:tblBorders") { tableBorders[id] = b; break }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let ind = node.first("w:tblPr")?.first("w:tblInd"), (ind["w:type"] ?? "dxa") == "dxa", let w = Double(ind["w:w"] ?? "") {
                        tableIndents[id] = w
                        break
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            for id in tableNodes.keys {
                var cond = _Cond(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if cond.cellVAlign == nil, let v = node.first("w:tcPr")?.first("w:vAlign")?["w:val"], v == "center" || v == "bottom" { cond.cellVAlign = v }
                    if cond.rowBandSize == nil, let v = node.first("w:tblPr")?.first("w:tblStyleRowBandSize")?["w:val"].flatMap({ Int($0) }) { cond.rowBandSize = v }
                    if cond.colBandSize == nil, let v = node.first("w:tblPr")?.first("w:tblStyleColBandSize")?["w:val"].flatMap({ Int($0) }) { cond.colBandSize = v }
                    for part in node.all("w:tblStylePr") {
                        let fill = part.first("w:tcPr")?.first("w:shd")?["w:fill"].flatMap { hex -> Color? in
                            guard hex.count == 6, let v = Int64(hex, radix: 16) else { return nil }
                            return Color(0xFF00_0000 | Int64(v))
                        }
                        switch part["w:type"] {
                        case "firstRow":
                            if cond.headerChar == nil, let rPr = part.first("w:rPr") { cond.headerChar = _charStyle(rPr, base: CharStyle()) }
                            if cond.headerBorders == nil { cond.headerBorders = part.first("w:tcPr")?.first("w:tcBorders") }
                            if cond.headerVAlign == nil, let v = part.first("w:tcPr")?.first("w:vAlign")?["w:val"], v == "center" || v == "bottom" { cond.headerVAlign = v }
                            if let h = part.first("w:trPr")?.first("w:tblHeader"), !_isOff(h) { cond.headerRepeats = true }
                        case "firstCol":
                            if cond.firstColChar == nil, let rPr = part.first("w:rPr") { cond.firstColChar = _charStyle(rPr, base: CharStyle()) }
                        case "lastRow":
                            if cond.lastRowChar == nil, let rPr = part.first("w:rPr") { cond.lastRowChar = _charStyle(rPr, base: CharStyle()) }
                        case "lastCol":
                            if cond.lastColChar == nil, let rPr = part.first("w:rPr") { cond.lastColChar = _charStyle(rPr, base: CharStyle()) }
                        default: break
                        }
                        if let t = part["w:type"], let fill, cond.fills[t] == nil { cond.fills[t] = fill }
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                tableConds[id] = cond
            }
            // (A table style's text size stands under the paragraph's own
            // style, over the document's defaults: zh-e2dc9dce's form, style
            // "表格格線1" at 10pt under a Normal that says no size over 12pt
            // defaults, sets its cells' unsized text at 10pt in Word's print;
            // ours at 12, its rows grew and its lines wrapped elsewhere.)
            normalStatesSize = styles.all("w:style").contains { style in
                style["w:type"] == "paragraph" && (style["w:default"] == "1" || style["w:styleId"] == "Normal")
                    && style.first("w:rPr")?.first("w:sz") != nil
            }
            // (A table style's own cell spacing, by its chain: the Forestry Commission style of gv-9fba5bc3b0
            // says 1pt between cells and its rows step 16.8pt in Word's print, 14.6 + 2.2, not the 14.6 of
            // rows with none.)
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let sp = node.first("w:tblPr")?.first("w:tblCellSpacing"), (sp["w:type"] ?? "dxa") == "dxa",
                       let w = Double(sp["w:w"] ?? ""), w > 0 { tableSpacings[id] = w / 20; break }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            for id in tableNodes.keys {
                var seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    if let v = node.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init) { tableSizes[id] = v / 2; break }
                    cur = node.first("w:basedOn")?["w:val"]
                }
            }
            if let normal = styles.all("w:style").first(where: { style in
                style["w:type"] == "paragraph" && (style["w:default"] == "1" || style["w:styleId"] == "Normal") }),
               let rPr = normal.first("w:rPr") {
                normalStatedChar = _charStyle(rPr, base: CharStyle())
            }
            for id in tableNodes.keys {
                var chain: [XNode] = [], seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    chain.append(node)
                    cur = node.first("w:basedOn")?["w:val"]
                }
                var cs = CharStyle()
                for node in chain.reversed() { if let rPr = node.first("w:rPr") { cs = _charStyle(rPr, base: cs) } }
                tableChars[id] = cs
            }
            for id in tableNodes.keys {
                var m = _Margins(), seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = tableNodes[c] {
                    seen.insert(c)
                    m = m.under(Self._isDefaultTableStyle(node) ? _defaultStyleMargins(node) : _cellMargins(node.first("w:tblPr")))
                    cur = node.first("w:basedOn")?["w:val"]
                }
                tableMargins[id] = m
            }
            // A style's look is its chain's: its own props over its
            // `basedOn` parent's, over that one's, down to the defaults.
            // Reading each style alone lost everything a parent gave it
            // (52288's "Chapter Number", based on a "Chapter Name" that holds
            // the bold and the size, came back as plain Normal text).
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                if let id = style["w:styleId"] { paragraphStyles[id] = style }
            }
            for style in styles.all("w:style") {
                if let name = style.first("w:name")?["w:val"] {
                    notes.styleNames.insert(name.lowercased())
                    if let id = style["w:styleId"] { notes.styleDisplayNames[id] = name }
                }
            }
            var charNodes: [String: XNode] = [:]
            for style in styles.all("w:style") where style["w:type"] == "character" {
                if let id = style["w:styleId"] { charNodes[id] = style }
            }
            // Kept as written, less what would not stand alone in the
            // saved styles part: other namespaces, theme references (the
            // faces were resolved above) and the link to a paragraph style.
            func standalone(_ node: XNode) -> XNode {
                let copy = XNode(name: node.name, attrs: node.attrs.filter { $0.key.hasPrefix("w:") && !$0.key.lowercased().containsSubstring("theme") })
                copy.text = node.text
                copy.children = node.children.filter { $0.name.hasPrefix("w:") && $0.name != "w:link" && $0.name != "w:rsid" }.map(standalone)
                return copy
            }
            for (id, node) in charNodes {
                keptCharacterStyles[id] = PptxXML.serialize(standalone(node))
                if let name = node.first("w:name")?["w:val"] { keptCharacterStyleIds[name.lowercased()] = id }
            }
            for id in charNodes.keys {
                var chain: [XNode] = [], seen = Set<String>(), cur: String? = id
                while let c = cur, !seen.contains(c), let node = charNodes[c] {
                    seen.insert(c)
                    if let rPr = node.first("w:rPr") { chain.insert(rPr, at: 0) }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                notes.charStyleChains[id] = chain
            }
            // The level a numbering definition ties a style to (w:lvl's
            // w:pStyle): a style that names a list and no level is that one.
            var linkedLevel: [String: Int] = [:]
            if let numbering = part("word/numbering.xml").flatMap(XNode.parse) {
                for a in numbering.all("w:abstractNum") {
                    for lvl in a.all("w:lvl") {
                        if let sid = lvl.first("w:pStyle")?["w:val"], let n = Int(lvl["w:ilvl"] ?? "") { linkedLevel[sid] = n }
                    }
                }
            }
            for id in paragraphStyles.keys {
                var seen = Set<String>(), cur: String? = id
                // The list and the level are inherited apart: "heading 3"
                // says level 2 and takes the list from "heading 1" under it
                // (a Taiwanese handbook's 一、 and (一) were gone from every
                // heading). And the indent the chain states from this style
                // down to the one that names the list: a numbered style's
                // own w:ind stands over its level's (another's "heading 5"
                // items sat 61pt right of where their style puts them).
                var left: Double? = nil, first: Double? = nil
                var numId: String? = nil, ilvl: Int? = nil
                while let c = cur, !seen.contains(c), let node = paragraphStyles[c] {
                    seen.insert(c)
                    if let ind = node.first("w:pPr")?.first("w:ind") {
                        if left == nil, let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { left = v / 20 }
                        if first == nil {
                            if let v = Double(ind["w:hanging"] ?? "") { first = -v / 20 }
                            else if let v = Double(ind["w:firstLine"] ?? "") { first = v / 20 }
                        }
                    }
                    if let numPr = node.first("w:pPr")?.first("w:numPr") {
                        if ilvl == nil, let v = Int(numPr.first("w:ilvl")?["w:val"] ?? "") { ilvl = v }
                        if let v = numPr.first("w:numId")?["w:val"] { numId = v; break }
                    }
                    cur = node.first("w:basedOn")?["w:val"]
                }
                if let numId, numId != "0" { styleNums[id] = (numId, ilvl ?? linkedLevel[id] ?? 0, left, first) }
            }
            var resolved: [String: (paragraph: RichParagraphStyle, char: CharStyle)] = [:]
            func resolve(_ id: String, _ seen: Set<String> = []) -> (paragraph: RichParagraphStyle, char: CharStyle) {
                if let r = resolved[id] { return r }
                guard let style = paragraphStyles[id], !seen.contains(id) else { return (paragraph: base, char: CharStyle()) }
                let isDefault = style["w:default"] == "1" || id == "Normal"
                var r = style.first("w:basedOn")?["w:val"].map { resolve($0, seen.union([id])) }
                    ?? (isDefault ? (paragraph: base, char: CharStyle()) : (paragraph: docBase, char: rootChar))
                // A style that turns the list OFF (numId 0) over a parent that
                // carries one does not take the left indent and hanging the parent
                // wrote beside its numbering: tdf132752's "Hinweis3" (numId 0, no
                // w:ind) stands at the margin in Word's print, though "Anleitung"
                // under it says left 2697, and "Hinweis1" (numId 0, its own left
                // and right) takes no hanging from it. The right indent stays
                // (Hinweis3 wraps in 284pt, Anleitung's 3340 twips from the right).
                if style.first("w:pPr")?.first("w:numPr")?.first("w:numId")?["w:val"] == "0",
                   let parent = style.first("w:basedOn")?["w:val"] {
                    var seenUp = Set<String>(), up: String? = parent, numbered = false
                    while let c = up, !seenUp.contains(c), let node = paragraphStyles[c] {
                        seenUp.insert(c)
                        if let v = node.first("w:pPr")?.first("w:numPr")?.first("w:numId")?["w:val"] { numbered = v != "0"; break }
                        up = node.first("w:basedOn")?["w:val"]
                    }
                    if numbered {
                        r.paragraph.indentLeft = docBase.indentLeft
                        r.paragraph.firstLineIndent = docBase.firstLineIndent
                    }
                }
                if let pPr = style.first("w:pPr") { _paragraphProps(pPr, into: &r.paragraph) }
                if let rPr = style.first("w:rPr") { r.char = _charStyle(rPr, base: r.char) }
                resolved[id] = r
                return r
            }
            // The styles the document's paragraphs name: those of ours they
            // map to take the file's look; the rest (custom styles) join
            // the sheet under their own ids, so they lay out and save as
            // they were.
            var used = Set<String>()
            func collect(_ n: XNode) {
                if n.name == "w:pStyle", let v = n["w:val"] { used.insert(v) }
                for c in n.children { collect(c) }
            }
            collect(root)
            for (name, data) in notes.kept where name.hasSuffix(".xml") {
                if let n = XNode.parse(data) { collect(n) }
            }
            // And by every header and footer part the document relates to:
            // a section break in the text keeps the ones it names only
            // later, when its paragraph is read, and their styles were
            // not written (footers of a "footer" style at 9pt came back
            // at the body's size, a line lower).
            for rel in relInfo.values where !rel.external && (rel.type.hasSuffix("/header") || rel.type.hasSuffix("/footer")) {
                let path = _resolvePath("word", rel.target)
                if notes.kept[path] == nil, let data = part(path), let n = XNode.parse(data) { collect(n) }
            }
            for style in styles.all("w:style") where style["w:type"] == "paragraph" {
                guard let id = style["w:styleId"] else { continue }
                let rawName = style.first("w:name")?["w:val"] ?? id
                let name = rawName.lowercased()
                let chain = resolve(id)
                if let ours = _styleId(name) ?? _styleId(id.lowercased()) {
                    // Two of the file's styles can map to one of ours (Quote
                    // and Intense Quote): the first defines the look, both use it.
                    let first = !styleByDocx.values.contains(ours)
                    styleByDocx[id] = ours
                    if first { styleSourceIds[ours] = id }
                    guard first, var entry = sheet[ours], ours != RichNamedStyle.normalId else { continue }
                    var cs = chain.char
                    if cs.fontFamily == nil { cs.fontFamily = entry.char.fontFamily }
                    entry.char = cs
                    var ps = chain.paragraph
                    ps.heading = entry.paragraph.heading
                    entry.paragraph = ps
                    if let next = style.first("w:next")?["w:val"] { entry.next = styleByDocx[next] ?? _styleId(next.lowercased()) }
                    sheet[ours] = entry
                } else if used.contains(id) || name == "balloon text", sheet[id] == nil {
                    // (Balloon Text too, which no paragraph names: Word
                    // prints a document's markup balloons in it — delins's
                    // Tahoma 8pt, which went to the 9pt serif without it.)
                    styleByDocx[id] = id
                    styleSourceIds[id] = id
                    sheet[id] = RichNamedStyle(id: id, name: rawName, paragraph: chain.paragraph, char: chain.char)
                }
            }
            // Kept markup (a nested table, a header part) still names the
            // file's ids: drawing.docx's heading 1 is "1", and inside its
            // kept table it fell back to plain text.
            styleAliases = styleByDocx.filter { used.contains($0.key) && $0.key != $0.value }
        }
        if var normal = sheet[RichNamedStyle.normalId] {
            normal.paragraph = base
            // Normal's look — the document defaults' run properties under
            // Normal's own: the font and size every plain paragraph is set
            // in. Without it a 12-point document came back at Calibri 11
            // (the writer's defaults), and every line wrapped elsewhere.
            if let styles = styleTree() {
                _resolveThemeFonts(styles, theme)
                _followThaiAlternates(styles, _thaiAlternates(entries))
                _normaliseStyleIds(styles)
                var cs = CharStyle()
                if let rPr = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                for style in styles.all("w:style") where style["w:type"] == "paragraph"
                    && (style["w:default"] == "1" || style["w:styleId"] == "Normal") {
                    if let rPr = style.first("w:rPr") { cs = _charStyle(rPr, base: cs) }
                }
                // A file that states no size anywhere is 10pt in Word (the
                // 2003-era default), not the 11pt of a fresh document. One
                // whose styles part has no run defaults at all (LibreOffice's
                // empty w:styles: tdf108496, tdf132752, four more) is Word's own
                // Normal, as with no styles part: 12pt.
                // A file that names no face anywhere, and carries no theme, is set in Times New Roman:
                // lo tdf109308_dropCapNumbered's print is TimesNewRomanPSMT.
                if cs.fontFamily == nil, styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts") == nil,
                   !styles.all("w:style").contains(where: { $0.first("w:rPr")?.first("w:rFonts") != nil
                       && (part("word/theme/theme1.xml") == nil || $0["w:default"] == "1") }),
                   // With a theme, Word keeps the theme face unless the file states (empty) run
                   // defaults itself (Google Docs, kor c9baf7); LibreOffice files with no
                   // w:docDefaults at all draw the theme's Calibri (lo-8882730a, lo-029954d7).
                   part("word/theme/theme1.xml") == nil || styles.first("w:docDefaults") != nil {
                    cs.fontFamily = "Times New Roman"
                    RuleTrace.hit("no-fonts-named-times")
                    // Its Hangul is Batang in Word for Windows, line 1.31 em (batch B 9b36b8: 8 pages,
                    // ours 10 with Malgun's 1.73 em); a file with no Hangul keeps the default.
                    if cs.eastAsiaFontFamily == nil, let d = part("word/document.xml"),
                       String(decoding: d, as: UTF8.self).unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
                        cs.eastAsiaFontFamily = "Batang"
                        RuleTrace.hit("no-fonts-named-batang")
                    }
                }
                if cs.fontSize == nil {
                    if styles.first("w:docDefaults")?.first("w:rPrDefault") == nil {
                        cs.fontSize = 12
                    } else {
                        cs.fontSize = 10
                    }
                }
                // A file whose styles carry no document defaults at all
                // (LibreOffice's older export) kerns every pair, as one
                // without styles does: fdo63164-1's "Wasserschöpfe" is
                // 0.4pt shorter in Word's print by "Wa", and fits a line
                // that ours, unkerned, spilled by a tenth of a point.
                if styles.first("w:docDefaults") == nil, cs.kerningFrom == nil {
                    cs.kerningFrom = 1
                    RuleTrace.hit("no-docdefaults-kerns")
                }
                normal.char = cs
            } else if noStyles {
                normal.char.fontSize = 12
                normal.char.kerningFrom = 1   // that Normal kerns, and the lines are half a percent shorter for it
            }
            sheet[RichNamedStyle.normalId] = normal
        }

        // Numbering: numId → level → bullet/decimal, and each numbered
        // level's label format, which the document keeps per list id.
        var kindByNum: [String: [Int: ListKind]] = [:]
        var listFormats: [String: [Int: ListLevelFormat]] = [:]
        var listCounterOf: [String: String] = [:]
        var listRestarts: [String: [Int: Int]] = [:]
        if let numData = part("word/numbering.xml"), let numbering = XNode.parse(numData) {
            _resolveThemeFonts(numbering, theme)
            _followThaiAlternates(numbering, thaiAlternates)
            var abstract: [String: [Int: ListKind]] = [:]
            var abstractFormats: [String: [Int: ListLevelFormat]] = [:]
            func readLevel(_ lvl: XNode, _ levels: inout [Int: ListKind], _ formats: inout [Int: ListLevelFormat]) {
                let ilvl = Int(lvl["w:ilvl"] ?? "0") ?? 0
                // (Word 2010's custom formats — "α, β, γ, ..." — stand in
                // an mc:Choice over a decimal fallback.)
                let chosen = lvl.first("mc:AlternateContent")?.first("mc:Choice")?.first("w:numFmt")
                let fmtNode = chosen ?? lvl.first("w:numFmt") ?? lvl.first("mc:AlternateContent")?.first("mc:Fallback")?.first("w:numFmt")
                let customSpec = fmtNode?["w:val"] == "custom" ? fmtNode?["w:format"] : nil
                let fmt = customSpec == nil ? (fmtNode?["w:val"] == "custom" ? "decimal" : fmtNode?["w:val"] ?? "decimal") : "custom"
                levels[ilvl] = fmt == "bullet" ? .bullet : .numbered
                if fmt == "bullet" {
                    // Word's stock bullets are Symbol/Wingdings private-use
                    // glyphs; map the common ones, else a plain bullet.
                    if let raw = lvl.first("w:lvlText")?["w:val"], let ch = raw.unicodeScalars.first {
                        let glyph: String
                        let face = lvl.first("w:rPr")?.first("w:rFonts")?["w:ascii"]?.lowercased()
                        let wingdings = face == "wingdings"
                        switch ch.value {
                        // (Wingdings' own shapes where the level names that face — Word's prints
                        // draw them: "n" a black square, "u" a diamond, the box at 0xA8, "o" a white
                        // square, 0x9E a small dot. Symbol's 0xA8 is a diamond suit, not this.)
                        // (Wingdings 2's "*" (0x2A) is its empty box ☐ in Word's print: dx2 bea98273's checkbox bullets, which
                        // drew as an asterisk and made every row of the cell 5 pt too tall.)
                        case 0x2A, 0xF02A where face == "wingdings 2": glyph = "\u{2610}"
                        case 0xF06E where wingdings: glyph = "\u{25FC}"
                        case 0xF075 where wingdings: glyph = "\u{25C6}"
                        case 0xF0A8 where wingdings: glyph = "\u{25FB}"
                        case 0xF06F where wingdings: glyph = "\u{25A1}"
                        case 0xF09E where wingdings: glyph = "\u{00B7}"
                        // (Symbol's 0x2D is its minus sign: the label of xb fra-g255's bullets, "−" in Word's print.)
                        case 0xF02D where face == "symbol": glyph = "\u{2212}"
                        case 0xF0B7, 0x2022: glyph = "\u{2022}"
                        case 0xF06F: glyph = "\u{25E6}"
                        case 0xF0A7, 0x25AA: glyph = "\u{25AA}"
                        // (Wingdings "l", the round bullet: "⚫" in a Word print's text,
                        // and a round dot where the default bullet is a small one.)
                        case 0xF06C: glyph = "\u{26AB}"
                        case 0xF0D8, 0x27A2: glyph = "\u{27A2}"
                        case 0xF0FC, 0x2713: glyph = "\u{2713}"
                        case 0xF076, 0x2756: glyph = "\u{2756}"
                        case 0xE000 ... 0xF8FF: glyph = ListLevelFormat.defaultBullet(ilvl)
                        default: glyph = raw
                        }
                        // A picture bullet (`w:lvlPicBulletId`) is an image in Word's print,
                        // never a glyph: lo-ca9b51bc's "下文…" line reads "下文…" there, not "⚫下文…".
                        let picture = lvl.first("w:lvlPicBulletId") != nil
                        formats[ilvl] = ListLevelFormat(text: picture ? "\u{200B}" : glyph, format: .bullet)
                        if picture { formats[ilvl]!.pictureBullet = true }
                        else if glyph != raw { formats[ilvl]!.rawText = raw; formats[ilvl]!.rawTextGlyph = glyph }
                    }
                } else {
                    let number: ListNumberFormat
                    switch fmt {
                    case "lowerLetter": number = .lowerLetter
                    case "upperLetter": number = .upperLetter
                    case "lowerRoman": number = .lowerRoman
                    case "upperRoman": number = .upperRoman
                    default: number = .decimal
                    }
                    formats[ilvl] = ListLevelFormat(text: lvl.first("w:lvlText")?["w:val"] ?? "%\(ilvl + 1).",
                                                    format: number)
                    // "一、二、三": a format the editor counts in digits.
                    if !["decimal", "lowerLetter", "upperLetter", "lowerRoman", "upperRoman"].contains(fmt) { formats[ilvl]!.rawFormat = fmt }
                    if let spec = customSpec { formats[ilvl]!.rawFormat = "custom:" + spec }
                }
                // The level's indents (65099's "1.1.1" hangs 0.5in at the
                // margin; the editor's default put it 1.5in in).
                if formats[ilvl] != nil {
                    // Kept as written, in the namespaces the numbering part
                    // declares (a number's w14 text effects — ten Chinese
                    // government files in a first sample of 179 — made the
                    // saved part ill-formed while it declared w alone).
                    if let v = Int(lvl.first("w:start")?["w:val"] ?? ""), v != 1 { formats[ilvl]!.start = v }
                    if let v = lvl.first("w:lvlJc")?["w:val"], v != "left", v != "start" { formats[ilvl]!.justification = v }
                    if let rPr = lvl.first("w:rPr"), !rPr.children.isEmpty {
                        let kept = XNode(name: rPr.name, attrs: rPr.attrs)
                        kept.children = rPr.children.filter { c in ["w:", "w14:", "w15:"].contains { c.name.hasPrefix($0) } }
                        if !kept.children.isEmpty, !formats[ilvl]!.pictureBullet { formats[ilvl]!.numberRPrXML = PptxXML.serialize(kept) }
                    }
                    if let suff = lvl.first("w:suff")?["w:val"] { formats[ilvl]!.suffix = suff }
                    // No label, no tab after it: 3922c734's empty-label items start at the
                    // margin in Word; a tab there ran to the next default stop (65 pt in).
                    else if lvl.first("w:lvlText")?["w:val"] == "" { formats[ilvl]!.suffix = "nothing" }
                }
                if let ind = lvl.first("w:pPr")?.first("w:ind"), formats[ilvl] != nil {
                    if let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") { formats[ilvl]!.indentLeft = v / 20 }
                    if let v = Double(ind["w:hanging"] ?? "") { formats[ilvl]!.hanging = v / 20 }
                    else if let v = Double(ind["w:firstLine"] ?? "") { formats[ilvl]!.hanging = -v / 20 }
                }
            }
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                var levels: [Int: ListKind] = [:]
                var formats: [Int: ListLevelFormat] = [:]
                for lvl in a.all("w:lvl") { readLevel(lvl, &levels, &formats) }
                abstract[id] = levels
                abstractFormats[id] = formats
            }
            // (A definition that only names a numbering style —
            // w:numStyleLink — has its levels in the definition that
            // style is (w:styleLink): zh-12c4f07a's "3.1.1" items are a
            // list over such a one, which ours, finding no levels, drew
            // as bullets.)
            var styleLinked: [String: String] = [:]
            var numStyleLinks: [String: String] = [:]
            for a in numbering.all("w:abstractNum") {
                guard let id = a["w:abstractNumId"] else { continue }
                if let s = a.first("w:styleLink")?["w:val"] { styleLinked[s] = id }
                if let s = a.first("w:numStyleLink")?["w:val"] { numStyleLinks[id] = s }
            }
            for n in numbering.all("w:num") {
                guard let id = n["w:numId"], var aid = n.first("w:abstractNumId")?["w:val"] else { continue }
                if (abstract[aid] ?? [:]).isEmpty, let style = numStyleLinks[aid], let linked = styleLinked[style] { aid = linked }
                var levels = abstract[aid] ?? [:]
                var formats = abstractFormats[aid] ?? [:]
                // A level the list itself redefines (w:lvlOverride with a
                // whole w:lvl) replaces the definition's: form_footnotes'
                // instructions are bullets at 0.25in over a definition
                // that says "*" and nothing else.
                for ov in n.all("w:lvlOverride") {
                    guard let lvl = ov.first("w:lvl") else { continue }
                    let ilvl = Int(lvl["w:ilvl"] ?? ov["w:ilvl"] ?? "0") ?? 0
                    formats[ilvl] = nil
                    readLevel(lvl, &levels, &formats)
                }
                kindByNum[id] = levels
                listFormats[id] = formats
                notes.listFormats[id] = formats
                // Lists over one definition share its numbers; a list's
                // startOverride restarts a level the first time it is used.
                listCounterOf[id] = "abstract:" + aid
                for ov in n.all("w:lvlOverride") {
                    guard let v = Int(ov.first("w:startOverride")?["w:val"] ?? "") else { continue }
                    listRestarts[id, default: [:]][Int(ov["w:ilvl"] ?? "0") ?? 0] = v
                }
            }
        }

        var paragraphs: [RichParagraph] = []
        var pageSetup: PageSetup? = nil
        var pendingPageBreak = false
        var afterCentredFloat = -1
        var afterCentredFloatCell: CellRef? = nil
        var pendingBreakCharacter = false   // ... made by a break character, in a run with these properties
        var pendingBreakRPr: String? = nil
        var pendingBreakColumn = false
        var tableColumns: [String: [Double]] = [:]
        var tableCellColumns: [String: [Double]] = [:]
        var tableStyles: [String: TableStyle] = [:]
        var tableStyleIds: [String: String] = [:], tableLooks: [String: String] = [:], tableCondFills: [String: TableCondFills] = [:]
        var tableCount = 0
        var currentCell: CellRef? = nil
        var rowExcepted = false   // the row of `currentCell` states its own cell margins (w:tblPrEx)
        var cellChar = CharStyle()   // the table style's look for the first row's runs
        var keptTables: [String: KeptTable] = [:]
        var keptTableCount = 0
        /// Each top-level body paragraph's own `w:p`, while the body is read
        /// (the column sections read as table rows keep their markup).
        var bodyNodes: [Int: XNode] = [:]
        var recordingBody = true
        /// A paragraph style's chain laid over `base` — the table style's
        /// paragraph props inside a cell: Word puts the table style under
        /// the paragraph style, so a style that sets only "after" keeps the
        /// table style's line rule (65099's cells were a line of 1.15, not 1.0).
        func chainOver(_ id: String, _ base: RichParagraphStyle, _ rootBase: RichParagraphStyle) -> RichParagraphStyle? {
            guard paragraphStyles[id] != nil else { return nil }
            var ids: [String] = [], seen = Set<String>(), cur: String? = id
            while let c = cur, !seen.contains(c), let node = paragraphStyles[c] {
                ids.append(c); seen.insert(c); cur = node.first("w:basedOn")?["w:val"]
            }
            // A chain that ends in a style other than Normal never takes
            // Normal's look (see `docBase`).
            let root = ids.last.flatMap { paragraphStyles[$0] }
            let reachesNormal = root.map { $0["w:default"] == "1" || $0["w:styleId"] == "Normal" } ?? true
            var ps = reachesNormal ? base : rootBase
            for c in ids.reversed() { if let pPr = paragraphStyles[c]?.first("w:pPr") { _paragraphProps(pPr, into: &ps) } }
            return ps
        }
        let outerBase = base   // the paragraph defaults outside any table
        var cellBase = base   // the table style's spacing while inside one
        var cellRootBase = docBase
        // (A cell's paragraph of no style of its own is Normal's, and
        // Normal's own settings stand over the table style's, as a named
        // style's chain does — Word applies the table style under the
        // paragraph's style, not over it. zh-0b48a0db's Normal says 1.08
        // lines (w:line 259) and its "TableGrid" single, no space after;
        // Word's print sets the table's 14pt lines 25.9pt apart, 1.08 of
        // YaHei's 24, with nothing after; ours took the table style's
        // single line, 24.4, and the table ran a line short a page.)
        let normalStyleId = paragraphStyles.first(where: { $0.value["w:default"] == "1" })?.key
        func cellNormal() -> RichParagraphStyle {
            normalStyleId.flatMap { chainOver($0, cellBase, cellRootBase) } ?? cellBase
        }

        var joinInto: Int? = nil
        func emit(_ p: RichParagraph) {
            var p = p
            if afterCentredFloat == paragraphs.count, afterCentredFloatCell == currentCell, p.cell == nil || p.cell == currentCell { p.style.besideFloat = true }
            afterCentredFloat = -1
            if pendingPageBreak {
                p.style.pageBreakBefore = true; pendingPageBreak = false
                if pendingBreakCharacter, !p.style.pageBreakInline {
                    p.style.breakEndsPrevious = true; p.style.breakRunPropertiesXML = pendingBreakRPr; p.style.columnBreak = pendingBreakColumn
                }
                // (A paragraph of a page break alone, then one opening with
                // its own: Word's page between is blank but for the second
                // paragraph's start — zh-e74dd0a1's page 63, its folio
                // alone, before "衢州市政府信息公开工作社会评议办法" on 64;
                // ours merged the two breaks, and ran two pages short.)
                else if pendingBreakCharacter, p.style.pageBreakInline, !pendingBreakColumn, !p.style.columnBreak {
                    p.style.pageBreakTwice = true
                }
                pendingBreakCharacter = false; pendingBreakRPr = nil; pendingBreakColumn = false
            }
            if p.cell == nil { p.cell = currentCell }
            // (A paragraph whose mark is hidden runs on into the next, as
            // Word shows it — a style separator (`w:vanish` and
            // `w:specVanish` on the mark): zh-9f24d3eb's "(二)附件2" and
            // "：切結書暨領據…" are one line in Word's print, the first's
            // numbering and indents for both; ours set two, and page 2 ran
            // a line long.)
            if let i = joinInto, i == paragraphs.count - 1, paragraphs[i].cell == p.cell, p.image == nil, paragraphs[i].image == nil {
                // (A plain hidden mark, no style separator: the joined paragraph
                // is set as the second is — merge_hidden_redline's centred "abc"
                // and the left "def" print as one line set left in Word's.)
                // (Its alignment only: zh-621d8756's hidden mark and the empty
                // paragraph after it differ in line spacing, where the first's
                // stands.)
                if !paragraphs[i].style.markSpecVanish, !p.style.markHidden, paragraphs[i].style.alignment != p.style.alignment {
                    RuleTrace.hit("hidden-mark-joins-second")
                    paragraphs[i].style.alignment = p.style.alignment
                }
                let bookmarkOffset = paragraphs[i].length
                paragraphs[i].bookmarkMarkers += p.bookmarkMarkers.map {
                    RichBookmarkMarker(id: $0.id, name: $0.name, offset: bookmarkOffset + $0.offset)
                }
                paragraphs[i].text += p.text
                paragraphs[i].runs += p.runs
                paragraphs[i].bookmarks += p.bookmarks
                for (k, v) in p.inlineImages { paragraphs[i].inlineImages[k] = v }
                if !p.style.markHidden { paragraphs[i].style.markHidden = false; paragraphs[i].style.mark = p.style.mark; joinInto = nil }
                return
            }
            joinInto = nil
            paragraphs.append(p)
            if p.style.markHidden, p.image == nil, p.runs.contains(where: { !$0.style.hidden && $0.length > 0 }) { joinInto = paragraphs.count - 1 }
        }

        // A row or cell may sit inside a content control (`w:sdt` >
        // `w:sdtContent` > `w:tr`/`w:tc`, as Word writes repeating-section
        // and cell controls): the wrapper is transparent here.
        var inWrapperBody = false
        var wrapperIndent = 0.0
        func unwrapped(_ parent: XNode, _ name: String) -> [XNode] {
            var out: [XNode] = []
            for c in parent.children {
                if c.name == name { out.append(c) }
                else if c.name == "w:sdt", let inner = c.first("w:sdtContent") { out += unwrapped(inner, name) }
            }
            return out
        }
        // Tables nest through cells; a fuzzer's 5000-deep nest overflowed the
        // stack, so past this depth a cell's paragraphs are gathered without
        // recursing further.
        let maxNesting = 32
        /// The characters of text under `node`.
        func textLength(_ node: XNode) -> Int {
            var n = 0
            var stack = [node]
            while let x = stack.popLast() {
                if x.name == "w:t" { n += x.text.count; continue }
                stack.append(contentsOf: x.children)
            }
            return n
        }
        func deepParagraphs(_ node: XNode) -> [XNode] {
            var out: [XNode] = []
            var stack = [node]
            while let n = stack.popLast() {
                if n.name == "w:p" { out.append(n); continue }
                stack.append(contentsOf: n.children.reversed())
            }
            return out
        }
        /// Flags the paragraph just read, when it is the empty one that
        /// ends cell `tc` right under a table nested in it
        /// (`RichParagraphStyle.markUnderNestedTable`).
        func flagMarkUnderNestedTable(_ tc: XNode, since first: Int) {
            let blocks = tc.children.filter { ["w:p", "w:tbl", "w:sdt"].contains($0.name) }
            guard blocks.count >= 2, blocks[blocks.count - 1].name == "w:p", blocks[blocks.count - 2].name == "w:tbl",
                  paragraphs.count > first, let last = paragraphs.indices.last,
                  paragraphs[last].text.isEmpty, paragraphs[last].image == nil else { return }
            paragraphs[last].style.markUnderNestedTable = true
            // (Word for Windows' lab nb, zh-cb57eaad's last outer table: the empty mark under a nested table
            // adds nothing to the cell, whatever its size, grid or row — the outer cell closes 0.72pt, a rule,
            // under the nested table's foot. Left out, where the cell has the table's own paragraphs before it;
            // set at zero height it still made the row 14pt taller, and the final line went to a page of its own.)
            if Self.wordOnWindows, paragraphs.count - 1 > first, paragraphs[last].cell != nil, paragraphs[last - 1].cell == paragraphs[last].cell { paragraphs.removeLast() }
        }
        func walkBlock(_ source: XNode, indent: Double, depth: Int = 0) {
            // (A table with w:bidiVisual runs its first column at the right edge: Word's
            // ara-z8215570 header has the Urdu title cell right, the date left; walked
            // in file order ours drew them the other way round.)
            let node = Self._mirroredTable(source)
            switch node.name {
            case "w:p":
                let first = paragraphs.count
                notes.cellBoxBase = currentCell != nil ? base : nil
                for p in _paragraphs(node, currentCell != nil ? cellNormal() : base, styleByDocx, styleNums, sheet, kindByNum, rels, media, indent, notes, cellChar,
                                     currentCell != nil ? { id in chainOver(id, cellBase, cellRootBase) } : nil) {
                    // (A page break that ends the paragraph holding a
                    // section's mark is that section's break, as Word lays
                    // it — and where the next section is continuous there
                    // is none: zh-e2dc9dce's contents end in a page break
                    // and a continuous section, and Word for Windows sets
                    // chapter 1's title picture, the paragraph after, on
                    // the contents page, the body from page 3; ours gave
                    // the picture a page and ran a page long to the end.
                    // Only there: Mac Word keeps the break, and its print of
                    // the same document has a page 3 of the picture alone.
                    // And only where the margins stay: a continuous section with
                    // other top or bottom margins keeps the break — LibreOffice's
                    // tdf149555, "Seriously" and a page break before a contents
                    // section of 1422 twips on top for 5982, has the contents
                    // on Word's page 2; ours ran them on under it.)
                    let sectionsOwn = Self.wordOnWindows && currentCell == nil && !p.breakColumn && p.paragraph.style.sectionXML != nil
                        && p.paragraph.style.sectionBreaksPage == false && !p.sectionMarginsChange
                    if p.pageBreakAfter, !sectionsOwn { emit(p.paragraph); pendingPageBreak = true; pendingBreakCharacter = p.breakCharacter; pendingBreakRPr = p.breakRPr; pendingBreakColumn = p.breakColumn } else if p.pageBreakAfter, p.breakCharacter { var q = p.paragraph; q.style.ignoredSectionPageBreak = true; emit(q) } else { emit(p.paragraph) }
                }
                if recordingBody, currentCell == nil { for k in first ..< paragraphs.count { bodyNodes[k] = node } }
                // (A line break that clears opens a paragraph after a table floating over the text: the
                // line is the one level with the table, and the text after it stands under the table.
                // LibreOffice's fdo76248, "*Projections" after Table 5: 499.5 in Word's print, the table's
                // foot, where ours set it and the paragraphs after in the 218pt beside it.)
                if Self.wordOnWindows, currentCell == nil, first > 0, first < paragraphs.count, let above = paragraphs[first - 1].cell,
                   tableStyles[above.table]?.floatsOverText == true, paragraphs[first].image == nil, paragraphs[first].text.hasPrefix("\n"), paragraphs[first].text.utf16.count > 1,
                   let run = node.children.first(where: { $0.name == "w:r" }),
                   let br = run.children.first(where: { $0.name != "w:rPr" }), br.name == "w:br",
                   (br["w:type"] ?? "textWrapping") == "textWrapping", ["all", "left", "right"].contains(br["w:clear"] ?? "") {
                    paragraphs[first].text.removeFirst()
                    if !paragraphs[first].runs.isEmpty {
                        if paragraphs[first].runs[0].length > 1 { paragraphs[first].runs[0].length -= 1 } else { paragraphs[first].runs.removeFirst() }
                    }
                    paragraphs[first].style.clearsFloat = true
                }
                // A text box whose text holds a table (`_Shared.boxTables`):
                // its text read again here, tables and all, as a small table
                // in a cell is (below). zh-64044a1d's 災民收容登記表 is a form
                // in a VML box behind the text; read for its paragraphs alone,
                // the box held one empty line and printed as nothing.
                if !notes.boxTables.isEmpty || !notes.boxPartTables.isEmpty {
                    /// A box's content read again with its tables.
                    func readBlocks(_ content: XNode) -> [RichParagraph] {
                        let saved = (paragraphs, currentCell, cellChar, cellBase, cellRootBase, recordingBody,
                                     pendingPageBreak, pendingBreakCharacter, pendingBreakRPr, pendingBreakColumn)
                        let counts = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                                      notes.seenComments, notes.fieldShown)
                        paragraphs = []; currentCell = nil; recordingBody = false; pendingPageBreak = false
                        cellChar = CharStyle()
                        notes.inTextBox = true
                        for child in content.children { walkBlock(child, indent: 0, depth: 1) }
                        notes.inTextBox = false
                        let inner = paragraphs
                        (paragraphs, currentCell, cellChar, cellBase, cellRootBase, recordingBody,
                         pendingPageBreak, pendingBreakCharacter, pendingBreakRPr, pendingBreakColumn) = saved
                        (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                         notes.seenComments, notes.fieldShown) = counts
                        return inner
                    }
                    /// A group's boxes of tables: each part's paragraphs read
                    /// again with its tables, the table moved to its box's place.
                    func boxedParts(_ image: ImageAttachment) -> ImageAttachment {
                        guard let tables = notes.boxPartTables.removeValue(forKey: image.id), var box = image.textBox, !box.parts.isEmpty else { return image }
                        let all = box.paragraphs
                        var made: [RichParagraph] = []
                        var styles = box.tableStyles, columns = box.tableColumns
                        for n in box.parts.indices {
                            let start = box.parts[n].first
                            let end = n + 1 < box.parts.count ? box.parts[n + 1].first : all.count
                            box.parts[n].first = made.count
                            guard let t = tables[n] else { made += all[min(start, all.count) ..< min(max(start, end), all.count)]; continue }
                            var inner = readBlocks(t.content)
                            for q in inner.indices where inner[q].cell == nil {
                                inner[q].style.indentLeft += t.left
                                if let own = inner[q].style.listIndentLeft ?? Self._levelLeft(inner[q].style, notes) { inner[q].style.listIndentLeft = own + t.left }
                                inner[q].style.indentRight += t.right
                                inner[q].style.boxInsetRight = t.inset
                            }
                            for id in Set(inner.compactMap { $0.cell?.table }) {
                                if var style = tableStyles[id] { style.indent += t.left; styles[id] = style }
                                columns[id] = tableColumns[id]
                            }
                            made += inner
                        }
                        box.paragraphs = made
                        box.tableStyles = styles
                        box.tableColumns = columns
                        var out = image
                        out.textBox = box
                        return out
                    }
                    func boxed(_ image: ImageAttachment) -> ImageAttachment {
                        let image = boxedParts(image)
                        guard let content = notes.boxTables.removeValue(forKey: image.id), var box = image.textBox else { return image }
                        let inner = readBlocks(content)
                        guard !inner.isEmpty else { return image }
                        let ids = Set(inner.compactMap { $0.cell?.table })
                        box.paragraphs = inner
                        box.tableStyles = tableStyles.filter { ids.contains($0.key) }
                        box.tableColumns = tableColumns.filter { ids.contains($0.key) }
                        var out = image
                        out.textBox = box
                        return out
                    }
                    for k in first ..< paragraphs.count {
                        if let image = paragraphs[k].image { paragraphs[k].image = boxed(image) }
                        for (key, image) in paragraphs[k].inlineImages { paragraphs[k].inlineImages[key] = boxed(image) }
                    }
                }
            case "w:tbl" where currentCell != nil && depth < maxNesting && Self._isTallNarrowFloat(node):
                // (See `_isTallNarrowFloat`: its rows are paragraphs of the
                // cell, set in from its sides where the float stands, each
                // as tall as its row asks, and kept whole at a page's foot.)
                let before = paragraphs.count
                var keptId: String? = nil
                if _nestingDepth(node) <= 6, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    keptId = "kt\(keptTableCount)"
                    keptTables[keptId!] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [])
                }
                let pos = node.first("w:tblPr")?.first("w:tblpPr")
                let gridW = (Double(node.first("w:tblGrid")?.all("w:gridCol").first?["w:w"] ?? "") ?? 0) / 20
                var wide = gridW
                if let w = node.first("w:tblPr")?.first("w:tblW"), (w["w:type"] ?? "dxa") == "dxa", let v = Double(w["w:w"] ?? ""), v > 0 { wide = v / 20 }
                var cellWide = 0.0
                if let c = currentCell, let cols = tableColumns[c.table] {
                    cellWide = cols.dropFirst(c.column).prefix(c.span).reduce(0, +)
                }
                var left = 0.0, right = 0.0
                if cellWide > wide + 1 {
                    switch pos?["w:tblpXSpec"] {
                    case "center"?: left = (cellWide - wide) / 2
                    case "right"?, "outside"?: left = cellWide - wide
                    case "left"?, "inside"?: left = 0
                    default: left = min(max(0, (Double(pos?["w:tblpX"] ?? "") ?? 0) / 20), cellWide - wide)
                    }
                    right = cellWide - wide - left
                }
                let tableMargins = _cellMargins(node.first("w:tblPr"))
                // (Each row is a rule's width taller at its head, and the
                // table stands its tblpY under the paragraph it floats by:
                // Word's print of floattable-in-inlinetable has the first
                // line 5.9pt under the cell's, the tblpY 5.4 and the rule
                // 0.5, and the row on the next page 0.5 under its margin.)
                func rule(_ name: String) -> Double {
                    guard let b = node.first("w:tblPr")?.first("w:tblBorders")?.first(name), (b["w:val"] ?? "none") != "none",
                          let sz = Double(b["w:sz"] ?? "") else { return 0 }
                    return sz / 8
                }
                var rowNumber = 0
                for tr in unwrapped(node, "w:tr") {
                    defer { rowNumber += 1 }
                    for tc in unwrapped(tr, "w:tc") {
                        let first = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        guard paragraphs.count > first else { continue }
                        let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                        paragraphs[first].style.spaceBefore += (m.top ?? 0) + rule(rowNumber == 0 ? "w:top" : "w:insideH")
                            + (rowNumber == 0 && pos?["w:vertAnchor"] == "text" ? max(0, (Double(pos?["w:tblpY"] ?? "") ?? 0) / 20) : 0)
                        paragraphs[paragraphs.count - 1].style.spaceAfter += m.bottom ?? 0
                        let least = (tr.first("w:trPr")?.first("w:trHeight")).flatMap { h in h["w:hRule"] == "exact" ? nil : Double(h["w:val"] ?? "").map { $0 / 20 } }
                        for k in first ..< paragraphs.count {
                            paragraphs[k].style.indentLeft += left
                            paragraphs[k].style.indentRight += right
                            if pos?["w:tblpXSpec"] == "center" { paragraphs[k].style.centredFloat = true }
                            if let least, least < 500 {
                                paragraphs[k].style.keepLines = true
                                if k < paragraphs.count - 1 { paragraphs[k].style.keepNext = true }
                            }
                        }
                        if let least, least > 0 {
                            paragraphs[paragraphs.count - 1].style.blockMinHeight = least
                            paragraphs[paragraphs.count - 1].style.blockParagraphs = paragraphs.count - first
                        }
                    }
                }
                if let kid = keptId {
                    if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid]!.texts = paragraphs[before...].map(\.text)
                }
                if pos?["w:tblpXSpec"] == "center", pos?["w:vertAnchor"] == "text", paragraphs.count > before { afterCentredFloat = paragraphs.count; afterCentredFloatCell = currentCell }
            case "w:tbl" where currentCell != nil && depth < maxNesting && (_nestingDepth(node) == 1 || Self._formHoldingATable(node))
                                // (Not a single row of as many paragraphs as a page holds: a block does not part inside a row,
                                // and one of 75 lines ran 40pt past the foot with the rest of its lines
                                // lost. Lab nt1, Word for Windows: such a row parts at the foot like any.)
                                && !(unwrapped(node, "w:tr").count == 1 && node.descendants("w:p").count >= 50)
                                // (No limit on text or rows: a block parts across pages by rows, and inside a row at its
                                // cells' line ends, as Word's nested table does. Lab nt1; sa1 a8eb7723.)
                                :
                // A small table in a cell, with none in it, is a table of
                // its own: read as a document is, and set in its cell as a
                // block as tall as it lays out (`RichTextBox.growsToFit`).
                // Flattened, zh-454e2e29's form of five columns — "姓名",
                // "職稱", "職務編號"… — stood as a column of lines 36pt
                // apart. (A long one is still flattened below: a block
                // does not part across pages, and 60329's protocol text,
                // 2,235 characters in a three-row table in a cell, ran to
                // six pages for it.) Its markup is kept for the save.
                let outerExcepted = rowExcepted
                let saved = (paragraphs, currentCell, cellChar, cellBase, cellRootBase)
                paragraphs = []
                currentCell = nil
                walkBlock(node, indent: 0, depth: depth + 1)
                let inner = paragraphs
                (paragraphs, currentCell, cellChar, cellBase, cellRootBase) = saved
                let ids = Set(inner.compactMap { $0.cell?.table })
                var box = RichTextBox(paragraphs: inner)
                box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                // (Word for Windows' labs T0-T2: the cell that holds a table is taller by that table's own
                // cell margins, top and bottom, once more — lo-eb12e7d4's groups stand 2.8pt, the 28 twips
                // of a pair, short of its print.)
                if let outer = saved.1, outerExcepted, (outer.padding?.top ?? 0) == 0, (outer.padding?.bottom ?? 0) == 0, node.first("w:tblPr")?.first("w:tblpPr") == nil, node.descendants("w:drawing").isEmpty, let tcMar = node.descendants("w:tcMar").first {
                    let pr = XNode(name: "w:tcPr", attrs: [:]); pr.children = [tcMar]
                    let m = _cellMargins(pr, "w:tcMar")
                    box.insetBottom = (m.top ?? 0) + (m.bottom ?? 0)
                }
                box.tableStyles = tableStyles.filter { ids.contains($0.key) }
                box.tableColumns = tableColumns.filter { ids.contains($0.key) }
                box.growsToFit = true
                let gridWidth = (node.first("w:tblGrid")?.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") }.reduce(0, +) ?? 0) / 20
                var image = ImageAttachment(data: Data(), width: max(1, gridWidth), height: 1, name: "table")
                image.textBox = box
                // (One placed as it floats, `w:tblpPr`, stands where it says,
                // from the cell, and the text goes round it — lab `tf` on
                // Word for Windows: zh-291fcea7 p5's flowchart boxes, placed
                // against the "page" at 29.25 and 320.85pt and centred on the
                // "margin", stand 29.5 and 321.2pt from the cell's left edge
                // and centred on the cell, side by side; ours stacked them
                // down the cell.)
                var nominalLeft = 0.0
                if let pos = node.first("w:tblPr")?.first("w:tblpPr") {
                    var f = ImageFloat()
                    f.horizontalFrom = "cell"
                    f.verticalFrom = "paragraph"
                    if let spec = pos["w:tblpXSpec"] { f.horizontalAlign = spec } else { f.x = (Double(pos["w:tblpX"] ?? "") ?? 0) / 20 }
                    f.y = (Double(pos["w:tblpY"] ?? "") ?? 0) / 20
                    f.wraps = true
                    if let l = Double(pos["w:leftFromText"] ?? "") { f.distanceLeft = l / 20 }
                    if let r = Double(pos["w:rightFromText"] ?? "") { f.distanceRight = r / 20 }
                    f.againstText = pos["w:vertAnchor"] == "text"
                    f.fromCellTop = pos["w:vertAnchor"] == "page" || pos["w:vertAnchor"] == "margin"
                    f.fromCellText = pos["w:horzAnchor"] == "margin"
                    // (One that floats only in name — against the text, from the
                    // column's edge, a twip or so under its paragraph's top —
                    // stands where it is set, an inline block shifted by its x:
                    // LibreOffice's tdf170381, a 75pt table in a 383pt cell,
                    // which Word parts over two pages between its rows, as an
                    // inline one does; a floating box ran off the page's foot
                    // and its rows were never cut.)
                    // (Nor one as wide as its cell, which leaves no room for text beside it: the whole cell's width
                    // by `w:tblW`, 100%. sa1 03f63881's two-column table in an outer cell, `w:tblpPr` against the
                    // page, starts at the foot of page 13 and goes on at the top of page 14 in Word's print,
                    // as an inline nested table does; the floating box moved whole to page 14.)
                    let tblW = node.first("w:tblPr")?.first("w:tblW")
                    let fullWidth = Self.wordOnWindows && pos["w:tblpXSpec"] == nil && pos["w:tblpYSpec"] == nil
                        && tblW?["w:type"] == "pct" && (Double(tblW?["w:w"] ?? "") ?? 0) >= 5000
                    if fullWidth {
                        nominalLeft = 0
                        // (Against the page, it stands at its outer cell's own edge, not its text: lab fltpos on
                        // Word for Windows, 03f63881's table in a cell with 5.4pt margins, its continuation's text
                        // 4.9pt left of ours; the half border it shares with the cell's brings it to margin + 1pt.)
                        if pos["w:horzAnchor"] == "page", let outer = saved.1 { nominalLeft = -(outer.padding?.left ?? 5.4) + 0.5 }
                        box.insetTop = f.y   // (its y under the anchor paragraph's top)
                    } else if pos["w:vertAnchor"] == "text", (pos["w:horzAnchor"] ?? "text") == "text", pos["w:tblpXSpec"] == nil, pos["w:tblpYSpec"] == nil,
                       f.y <= 1, f.x >= 0 {
                        nominalLeft = f.x
                    } else {
                        image.float = f
                    }
                    // (Placed so, it stands at its box's corner inside it: the
                    // box's copy of its style floats it no further.)
                    for (key, var st) in box.tableStyles {
                        st.floatOffsetY = nil; st.floatRaiseY = nil; st.floatX = nil; st.floatXAnchor = nil
                        st.pageAnchored = false; st.pageOffsetY = nil; st.floatsOverText = false; st.alignment = .left
                        box.tableStyles[key] = st
                    }
                    image.textBox = box
                }
                var para = RichParagraph(image: image, style: cellBase)
                para.style.indentLeft += nominalLeft
                if nominalLeft < 0 { para.style.indentRight -= nominalLeft }   // (moved left, not wider: Word's lab fltpos table ends 4.9pt short of ours)
                // (Word for Windows' labs T0-T2: the cell that holds a table is taller by that table's own
                // cell margins, top and bottom, once more — lo-eb12e7d4's groups stand 2.8pt, the 28 twips
                // of a pair, short of its print.)
                if let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    let kid = "kt\(keptTableCount)"
                    keptTables[kid] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [para.text])
                    para.keptTable = kid
                }
                emit(para)
            case "w:tbl" where currentCell != nil:
                // A nested table flattens into its cell, indented — and,
                // unless it nests absurdly (a fuzzer's 5,000 levels), is
                // kept as written: 60329's body is a table in a cell, and
                // flattened it lost its boxes and widths. The save writes
                // the kept markup back while the flattened text stands.
                let before = paragraphs.count
                var keptId: String? = nil
                if depth < maxNesting, _nestingDepth(node) <= 6, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    keptId = "kt\(keptTableCount)"
                    keptTables[keptId!] = KeptTable(xml: frag.xml, rels: frag.rels, texts: [])
                }
                if depth >= maxNesting {
                    for p in deepParagraphs(node) { walkBlock(p, indent: indent + 18, depth: depth + 1) }
                } else {
                    // (Each cell keeps the room its table gave it above and
                    // below — its top and bottom margins and the table's
                    // cell spacing — as its first and last paragraphs'
                    // spacing: drawing.docx's article heads stand in HTML
                    // tables three deep, and flattened they lost 10.5pt of
                    // it, the "12.04.2006 - Cbonds" line 11pt high of Word's
                    // print and three pages after it a line early.)
                    let rows = unwrapped(node, "w:tr")
                    let tableMargins = _cellMargins(node.first("w:tblPr"))
                    let spacing = node.first("w:tblPr")?.first("w:tblCellSpacing").flatMap { sp -> Double? in
                        (sp["w:type"] ?? "dxa") == "dxa" ? Double(sp["w:w"] ?? "").map { $0 / 20 } : nil
                    } ?? 0
                    for (r, tr) in rows.enumerated() {
                        for tc in unwrapped(tr, "w:tc") {
                            let first = paragraphs.count
                            for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                            guard paragraphs.count > first else { continue }
                            flagMarkUnderNestedTable(tc, since: first)
                            let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                            // (The nested table's own left cell margin and left border put its text in
                            // from the outer cell's: lo-c7082c66's middle table stands 5.6pt in, even in
                            // compat mode 11, and lo-5c5eb1f7's frames in nested cells 5.65pt. This
                            // replaces the flat 18pt the children used to be handed, which was 12pt too much.)
                            let edge = (node.first("w:tblPr")?.first("w:tblBorders")?.first("w:left")).flatMap { b -> Double? in
                                (b["w:val"] ?? "none") == "none" ? nil : Double(b["w:sz"] ?? "").map { $0 / 16 } } ?? 0
                            let lead = (m.left ?? 5.4) + edge
                            // (A float centred in the cell stands at the middle of the cell, as its margins are the same both sides:
                            // lo-c7082c66's, 277.1 in Word's print, was 283 with the left margin added.)
                            for k in first ..< paragraphs.count where paragraphs[k].cell == currentCell && !paragraphs[k].style.centredFloat { paragraphs[k].style.indentLeft += lead }
                            // (A table floating by the text keeps its right distance from the text out of the room its
                            // lines have: lo-660753a9's middle table, 141 twips each side, sets "before the inner
                            // table" in a cell 7pt narrower, and its inner table's "inner table row 1" in two lines.)
                            if let fp = node.first("w:tblPr")?.first("w:tblpPr"), fp["w:vertAnchor"] == "text" {
                                let gap = (Double(fp["w:rightFromText"] ?? "") ?? 0) / 20
                                for k in first ..< paragraphs.count where paragraphs[k].cell == currentCell && !paragraphs[k].style.centredFloat { paragraphs[k].style.indentRight += gap }
                            }
                            // (Its top margin and top line stand again over a part of it that goes over a
                            // page — see `RichParagraphStyle.nestedTopRepeat`; not over its first paragraph,
                            // which brings its own space. The cell's own line, else the table's: Word for
                            // Windows' lab nt1 sets three nested levels 6.12pt each under their 5.65 margins
                            // and 0.5pt lines, and 15.0pt for 0 + 0.5, 10 + 1.5 and 3 + none.)
                            func line(_ name: String, _ fallback: String) -> Double {
                                let b = tc.first("w:tcPr")?.first("w:tcBorders")?.first(name) ?? node.first("w:tblPr")?.first("w:tblBorders")?.first(fallback)
                                guard let b, (b["w:val"] ?? "none") != "none" else { return 0 }
                                return Double(b["w:sz"] ?? "").map { $0 / 8 } ?? 0
                            }
                            let topEdge = line("w:top", r == 0 ? "w:top" : "w:insideH")
                            let bottomEdge = line("w:bottom", r == rows.count - 1 ? "w:bottom" : "w:insideH")
                            for k in (first + 1) ..< max(first + 1, paragraphs.count) where paragraphs[k].cell == currentCell {
                                paragraphs[k].style.nestedTopRepeat += (m.top ?? 0) + topEdge
                            }
                            for k in first ..< max(first, paragraphs.count - 1) where paragraphs[k].cell == currentCell {
                                paragraphs[k].style.nestedBottomRepeat += (m.bottom ?? 0) + bottomEdge
                            }
                            paragraphs[first].style.spaceBefore += (m.top ?? 0) + topEdge + spacing * (r == 0 ? 2 : 1)
                            paragraphs[paragraphs.count - 1].style.spaceAfter += (m.bottom ?? 0) + bottomEdge + spacing * (r == rows.count - 1 ? 2 : 1)
                        }
                    }
                }
                if let kid = keptId {
                    if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid]!.texts = paragraphs[before...].map(\.text)
                }
            case "w:tbl" where currentCell == nil && depth == 0 && Self._isInvisibleWrapper(node):
                // A one-column table that draws nothing round tables of its
                // own is a page's frame, and its tables are the body's:
                // zh-e9616b2b is all one such cell (its only line an
                // insideV, which one column never draws), and its 35-row
                // checklist, flattened as a table in a cell is, ran four
                // pages where Word's print parts it over two. Read as the
                // body; the wrapper goes back as written while the text is.
                // (Each cell keeps the room the wrapper gave it above and
                // below, as a nested table's do — see there: zh-045c5a75's
                // law text stands in a wrapper of 0.75pt margins and
                // spacing, and Word sets its first line 2.35pt lower than
                // ours, the row that parts at page 9's foot a line shorter.)
                let before = paragraphs.count
                let rows = unwrapped(node, "w:tr")
                let tableMargins = _cellMargins(node.first("w:tblPr"))
                let spacing = node.first("w:tblPr")?.first("w:tblCellSpacing").flatMap { sp -> Double? in
                    (sp["w:type"] ?? "dxa") == "dxa" ? Double(sp["w:w"] ?? "").map { $0 / 20 } : nil
                } ?? 0
                for (r, tr) in rows.enumerated() {
                    for tc in unwrapped(tr, "w:tc").prefix(1) {
                        let first = paragraphs.count
                        // (The cell's mark under a table it ends with takes
                        // no room in Word, as under a nested one: 60329's
                        // rows, each a table and that mark, stood a line
                        // apart read as the body's.)
                        var children = tc.children
                        if let last = children.last, last.name == "w:p", children.dropLast().last?.name == "w:tbl",
                           !last.children.contains(where: { $0.name != "w:pPr" }) { children.removeLast() }
                        inWrapperBody = true
                        wrapperIndent = Self.wordOnWindows ? (node.first("w:tblPr")?.first("w:tblInd").flatMap { (($0["w:type"] ?? "dxa") == "dxa") ? Double($0["w:w"] ?? "") : nil } ?? 0) / 20 : 0
                        for child in children { walkBlock(child, indent: indent, depth: depth) }
                        inWrapperBody = false
                        wrapperIndent = 0
                        guard paragraphs.count > first else { continue }
                        // (A row of one paragraph keeps the height the row
                        // was given as that line's least: 60329's 9pt
                        // spacer row holds a 1pt empty mark, and Word's
                        // print has the 9pt between its tables.)
                        // (An empty cell whose end mark the file hides (`w:hideMark`)
                        // asks nothing of its row, as in a table's own rows: the row is
                        // its stated height, or none. Lab ebb4 (Word, 2026-11-08): the
                        // two 150-twip rows of ebb4a037's wrapper are 7.5 each with the
                        // height and 0 without, where a 9.65 pt mark line held them.)
                        if paragraphs.count == first + 1, !children.contains(where: { $0.name == "w:tbl" }),
                           paragraphs[first].text.isEmpty, paragraphs[first].image == nil, paragraphs[first].inlineImages.isEmpty,
                           _on(tc.first("w:tcPr")?.first("w:hideMark")),
                           tr.first("w:trPr")?.first("w:trHeight")?["w:hRule"] != "exact" {
                            let v = (tr.first("w:trPr")?.first("w:trHeight")).flatMap { Double($0["w:val"] ?? "") } ?? 0
                            paragraphs[first].style.lineHeightPoints = max(v / 20, 0.05)
                            paragraphs[first].style.lineHeightIsMinimum = false
                        } else
                        if paragraphs.count == first + 1, !children.contains(where: { $0.name == "w:tbl" }),
                           let h = tr.first("w:trPr")?.first("w:trHeight"), h["w:hRule"] != "exact",
                           let v = Double(h["w:val"] ?? ""), v > 0,
                           paragraphs[first].style.lineHeightPoints == nil || paragraphs[first].style.lineHeightIsMinimum {
                            paragraphs[first].style.lineHeightPoints = max(paragraphs[first].style.lineHeightPoints ?? 0, v / 20)
                            paragraphs[first].style.lineHeightIsMinimum = true
                        }
                        let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(tableMargins)
                        // (Over the first paragraph that takes room in the flow: a table
                        // floating by the text opening the cell has none, and its rows
                        // would give the space away — floattable-del-empty's heading
                        // stands 2.25pt over where Word's does.)
                        var lead = first
                        while lead < paragraphs.count - 1, let c = paragraphs[lead].cell,
                              tableStyles[c.table]?.floatsOverText == true, tableStyles[c.table]?.pageAnchored == false { lead += 1 }
                        if paragraphs[lead].cell != nil, let c = paragraphs[lead].cell, tableStyles[c.table]?.floatsOverText == true { lead = first }
                        // (And its automatic space before is the cell's top, none:
                        // the heading under the table stands at the cell's head.)
                        // (Word sets that table a second margin down, from the cell's
                        // content: the 69pt table of floattable-del-empty stands 4.5pt
                        // under where the flow reached, twice the wrapper's 2.25.)
                        if lead != first {
                            var moved = Set<String>()
                            for k in first ..< lead {
                                if let c = paragraphs[k].cell, var st = tableStyles[c.table], st.floatsOverText, !st.pageAnchored, moved.insert(c.table).inserted {
                                    st.floatOffsetY = (st.floatOffsetY ?? 0) + (Self.wordOnWindows ? 1 : 2) * (m.top ?? 0)
                                    tableStyles[c.table] = st
                                }
                            }
                        }
                        if lead != first, paragraphs[lead].style.spaceBeforeAuto {
                            paragraphs[lead].style.spaceBeforeAuto = false
                            paragraphs[lead].style.spaceBefore = 0
                        }
                        let tblW = node.first("w:tblPr")?.first("w:tblW")
                        let fixedLayout = node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed"
                        let indentPt = (node.first("w:tblPr")?.first("w:tblInd").flatMap { (($0["w:type"] ?? "dxa") == "dxa") ? Double($0["w:w"] ?? "") : nil } ?? 0) / 20
                        if indentPt != 0 {
                            for k in first ..< paragraphs.count where paragraphs[k].cell == nil && paragraphs[k].image == nil { paragraphs[k].style.indentLeft += indentPt }
                        }
                        if fixedLayout, (tblW?["w:type"] ?? "") == "dxa", let dxa = Double(tblW?["w:w"] ?? "") {
                            for k in first ..< paragraphs.count where paragraphs[k].cell == nil && paragraphs[k].image == nil {
                                paragraphs[k].style.wrapperRight = indentPt + dxa / 20 - (tableMargins.left ?? 5.4) - (tableMargins.right ?? 5.4)
                            }
                        } else if Self.wordOnWindows, let tw = node.first("w:tblPr")?.first("w:tblW"), (tw["w:type"] ?? "") == "dxa",
                           let dxa = Double(tw["w:w"] ?? ""), tc.first("w:tcPr")?.first("w:tcW").map({ ($0["w:type"] ?? "auto") == "auto" }) ?? true {
                            let room = dxa / 20 - (tableMargins.left ?? 0) - (tableMargins.right ?? 0)
                            for k in first ..< paragraphs.count where paragraphs[k].cell == nil && paragraphs[k].image == nil { paragraphs[k].style.wrapperRoom = room }
                        }
                        paragraphs[lead].style.spaceBefore += (m.top ?? 0) + spacing * (r == 0 ? 2 : 1)
                        // (Its automatic space after is the cell's foot, none, as in any
                        // cell: floattable-del-empty's last "NormalWeb" paragraph of a
                        // wrapper stands 17pt over the rule under it in Word's print,
                        // ours 28.7.)
                        if paragraphs[paragraphs.count - 1].style.spaceAfterAuto, paragraphs[paragraphs.count - 1].style.list == nil {
                            paragraphs[paragraphs.count - 1].style.spaceAfterAuto = false
                            paragraphs[paragraphs.count - 1].style.spaceAfter = 0
                        }
                        paragraphs[paragraphs.count - 1].style.spaceAfter += (m.bottom ?? 0) + spacing * (r == rows.count - 1 ? 2 : 1)
                        // (And on each page the row goes on to — see
                        // `RichParagraphStyle.frameInsetTop`.)
                        if rows.count == 1 {
                            for k in first ..< paragraphs.count {
                                paragraphs[k].style.frameInsetTop = (m.top ?? 0) + spacing * 2
                                paragraphs[k].style.frameInsetBottom = (m.bottom ?? 0) + spacing * 2
                            }
                        }
                    }
                }
                if paragraphs.count > before, let frag = _keptFragment(node, notes) {
                    keptTableCount += 1
                    let kid = "kc\(keptTableCount)"
                    for k in before ..< paragraphs.count { paragraphs[k].keptTable = kid }
                    keptTables[kid] = KeptTable(xml: frag.xml, rels: frag.rels, texts: paragraphs[before...].map(\.text))
                }
            case "w:tbl":
                tableCount += 1
                let id = "t\(tableCount)"
                // Word's Table Grid says no space after and single lines;
                // a table with no style leaves the document defaults.
                cellBase = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBases[$0] } ?? base
                cellRootBase = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableRootBases[$0] } ?? docBase
                if let grid = node.first("w:tblGrid") {
                    let widths = grid.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") }.map { $0 / 20 }
                    if !widths.isEmpty { tableColumns[id] = widths }
                }
                // (Cells wider than the grid column they stand in make the column wider, in a table
                // that fits its content: Word's print of the lab tw1 has each column as wide as its
                // widest cell, 6381 + 6381 under a 4536 + 1845 grid, and the whole scaled down to the
                // text when it is wider. LibreOffice's tdf79329.)
                // (A preferred width under 6/10 of the grid it sits over, on an autofit table, is a converter's
                // stale figure: sa2 cb623f0a says 7800 twips over five columns of 7800, and Word's print has the
                // five scaled to the text width, 90 pt each. Treated as auto.)
                let staleTblW: Bool = {
                    guard DocxFormat.wordOnWindows, let tw = node.first("w:tblPr")?.first("w:tblW"), tw["w:type"] == "dxa",
                          let w = Double(tw["w:w"] ?? ""), w > 0, let cols = tableColumns[id] else { return false }
                    return w / 20 < cols.reduce(0, +) * 0.6
                }()
                if let cols = tableColumns[id], node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] != "fixed",
                   !(node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].map { fixedTableStyles.contains($0) } ?? defaultTableFixed),
                   staleTblW || (node.first("w:tblPr")?.first("w:tblW")?["w:type"] ?? "auto") == "auto" {
                    var widest = cols
                    var wider = false
                    // (Only where a row is far wider than the grid — nearly twice: lo-a197b7a8's three 4428-twip cells under an 8812 grid, 1.5 times, keep the grid in Word's print; a grid Word wrote is its own
                    // layout of the columns, and cells wider than it are preferences it overruled.)
                    let gridTotal = cols.reduce(0, +)
                    for tr in unwrapped(node, "w:tr") where tr.first("w:trPr")?.first("w:gridBefore") == nil {
                        var col = 0
                        var rowTotal = 0.0
                        for tc in unwrapped(tr, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? "") { rowTotal += v / 20 }
                        }
                        guard rowTotal > gridTotal * 1.75 else { continue }
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if span == 1, col < widest.count, w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v / 20 > widest[col] + 1 {
                                widest[col] = v / 20
                                wider = true
                            }
                            col += span
                        }
                    }
                    if wider { tableColumns[id] = widest }
                    // (A table nested in a cell takes its columns from its cells' stated
                    // widths, scaled to the room its grid has: lo-5c5eb1f7's header table,
                    // cells of 1266 and 7868 twips over a grid of 1253 and 5354, has its
                    // first column 45pt in Word's print, 1266 of 9134 of the grid's
                    // 330pt, where the grid's own gave 62.7.)
                    else if currentCell != nil || depth > 0, let first = unwrapped(node, "w:tr").first, first.first("w:trPr")?.first("w:gridBefore") == nil {
                        var widths: [Double] = []
                        var ok = true
                        for tc in unwrapped(first, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0, tc.first("w:tcPr")?.first("w:gridSpan") == nil else { ok = false; break }
                            widths.append(v / 20)
                        }
                        let total = widths.reduce(0, +)
                        if ok, widths.count == cols.count, total > gridTotal * 1.05 {
                            tableColumns[id] = widths.map { $0 / total * gridTotal }
                        }
                    }
                }
                // (An auto-width table whose grid is an equal split, a converter's stand-in, while
                // every row's cells state the same widths in twips: Word lays the columns out by those
                // cells, not by the grid. jpn-z20806500-dacd38: a grid of 3427 x 3 under cells of
                // 1728 / 6048 / 2304, its columns at 59.4 / 145.8 / 448.3 pt in Word's print.)
                // (Fixed layout too: jpn-z22667840-bc5fb7's python-docx table, grid 3293 x 3 under cells
                // of 3168 / 2016 / 4464 and tblLayout fixed, has its edges by the cells in Word's print.)
                // (Or any auto-layout table whose rows all state the same widths: Word's autofit starts from the
                // cells' widths, not the grid, and shrinks them to the room by their slack over the content minimum:
                // dx2 cf39f18f, cells 1060/1944/6376 over a grid of 931/2471/5318, columns 49/101/287 pt in Word's print.)
                if let cols = tableColumns[id], cols.count > 1,
                   let cw = _statedCellColumns(node, count: cols.count, widest: true),
                   _cellsAgreeWithTableWidth(node, cells: cw.reduce(0, +)) {
                    if (cols.max() ?? 0) - (cols.min() ?? 0) <= 0.1 { tableColumns[id] = cw }
                    // (Left to the layout, which takes them when no cell's narrowest outgrows its stated width.)
                    else if zip(cw, cols).contains(where: { abs($0 - $1) > 1 }),
                            node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] != "fixed",
                            // (A table that zeroes its own left and right cell margins keeps its grid: sa1 8b5747ec's
                            // table, tblCellMar 0 / 0 with the cells' 108 stated per cell, has all seven columns on the grid
                            // within 0.1 pt in Word's print.)
                            !_tableZeroesSideMargins(node) { tableCellColumns[id] = cw }
                }
                // (A fixed table of a stated share whose cells all state widths, each row the
                // same, a little under its grid: Word rules the cells' widths, not the grid.
                // zh-4a90bb2f's table, 6306 pct of a 442pt column over a grid of 11267 twips,
                // cells 1914 5515 939 1336 1464 = 11168: rules at 95.8 and 371.8pt from the left
                // edge in Word's print, the cells' 95.7 and 371.5, the grid's 96.6 and 372.7.)
                if let cols = tableColumns[id], node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] == "fixed",
                   node.first("w:tblPr")?.first("w:tblW")?["w:type"] == "pct" {
                    var widths: [Double]? = nil
                    var same = true
                    for tr in unwrapped(node, "w:tr") {
                        var row: [Double] = []
                        // (Rows with merged cells are left out: the whole-width rows state their own.)
                        if tr.first("w:trPr")?.first("w:gridBefore") != nil || unwrapped(tr, "w:tc").contains(where: { $0.first("w:tcPr")?.first("w:gridSpan") != nil }) { continue }
                        for tc in unwrapped(tr, "w:tc") {
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0 else { same = false; break }
                            row.append(v / 20)
                        }
                        if !same || row.count != cols.count { same = false; break }
                        if let first = widths { if first != row { same = false; break } } else { widths = row }
                    }
                    if same, let w = widths {
                        let total = w.reduce(0, +), gridTotal = cols.reduce(0, +)
                        if total < gridTotal - 1, total > gridTotal * 0.95 { tableColumns[id] = w }
                    }
                }
                // (A table with no grid at all has its first row's cells for one:
                // LibreOffice's floattable-nested-3tables, tables of 2000-twip
                // cells, wraps "before the middle table:" in them in Word's print.)
                if tableColumns[id] == nil, node.first("w:tblGrid") == nil, let first = unwrapped(node, "w:tr").first,
                   first.first("w:trPr")?.first("w:gridBefore") == nil {
                    var widths: [Double] = []
                    var ok = true
                    for tc in unwrapped(first, "w:tc") {
                        let w = tc.first("w:tcPr")?.first("w:tcW")
                        let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                        guard w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0 else { ok = false; break }
                        widths += Array(repeating: v / 20 / Double(span), count: span)
                    }
                    if ok, !widths.isEmpty { tableColumns[id] = widths }
                }
                var style = TableStyle()
                if let pr = node.first("w:tblPr") {
                    if let sid = pr.first("w:tblStyle")?["w:val"], keptTableStyles[sid] != nil { tableStyleIds[id] = sid }
                    if tableStyleIds[id] != nil, let look = pr.first("w:tblLook") { tableLooks[id] = PptxXML.serialize(_standaloneW(look)) }
                    if tableStyleIds[id] != nil, let c = pr.first("w:tblStyle")?["w:val"].flatMap({ tableConds[$0] }), !c.fills.isEmpty {
                        tableCondFills[id] = TableCondFills(byType: c.fills, rowBandSize: c.rowBandSize ?? 0, colBandSize: c.colBandSize ?? 0)
                    }
                }
                // The table's own borders, else its style's, else none —
                // 64 of the corpus's 109 tables say nothing and have none.
                // Tables converted from HTML say it per cell instead
                // (bug65649's 5,734-cell table, bug59058, table-indent):
                // what most cells say wins, with their colour.
                let styledBorders = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableBorders[$0] }
                let cells = unwrapped(node, "w:tr").flatMap { unwrapped($0, "w:tc") }
                let lostEdges = _lostCellEdges(rows: unwrapped(node, "w:tr").map { unwrapped($0, "w:tc") })
                // A cell that only switches its left/right sides off says nothing about
                // the horizontal rules, which the table's own or its style's top and
                // bottom borders still draw (sa2 fee2a9e5: Light Shading's 1pt top rule
                // above rows whose cells name left/right none; Word's print has it).
                let cellSaid = cells.compactMap { c -> _Borders? in
                    guard let b = _borders(c.first("w:tcPr"), "w:tcBorders", lost: lostEdges[ObjectIdentifier(c)] ?? []) else { return nil }
                    if !b.on, RichTextTheme.wordWindowsPages, styledBorders?.on == true, node.first("w:tblPr")?.first("w:tblBorders") == nil,
                       let tb = c.first("w:tcPr")?.first("w:tcBorders"),
                       !tb.children.contains(where: { $0.name == "w:top" || $0.name == "w:bottom" }) { return nil }
                    return b
                }
                var cellBorders: _Borders? = nil
                if cellSaid.count * 2 >= cells.count, !cells.isEmpty {
                    let on = cellSaid.filter(\.on)
                    if on.count * 2 > cells.count {
                        // The width most cells draw, not the first cell's:
                        // bug65649's estimate rows rule their cells at sz 6
                        // and a few headings at sz 12, and the first cell
                        // was a heading — every row came out a point taller.
                        var pick = on.first { $0.color != nil } ?? on[0]
                        var counts: [Double: Int] = [:]
                        for b in on { if let w = b.width { counts[w, default: 0] += 1 } }
                        if let best = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }) { pick.width = best.key }
                        cellBorders = pick
                    }
                    else if (cellSaid.count - on.count) * 2 > cells.count { cellBorders = _Borders(on: false, color: nil) }
                }
                let borders = cellBorders ?? _borders(node.first("w:tblPr"), "w:tblBorders") ?? styledBorders ?? defaultBorders
                style.borders = borders?.on ?? false
                if cellBorders != nil, node.first("w:tblPr")?.first("w:tblBorders") == nil, styledBorders == nil {
                    style.bordersFromCells = true
                }
                // (The table's own colour when its cells decided the switch
                // and named none: bug57031's grey frames came back black.)
                style.borderColor = borders?.color ?? _borders(node.first("w:tblPr"), "w:tblBorders")?.color
                // (The width a side no cell states takes is the table's own,
                // else its style's, where either says one — the cells decide
                // only whether it is ruled: zh-bbbb2e6a's review form rules
                // its cells' outer sides 1.5pt and leaves the rows to Table
                // Grid's 0.5pt, its 96.6pt rows 97.1 apart in Word's print;
                // ours took 1.5 between them, 98.1, and the form's closing
                // lines went to a page of their own.)
                let tableSaid = _borders(node.first("w:tblPr"), "w:tblBorders") ?? styledBorders
                let widthFrom = cellBorders != nil && tableSaid?.on == true ? tableSaid : borders
                style.borderWidth = widthFrom?.width.flatMap { $0 == 0.5 ? nil : $0 }   // nil is Word's 0.5pt
                // The line style: the cells' when they decided, else the
                // table's own (a table ruled by its cells' nil sides still
                // names outset on its tblBorders).
                style.borderStyle = borders?.style ?? _borders(node.first("w:tblPr"), "w:tblBorders")?.style
                // Sides whose line style or width differ from the table's.
                // (A side the table's own borders leave out is its style's,
                // width and all: zh-5251dd23's tables name a 2.25pt frame
                // and leave the rows to Table Grid's 0.5pt insideH; ours
                // drew them 2.25 and every row 1.8pt taller.)
                let styledSides = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableSides[$0] }
                if let tb = node.first("w:tblPr")?.first("w:tblBorders") {
                    for side in ["top", "left", "bottom", "right", "insideH", "insideV"] {
                        guard let e = tb.first("w:" + side) ?? styledSides?.first("w:" + side),
                              !["nil", "none"].contains(e["w:val"] ?? "nil") else { continue }
                        if let v = e["w:val"], v != (style.borderStyle ?? "single") { style.edgeStyles[side] = v }
                        if let sz = Double(e["w:sz"] ?? ""), max(0.25, sz / 8) != (style.borderWidth ?? 0.5) { style.edgeWidths[side] = max(0.25, sz / 8) }
                    }
                }
                // The table's sides, where they differ from that verdict:
                // its own w:tblBorders over its style's, and a side neither
                // names is none (form_footnotes' tables are ruled outside,
                // not between their cells; the verdict alone ruled every
                // row and grew the form by a line of borders).
                let styledEdges = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableEdges[$0] ?? nil }
                if let own = _edges(node.first("w:tblPr"), "w:tblBorders") ?? styledEdges {
                    var e = BorderEdges()
                    e.top = own.top ?? styledEdges?.top ?? false
                    e.left = own.left ?? styledEdges?.left ?? false
                    e.bottom = own.bottom ?? styledEdges?.bottom ?? false
                    e.right = own.right ?? styledEdges?.right ?? false
                    e.insideH = own.insideH ?? styledEdges?.insideH ?? false
                    e.insideV = own.insideV ?? styledEdges?.insideV ?? false
                    if e.top == style.borders { e.top = nil }
                    if e.left == style.borders { e.left = nil }
                    if e.bottom == style.borders { e.bottom = nil }
                    if e.right == style.borders { e.right = nil }
                    if e.insideH == style.borders { e.insideH = nil }
                    if e.insideV == style.borders { e.insideV = nil }
                    if !e.isEmpty { style.edges = e }
                }
                // Leading rows that repeat on every page: all of them.
                var repeating = unwrapped(node, "w:tr").prefix { _on($0.first("w:trPr")?.first("w:tblHeader")) }.count
                // The style's conditional parts, as w:tblLook switches them
                // on (attributes in 2010 files, bits of w:val in 2007's).
                let cond = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableConds[$0] } ?? _Cond()
                let tableStyleSize = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableSizes[$0] }
                let tableStyleChar = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableChars[$0] }
                let look = node.first("w:tblPr")?.first("w:tblLook")
                let lookVal = look.flatMap { Int($0["w:val"] ?? "", radix: 16) } ?? 0x04A0
                // A table with no named style keeps a look that is not Word's default, so a save writes it back.
                if node.first("w:tblPr")?.first("w:tblStyle") == nil, look != nil {
                    let bit: (String, Int) -> Bool = { name, mask in look?[name].map { $0 != "0" } ?? (lookVal & mask != 0) }
                    let v = (bit("w:firstRow", 0x20) ? 0x20 : 0) | (bit("w:lastRow", 0x40) ? 0x40 : 0) | (bit("w:firstColumn", 0x80) ? 0x80 : 0)
                        | (bit("w:lastColumn", 0x100) ? 0x100 : 0) | (bit("w:noHBand", 0x200) ? 0x200 : 0) | (bit("w:noVBand", 0x400) ? 0x400 : 0)
                    if v != 0x04A0 { style.look = v }
                }
                let lookBit: (String, Int) -> Bool = { name, mask in look?[name].map { $0 != "0" } ?? (lookVal & mask != 0) }
                let lookBits = (lookBit("w:firstRow", 0x20) ? 0x20 : 0) | (lookBit("w:lastRow", 0x40) ? 0x40 : 0) | (lookBit("w:firstColumn", 0x80) ? 0x80 : 0)
                    | (lookBit("w:lastColumn", 0x100) ? 0x100 : 0) | (lookBit("w:noHBand", 0x200) ? 0x200 : 0) | (lookBit("w:noVBand", 0x400) ? 0x400 : 0)
                let firstRowOn = look?["w:firstRow"].map { $0 != "0" } ?? (lookVal & 0x0020 != 0)
                // (A style whose first row repeats does so in every table of
                // it that has a header row on: LibreOffice's fdo78904_fileHang,
                // 12 tables of "Table with Header", repeats "Account /
                // Description / Permissions" at the head of its next page in
                // Word's print, with no tblHeader in the file's rows.)
                if repeating == 0, firstRowOn, cond.headerRepeats { repeating = 1 }
                if repeating > 0 { style.headerRow = true; style.headerRowCount = repeating }
                let firstColOn = look?["w:firstColumn"].map { $0 != "0" } ?? (lookVal & 0x0080 != 0)
                // Where the table sits in the column (w:jc on the table).
                // (Or on its rows, every one of them, when the table says
                // nothing: a centred form came back at the left margin.)
                let rowJc = Set(unwrapped(node, "w:tr").map { $0.first("w:trPr")?.first("w:jc")?["w:val"] ?? "" })
                switch node.first("w:tblPr")?.first("w:jc")?["w:val"] ?? (rowJc.count == 1 ? rowJc.first! : "") {
                case "center": style.alignment = .center
                case "right", "end": style.alignment = .right
                default: break
                }
                let styled = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap { tableMargins[$0] } ?? _Margins()
                // Margins the cells carry themselves (w:tcMar, again the
                // HTML converters' habit) when most of them do.
                let cellMars = cells.filter { $0.first("w:tcPr")?.first("w:tcMar") != nil }
                var cellMar = cellMars.count * 2 >= cells.count && !cellMars.isEmpty
                    ? _cellMargins(cellMars[0].first("w:tcPr"), "w:tcMar") : _Margins()
                // (A side that more than half of them state: a margin one cell
                // alone gives its right is its own — lo tdf160077_layoutInCellB's
                // first cell, right 720 beside a second that says nothing of it,
                // took 36pt off the second's lines, which wrapped a word early.)
                let statedBy = cellMars.map { _cellMargins($0.first("w:tcPr"), "w:tcMar") }
                if statedBy.filter({ $0.top != nil }).count * 2 <= cells.count { cellMar.top = nil }
                if statedBy.filter({ $0.left != nil }).count * 2 <= cells.count { cellMar.left = nil }
                if statedBy.filter({ $0.bottom != nil }).count * 2 <= cells.count { cellMar.bottom = nil }
                if statedBy.filter({ $0.right != nil }).count * 2 <= cells.count { cellMar.right = nil }
                let margins = cellMar.under(_cellMargins(node.first("w:tblPr"))).under(styled).under(defaultMargins).under(_Margins.word)
                style.cellMarginTop = margins.top
                style.cellMarginLeft = margins.left
                style.cellMarginBottom = margins.bottom
                style.cellMarginRight = margins.right
                // (The table's own margins, else its style's, else Word's:
                // what the layout sets a table out by before Word 2013's
                // layout — a stated margin too, lab `tc` 2026-10-14.)
                let own = _cellMargins(node.first("w:tblPr"))
                let base = styled.under(defaultMargins).under(_Margins.word)
                style.textOutdent = own.left ?? base.left ?? 5.4
                style.textOutdentRight = own.right ?? base.right ?? 5.4
                style.tableOwnMarginLeft = own.left ?? base.left ?? 5.4
                // (A styles part with no default table style: the table stands on the margin and its text 0.5pt in, rules or none, in
                // every mode: lab tblx, Word for Windows, compat 12 and 15; dx2 8afcc2c4's tables at 72.5.)
                if Self.wordOnWindows, noDefaultTableStyle, own.left == nil, styled.left == nil, (margins.left ?? 0) == 0, node.first("w:tblPr")?.first("w:tblBorders")?.first("w:left") == nil {
                    RuleTrace.hit("no-default-table-style-text-half-point-in")
                    style.cellMarginLeft = 0.5
                    style.textOutdent = 0
                    style.cellMarginRight = 0.5
                }
                // (The same file states its own table margin and a cell spacing: the table stands on the page's margin all the same and its text one margin in,
                // not set out by it: lab tbauto, Word for Windows, compat 12, 80-twip margins, text at 76 and 81 with 50-twip spacing.)
                else if Self.wordOnWindows, noDefaultTableStyle, own.left != nil, styled.left == nil, node.first("w:tblPr")?.first("w:tblCellSpacing") != nil {
                    RuleTrace.hit("no-default-table-style-own-margin-not-set-out")
                    style.textOutdent = 0
                    style.notSetOut = true
                }
                // (… unless its first cell states its own: the table is set
                // out by the margin of the cell whose text it lines up.
                // zh-6143e5f0's plans, cells of zero margin in a table of
                // Word's 5.4pt, have their left rule on the page's margin
                // in Word's print, where ours stood 5.4pt left of it.)
                if let first = node.first("w:tr")?.first("w:tc"),
                   let l = _cellMargins(first.first("w:tcPr"), "w:tcMar").left {
                    style.textOutdent = l
                }
                // (A table read out of a frame's wrapper is a nested table
                // all the same: Word sets it out by nothing — lab nestmargin.)
                if inWrapperBody, Self.wordOnWindows { style.textOutdent = 0; style.textOutdentRight = 0; style.inWrapperCell = true }
                // The table's own margins, for the save: the cells keep
                // their w:tcMar, and the cells that state none take these
                // (drawing.docx zeroes its banner row's and leaves 5.25pt
                // on the rest; flattened to zero, every article under a
                // banner sat that much high — 6.1% over twenty pages).
                if !cellMars.isEmpty {
                    let own = _cellMargins(node.first("w:tblPr")).under(styled).under(defaultMargins).under(_Margins.word)
                    var xml = "<w:tblCellMar>"
                    for (side, v) in [("top", own.top), ("left", own.left), ("bottom", own.bottom), ("right", own.right)] {
                        if let v { xml += "<w:\(side) w:w=\"\(Int((v * 20).rounded()))\" w:type=\"dxa\"/>" }
                    }
                    style.keptCellMarginsXML = xml + "</w:tblCellMar>"
                    style.keptCellMarginsUnder = [margins.top, margins.left, margins.bottom, margins.right]
                }
                if node.mirroredFrom != nil { style.bidiVisual = true }
                if let ind = node.first("w:tblPr")?.first("w:tblInd"), (ind["w:type"] ?? "dxa") == "dxa",
                   let w = Double(ind["w:w"] ?? "") {
                    // (A table nested in a cell never starts left of the cell's text edge in
                    // Word for Windows, either compat mode: lab nest51 prints tblInd -120, -60
                    // and 0 all at the edge, +60 and +120 that far in. zh-/lo-51b81ccd's -60.)
                    style.indent = Self.wordOnWindows && (currentCell != nil || depth > 0) ? max(0, w / 20) : w / 20
                    if inWrapperBody, wrapperIndent > 0 { style.indent += wrapperIndent }
                    if node.mirroredFrom != nil { style.bidiVisual = true }
                } else if node.first("w:tblPr")?.first("w:tblInd") == nil,
                          let w = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap({ tableIndents[$0] }) {
                    // (Or its style's: LibreOffice's NumberedList, a table style that
                    // indents by 360 twips for a list, stands 41pt in from the margin
                    // in Word's print and stood at it.)
                    style.indent = w / 20
                }
                if let own = node.first("w:tblPr")?.first("w:tblLayout")?["w:type"] {
                    if own == "fixed" { style.fixedLayout = true }
                } else if node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].map({ fixedTableStyles.contains($0) }) ?? defaultTableFixed {
                    style.fixedLayout = true
                }
                // A floating table's anchor (Bug54771b's title block sits at
                // the right margin, a set distance down the page).
                style.keptShdXML = node.first("w:tblPr")?.first("w:shd").map { PptxXML.serialize($0) }
                if let pos = node.first("w:tblPr")?.first("w:tblpPr") {
                    if pos["w:vertAnchor"] == "page" { style.pageAnchored = true }
                    if pos["w:vertAnchor"] == "page", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? "") { style.pageOffsetY = v / 20 }
                    if pos["w:tblpYSpec"] == "bottom", pos["w:tblpY"] == nil { style.pageAnchored = true; style.bottomAligned = true }
                    style.keptPosition = PptxXML.serialize(pos)
                        + (node.first("w:tblPr")?.first("w:tblOverlap").map { PptxXML.serialize($0) } ?? "")
                    // (No `w:vertAnchor` is the text's, the schema's default: LibreOffice's fdo68607, `w:tblpY` 495
                    // and none, stands 24.75pt under the margin in Word for Windows' print, where ours stood at it.)
                    let vertText = (pos["w:vertAnchor"] ?? "text") == "text"
                    if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
                        if pos["w:vertAnchor"] == nil { style.marginOffsetY = v / 20 } else { style.floatOffsetY = v / 20 }
                    }
                    // (A table anchored to the margin stands w:tblpY under the nominal top margin, as one
                    // with no anchor stated does: Word's print of lab tblhdr h2, first baseline 151.82.)
                    if Self.wordOnWindows, pos["w:vertAnchor"] == "margin", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
                        style.marginOffsetY = v / 20
                    }
                    if Self.wordOnWindows, pos["w:vertAnchor"] == "margin", pos["w:tblpYSpec"] == nil, style.marginOffsetY != nil { style.floatOffsetY = style.marginOffsetY }
                    // (`w:tblpYSpec="top"` with no anchor stated stands at the margin's top, over the empty
                    // paragraph before it: LibreOffice's lo-0dd5bc0a, a cover-page SDT; Word's print has it 26pt
                    // higher than ours, which set it under that paragraph.)
                    if let v = Double(pos["w:bottomFromText"] ?? ""), v > 0, style.floatOffsetY != nil, pos["w:tblpYSpec"] == nil { style.floatBottomGap = v / 20 }
                    if pos["w:tblpYSpec"] == "top", pos["w:vertAnchor"] == nil || pos["w:vertAnchor"] == "margin", pos["w:tblpY"] == nil {
                        style.marginOffsetY = 0
                    }
                    // (A table placed "inside" the text's line takes no room in it either: LibreOffice's
                    // tdf-less lo-4c84a541 has "After table1" level with it in Word's print.)
                    if vertText || (Self.wordOnWindows && pos["w:vertAnchor"] == "margin" && style.marginOffsetY != nil), pos["w:tblpYSpec"] == nil || pos["w:tblpYSpec"] == "inside" { style.floatsOverText = true }
                    if pos["w:vertAnchor"] == "text", pos["w:tblpYSpec"] == "top" { style.floatsTopByText = true }
                    // (A drawing the table holds that is not laid out in its cell.)
                    if node.descendants("wp:anchor").contains(where: { $0["layoutInCell"] == "0" }) { style.shapesLeaveCell = true }
                    if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v < 0 {
                        style.floatRaiseY = -v / 20
                    }
                    if pos["w:tblpXSpec"] == nil, let v = Double(pos["w:tblpX"] ?? "") {
                        style.floatX = v / 20
                        style.floatXAnchor = pos["w:horzAnchor"] ?? "text"
                    } else if let spec = pos["w:tblpXSpec"], (pos["w:horzAnchor"] ?? "text") != "page" || (spec == "center" && DocxFormat.wordOnWindows) {
                        // (Centred on the PAGE, as zh-a4e8599d p3's: its first rule at 67.8 in Word's print, the middle of 595pt
                        // for 460pt of table, where ours stood at the margin, 84.6. On a page of equal margins the two middles are one.)
                        // Or aligned in its margin or column, a table wider
                        // than it standing out on both sides: zh-0243e7fc
                        // p11's 539pt form, centred on its 415pt margin, has
                        // its first column's text at 54pt in Word's print,
                        // where ours, at the margin, stood at 115.
                        if spec == "center" { style.alignment = .center }
                        if spec == "center", DocxFormat.wordOnWindows,
                           let bv = node.first("w:tblPr")?.first("w:bidiVisual") ?? node.mirroredFrom?.first("w:tblPr")?.first("w:bidiVisual"),
                           !["0", "false", "off"].contains((bv["w:val"] ?? "1").lowercased()) { style.floatCentredBidi = true }
                        if spec == "right" { style.alignment = .right }
                        style.floatXAnchor = pos["w:horzAnchor"] ?? "text"   // (read only for the table's x in columns)
                    }
                } else if case let frames = unwrapped(node, "w:tr").flatMap({ unwrapped($0, "w:tc") }).flatMap({ unwrapped($0, "w:p") })
                            .map({ $0.first("w:pPr")?.first("w:framePr") }),
                          !frames.isEmpty, let frame = frames[0], frame["w:vAnchor"] == "text", frame["w:wrap"] == "notBeside",
                          Set(frames.map { $0.map { PptxXML.serialize($0) } ?? "" }).count == 1 {
                    // A table set in a frame — Word writes one by giving
                    // every paragraph of every cell the same w:framePr —
                    // stands where the frame says, as a floating table
                    // does: its y below the text's place, the text under
                    // it, and centred on the margin where it says so.
                    // zh-621d8756 p15's form (y 342) starts 17.1pt under
                    // "需要补正内容如下：" in Word's print; ours sat on it.
                    if frame["w:yAlign"] == nil, let v = Double(frame["w:y"] ?? ""), v > 0 { style.floatOffsetY = v / 20 }
                    if frame["w:xAlign"] == "center", frame["w:x"] == nil { style.alignment = .center }
                } else if case let frames = unwrapped(node, "w:tr").flatMap({ unwrapped($0, "w:tc") }).flatMap({ unwrapped($0, "w:p") })
                            .map({ $0.first("w:pPr")?.first("w:framePr") }),
                          !frames.isEmpty, let frame = frames[0], frame["w:vAnchor"] == "page", frame["w:hAnchor"] == "page",
                          frame["w:wrap"] == "notBeside", frame["w:yAlign"] == nil, frame["w:xAlign"] == nil,
                          let fx = Double(frame["w:x"] ?? ""), let fy = Double(frame["w:y"] ?? ""),
                          Set(frames.map { $0.map { PptxXML.serialize($0) } ?? "" }).count == 1 {
                    // (Set in a frame placed on the page, the same way:
                    // the ICS and CCS lines of a standard's cover, zh-cd8987db
                    // — x 68.6, y 28.4 from the page's edge in Word's print,
                    // where ours flowed from the margin.)
                    style.pageAnchored = true
                    style.pageOffsetY = fy / 20
                    style.floatX = fx / 20
                    style.floatXAnchor = "page"
                }
                // A spacing of ZERO is still a statement: Word then rules each
                // cell on its own rather than collapsing shared edges, and
                // every row of an HTML-converted table stands a border
                // taller (bug57031's SAS tables, 2.2% -> 0.3% with the
                // table's zero written back; the rows' own add nothing).
                if let sp = node.first("w:tblPr")?.first("w:tblCellSpacing"), (sp["w:type"] ?? "dxa") == "dxa",
                   let w = Double(sp["w:w"] ?? ""), w >= 0 {
                    style.cellSpacing = w / 20
                } else if let sp = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"].flatMap({ tableSpacings[$0] }) {
                    style.cellSpacing = sp
                }
                // The preferred width: HTML-converted tables say 100% and
                // their grid says less (bug65649's came back narrower).
                if let tw = node.first("w:tblPr")?.first("w:tblW"), let w = Double(tw["w:w"] ?? ""), w > 0 {
                    switch tw["w:type"] ?? "auto" {
                    case "pct": style.widthPercent = w / 50
                    case "dxa": if !staleTblW { style.width = w / 20 }
                    default: break
                    }
                }
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    if let h = tr.first("w:trPr")?.first("w:trHeight"), let v = Double(h["w:val"] ?? ""), v > 0 {
                        style.rowHeights[r] = v / 20
                        // An exact height stays exact: a comparison table of
                        // exact rows clips its cells, and at "at least" the
                        // copy ran 12 pages to the original's 9.
                        if h["w:hRule"] == "exact" { style.rowsExactHeight.insert(r) }
                    }
                    if let c = tr.first("w:trPr")?.first("w:cantSplit"), !_isOff(c) { style.rowsCantSplit.insert(r) }
                    // (A row's own cell spacing of none: zh-147bdae0's
                    // commitment tables state 0 and most of their rows
                    // nil, and those rows step a line apart in Word's print
                    // — 21.1pt a one-line row, ours 21.6, the 0.5pt line
                    // taken twice — where its first rows, 0 again, stand
                    // their lines in pairs.)
                    if style.cellSpacing != nil,
                       let sp = tr.first("w:trPr")?.first("w:tblCellSpacing") ?? tr.first("w:tblPrEx")?.first("w:tblCellSpacing"),
                       sp["w:type"] == "nil" {
                        style.rowsUnspaced.insert(r)
                    }
                    if let v = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? ""), v > 0 { style.rowsGridBefore[r] = v }
                    // Its cell spacing, borders and cell margins (the table's own
                    // and each cell's go back beside them).
                    if let ex = tr.first("w:tblPrEx") {
                        let kept = ["w:tblCellSpacing", "w:tblBorders", "w:shd", "w:tblCellMar"].compactMap { ex.first($0) }.map { PptxXML.serialize($0) }.joined()
                        if !kept.isEmpty { style.rowExceptions[r] = "<w:tblPrEx>" + kept + "</w:tblPrEx>" }
                    }
                }
                // Cells without a stated width autofit to their content.
                let widthless = cells.filter { c in
                    let w = c.first("w:tcPr")?.first("w:tcW")
                    return w == nil || w?["w:type"] == "auto"
                }.count
                if !cells.isEmpty, widthless * 2 > cells.count, !style.fixedLayout { style.autoCellWidths = true }
                // (A percentage-width table keeps the grid Word saved, which is Word's own fit; only an
                // equal-split grid, as Pandoc writes, says nothing: zh-6d402586 and lo-2c85bb1477d36796 hold theirs.)
                let gridCols = node.first("w:tblGrid")?.all("w:gridCol").compactMap { Double($0["w:w"] ?? "") } ?? []
                let equalGrid = gridCols.count > 1 && (gridCols.max() ?? 0) - (gridCols.min() ?? 0) <= 2
                if !cells.isEmpty, widthless == cells.count, style.width == nil, !style.fixedLayout, style.widthPercent == nil || equalGrid { style.contentFit = true }
                // (A gridless table 100% wide whose cells state no width is fitted to its content, the room wide: lab pctfit T1, T4,
                // T7, T10, T13, T15, T17 against Word's print. One whose cells all state twips takes those as a floor and is scaled: below.)
                if !cells.isEmpty, !style.contentFit, gridCols.isEmpty, style.widthPercent == 100, widthless == cells.count, !style.fixedLayout, RichTextTheme.wordWindowsPages { style.contentFit = true }
                if !cells.isEmpty, gridCols.isEmpty, style.widthPercent == 100, !style.fixedLayout, RichTextTheme.wordWindowsPages {
                    let rows = unwrapped(node, "w:tr")
                    let counts = Set(rows.map { unwrapped($0, "w:tc").count })
                    let plain = cells.allSatisfy { tc in
                        let pr = tc.first("w:tcPr")
                        return pr?.first("w:tcW")?["w:type"] == "dxa" && pr?.first("w:gridSpan") == nil && pr?.first("w:vMerge") == nil
                    }
                    if plain, counts.count == 1, rows.allSatisfy({ $0.first("w:trPr")?.first("w:gridBefore") == nil }) { style.twipScale = true }
                    // (Cells in twips and in a share, a column to each kind: the share's columns keep that share of the room, the others are scaled into the rest. sa2 be63fe36 table 7.)
                    if !plain, counts.count == 1, rows.allSatisfy({ $0.first("w:trPr")?.first("w:gridBefore") == nil }), let first = rows.first {
                        var stated: [Double] = [], shares: [Int: Double] = [:], ok = true
                        for (k, tc) in unwrapped(first, "w:tc").enumerated() {
                            let pr = tc.first("w:tcPr"), w = pr?.first("w:tcW")
                            guard pr?.first("w:gridSpan") == nil, pr?.first("w:vMerge") == nil, let v = Double(w?["w:w"] ?? ""), v > 0 else { ok = false; break }
                            if w?["w:type"] == "dxa" { stated.append(v / 20) } else if w?["w:type"] == "pct" { stated.append(0); shares[k] = v / 50 } else { ok = false; break }
                        }
                        if ok, !shares.isEmpty, shares.count < stated.count { style.twipScale = true; style.twipStated = stated; style.twipShares = shares }
                    }
                }
                // (A table of a width in twips over an equal-split grid is content-fitted too, to that width: lab atcol1.)
                if !cells.isEmpty, widthless == cells.count, style.width != nil, style.widthPercent == nil, equalGrid, !style.fixedLayout { style.contentFit = true }
                // (… and one whose stated cells are whole columns of one
                // width in twips, the rest auto: those columns keep their
                // width and the others are fitted — zh-72da925e's rain
                // tables, a 794-twip rank column beside six auto ones, are
                // 39.6/46.1/57.1/45.9/57.3/51.9/57.1pt in Word's print, the
                // year columns widened past a grid that parted "2001" / "年".)
                if !cells.isEmpty, !style.contentFit, widthless * 2 > cells.count, style.width == nil, style.widthPercent == nil, !style.fixedLayout {
                    var fixed: [Int: Double] = [:], auto = Set<Int>(), mixed = false
                    for tr in unwrapped(node, "w:tr") {
                        var col = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? "") ?? 0
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w == nil || w?["w:type"] == "auto" {
                                auto.formUnion(col ..< col + span)
                            } else if w?["w:type"] == "dxa", span == 1, let v = Double(w?["w:w"] ?? ""), v > 0, fixed[col].map({ $0 == v / 20 }) ?? true {
                                fixed[col] = v / 20
                            } else { mixed = true }
                            col += span
                        }
                    }
                    if !mixed, !fixed.isEmpty, auto.isDisjoint(with: fixed.keys) {
                        style.contentFit = true
                        style.contentFitFixed = fixed
                    }
                }
                // (… and one whose only stated widths are in its first row, every other cell auto: Word fits the
                // columns to their content and sets the header's widths aside — dx2 zh-4cac8c37's shop table, a grid of
                // 115/210/100/100pt, is 72/325/67/62pt in Word's print.)
                // (A spaced table's width does not stop it: lab tbauto t7, tblW 450pt over a first row of 150 / 300, is 84.2 / 350.7
                // inside, as t2 without the width is 83.1.)
                if !cells.isEmpty, !style.contentFit, widthless * 2 > cells.count, style.width == nil || (style.cellSpacing ?? 0) > 0, style.widthPercent == nil, !style.fixedLayout {
                    let rows = unwrapped(node, "w:tr")
                    func stated(_ tr: XNode) -> Bool { unwrapped(tr, "w:tc").contains { let w = $0.first("w:tcPr")?.first("w:tcW"); return !(w == nil || w?["w:type"] == "auto") } }
                    if rows.count > 2, stated(rows[0]), !rows.dropFirst().contains(where: stated) {
                        style.contentFit = true
                        var col = Int(rows[0].first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? "") ?? 0
                        for tc in unwrapped(rows[0], "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if span == 1, w?["w:type"] == "dxa", let v = Double(w?["w:w"] ?? ""), v > 0 { style.contentFitFloor[col] = v / 20 }
                            col += span
                        }
                    }
                }
                for tr in unwrapped(node, "w:tr") where !style.hasPctCells {
                    for tc in unwrapped(tr, "w:tc") where tc.first("w:tcPr")?.first("w:tcW")?["w:type"] == "pct" { style.hasPctCells = true; break }
                }
                // (A spaced table of a stated share whose cells state shares
                // of it, column by column: zh-045c5a75's article table,
                // 85% with cells of 12% and 2% and one auto.)
                // (A table of no stated width whose cells state shares adding to more than 100% is as wide as
                // the room, and cut down as a 100% one: dx2 8afcc2c4's price tables, two 5000-pct cells over
                // an auto width, the price column at its narrowest in Word's print.)
                let autoWidthShares = style.widthPercent == nil && style.width == nil && RichTextTheme.wordWindowsPages
                if style.widthPercent != nil || autoWidthShares, !style.fixedLayout {
                    var shares: [Int: Double] = [:], noWrap = Set<Int>(), mixed = false
                    for tr in unwrapped(node, "w:tr") {
                        var col = Int(tr.first("w:trPr")?.first("w:gridBefore")?["w:val"] ?? "") ?? 0
                        for tc in unwrapped(tr, "w:tc") {
                            let span = max(1, Int(tc.first("w:tcPr")?.first("w:gridSpan")?["w:val"] ?? "") ?? 1)
                            let w = tc.first("w:tcPr")?.first("w:tcW")
                            if w?["w:type"] == "pct", span == 1, let v = Double((w?["w:w"] ?? "").replacingAll("%", with: "")) {
                                let share = (w?["w:w"] ?? "").hasSuffix("%") ? v : v / 50
                                if let had = shares[col], abs(had - share) > 0.01 { mixed = true }
                                shares[col] = share
                                if _on(tc.first("w:tcPr")?.first("w:noWrap")) { noWrap.insert(col) }
                            } else if span > 1, w?["w:type"] == "pct", (style.cellSpacing ?? 0) == 0 {
                                // (A cell across columns says nothing of any one.)
                            } else if w != nil, w?["w:type"] != "auto" { mixed = true }
                            col += span
                        }
                    }
                    // (A table of no cell spacing keeps its shares only: its no-wrap columns are the layout's
                    // wrap rule for spaced tables (`noWrapColumns`), and eleven documents' unspaced pct
                    // tables moved when they were set on those too.)
                    if autoWidthShares, !(shares.values.reduce(0, +) > 100.5) { mixed = true }
                    if !mixed, !shares.isEmpty {
                        if autoWidthShares { style.widthPercent = 100 }
                        style.columnPercents = shares
                        if (style.cellSpacing ?? 0) > 0 || (shares.values.reduce(0, +) > 100.5) { style.noWrapColumns = noWrap }
                    }
                }
                if tableStyleIds[id] != nil {
                    if node.first("w:tblPr")?.first("w:tblBorders") == nil { style.inheritedBordersKey = style.bordersKey }
                    if node.first("w:tblPr")?.first("w:tblCellMar") == nil { style.inheritedMarginsKey = style.marginsKey }
                }
                if style != TableStyle() { tableStyles[id] = style }
                // vMerge: "restart" opens a span in a column; a bare vMerge
                // continues it, and that cell's (empty) content is dropped.
                var openSpan: [Int: Range<Int>] = [:]   // column → the spanning cell's paragraphs
                let rowCount = unwrapped(node, "w:tr").count
                let gridCount = tableColumns[id]?.count ?? Int.max
                // (A cell merged down into a row sets that row's top and
                // bottom margins where its own are the larger: lab `rgap`
                // (Word for Windows, zh-147bdae0's p19 table alone) — row 2's
                // continued "其他參與人員" states no margins and takes the
                // table's 108 twips above and below, every other cell says 0,
                // and Word sets the row's text 5.4pt lower and the row 5.4pt
                // deeper; with the continued cell's margins 0, or the
                // table's, it does not. Ours set the row as its own cells say.)
                let tableStart = paragraphs.count
                var continuedMargins: [Int: (top: Double, bottom: Double)] = [:]
                // (A cell merged down takes the largest top margin of its first row and the largest bottom margin of its
                // last, as its own: sa2 be63fe36's signature picture, 75pt over two rows whose text cells say 225 twips
                // above and below, is 98pt of rows (75 + 11.25 + 11.25 + rules) in Word's print, ours 87.)
                var rowMaxMargins: [Int: (top: Double, bottom: Double)] = [:]
                if RichTextTheme.wordWindowsPages {
                    for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                        for tc in unwrapped(tr, "w:tc") where tc.first("w:tcPr")?.first("w:tcMar") != nil {
                            let m = _cellMargins(tc.first("w:tcPr"), "w:tcMar").under(margins)
                            let was = rowMaxMargins[r] ?? (0, 0)
                            rowMaxMargins[r] = (max(was.top, m.top ?? 0), max(was.bottom, m.bottom ?? 0))
                        }
                    }
                }
                for (r, tr) in unwrapped(node, "w:tr").enumerated() {
                    // (A row's cells start after the grid columns it leaves
                    // empty: zh-51af781b's scoring table switches from a
                    // first cell spanning 5 + 840 twips to gridBefore 1 and
                    // an 840 cell at row 165, and ours set each number in
                    // the 5-twip column a character a line and each
                    // description in the number's — 70 pages to Word's 65.)
                    var column = style.rowsGridBefore[r] ?? 0
                    for tc in unwrapped(tr, "w:tc") {
                        let tcPr = tc.first("w:tcPr")
                        let span = max(1, Int(tcPr?.first("w:gridSpan")?["w:val"] ?? "1") ?? 1)
                        var restart = false
                        if let v = tcPr?.first("w:vMerge") {
                            if v["w:val"] == "restart" {
                                restart = true
                            } else if let range = openSpan[column], range.upperBound <= paragraphs.count {
                                // Every paragraph of the cell carries the span,
                                // and this row's own stated sides.
                                var contEdges = _edges(tcPr, "w:tcBorders")
                                contEdges?.insideH = nil; contEdges?.insideV = nil
                                let contXML = tcPr?.first("w:tcBorders").map { PptxXML.serialize($0) }
                                // Its own (empty) paragraphs, as written — when
                                // that is all it holds and they name no part.
                                let blocks = tc.children.filter { $0.name != "w:tcPr" }
                                var contContent: String? = nil
                                if !blocks.isEmpty, blocks.allSatisfy({ $0.name == "w:p" }) {
                                    let xml = blocks.map { PptxXML.serialize($0) }.joined()
                                    if !xml.containsSubstring(" r:") && !xml.containsSubstring("<w:drawing") && !xml.containsSubstring("<w:pict") { contContent = xml }
                                }
                                // … and read, for the height they ask of a row
                                // that has no cell of its own (`RichLayout`).
                                var contParagraphs: [RichParagraph] = []
                                if contContent != nil {
                                    for block in blocks where block.first("w:pPr")?.first("w:numPr") == nil {
                                        // (A merged-down cell's hidden paragraphs are sized by the document's
                                        // paragraph defaults, not the table style's spacing: sa2 f70e17f6's
                                        // TableGrid says after 0 / single, Word's rows 6-8 stand 8pt taller on the
                                        // defaults' after 8 / 1.08.)
                                        contParagraphs += _paragraphs(block, normalStyleId.flatMap { chainOver($0, outerBase, docBase) } ?? outerBase, styleByDocx, styleNums, sheet, kindByNum, rels, media, indent, notes, cellChar,
                                                                      { id in chainOver(id, outerBase, docBase) }).map(\.paragraph)
                                    }
                                }
                                // (Its margins, as an own cell's are read below.)
                                let m = tcPr?.first("w:tcMar") != nil ? _cellMargins(tcPr, "w:tcMar").under(margins)
                                    : !cellMars.isEmpty && (cellMar.top != nil || cellMar.left != nil || cellMar.bottom != nil || cellMar.right != nil)
                                    ? _cellMargins(tr.first("w:tblPrEx")).under(_cellMargins(node.first("w:tblPr"))).under(styled).under(defaultMargins).under(_Margins.word)
                                    : _cellMargins(tr.first("w:tblPrEx")).under(margins)
                                let was = continuedMargins[r] ?? (0, 0)
                                continuedMargins[r] = (max(was.top, m.top ?? 0), max(was.bottom, m.bottom ?? 0))
                                for k in range {
                                    paragraphs[k].cell?.rowSpan += 1
                                    paragraphs[k].cell?.continuationEdges.append(contEdges)
                                    paragraphs[k].cell?.continuationBordersXML.append(contXML)
                                    paragraphs[k].cell?.continuationShdXML.append(tcPr?.first("w:shd").map { PptxXML.serialize($0) })
                                    paragraphs[k].cell?.continuationContentXML.append(contContent)
                                    paragraphs[k].cell?.continuationParagraphs.append(contParagraphs)
                                    paragraphs[k].cell?.continuationHidden.append(tcPr?.first("w:hideMark") != nil)
                                }
                                column += span
                                continue
                            }
                        } else {
                            openSpan[column] = nil
                        }
                        // The cell's own shading: a fill colour, not "auto".
                        var fill: Color? = nil
                        if let shd = tcPr?.first("w:shd"), let hex = shd["w:fill"], hex.count == 6,
                           let v = UInt32(hex, radix: 16) {
                            fill = Color(0xFF00_0000 | Int64(v))
                        }
                        var fromStyle = false
                        if fill == nil {
                            fill = TableCondFills(byType: cond.fills, rowBandSize: cond.rowBandSize ?? 0, colBandSize: cond.colBandSize ?? 0).fill(look: lookBits, row: r, column: column, lastRow: r == rowCount - 1, lastColumn: column + span >= gridCount)
                            fromStyle = fill != nil && tableStyleIds[id] != nil
                        }
                        // The cell's own borders, when they differ from the
                        // table's verdict: nil sides inside a ruled table.
                        // The cell's own sides, where they differ from what
                        // the table gives that position (an outer side on
                        // the rim, an inside one elsewhere).
                        // (A row's own borders — `w:tblPrEx` — stand for its
                        // cells' unstated sides: form_footnotes' last table
                        // rules nothing inside, its rows rule every line
                        // between them, and its rows stood a rule short.)
                        var rowSides: XNode? = nil
                        if let rex = tr.first("w:tblPrEx")?.first("w:tblBorders") {
                            let lastRowHere = r == rowCount - 1, lastColHere = column + span >= gridCount
                            let said = tcPr?.first("w:tcBorders")
                            let made = XNode(name: "w:tcBorders", attrs: [:])
                            for (side, from) in [("top", r == 0 ? "top" : "insideH"), ("left", column == 0 ? "left" : "insideV"),
                                                 ("bottom", lastRowHere ? "bottom" : "insideH"), ("right", lastColHere ? "right" : "insideV")] {
                                guard said?.first("w:" + side) == nil, let e = rex.first("w:" + from) else { continue }
                                made.children.append(XNode(name: "w:" + side, attrs: e.attrs))
                            }
                            if !made.children.isEmpty { rowSides = made }
                        }
                        // (The header row's own lines from the table style's
                        // `firstRow`, where the cell states none: zh-61aaad09's
                        // "浅色网格" header rules its foot 2.25pt, drawn so in
                        // Word's print and the two rows either side of it each
                        // half that taller; ours drew 1pt and stood 1.2 short.
                        // Not the foot of a cell merged on down: Word ends the
                        // merged "销售方式" cell on the inside line.)
                        if r == 0, firstRowOn, let hb = cond.headerBorders {
                            let said = tcPr?.first("w:tcBorders")
                            let mergesOn = tcPr?.first("w:vMerge")?["w:val"] == "restart"
                            let made = rowSides ?? XNode(name: "w:tcBorders", attrs: [:])
                            for side in ["top", "left", "bottom", "right"] where !(side == "bottom" && mergesOn) {
                                guard said?.first("w:" + side) == nil, made.first("w:" + side) == nil, let e = hb.first("w:" + side) else { continue }
                                // A rule with no w:sz: Word prints a hairline
                                // and the row does not grow (463426 page 8).
                                if e["w:sz"] == nil, e["w:val"] != "nil", e["w:val"] != "none" { continue }
                                made.children.append(XNode(name: "w:" + side, attrs: e.attrs))
                            }
                            if !made.children.isEmpty { rowSides = made }
                        }
                        let sidesPr: XNode? = {
                            guard let rowSides else { return tcPr }
                            let merged = XNode(name: "w:tcBorders", attrs: [:])
                            merged.children = (tcPr?.first("w:tcBorders")?.children ?? []) + rowSides.children
                            let pr = XNode(name: "w:tcPr", attrs: [:])
                            pr.children = [merged]
                            return pr
                        }()
                        var ownEdges: BorderEdges? = nil
                        if var own = _edges(sidesPr, "w:tcBorders") {
                            // A cell's "none" on the table's outer top or bottom does not
                            // take away the rule the table's style draws there: Word's print
                            // of sa2 fee2a9e5 (Light Shading, every cell "none" on all four
                            // sides in the header row) rules the table 1pt top and bottom.
                            if RichTextTheme.wordWindowsPages, !style.bordersFromCells, style.borders,
                               node.first("w:tblPr")?.first("w:tblStyle") != nil, node.first("w:tblPr")?.first("w:tblBorders") == nil {
                                let te = style.edges ?? BorderEdges()
                                // (Only a "none": a cell's "nil" is no rule at all. sa1 9881dc01's first rows say `w:top w:val="nil"` under
                                // Table Grid, and Word's print has their text 0.58pt higher than the table's top rule would leave it.)
                                let nilSide = { (n: String) in sidesPr?.first("w:tcBorders")?.first(n)?["w:val"] == "nil" }
                                if r == 0, own.top == false, te.top ?? style.borders, !nilSide("w:top") { own.top = nil }
                                if r == rowCount - 1, own.bottom == false, te.bottom ?? style.borders, !nilSide("w:bottom") { own.bottom = nil }
                            }
                            own.insideH = nil; own.insideV = nil
                            if style.bordersFromCells {
                                // Every stated side stays: the writer puts
                                // no table-level borders under them.
                                ownEdges = own
                            } else {
                            let te = style.edges ?? BorderEdges()
                            let lastRow = r == rowCount - 1, lastCol = column + span >= gridCount
                            // A cell ruled at its own width keeps the sides it
                            // draws even where the table draws them too — the
                            // width is the difference (form_footnotes' heading
                            // cell: 2.25pt over the table's 1.5pt).
                            let ownWidth = _borders(tcPr, "w:tcBorders")?.width
                            let wider = ownWidth != nil && ownWidth != (style.borderWidth ?? 0.5)
                            if wider {
                                if own.top == false, own.top == (r == 0 ? te.top : te.insideH) ?? style.borders { own.top = nil }
                                if own.left == false, own.left == (column == 0 ? te.left : te.insideV) ?? style.borders { own.left = nil }
                                if own.bottom == false, own.bottom == (lastRow ? te.bottom : te.insideH) ?? style.borders { own.bottom = nil }
                                if own.right == false, own.right == (lastCol ? te.right : te.insideV) ?? style.borders { own.right = nil }
                            } else {
                            if own.top == (r == 0 ? te.top : te.insideH) ?? style.borders { own.top = nil }
                            if own.left == (column == 0 ? te.left : te.insideV) ?? style.borders { own.left = nil }
                            if own.bottom == (lastRow ? te.bottom : te.insideH) ?? style.borders { own.bottom = nil }
                            if own.right == (lastCol ? te.right : te.insideV) ?? style.borders { own.right = nil }
                            }
                            if !own.isEmpty { ownEdges = own }
                            }
                        }
                        // (A cell with no vAlign of its own takes its table style's: jpn-z22306877-1047a4's Table1.)
                        let vAlign = tcPr?.first("w:vAlign")?["w:val"].flatMap { ["center", "bottom"].contains($0) ? $0 : nil } ?? (tcPr?.first("w:vAlign") == nil ? ((r == 0 && firstRowOn ? cond.headerVAlign : nil) ?? cond.cellVAlign) : nil)
                        currentCell = CellRef(table: id, row: r, column: column, span: span, fill: fill, edges: ownEdges, verticalAlign: vAlign)
                        if fromStyle { currentCell?.styleFilled = true }
                        if let shd = tcPr?.first("w:shd"), shd["w:fill"] == nil || shd["w:fill"]?.lowercased() == "auto", fill == nil { currentCell?.fillNoneXML = PptxXML.serialize(shd) }
                        if let shd = tcPr?.first("w:shd"), shd["w:fill"]?.count == 6, shd["w:themeFill"] != nil {
                            currentCell?.fillThemeAttrs = ["w:themeFill", "w:themeFillTint", "w:themeFillShade"].compactMap { k in shd[k].map { " \(k)=\"\(_esc($0))\"" } }.joined()
                        }
                        // (The foot of a merged header cell is no drawn line, yet it takes its room where the span ends: lab sa1f9, Word's merged rows stand 0.96 taller than their stated sum.)
                        if r == 0, firstRowOn, tcPr?.first("w:vMerge")?["w:val"] == "restart", let e = cond.headerBorders?.first("w:bottom") ?? styledSides?.first("w:insideH"),
                           let sz = Double(e["w:sz"] ?? ""), tcPr?.first("w:tcBorders")?.first("w:bottom") == nil {
                            currentCell?.spanFootStyle = e["w:val"] ?? "single"; currentCell?.spanFootWidth = sz / 8
                        }
                        rowExcepted = tr.first("w:tblPrEx")?.first("w:tblCellMar") != nil
                        if let rev = tcPr?.first("w:cellDel") ?? tcPr?.first("w:cellIns") {
                            currentCell?.revision = RevisionMark(kind: rev.name == "w:cellIns" ? .inserted : .deleted, author: rev["w:author"] ?? "",
                                                                 date: rev["w:date"] ?? "", moved: false)
                        }
                        currentCell?.bordersXML = tcPr?.first("w:tcBorders").map { PptxXML.serialize($0) }
                        // A side the cell rules at a width of its own is drawn
                        // at that width, in its colour (auto is black):
                        // zh-cec9d337's outer frame is 2.25pt over the
                        // table's 0.5pt, stated by its rows' `w:tblPrEx`.
                        if RichTextTheme.wordWindowsPages, let tb = sidesPr?.first("w:tcBorders") {
                            func own(_ names: [String]) -> CellRef.CellLine? {
                                for n in names {
                                    guard let e = tb.first(n), !["nil", "none"].contains(e["w:val"] ?? "nil"), let sz = Double(e["w:sz"] ?? "") else { continue }
                                    let width = max(0.25, sz / 8)
                                    // (A table whose width came from its cells' own lines draws each cell's side as it states it:
                                    // lo-c657ba7d's rows say 4.5pt navy on some sides and 1pt on others, the table's width the
                                    // 4.5 they mostly name, so those sides were left to the table's edges and drew nothing;
                                    // Word's print has the heavy rules between the rows.)
                                    var color = Color(0xFF000000)
                                    if let hex = e["w:color"], hex.lowercased() != "auto", hex.count == 6, let v = Int(hex, radix: 16) {
                                        color = Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
                                    }
                                    // (A side at the table's own width but in a colour of its own, white over the table's black, is drawn in that colour:
                                    // xd e86e26f7's cell rules are FFFFFF at the table's width, drawn white in Word's print, black here.)
                                    let recoloured = color != (style.borderColor ?? Color(0xFF000000))
                                    guard (e["w:val"] ?? "single") == "single", width != (style.borderWidth ?? 0.5) || (style.bordersFromCells && width > 1) || recoloured else { return nil }
                                    return CellRef.CellLine(width: width, color: color)
                                }
                                return nil
                            }
                            currentCell?.borders.top = own(["w:top"])
                            currentCell?.borders.left = own(["w:left", "w:start"])
                            currentCell?.borders.bottom = own(["w:bottom"])
                            currentCell?.borders.right = own(["w:right", "w:end"])
                        }
                        currentCell?.rowBordersXML = rowSides.map { PptxXML.serialize($0) }
                        currentCell?.marginsXML = tcPr?.first("w:tcMar").map { PptxXML.serialize($0) }
                        // (Its own margins, over the table's: zh-6cd1befe's
                        // list of emergency departments narrows its cells'
                        // margins to 51 twips where the table says 108, and
                        // "生物灾害指因病" at 10pt fills its 70.5pt line in
                        // Word's print; at the table's margins ours held six.)
                        if tcPr?.first("w:tcMar") != nil {
                            let m = _cellMargins(tcPr, "w:tcMar").under(margins)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        } else if !cellMars.isEmpty, cellMar.top != nil || cellMar.left != nil || cellMar.bottom != nil || cellMar.right != nil {
                            // (And one that states none, where the table's
                            // margins were taken from what most cells say,
                            // has the table's own: drawing.docx's article
                            // rows zero their cells' margins but one, whose
                            // 5.25pt above and below the table's 105 twips
                            // give — its articles stood 5pt high of Word's.)
                            // (Its row's own exception first: the logo row
                            // above them zeroes its margins in `w:tblPrEx`.)
                            let m = _cellMargins(tr.first("w:tblPrEx")).under(_cellMargins(node.first("w:tblPr")))
                                .under(styled).under(defaultMargins).under(_Margins.word)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        } else if case let ex = _cellMargins(tr.first("w:tblPrEx")), ex.top != nil || ex.left != nil || ex.bottom != nil || ex.right != nil {
                            // (A row's own margins — `w:tblPrEx` — over the
                            // table's, for a cell that states none: zh-64044a1d's
                            // task tables say 28 twips a side and every row 108,
                            // and Word's print sets the duty column's text 5.4pt
                            // in, where ours at 1.4 held a character more a line.)
                            let m = ex.under(margins)
                            currentCell?.padding = EdgeInsets(left: m.left ?? 5.4, top: m.top ?? 0, right: m.right ?? 5.4, bottom: m.bottom ?? 0)
                        }
                        let keptCell = ["w:noWrap", "w:tcFitText", "w:hideMark"].compactMap { tcPr?.first($0) }.map { PptxXML.serialize($0) }.joined()
                        currentCell?.keptPropertiesXML = keptCell.isEmpty ? nil : keptCell
                        if let grid = tableColumns[id], column + span <= grid.count {
                            currentCell?.widthXML = tcPr?.first("w:tcW").map { PptxXML.serialize($0) }
                            currentCell?.widthKeptUnder = grid[column ..< column + span].map { Int(($0 * 20).rounded()) }.reduce(0, +)
                        }
                        currentCell?.bordersKeptUnder = style.borders
                        // The cell's own line width, over the table's.
                        if let w = _borders(tcPr, "w:tcBorders")?.width, w != (style.borderWidth ?? 0.5) { currentCell?.borderWidth = w }
                        // Text turned a quarter (Word's w:textDirection);
                        // its vertical writing keeps ideographs upright.
                        let direction = tcPr?.first("w:textDirection")?["w:val"]
                        switch direction {
                        case "tbRl", "tbRlV", "tbLrV":
                            currentCell?.textDirection = .down
                            currentCell?.uprightIdeographs = true
                        // (The strict spelling "lr" turns the text up in Word's
                        // print — LibreOffice's tdf79272_strictDxa: "USA" in a
                        // 34.55pt column runs bottom to top, where ours set it
                        // flat and made the column 41pt.)
                        case "btLr", "lr": currentCell?.textDirection = .up
                        default: break
                        }
                        // (lrTbV is a horizontal cell — its text runs left to
                        // right as any, only East Asian characters turned
                        // where a vertical layout would stand them: zh-e0ca7252's
                        // equipment list, every cell lrTbV, has rows of a
                        // 12pt line in Word's print, where ours turned them
                        // and its 29 empty rows were 4pt apiece. Kept, so the
                        // save writes it back.)
                        if direction != nil, currentCell?.textDirection != .horizontal || direction == "lrTbV" { currentCell?.textDirectionValue = direction }
                        cellChar = r == 0 && firstRowOn ? (cond.headerChar ?? CharStyle())
                            : (lookBits & 0x40 != 0 && r == rowCount - 1 && cond.lastRowChar != nil ? cond.lastRowChar!
                            : (column == 0 && firstColOn ? (cond.firstColChar ?? CharStyle())
                            : (lookBits & 0x100 != 0 && column + span >= gridCount ? (cond.lastColChar ?? CharStyle()) : CharStyle())))
                        // (Normal's own face stands over a conditional part's too: a replaced Normal
                        // in Cambria, table style firstRow Arial, prints Cambria in Word.)
                        for (name, k) in _tableCharKeys where normalStatedChar[keyPath: k] != nil || (name == "hAnsi" && normalStatedChar.fontFamily != nil) { cellChar[keyPath: k] = nil }
                        if let sid = node.first("w:tblPr")?.first("w:tblStyle")?["w:val"] {
                            if r == 0, firstRowOn, let hb = headerBases[sid], let hr = headerRootBases[sid] { cellBase = hb; cellRootBase = hr }
                            else if let tb = tableBases[sid], let tr = tableRootBases[sid] { cellBase = tb; cellRootBase = tr }
                        }
                        notes.cellSizeFromTable = false
                        if cellChar.fontSize == nil, !normalStatesSize, let size = tableStyleSize { cellChar.fontSize = size; notes.cellSizeFromTable = true }
                        notes.cellCharFromTable = tableStyleChar.map { _takeTableChar(&cellChar, $0, normal: normalStatedChar) } ?? []
                        let before = paragraphs.count
                        for child in tc.children { walkBlock(child, indent: indent, depth: depth + 1) }
                        if paragraphs.count == before { emit(RichParagraph(style: cellBase)) }
                        else { flagMarkUnderNestedTable(tc, since: before) }
                        if restart { openSpan[column] = before ..< paragraphs.count }
                        column += span
                    }
                }
                // (A merged cell's own foot is in its last row, and that
                // row's margin is its own continuation's: zh-147bdae0's
                // centred "其他參與人員" stands 2.7pt higher in Word's print,
                // half the 5.4 its continued part takes off below.)
                for k in tableStart ..< paragraphs.count {
                    guard let cell = paragraphs[k].cell, cell.table == id else { continue }
                    if let t = continuedMargins[cell.row]?.top, t > 0 { paragraphs[k].cell?.rowMarginTop = t }
                    if let b = continuedMargins[cell.row + max(1, cell.rowSpan) - 1]?.bottom, b > 0 { paragraphs[k].cell?.rowMarginBottom = b }
                    if cell.rowSpan > 1 {
                        if let t = rowMaxMargins[cell.row]?.top, t > (paragraphs[k].cell?.rowMarginTop ?? 0) { paragraphs[k].cell?.rowMarginTop = t }
                        if let b = rowMaxMargins[cell.row + cell.rowSpan - 1]?.bottom, b > (paragraphs[k].cell?.rowMarginBottom ?? 0) { paragraphs[k].cell?.rowMarginBottom = b }
                    }
                }
                currentCell = nil
                cellChar = CharStyle()
            case "w:sdt":
                if let content = node.first("w:sdtContent") {
                    // A control over whole paragraphs keeps its properties (W-RV-3): start on the first paragraph
                    // it yields, end on the last.
                    let first = paragraphs.count
                    for child in content.children { walkBlock(child, indent: indent) }
                    if paragraphs.count > first, let pr = node.first("w:sdtPr"), let kept = Self._keptFragment(pr, notes) {
                        notes.controlCount += 1
                        let id = notes.controlCount
                        let kids = content.children.filter { ["w:p", "w:tbl", "w:sdt"].contains($0.name) }
                        paragraphs[first].blockControlsBefore.insert(
                            RichBlockControl(id: id, properties: kept.xml, aroundTable: kids.first?.name == "w:tbl"), at: 0)
                        paragraphs[paragraphs.count - 1].blockControlsAfter.append(
                            RichBlockControl(id: id, aroundTable: kids.last?.name == "w:tbl"))
                    }
                }
            case "w:bookmarkStart":
                if let name = node["w:name"], name != "_GoBack" {
                    notes.pendingBookmarks.append(name)
                    if let id = node["w:id"] { notes.pendingBookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: 0)) }
                }
            case "w:bookmarkEnd":
                if let id = node["w:id"] {
                    if notes.pendingBookmarkMarkers.contains(where: { $0.id == id }) {
                        notes.pendingBookmarkMarkers.append(RichBookmarkMarker(id: id, offset: 0))
                    } else if !paragraphs.isEmpty {
                        let i = paragraphs.count - 1
                        paragraphs[i].bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: paragraphs[i].length))
                    }
                }
            case "w:commentRangeStart":
                // A range may open or close between paragraphs
                // (WordWithAttachments), not only inside one.
                if notes.kept["word/comments.xml"] != nil, let id = node["w:id"] { notes.openComments.append(id); notes.seenComments.insert(id) }
            case "w:commentRangeEnd":
                if let id = node["w:id"] { notes.openComments.removeAll { $0 == id } }
            case "w:sectPr":
                // (A body-level section with no properties at all, after one that has them, does not reset the page:
                // sa2 be63fe36 opens its body with a full sectPr (margins 1400/600, headers) and ends with an empty one;
                // Word prints the first's margins, we took the empty one's 1-inch defaults.)
                if node.children.isEmpty, pageSetup != nil { RuleTrace.hit("empty-body-sectpr-keeps-earlier-page-setup"); break }
                pageSetup = _pageSetup(node, notes, normalSize: sheet[RichNamedStyle.normalId]?.char.fontSize ?? 11)
            case "w:altChunk":
                // An HTML chunk, as Word imports it: paragraphs of the markup's
                // text in Times New Roman 12, 14pt of auto spacing either side
                // (lo alt-chunk-html: "HTML AltChunk" 13.3pt tall, 31.4 under the
                // line before it and 27.4 over the line after, in Word's print).
                if let id = node["r:id"], let rel = notes.rels[id], !rel.external,
                   ["html", "htm", "xhtml"].contains(rel.target.split(separator: ".").last.map { $0.lowercased() } ?? ""),
                   let data = part(_resolvePath("word", rel.target)) {
                    RuleTrace.hit("html-alt-chunk-is-paragraphs")
                    for text in Self._htmlParagraphs(String(decoding: data, as: UTF8.self)) {
                        let run = XNode(name: "w:r", attrs: [:])
                        let rPr = XNode(name: "w:rPr", attrs: [:])
                        rPr.children = [XNode(name: "w:rFonts", attrs: ["w:ascii": "Times New Roman", "w:hAnsi": "Times New Roman", "w:cs": "Times New Roman"]),
                                        XNode(name: "w:sz", attrs: ["w:val": "24"])]
                        let t = XNode(name: "w:t", attrs: ["xml:space": "preserve"])
                        t.text = text
                        run.children = [rPr, t]
                        let pPr = XNode(name: "w:pPr", attrs: [:])
                        pPr.children = [XNode(name: "w:spacing", attrs: ["w:before": "280", "w:after": "280"])]
                        let para = XNode(name: "w:p", attrs: [:])
                        para.children = [pPr, run]
                        walkBlock(para, indent: indent, depth: depth)
                    }
                }
            default:
                break
            }
        }
        for child in body.children { walkBlock(child, indent: 0) }
        recordingBody = false
        // A section of columns that a continuous section follows on the
        // same page, its columns filled by column breaks, is set as a row
        // of a borderless table: one cell a column, the columns' gaps
        // between them — the layout has one column count for the whole
        // document. zh-a0e932c2's "12 | 大肠菌群 | GB 4789.3 大肠菌群
        // 平板计数法" row of three unequal columns had taken a page a
        // column. The section's end stays a top-level paragraph of its
        // own, empty (it takes no room), so the sections count as they
        // did; the markup is kept for the save (`KeptTable`, id "kc…").
        do {
            var out: [RichParagraph] = []
            out.reserveCapacity(paragraphs.count + 8)
            var start = 0
            // (The document's own last section too, where it follows others
            // on their page: zh-8f9b19f4 ends in a continuous section of
            // three columns, "填报人：" | "审核人：" | "负责人：", which Word
            // prints as one line and ours as a page each.)
            let finalSect = body.first("w:sectPr")
            let finalColumns = finalSect.flatMap { sect -> String? in
                guard sect.first("w:type")?["w:val"] == "continuous" else { return nil }
                return PptxXML.serialize(sect)
            }
            let finalPage = finalSect.flatMap { _pageSetup($0, normalSize: sheet[RichNamedStyle.normalId]?.char.fontSize ?? 11) }
            for (i, para) in paragraphs.enumerated() {
                out.append(para)
                let final = para.style.sectionXML == nil && i == paragraphs.count - 1 && start > 0 && finalColumns != nil
                guard para.cell == nil, para.style.sectionXML != nil || final else { continue }
                defer { start = i + 1 }
                // (… or one that follows another on its page itself, a
                // page starting after it: zh-b8de3ae2's "資料來源" | " ",
                // a column break into a second column of 422pt before a
                // section of its own page, has the space in the second
                // column at the note's height in Word's print, where ours
                // took the break for a page — a blank page, every page
                // after it one late.)
                let opensOnItsPage = start > 0 && para.style.sectionXML.flatMap { XNode.parse(Data($0.utf8)) }?
                    .descendant("w:type")?["w:val"] == "continuous"
                guard !RichTextTheme.sectionColumnsFlow, para.style.sectionBreaksPage == false || final || opensOnItsPage, let sx = para.style.sectionXML ?? finalColumns,
                      let gaps = _sectionColumns(sx, final ? finalPage : para.style.sectionPage), gaps.count > 1,
                      paragraphs[start ... i].allSatisfy({ $0.cell == nil }) else { continue }
                var columns: [[RichParagraph]] = [[]]
                for k in start ... i {
                    var q = paragraphs[k]
                    if k > start, q.style.columnBreak, q.style.pageBreakBefore {
                        // (A paragraph that is only the break opens the next
                        // column with its line, where a page's would stay on
                        // the page before: zh-6cd1befe's "附件3" | (break) |
                        // "应急保障职责部门任务分配表" has the break's empty
                        // line at the second column's head in Word's print,
                        // the title under it, 20.7pt lower than ours.)
                        var carried: RichParagraph? = nil
                        // (When the paragraph opening the column is that empty
                        // line itself — the reader keeps the break's mark as a
                        // paragraph of its own — the one before it is only
                        // taken out of the first column, not carried on: set
                        // twice, the title stood 26pt low in zh-6cd1befe, and
                        // left in the first column its line ran zh-8f9b19f4's
                        // section 8pt long.)
                        let opensWithItsMark = q.text.isEmpty && q.image == nil && notes.columnMarksFollow
                        if q.style.breakEndsPrevious, let prev = columns[columns.count - 1].last, prev.text.isEmpty, prev.image == nil,
                           columns[columns.count - 1].count > 1 {
                            let taken = columns[columns.count - 1].removeLast()
                            if !opensWithItsMark { carried = taken }
                        }
                        columns.append(carried.map { [$0] } ?? [])
                        q.style.pageBreakBefore = false
                        q.style.columnBreak = false
                        q.style.breakEndsPrevious = false
                        q.style.breakRunPropertiesXML = nil
                    }
                    columns[columns.count - 1].append(q)
                }
                guard columns.count == gaps.count, (start ... i).allSatisfy({ bodyNodes[$0] != nil }) else { continue }
                // (Only where every paragraph's markup can be kept for the save:
                // one that names a part the package does not hold — LibreOffice's
                // tdf123163-1 has a picture with no media in it — has none, and
                // was left out of the kept markup, text and all.)
                var captured = Set<ObjectIdentifier>()
                guard (start ... i).allSatisfy({ k in
                    let node = bodyNodes[k]!
                    return !captured.insert(ObjectIdentifier(node)).inserted || _keptFragment(node, notes) != nil
                }) else { continue }
                out.removeLast(i - start + 1)
                tableCount += 1
                let id = "t\(tableCount)"
                keptTableCount += 1
                let kid = "kc\(keptTableCount)"
                var widths: [Double] = []
                let firstOut = out.count
                // (The section's end: its text in the cell, its break
                // after the table — and an empty one not in the cell at
                // all, as it takes no room in Word: zh-a0e932c2's put a
                // line under "法" and the table after the row 12pt low.)
                if let last = columns[columns.count - 1].last, last.text.isEmpty, last.image == nil, columns[columns.count - 1].count > 1 {
                    columns[columns.count - 1].removeLast()
                }
                for (c, column) in columns.enumerated() {
                    for var q in column {
                        q.style.sectionXML = nil; q.style.sectionRels = []; q.style.sectionPage = nil; q.style.sectionBreaksPage = nil
                        q.cell = CellRef(table: id, row: 0, column: c * 2)
                        out.append(q)
                    }
                    widths.append(gaps[c].width)
                    if c < columns.count - 1 {
                        var gap = RichParagraph(style: column.last?.style ?? RichParagraphStyle())
                        gap.style.sectionXML = nil; gap.style.sectionPage = nil; gap.style.sectionBreaksPage = nil
                        // (None of its indents: in the narrow gap a column's
                        // last paragraph's 56pt indent widened the gap, and
                        // zh-a0e932c2's second column stood 16pt right.)
                        gap.style.indentLeft = 0; gap.style.indentRight = 0; gap.style.firstLineIndent = 0
                        for key in ["w:leftChars", "w:startChars", "w:rightChars", "w:endChars", "w:hangingChars", "w:firstLineChars"] { gap.style.eastAsian[key] = nil }
                        gap.cell = CellRef(table: id, row: 0, column: c * 2 + 1)
                        out.append(gap)
                        widths.append(gaps[c].space)
                    }
                }
                if !final {
                    var mark = RichParagraph(style: para.style)
                    mark.style.pageBreakBefore = false
                    mark.style.columnBreak = false
                    mark.style.breakEndsPrevious = false
                    mark.style.breakRunPropertiesXML = nil
                    out.append(mark)
                }
                tableColumns[id] = widths
                var ts = TableStyle()
                ts.borders = false
                ts.sectionColumns = true; RuleTrace.hit("section-columns-as-row")
                ts.cellMarginTop = 0; ts.cellMarginLeft = 0; ts.cellMarginBottom = 0; ts.cellMarginRight = 0
                tableStyles[id] = ts
                var xml = "", kept: [KeptRel] = []
                var seenNodes = Set<ObjectIdentifier>()
                for k in start ... i {
                    let node = bodyNodes[k]!
                    guard seenNodes.insert(ObjectIdentifier(node)).inserted, let frag = _keptFragment(node, notes) else { continue }
                    xml += frag.xml
                    for r in frag.rels where !kept.contains(where: { $0.id == r.id }) { kept.append(r) }
                }
                for k in firstOut ..< out.count { out[k].keptTable = kid }
                keptTables[kid] = KeptTable(xml: xml, rels: kept, texts: out[firstOut...].map(\.text))
            }
            paragraphs = out
        }
        // The caret must be able to leave a table that ends the document.
        // (Not after a section's columns set as a table: that is no table in
        // Word, its last column's paragraph ends the page, and the line added
        // here ran past a page foot of no margin onto a page of its own —
        // zh-8f9b19f4's landscape last page, 14 pages for Word's 13.)
        if paragraphs.isEmpty || (paragraphs.last?.cell.map({ tableStyles[$0.table]?.sectionColumns != true }) ?? false) { paragraphs.append(RichParagraph()) }
        // The kept headers and footers again as paragraphs, read like the
        // body (each part by its own relationships), for the layout.
        var headerFooters: [RichHeaderFooter] = []
        do {
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            // Section by section: what each names, and what it does
            // not it has from the one before — type by type, so a
            // section that names only a first page's footer goes on
            // with the earlier default one.
            var earlier: [XNode] = []
            func sections(_ n: XNode) {
                for c in n.children {
                    if c.name == "w:p", let sp = c.first("w:pPr")?.first("w:sectPr") { earlier.append(sp) }
                    else if c.name != "w:p", c.name != "w:sectPr" { sections(c) }
                }
            }
            sections(body)
            var named: [String: (kind: KeptHeaderFooter.Kind, type: String, part: String)] = [:]
            var perSection: [[String: (kind: KeptHeaderFooter.Kind, type: String, part: String)]] = []
            for sect in earlier {
                for ref in sect.children where ref.name == "w:headerReference" || ref.name == "w:footerReference" {
                    let kind: KeptHeaderFooter.Kind = ref.name == "w:headerReference" ? .header : .footer
                    let type = ref["w:type"].map { $0 == "odd" ? "default" : $0 } ?? "default"
                    guard ["default", "first", "even"].contains(type),
                          let rid = ref["r:id"], let target = relInfo[rid]?.target, !(relInfo[rid]?.external ?? false) else { continue }
                    named["\(kind.rawValue)|\(type)"] = (kind, type, _resolvePath("word", target))
                }
                perSection.append(named)
            }
            for k in keptHeaderFooters { named["\(k.kind.rawValue)|\(k.type)"] = (k.kind, k.type, k.part) }
            perSection.append(named)
            // (Counted as the layout counts them; where the two differ
            // the last section's stand for every page.)
            var marks = 0
            for (i, p) in bodyParagraphs.enumerated() where p.cell == nil && p.style.sectionPage != nil && i < bodyParagraphs.count - 1 { marks += 1 }
            let numbered = marks == earlier.count
            if !numbered { perSection = [named] }
            var read: [String: [RichParagraph]] = [:]
            func paragraphsOf(_ path: String) -> [RichParagraph] {
                if let hit = read[path] { return hit }
                read[path] = []
                // (A phantom part — see below — is Word's empty header or
                // footer: its built-in style, Normal set single with
                // nothing after.)
                // (A header's first line is in that style and its second
                // in Normal, spacing and all: Word's two marks stand 13.5pt
                // apart at 11pt, and its body starts 11.9pt under the
                // second's line — Normal's 1.15 lines and 10pt after. A
                // footer is the one line in that style: as Normal, the
                // page held a line fewer than Word's.)
                let phantom: Data? = path == "phantom:mark" ? Data("<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p/></w:hdr>".utf8)
                    : path.hasPrefix("phantom:") ? Data((
                    "<w:\(path.hasSuffix("header") ? "hdr" : "ftr") xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + "<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:p>"
                    + (path.hasSuffix("header") ? "<w:p/>" : "")
                    + "</w:\(path.hasSuffix("header") ? "hdr" : "ftr")>").utf8) : nil
                guard let data = phantom ?? part(path), let node = XNode.parse(data) else { return [] }
                _inheritSpace(node)
                _followThaiAlternates(node, thaiAlternates)
                _bindCoreProperties(node, part: part)
                // (Their theme font references too: zh-a4b0f6ea's page
                // numbers are `majorEastAsia`, 宋体, in a footer.)
                _resolveThemeFonts(node, theme)
                Self._resolveShareWidths(node.descendants("wp:anchor"), body.first("w:sectPr") ?? earlier.last)
                var comps = path.split(separator: "/").map(String.init)
                let file = comps.popLast() ?? ""
                let dir = comps.joined(separator: "/")
                rels = [:]
                var info: [String: KeptRel] = [:]
                if let relsData = part(dir + "/_rels/" + file + ".rels"), let relsNode = XNode.parse(relsData) {
                    for r in relsNode.relationships() {
                        guard let id = r["Id"], let target = r["Target"] else { continue }
                        rels[id] = target
                        info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                    }
                }
                notes.rels = info
                notes.inHeaderFooter = true
                notes.normalAsciiIsCs = sheet[RichNamedStyle.normalId].map { $0.char.fontFamily != nil && $0.char.fontFamily == $0.char.complexFontFamily } ?? false
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in node.children { walkBlock(child, indent: 0) }
                notes.inHeaderFooter = false
                read[path] = paragraphs
                return paragraphs
            }
            for (s, entries) in perSection.enumerated() {
                for key in entries.keys.sorted() {
                    guard let hf = entries[key] else { continue }
                    var made = paragraphsOf(hf.part)
                    // (And a header it has ends in one more empty Normal
                    // paragraph: lab `5f` (zh-5f9b6549's package, Word 16,
                    // 2026-10-22) — its two empty header marks are followed
                    // by a 12pt Normal one, 67.3 to 80.6, and the body starts
                    // under it, 8.6pt below its 72pt margin; with Normal at
                    // 24pt that mark is 24pt, and without the background it
                    // is gone and the body starts at the margin. The footer
                    // stays as it is.)
                    if hf.kind == .header, !made.isEmpty, root.first("w:background") != nil, !Self.wordOnWindows { made += paragraphsOf("phantom:mark") }
                    if !made.isEmpty {
                        headerFooters.append(RichHeaderFooter(kind: hf.kind, type: hf.type, paragraphs: made, section: numbered ? s : nil))
                    }
                }
            }
            // A document with a background (`w:background`, never
            // printed) is laid out by Word as if it had a header of two
            // empty paragraphs and a footer of one wherever it has none: lab
            // `bg1`/`bg2` (bib-chernigovka's package, Word 16,
            // 2026-10-15) — with the background Word's print holds two
            // empty header marks and a footer mark and the body runs
            // 85.7 to 783.8 down the page; without it, no marks and 68.2
            // to 793. bib-chernigovka matched none of Word's lines, each
            // page's text 18 to 50pt higher than Word's. (So do 61991
            // and 51921-Word-Crash067, whose margins happen to hold it.)
            // (Word for Mac's only: Word for Windows lays such a file out
            // with no marks at all — its prints (word-win) of zh-b875d786,
            // zh-c599aaa1, zh-15f67ef1 and zh-4adfcce2 start the body at
            // the margin, 7 to 29pt above the Mac's.)
            if root.first("w:background") != nil, !Self.wordOnWindows {
                for kind in [KeptHeaderFooter.Kind.header, .footer] where !headerFooters.contains(where: { $0.kind == kind }) {
                    let made = paragraphsOf(kind == .header ? "phantom:header" : "phantom:footer")
                    if !made.isEmpty { headerFooters.append(RichHeaderFooter(kind: kind, type: "default", paragraphs: made)) }
                }
            }
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        // The footnotes, each read like the body, its own mark showing
        // the number the body's mark was given.
        var footnoteParagraphs: [Int: [RichParagraph]] = [:]
        var footnoteSeparator: [RichParagraph] = []
        if notes.footnotes, let data = part("word/footnotes.xml"), let root = XNode.parse(data) {
            _resolveThemeFonts(root, theme)
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            rels = [:]
            var info: [String: KeptRel] = [:]
            if let relsData = part("word/_rels/footnotes.xml.rels"), let relsNode = XNode.parse(relsData) {
                for r in relsNode.relationships() {
                    guard let id = r["Id"], let target = r["Target"] else { continue }
                    rels[id] = target
                    info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
            notes.rels = info
            notes.inHeaderFooter = true
            let saved = (notes.seenFootnotes, notes.seenEndnotes)
            for note in root.all("w:footnote") {
                guard let id = Int(note["w:id"] ?? "") else { continue }
                let type = note["w:type"] ?? "normal"
                guard type == "normal" || type == "separator" else { continue }
                guard type == "separator" || notes.footnoteNumbers[id] != nil || notes.customFootnotes.contains(id) else { continue }
                notes.currentNote = notes.footnoteNumbers[id]
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in note.children { walkBlock(child, indent: 0) }
                if type == "separator" { Self.sizeSeparatorByItsRun(note, &paragraphs); footnoteSeparator = paragraphs } else { footnoteParagraphs[id] = paragraphs }
            }
            notes.currentNote = nil
            (notes.seenFootnotes, notes.seenEndnotes) = saved
            notes.inHeaderFooter = false
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        // The endnotes, the same way: set after the body's last paragraph.
        var endnoteParagraphs: [Int: [RichParagraph]] = [:]
        var endnoteSeparator: [RichParagraph] = []
        var endnoteContinuation: [RichParagraph] = []
        if notes.endnotes, let data = part("word/endnotes.xml"), let root = XNode.parse(data) {
            _resolveThemeFonts(root, theme)
            let bodyParagraphs = paragraphs, bodyRels = rels, bodyInfo = notes.rels
            rels = [:]
            var info: [String: KeptRel] = [:]
            if let relsData = part("word/_rels/endnotes.xml.rels"), let relsNode = XNode.parse(relsData) {
                for r in relsNode.relationships() {
                    guard let id = r["Id"], let target = r["Target"] else { continue }
                    rels[id] = target
                    info[id] = KeptRel(id: id, type: r["Type"] ?? "", target: target, external: r["TargetMode"] == "External")
                }
            }
            notes.rels = info
            notes.inHeaderFooter = true
            let saved = (notes.seenFootnotes, notes.seenEndnotes)
            for note in root.all("w:endnote") {
                guard let id = Int(note["w:id"] ?? "") else { continue }
                let type = note["w:type"] ?? "normal"
                guard type == "normal" || type == "separator" || type == "continuationSeparator" else { continue }
                guard type == "separator" || type == "continuationSeparator" || notes.endnoteNumbers[id] != nil || notes.customEndnotes.contains(id) else { continue }
                notes.currentNoteLabel = notes.endnoteNumbers[id].map { notes.label($0, footnote: false) }
                paragraphs = []
                currentCell = nil
                pendingPageBreak = false
                for child in note.children { walkBlock(child, indent: 0) }
                if type == "separator" { Self.sizeSeparatorByItsRun(note, &paragraphs); endnoteSeparator = paragraphs } else if type == "continuationSeparator" { endnoteContinuation = paragraphs } else { endnoteParagraphs[id] = paragraphs }
            }
            notes.currentNoteLabel = nil
            (notes.seenFootnotes, notes.seenEndnotes) = saved
            notes.inHeaderFooter = false
            paragraphs = bodyParagraphs
            rels = bodyRels
            notes.rels = bodyInfo
            currentCell = nil
            pendingPageBreak = false
        }
        // (A picture wrapped top and bottom whose position is "centre" or "bottom" of the margins' box, or of the page, is a
        // fixed band at that place: text before it keeps its lines, and the lines that would meet it go under it. Lab-free:
        // sa1 afbaab24's 136.5pt picture, centred in the margins of an A4 page, stands 354.7 to 491.2 in Word's print and
        // the text after it at 506.6; set in the line, ours stood it at 323.4 and the text at 484.9. Resolved here to an
        // offset from the margin's top (or the page's), where the section is known, so the fixed-band rules read it.)
        if let last = pageSetup {
            var sectionEnds: [Int] = []
            for (i, q) in paragraphs.enumerated() where q.cell == nil && q.style.sectionPage != nil { sectionEnds.append(i) }
            func setup(_ i: Int) -> PageSetup { sectionEnds.first { $0 >= i }.flatMap { paragraphs[$0].style.sectionPage } ?? last }
            func resolved(_ image: ImageAttachment, _ s: PageSetup) -> ImageAttachment? {
                guard var f = image.float, f.takesRoom, !f.wraps, f.horizontalFrom != "character",
                      f.verticalAlign == "center" || f.verticalAlign == "bottom", f.verticalFrom == "margin" || f.verticalFrom == "page",
                      image.height > 0 else { return nil }
                let whole = image.height + f.effectBottom
                let span = f.verticalFrom == "page" ? s.height : s.height - s.marginTop - s.marginBottom
                guard span > whole else { return nil }
                RuleTrace.hit("top-and-bottom-picture-centred-in-the-margins-is-a-fixed-band")
                f.y = f.verticalAlign == "center" ? (span - whole) / 2 : span - whole
                f.verticalAlign = nil
                Self._bandPage(&f)
                var out = image
                out.float = f
                return out
            }
            for i in paragraphs.indices where paragraphs[i].cell == nil {
                let s = setup(i)
                if let image = paragraphs[i].image, let r = resolved(image, s) { paragraphs[i].image = r }
                for (key, image) in paragraphs[i].inlineImages { if let r = resolved(image, s) { paragraphs[i].inlineImages[key] = r } }
            }
        }
        var document = RichDocument(paragraphs: paragraphs)
        document.headerFooters = headerFooters
        document.footnotes = footnoteParagraphs
        document.footnoteSeparator = footnoteSeparator
        document.endnotes = endnoteParagraphs
        document.endnoteSeparator = endnoteSeparator
        document.endnoteContinuation = endnoteContinuation
        document.endnotesAtSectionEnd = part("word/settings.xml").flatMap(XNode.parse)?.first("w:endnotePr")?.first("w:pos")?["w:val"] == "sectEnd"
        // (Endnotes too long to stand under the last paragraph run on over the pages after it, as Word's do — urd-z8387389's
        // 58 notes are three pages of its 12 — so they are flowed as paragraphs of their own, in the order of their marks,
        // after a separator line's height. The painter that sets short ones under the last paragraph drops any that do not
        // fit it whole.)
        if !document.endnotesAtSectionEnd, !endnoteParagraphs.isEmpty {
            var order: [Int] = []
            for p in paragraphs { for run in p.runs { if let n = run.style.note, n.kind == .endnote, endnoteParagraphs[n.id] != nil, !order.contains(n.id) { order.append(n.id) } } }
            let characters = order.reduce(0) { $0 + (endnoteParagraphs[$1] ?? []).reduce(0) { $0 + $1.text.utf16.count } }
            if characters > 1500 {
                RuleTrace.hit("endnotes-flowed-after-body")
                var flowed: [RichParagraph] = []
                for var p in endnoteSeparator { p.flowedEndnote = -1; flowed.append(p) }
                for id in order { for var p in endnoteParagraphs[id] ?? [] { p.flowedEndnote = id; flowed.append(p) } }
                document.paragraphs.append(contentsOf: flowed)
                document.endnotes = [:]
            }
        }
        document.tableColumns = tableColumns
        document.tableCellColumns = tableCellColumns
        document.tableStyles = tableStyles
        document.tableStyleIds = tableStyleIds
        document.tableLooks = tableLooks
        document.tableCondFills = tableCondFills
        document.keptTableStyles = keptTableStyles
        document.styles = sheet
        document.styleAliases = styleAliases
        document.keptCharacterStyles = keptCharacterStyles
        document.keptCharacterStyleIds = keptCharacterStyleIds
        document.readFromFile = true
        // Word draws a Gurmukhi run whose complex face it lacks (Times New Roman) in Raavi, not Nirmala UI, through the whole document when the first Gurmukhi paragraph has a run naming Raavi as its Latin face
        // (labs punjabi-raavi prints: Raavi in the first Gurmukhi paragraph flips every run, first run Arial or not; theme and default language do not; none named stays Nirmala UI; dx2 60aa1e5d names Raavi once, late, and stays Nirmala UI)
        if let first = document.paragraphs.firstIndex(where: { $0.text.unicodeScalars.contains { $0.value >= 0x0A00 && $0.value <= 0x0A7F } }),
           document.paragraphs[first].runs.contains(where: { $0.style.fontFamily?.trimmingWhitespace().lowercased() == "raavi" }) {
            for pi in document.paragraphs.indices { for ri in document.paragraphs[pi].runs.indices { document.paragraphs[pi].runs[ri].style.gurmukhiRaavi = true } }
        }
        document.docDefaultParagraph = docBase
        document.fileFonts = _declaredFonts(docData).union(_declaredFonts(part("word/styles.xml")))
        document.listFormats = listFormats
        document.listCounterOf = listCounterOf
        document.listRestarts = listRestarts
        document.keptNumberingXML = part("word/numbering.xml").flatMap { String(data: $0, encoding: .utf8) }
        document.listFormatsSnapshot = listFormats
        document.listRestartsSnapshot = listRestarts
        if let bg = root.first("w:background"), let frag = _keptFragment(bg, notes) {
            document.backgroundXML = frag.xml
            document.backgroundRels = frag.rels
            if let tc = bg["w:themeColor"] {
                // (Word prints the theme slot, not the w:color fallback; a tint or shade moves its HSL lightness, and
                // with both present only the tint shows: lab bg 1-6, accent2 ED7D31 -> F7CAAC / C45911 / F4B083.)
                if let v = _themeBackground(tc, tint: bg["w:themeTint"], shade: bg["w:themeShade"]), v != 0xFFFFFF { document.backgroundColor = v }
            } else if let c = bg["w:color"], c.count == 6, let v = UInt32(c, radix: 16), v != 0xFFFFFF { document.backgroundColor = v }
        }
        document.keptParts = notes.kept
        document.keptPartTypes = notes.keptTypes
        if let data = part("_rels/.rels"), let rr = XNode.parse(data) {
            document.keptRootRels = rr.relationships().compactMap { r in
                guard let id = r["Id"], let type = r["Type"], let target = r["Target"],
                      !type.hasSuffix("/officeDocument"), r["TargetMode"] == "External" || notes.kept[target.hasPrefix("/") ? String(target.dropFirst()) : target] != nil
                else { return nil }
                return KeptRel(id: id, type: type, target: target, external: r["TargetMode"] == "External")
            }
        }
        for p in document.paragraphs { for c in p.customBoundControls where document.boundLoaded[c.store + "|" + c.xpath] == nil { document.boundLoaded[c.store + "|" + c.xpath] = c.text } }
        document.keptCustomXmlRels = relInfo.values.filter { $0.type.hasSuffix("/customXml") && notes.kept["customXml/" + ($0.target.split(separator: "/").last.map(String.init) ?? "")] != nil }
            .sorted { $0.id < $1.id }
        document.keptTables = keptTables
        document.keptHeaderFooters = keptHeaderFooters
        document.titlePage = titlePage
        document.sectionChange = sectionChange
        document.evenAndOddHeaders = evenAndOddHeaders
        document.widowControlSuspended = footerFramed
        document.keptCompat = keptCompat
        document.defaultTabStop = defaultTabStop
        if let pb = body.first("w:sectPr")?.first("w:pgBorders") { document.pageBordersXML = PptxXML.serialize(pb) }
        if let sect = body.first("w:sectPr") {
            if let grid = sect.first("w:docGrid") {
                document.docGridXML = PptxXML.serialize(grid)
                let verticalDoc = ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")
                if let type = grid["w:type"], type == "lines" || type == "linesAndChars" || type == "snapToChars", let pitch = Double(grid["w:linePitch"] ?? ""), pitch > 0 {
                    document.lineGridPitch = pitch / 20
                }
                // (A grid of characters that adds nothing to them is a grid
                // all the same: its lines hold whole characters — zh-18cb2079,
                // linesAndChars with no charSpace, sets 27 of 16pt in a
                // 442pt column in Word's print, where ours squeezed three
                // marks for a 28th. A hair stands for none.)
                if grid["w:type"] == "linesAndChars" || (grid["w:type"] == "snapToChars" && ["tbRl", "tbRlV"].contains(sect.first("w:textDirection")?["w:val"] ?? "")) {
                    let space = Double(grid["w:charSpace"] ?? "") ?? 0
                    document.characterGridSpace = space != 0 ? space / 4096 : 1e-6
                }
                if let cell = _snapCellSpace(sect, normalSize: sheet[RichNamedStyle.normalId]?.char.fontSize ?? 11) { document.characterGridSpace = cell; document.characterGridCellBase = sheet[RichNamedStyle.normalId]?.char.fontSize ?? 11 }
            }
            document.sectionTypeXML = sect.first("w:type").map { PptxXML.serialize($0) }
            if let cols = sect.first("w:cols") {
                document.columnsXML = PptxXML.serialize(cols)
                document.columnsKeptUnder = max(1, Int(cols["w:num"] ?? "1") ?? 1)
            }
            document.gutterTwips = sect.first("w:pgMar")?["w:gutter"].flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            let lead = ["w:lnNumType", "w:pgNumType"].compactMap { sect.first($0) }.map { PptxXML.serialize($0) }.joined()
            let tail = ["w:vAlign", "w:textDirection", "w:bidi", "w:rtlGutter"].compactMap { sect.first($0) }.map { PptxXML.serialize($0) }.joined()
            document.sectionLeadXML = lead.isEmpty ? nil : lead
            if let num = sect.first("w:pgNumType") {
                document.pageNumberStart = Int(num["w:start"] ?? "")
                document.pageNumberFormat = num["w:fmt"]
                document.chapterStyle = Int(num["w:chapStyle"] ?? "")
                document.chapterSeparator = num["w:chapSep"]
            }
            document.sectionTailXML = tail.isEmpty ? nil : tail
        }
        // (A file with no settings at all, or no styles, is set by the
        // East Asian rules: Word reads it as one of its older documents.)
        if part("word/settings.xml") == nil || _settingsBare { document.usesEastAsianLayout = true }
        // (Kana in the body text, UTF-8 E3 81..83 xx: a Japanese document whatever its language tag says.)
        do {
            var kana = false
            var prev: UInt8 = 0
            for byte in docData {
                if prev == 0xE3, byte >= 0x81, byte <= 0x83 { kana = true; break }
                prev = byte
            }
            document.hasKana = kana
        }
        if let table = part("word/fontTable.xml").flatMap(XNode.parse) {
            document.thaanaFaces.formUnion(Self.thaanaFaceNames(table))
            var charsets: [String: String] = [:]
            for font in table.all("w:font") {
                guard let name = font["w:name"], name.unicodeScalars.contains(where: { $0.value >= 0x2E80 }),
                      let charset = font.first("w:charset")?["w:val"] else { continue }
                // (Where the table repeats a name, its East Asian entry over
                // a charset-00 one, whichever comes first: zh-01bbcd4d lists
                // 方正仿宋简体 as GB2312, then as charset 00 with no PANOSE,
                // and Word sets its digits in YaHei, an East Asian face's
                // stand-in — ours took the second for a Latin face's;
                // zh-3f871b7d lists 仿宋_GB2312 as 00, then 86, and Word's
                // print is the East Asian face's.)
                if charsets[name] == nil || charsets[name] == "00" { charsets[name] = charset }
            }
            if !charsets.isEmpty { OfficeFonts.noteFontTable(charsets) }
            OfficeFonts.noteEmbedded(table.all("w:font").compactMap { font in
                font.first("w:embedRegular") != nil || font.first("w:embedBold") != nil ? font["w:name"] : nil
            })
            // The East Asian faces themselves (only those: the Latin ones
            // a file embeds are Word's own, which the shipped clones match
            // to the unit), drawn in their own glyphs.
            var faceTargets: [String: String] = [:]
            if let relRoot = part("word/_rels/fontTable.xml.rels").flatMap(XNode.parse) {
                for r in relRoot.relationships() {
                    if let id = r["Id"], let target = r["Target"] { faceTargets[id] = target }
                }
            }
            var faces: [String: String] = [:]
            for font in table.all("w:font") {
                // (And, in Word — for Windows and for the Mac alike — one with
                // a Latin name whose entry names an East Asian charset, for its
                // line: zh-1cfb652b's GWZT-EN, charset 86 — see `OfficeFonts.face`.)
                guard let name = font["w:name"],
                      OfficeFonts.isEastAsianFace(name) || (Self.wordOnWindows || Self.wordOnMac) && ["86", "88", "80", "81"].contains(font.first("w:charset")?["w:val"]?.uppercased() ?? ""),
                      let embed = font.first("w:embedRegular") ?? font.first("w:embedBold"),
                      let rid = embed["r:id"], let key = embed["w:fontKey"], let target = faceTargets[rid] else { continue }
                let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                guard let raw = part(path), let data = OfficeFonts.deobfuscate(raw, key: key),
                      let family = OfficeFonts.loadEmbedded(data) else { continue }
                faces[name] = family
                if OfficeFonts.mapsToZeroAdvance(data, 0x300C) { document.uncompressedFaces.insert(name) }
            }
            // (The Latin faces a file embeds that Word for Windows lacks: all four styles under one family.
            // jpn-z22306877's Libre Baskerville and Crimson Text, which Word prints.)
            if Self.wordOnWindows {
                for font in table.all("w:font") {
                    guard let name = font["w:name"], OfficeFonts.embeddedLatinWanted(name), faces[name] == nil else { continue }
                    var family: String? = nil
                    for tag in ["w:embedRegular", "w:embedBold", "w:embedItalic", "w:embedBoldItalic"] {
                        guard let embed = font.first(tag), let rid = embed["r:id"], let key = embed["w:fontKey"], let target = faceTargets[rid] else { continue }
                        let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
                        guard let raw = part(path), let data = OfficeFonts.deobfuscate(raw, key: key),
                              OfficeFonts.coversLatinLetters(data),
                              let f = OfficeFonts.loadEmbedded(data, sharedFamily: "Starling Embedded Latin " + name) else { continue }
                        family = f
                    }
                    if let family { faces[name] = family }
                }
            }
            OfficeFonts.noteEmbeddedFaces(faces)
            var alts: [String: String] = [:]
            var entries: [String: OfficeFonts.FontEntry] = [:]
            var entryCharsets: [String: String] = [:]
            for font in table.all("w:font") {
                guard let name = font["w:name"] else { continue }
                // (An East Asian entry over a charset-00 one for a repeated
                // name: see the charsets above.)
                let charset = font.first("w:charset")?["w:val"] ?? ""
                // (Whichever entry is kept, the last one's family: Word for
                // Mac's, `FontEntry.lastFamily`.)
                if entries[name] != nil { entries[name]!.lastFamily = font.first("w:family")?["w:val"] ?? "auto" }
                if entries[name] != nil, charset == "00" || entryCharsets[name] != "00" { continue }
                entryCharsets[name] = charset
                let alt = font.first("w:altName")?["w:val"]
                if let alt, !alt.isEmpty { alts[name] = alt }
                let panose = font.first("w:panose1")?["w:val"] ?? ""
                let sig = font.first("w:sig")
                entries[name] = OfficeFonts.FontEntry(alt: alt, family: font.first("w:family")?["w:val"] ?? "auto",
                                                      panoseZero: !panose.isEmpty && panose.allSatisfy { $0 == "0" }, panose: panose, charset: charset,
                                                      usb0: sig?["w:usb0"].flatMap { UInt32($0, radix: 16) },
                                                      usb1: sig?["w:usb1"].flatMap { UInt32($0, radix: 16) })
            }
            document.fontCharsets = Dictionary(entryCharsets.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
            document.fontUsb0 = Dictionary(entries.compactMap { e in e.value.usb0.map { (e.key.trimmingWhitespace().lowercased(), $0) } }, uniquingKeysWith: { a, _ in a })
            document.fontAlternates = Dictionary(alts.map { ($0.key.trimmingWhitespace().lowercased(), $0.value.trimmingWhitespace().lowercased()) }, uniquingKeysWith: { a, _ in a })
            OfficeFonts.noteAltNames(alts)
            OfficeFonts.noteFontEntries(entries)
            document.hasIndicText = Self._hasIndicBytes(docData)
            document.devanagariFirstRunMangal = Self._firstDevanagariRunNamesMangal(docData)
            OfficeFonts.noteIndicText(document.hasIndicText)
        } else {
            OfficeFonts.noteEmbedded([])
            OfficeFonts.noteEmbeddedFaces([:])
            OfficeFonts.noteAltNames([:])
            OfficeFonts.noteFontEntries([:])
            OfficeFonts.noteIndicText(false)
        }
        // The HTML blocks' margins, by the id a paragraph names (only a
        // block's own: drawing.docx's banner block, 0.75pt over and 3.75
        // under, inside a body block of 7.5pt all round, stands 4.5pt
        // taller in Word's print, the body's margins nowhere).
        if let web = part("word/webSettings.xml").flatMap(XNode.parse) {
            func walk(_ node: XNode) {
                for div in node.all("w:div") {
                    if let id = div["w:id"] {
                        let top = Double(div.first("w:marTop")?["w:val"] ?? "") ?? 0
                        let bottom = Double(div.first("w:marBottom")?["w:val"] ?? "") ?? 0
                        if top > 0 || bottom > 0 { document.divMargins[id] = DivMargins(top: top / 20, bottom: bottom / 20) }
                    }
                    if let children = div.first("w:divsChild") { walk(children) }
                }
            }
            if let divs = web.first("w:divs") { walk(divs) }
        }
        var legacyNoFE = false
        if !_settingsBare, let settings = part("word/settings.xml").flatMap(XNode.parse) {
            legacyNoFE = settings.first("w:compat")?.first("w:useFELayout") == nil
            document.themeFontLangXML = settings.first("w:themeFontLang").map { PptxXML.serialize($0) }
            document.characterSpacingControl = settings.first("w:characterSpacingControl")?["w:val"]
            document.kernsPunctuation = settings.first("w:noPunctuationKerning").map { _isOff($0) } ?? true
            document.htmlAutoSpacing = !(settings.first("w:compat")?.first("w:doNotUseHTMLParagraphAutoSpacing").map { !_isOff($0) } ?? false)
            document.usesEastAsianLayout = settings.first("w:compat")?.first("w:useFELayout").map { !_isOff($0) }
                ?? (part("word/styles.xml") == nil)
            document.doesNotExpandShiftReturn = settings.first("w:compat")?.first("w:doNotExpandShiftReturn").map { !_isOff($0) } ?? false
            document.numberTabReachesLevelIndent = settings.first("w:compat")?.first("w:binaryDocListTabs") != nil
            document.indentNotNumberingTabStop = settings.first("w:compat")?.first("w:doNotUseIndentAsNumberingTabStop").map { !_isOff($0) } ?? false
            document.balancesSpaceWidth = settings.first("w:compat")?.first("w:balanceSingleByteDoubleByteWidth").map { !_isOff($0) } ?? false
            document.underlinesTrailingSpaces = settings.first("w:compat")?.first("w:ulTrailSpace").map { !_isOff($0) } ?? false
            document.spacesForUnderline = settings.first("w:compat")?.first("w:spaceForUL").map { !_isOff($0) } ?? false
            document.adjustsLineHeightInTable = settings.first("w:compat")?.first("w:adjustLineHeightInTable").map { !_isOff($0) } ?? false
            document.leavesColumnsUnbalanced = settings.first("w:compat")?.first("w:noColumnBalance").map { !_isOff($0) } ?? false
            document.suppressesTopSpacing = settings.first("w:compat")?.first("w:suppressTopSpacing").map { !_isOff($0) } ?? false
            document.hangsHalf = settings.first("w:compat")?.first("w:useAltKinsokuLineBreakRules").map { !_isOff($0) } ?? false
            document.breakRulesOnlyForEastAsian = settings.first("w:compat")?.first("w:doNotUseEastAsianBreakRules").map { !_isOff($0) } ?? false
            document.doNotBreakWrappedTables = settings.first("w:compat")?.first("w:doNotBreakWrappedTables").map { !_isOff($0) } ?? false
            document.suppressBottomSpacing = settings.first("w:compat")?.first("w:suppressBottomSpacing").map { !_isOff($0) } ?? false
            document.compatibilityMode = settings.first("w:compat")?.all("w:compatSetting")
                .first { $0["w:name"] == "compatibilityMode" }.flatMap { Int($0["w:val"] ?? "") }
            // (A file that names no compatibility mode — with a w:compat block
            // or without, as Word for Windows' labs `compat` a, b: fdo63164-1
            // with none and with an empty one — hangs a line's last full stop
            // or comma past the margin, and is set by the East Asian rules
            // where its settings do not say.)
            document.autoSpacesWithoutFELayout = document.compatibilityMode != nil && settings.first("w:compat")?.first("w:useFELayout") == nil
            if document.compatibilityMode == nil, settings.first("w:compat")?.first("w:useFELayout") == nil {
                document.hangsLatinStops = part("word/styles.xml") != nil
                document.usesEastAsianLayout = document.usesEastAsianLayout || document.hangsLatinStops
            }
            document.flipsMirrorIndents = !(settings.first("w:compat")?.all("w:compatSetting")
                .contains { $0["w:name"] == "doNotFlipMirrorIndents" && ["1", "true", "on"].contains($0["w:val"] ?? "") } ?? false)
            document.addsParagraphSpacing = settings.first("w:compat")?.first("w:doNotUseHTMLParagraphAutoSpacing").map { !_isOff($0) } ?? false
            let margins = ["w:mirrorMargins", "w:gutterAtTop"].compactMap { settings.first($0) }.map { PptxXML.serialize($0) }.joined()
            document.marginSettingsXML = margins.isEmpty ? nil : margins
            for name in _keptSettingNames.flatMap({ $0 }) {
                if let n = settings.first(name) { document.keptSettings[name] = PptxXML.serialize(n) }
            }
        } else if part("word/settings.xml") == nil || _settingsBare, part("word/styles.xml") != nil {
            // (A file with no settings part names no compatibility mode either; a copy of
            // jpn-z23823926-b2a8e5 with an empty w:compat added went from 55.4 to 99.0.)
            document.hangsLatinStops = true
            document.usesEastAsianLayout = true
        }
        if let styles = styleTree() {
            // The defaults' language, or Normal's over it — each of its
            // three by itself: zh-63a571aa's Normal says only
            // `w:bidi="ar-SA"`, its East Asian text the defaults' zh-TW,
            // whose centred "。" keeps its em before "」" in Word's print;
            // ours took no East Asian language and closed it up.
            // (A Latin face named for East Asian text in the defaults turns
            // Word for Windows' punctuation compression off: labs tcd/q/x
            // (windows-1, Word for Windows, zh-cd48112c's package) — its
            // rPrDefault says eastAsia "Times New Roman", and every "，",
            // "、", "“" and "”" is a whole em in its print; with 宋体 there
            // the same paragraph squeezes its marks and takes a character
            // more a line. Its languages, swapped every way, changed
            // nothing.)
            if let ea = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:eastAsia"],
               !OfficeFonts.isEastAsianFace(ea),
               ["times new roman", "times", "arial", "calibri", "cambria", "ms serif", "verdana", "tahoma", "helvetica", "courier new", "segoe ui", "georgia"]
                .contains(ea.trimmingWhitespace().lowercased()) {
                document.eastAsianDefaultFaceIsLatin = true
                // (Not where the body itself names an East Asian language on a run:
                // docx-79737edb's runs say ja-JP/ko-KR/zh-CN and Word keeps its line-start ban.)
                if let d = part("word/document.xml"), String(decoding: d, as: UTF8.self).containsSubstring("<w:lang ") {
                    document.bodyStatesLang = true
                }
            }
            // (Defaults that name no East Asian face at all, no eastAsia and no eastAsiaTheme in rPrDefault's rFonts (or no rFonts): Word for
            // Windows squeezes no pause mark either, whatever Normal and the runs name. Lab pm4: the same 56 paragraphs squeeze with the real
            // zh-66451627 styles (docDefaults rFonts asciiTheme/eastAsiaTheme minorEastAsia) and stay a whole em each with that one element
            // removed (g1) or with no docDefaults (g5, a, b, c, d, f).)
            do {
                let rf = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")
                if rf?["w:eastAsia"] == nil && rf?["w:eastAsiaTheme"] == nil { document.eastAsianDefaultFaceUnnamed = true }
            }
            let normal = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }
            let own = normal?.first("w:rPr")?.first("w:lang")
            let defaults = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:lang")
            // (`RichDocument.joinsHanAfterSpace`.)
            // (hangsLatinStops is set only for a file with no compatibility mode and
            // no useFELayout: WPS and Chinese Word files carry useFELayout and keep a Han run whole.)
            // (A theme East Asian font keeps the rule for a file that does carry useFELayout: zh-7773163d.)
            let defaultEastAsia = styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:eastAsiaTheme"]
            // (Word-win prints of dx2 6ddc0960, 236cd3ae, f8ff8a48, 2a9d6c3a: a compat 12 file without
            // useFELayout also breaks after "3. " when the Han text after it overflows.)
            // (Mode 12 only: the four dx2 files with this behaviour are all compat 12; zh-202582e2, compat 14 with the same
            // en-US languages, breaks inside the Han stretch.)
            // (And only where the East Asian default face is a Latin one, as in those four: dx2 4cac8c37, compat 12 with YaHei
            // for every script, fills its line through the Han stretch after a blank, in Word's print.)
            let legacyCompat = document.compatibilityMode == 12 && legacyNoFE && document.eastAsianDefaultFaceIsLatin
            document.joinsHanAfterSpace = legacyCompat || document.compatibilityMode == nil
                && (document.hangsLatinStops || ["minorHAnsi", "majorHAnsi", "minorAscii", "majorAscii"].contains(defaultEastAsia ?? ""))
            document.defaultFontFamily = styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }?
                .first("w:rPr")?.first("w:rFonts")?["w:ascii"]
                ?? styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:rFonts")?["w:ascii"]
            document.defaultFontSize = (styles.all("w:style").first { $0["w:type"] == "paragraph" && ($0["w:default"] == "1" || $0["w:styleId"] == "Normal") }?
                .first("w:rPr")?.first("w:sz")?["w:val"]
                ?? styles.first("w:docDefaults")?.first("w:rPrDefault")?.first("w:rPr")?.first("w:sz")?["w:val"]).flatMap { Double($0) }.map { $0 / 2 }
            if let ea = defaults?["w:eastAsia"] { document.defaultsEastAsiaNotCJK = !["zh", "ja", "ko"].contains(String(ea.prefix(2)).lowercased()) }
            if let own, let defaults {
                document.defaultLangXML = PptxXML.serialize(XNode(name: own.name, attrs: defaults.attrs.merging(own.attrs) { _, mine in mine }))
            } else if let lang = own ?? defaults {
                document.defaultLangXML = PptxXML.serialize(lang)
            }
            // (Lab hang3, compat 14: Word hangs a Latin line-end , . ; ) } only with eastAsia zh-CN AND the minorEastAsia theme face;
            // either one removed, or both, and the stop wraps.)
            document.hangsStopsMinorEA = defaultEastAsia == "minorEastAsia"
        }
        // Header/footer: the section's default references, text with the
        // PAGE/NUMPAGES fields kept as placeholders.
        if let sect = body.first("w:sectPr") {
            for ref in sect.all("w:headerReference") where ref["w:type"] == "default" || ref["w:type"] == "odd" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.header = _fieldText(node)
                }
            }
            for ref in sect.all("w:footerReference") where ref["w:type"] == "default" || ref["w:type"] == "odd" || ref["w:type"] == nil {
                if let rid = ref["r:id"], let target = rels[rid], let data = media(target),
                   let node = XNode.parse(data) {
                    document.footer = _fieldText(node)
                }
            }
        }
        if let raw = part("word/styles.xml"), let text = String(data: raw, encoding: .utf8) {
            document.keptStylesXML = text
            document.styleFileIds = styleByDocx
            document.styleSource = styleSourceIds
            document.styleSnapshot = document.styles.styles
        }
        return DocxDocument(document: document, pageSetup: pageSetup)
    }

    /// A content control bound to a core property (the title, the author
    /// …: a cover page's) shows the property, not what the file cached —
    /// and its placeholder text where the property is empty. Lab-free:
    /// lo-9106c8eca7363cbc (fdo67013), a header's "Title" control cached
    /// "Sample Doc 002" over an empty `dc:title`; Word's print has
    /// "[Type the document title]".
}


extension DocxFormat {
    /// The faces a font table marks Thaana (MV Boli, or a face Windows lacks whose signature carries the Thaana bit).
    static func thaanaFaceNames(_ table: XNode) -> Set<String> {
        var out = Set<String>()
        for font in table.all("w:font") {
                if let name = font["w:name"], let usb2 = font.first("w:sig")?["w:usb2"], let v = UInt32(usb2, radix: 16), v & 0x100 != 0,
                   // (Only a face Windows lacks: Sakkal Majalla's own table carries the Thaana bit and Word draws it in Sakkal Majalla, a 1.40 em line, not MV Boli's 1.611: dx2 be31e911's body 25.8 pt a line against 22.4 in Word.)
                   name.trimmingWhitespace().lowercased() == "mv boli" || !WordWindowsFaces.names.contains(name.trimmingWhitespace().lowercased()),
                   // (A font-table entry of an East Asian charset (80 Shift-JIS, 81 Hangul, 86 GB2312, 88 Big5) is no Thaana face even when its signature claims every script: 한컴바탕 was laid out as an MV Boli line, 1.611 em against Batang's 1.303.)
                   !Self.isEastAsianCharset(font.first("w:charset")?["w:val"]) {
                    out.insert(name.trimmingWhitespace().lowercased())
                }
            }
        return out
    }

    static func thaanaFaceNames(fontTableXML: String) throws -> Set<String> {
        guard let t = XNode.parse(Data(fontTableXML.utf8)) else { return [] }
        return thaanaFaceNames(t)
    }

    /// Font-table charsets of the East Asian scripts (hex): 80 Shift-JIS, 81 Hangul, 86 GB2312, 88 Big5.
    static func isEastAsianCharset(_ charset: String?) -> Bool {
        guard let c = charset?.uppercased() else { return false }
        return ["80", "81", "86", "88"].contains(c)
    }

    /// A signed half-point count (`w:position`, `w:spacing` of a run), or a number with a
    /// unit (`6pt`, `-0.5mm`, `1in`; ST_SignedHpsMeasure), in points. Word honours the unit
    /// form: xb docx-8f1703b9 writes `w:position w:val="6pt"` and its raised word stands 6 pt up.
    static func halfPointsOrMeasure(_ text: String) -> Double? {
        if let v = Double(text) { return v / 2 }
        let units: [(String, Double)] = [("pt", 1), ("mm", 72 / 25.4), ("cm", 72 / 2.54), ("in", 72), ("pc", 12), ("pi", 12)]
        for (u, k) in units where text.hasSuffix(u) {
            if let v = Double(String(text.dropLast(u.count))) { return v * k }
        }
        return nil
    }
}
