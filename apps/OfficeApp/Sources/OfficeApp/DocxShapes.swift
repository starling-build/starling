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

// Part of the .docx reader/writer (split from Docx.swift, members unchanged).

extension DocxFormat {
    static func _followThaiAlternates(_ root: XNode, _ names: Set<String>) {
        guard !names.isEmpty else { return }
        var stack = [root]
        while let node = stack.popLast() {
            if node.name == "w:rFonts" {
                for attr in ["w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"] {
                    if let v = node.attrs[attr], names.contains(v.trimmingWhitespace().lowercased()) { node.attrs[attr] = "TH SarabunPSK" }
                }
            }
            stack.append(contentsOf: node.children)
        }
    }

    static func _resolveThemeFonts(_ root: XNode, _ theme: ThemeFonts) {
        guard !theme.isEmpty else { return }
        var stack = [root]   // iterative: a fuzzer's tree is deeper than the call stack
        while let node = stack.popLast() {
            if node.name == "w:rFonts" {
                for (ref, attr) in [("w:asciiTheme", "w:ascii"), ("w:hAnsiTheme", "w:hAnsi"), ("w:eastAsiaTheme", "w:eastAsia"), ("w:cstheme", "w:cs")] {
                    guard let t = node.attrs[ref] else { continue }
                    // (An East Asian slot pointed at a Latin theme font names no East Asian face: Word's print sets a hinted "·" in
                    // MS Mincho there, fas-z22973278's paragraphs 1.297 em tall; four xb Persian docs.)
                    // (Unless that theme font is itself an East Asian face, 맑은 고딕: dx2 471e57de's title, Malgun's 1.729 em line.)
                    if ref == "w:eastAsiaTheme", t.hasSuffix("HAnsi") || t.hasSuffix("Bidi"), !(theme.face(t).map { OfficeFonts.isEastAsianFace($0) } ?? false) { continue }
                    if let face = theme.face(t) { node.attrs[attr] = face }
                }
            }
            stack.append(contentsOf: node.children)
        }
    }

    /// Parses, and holds no character XML 1.0 forbids (Foundation's parser
    /// lets a stray control byte through; Word and expat do not).
    static func _wellFormed(_ data: Data) -> Bool {
        if data.contains(where: { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }) { return false }
        guard let root = XNode.parse(data) else { return false }
        // Names with an empty prefix or local part (`<a: val=…>`) get past
        // the small parser; a namespace-aware one rejects them.
        func bad(_ n: String) -> Bool { n.isEmpty || n.hasPrefix(":") || n.hasSuffix(":") }
        var stack = [root]
        while let node = stack.popLast() {
            if bad(node.name) || node.attrs.keys.contains(where: bad) { return false }
            stack.append(contentsOf: node.children)
        }
        return true
    }

    /// The parts the writer makes itself; a kept part never overrides one.
    static let _ownParts: Set<String> = [
        "word/document.xml", "word/styles.xml", "word/numbering.xml", "word/settings.xml",
        "word/_rels/document.xml.rels",
    ]

    static func _paragraphs(_ p: XNode, _ base: RichParagraphStyle,
                                    _ styleIds: [String: String], _ styleNums: [String: (numId: String, ilvl: Int, left: Double?, first: Double?)],
                                    _ sheet: RichStyleSheet,
                                    _ nums: [String: [Int: ListKind]],
                                    _ rels: [String: String], _ media: (String) -> Data?,
                                    _ indent: Double, _ notes: _Shared, _ cellChar: CharStyle = CharStyle(),
                                    _ cellResolve: ((String) -> RichParagraphStyle?)? = nil) -> [_Built] {
        var style = base
        var sectionBreakAfter = false
        var sectionMarginsChange = false
        // (The table style's size stands under the paragraph's own style:
        // zh-e2dc9dce's flow table, styled at 10pt, sets its "01 標題壹"
        // headings at that style's 14pt in Word's print.)
        var cellChar = cellChar
        if notes.cellSizeFromTable, let id = p.first("w:pPr")?.first("w:pStyle")?["w:val"], let ours = styleIds[id],
           sheet[ours]?.char.fontSize != nil {
            cellChar.fontSize = nil
        }
        if !notes.cellCharFromTable.isEmpty, let id = p.first("w:pPr")?.first("w:pStyle")?["w:val"], let ours = styleIds[id],
           let named = sheet[ours]?.char {
            _dropTableChar(&cellChar, stated: named, took: notes.cellCharFromTable)
        }
        // The paragraph mark's look (w:pPr/w:rPr): an empty paragraph is
        // as tall as its mark's font — a 28pt mark is a 28pt spacer. Word
        // honours it in every spelling (probed 2026-10-09 with 30 marks of
        // 28pt: END lands on page two; the 2026-10-08 probe that said
        // otherwise was wrong). bib-chernigovka's cover is 7 such spacers
        // at 16pt, and without them its first table ran onto page one.
        var markStyle: CharStyle? = nil
        var styleBreak = false
        if let pPr = p.first("w:pPr") {
            // The named style's props first, then the paragraph's own.
            if let id = pPr.first("w:pStyle")?["w:val"], let ours = styleIds[id] {
                sheet.apply(ours, to: &style)
                // (`apply` keeps the paragraph's break, as an edit that
                // restyles one must; read from the file, the style's is
                // the paragraph's too — see `_paragraphProps`.)
                if sheet[ours]?.paragraph.pageBreakBefore == true, !style.pageBreakBefore { style.pageBreakBefore = true; styleBreak = true }
                if let inCell = cellResolve?(id) {
                    let named = style.named, heading = style.heading
                    style = inCell
                    style.named = named
                    style.heading = heading
                }
            }
            // (A paragraph that says it is in no list — `w:numId` 0 — takes
            // no left, hanging or first-line indent from its style: lab
            // `lc2` (Word for Windows, zh-15428325's package), its style
            // "table of figures" at leftChars 200 hangingChars 200, sets the
            // paragraph's lines at the margin and its first two characters
            // in, where the same paragraph without the `w:numPr` keeps the
            // style's two; the corpus print has its lines so.)
            if pPr.first("w:numPr")?.first("w:numId")?["w:val"] == "0" {
                style.indentLeft = 0
                style.firstLineIndent = 0
                for key in ["w:leftChars", "w:startChars", "w:hangingChars", "w:firstLineChars"] { style.eastAsian[key] = nil }
            }
            _paragraphProps(pPr, into: &style, direct: true)
            // (A paragraph whose first run only opens a field and has no size of
            // its own: Word counts its first-line characters in the style's
            // size, not the first text's — zh-c2c92639 p8, "4.1" 3.1 pt in.)
            if let r0 = p.first("w:r"), r0.first("w:fldChar") != nil, r0.first("w:rPr")?.first("w:sz") == nil {
                style.eastAsian["w:fieldFirst"] = "1"
            }
            // (A field's begin, separate or end run that says nothing of its own is in the document's default font, and Word counts
            // it in the line's height though it draws nothing: d1fab599's contents rows, Arial 11 text over Roboto 11 defaults,
            // step 23.28 in Word's print against the Arial line's 22.65.)
            if !notes.inHeaderFooter, p.children.contains(where: { $0.name == "w:r" && $0.first("w:fldChar") != nil && $0.first("w:rPr") == nil }) {
                style.eastAsian["w:fieldMarkDefault"] = "1"
            }
            if let g = pPr.first("w:snapToGrid") { style.ownGridOff = _isOff(g) }
            style.indentLeft += indent
            // (A moved paragraph's mark too: `w:moveFrom` is a deleted mark and
            // `w:moveTo` an inserted one, a move's two ends. LibreOffice's
            // tdf104797: the moved-from paragraph is gone from Word's print with
            // markup and its balloon ends "…duplicated?¶"; ours kept it as an
            // empty line and the body stood 17pt low.)
            if let rPr = pPr.first("w:rPr"),
               let rev = rPr.first("w:del") ?? rPr.first("w:moveFrom") ?? rPr.first("w:ins") ?? rPr.first("w:moveTo") {
                let to = rev.name == "w:ins" || rev.name == "w:moveTo"
                style.markRevision = RevisionMark(kind: to ? .inserted : .deleted, author: rev["w:author"] ?? "", date: rev["w:date"] ?? "",
                                                  moved: rev.name.hasPrefix("w:move"),
                                                  segment: rev.name == "w:del" ? notes.commentReferences + p.descendants("w:commentReference").count : 0)
            }
            if let change = pPr.first("w:pPrChange") {
                style.propertyChange = FormatChange(author: change["w:author"] ?? "", date: change["w:date"] ?? "",
                                                    oldRPrXML: change.first("w:pPr").map { PptxXML.serialize($0) } ?? "",
                                                    newPPrXML: {
                                                        var x = PptxXML.serialize(pPr)
                                                        if let a = x.rangeOfSubstring("<w:pPrChange"), let b = x.rangeOfSubstring("</w:pPrChange>") { x.removeSubrange(a.lowerBound ..< b.upperBound) }
                                                        return x
                                                    }(),
                                                    styleName: pPr.first("w:pStyle")?["w:val"].flatMap { notes.styleDisplayNames[$0] } ?? "")
            }
            if let rPr = pPr.first("w:rPr") {
                // (The mark's character style first, then its own properties, as a run's:
                // tdf158597's "Char style mark" is plain text over an Emphasis 16pt mark,
                // and Word's line stands as tall as the mark.)
                var mark = cellChar
                if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id] {
                    for styled in chain { mark = _charStyle(styled, base: mark) }
                }
                // (A mark flagged w:rtl that gives w:sz and no w:szCs stands at the szCs its style gives, as a complex run does: dx2 b02602d2's
                // empty paragraph with sz 20 and w:rtl over BodyText's szCs 32 is a 19.3 pt Tahoma Bold line in Word; marks without w:rtl keep the sz.)
                markStyle = _charStyle(rPr, base: mark, complexSize: _on(rPr.first("w:rtl")) && rPr.first("w:szCs") == nil && rPr.first("w:sz") != nil ? true : nil)
            }
            // (A mark flagged w:cs, with no w:sz of its own, is a complex-script mark: its line is set at szCs, as Word's print of dx2 228c1f233c7a:
            // an empty centred paragraph with only <w:cs/> under szCs 28 is a 14 pt line, not the 11 pt one.)
            if DocxFormat.wordOnWindows, let r = pPr.first("w:rPr"), _on(r.first("w:cs")), r.first("w:sz") == nil, r.first("w:szCs") == nil, markStyle != nil { markStyle?.csMark = true }
            if markStyle?.hidden == true { style.markHidden = true }
            if style.markHidden, _on(pPr.first("w:rPr")?.first("w:specVanish")) { style.markSpecVanish = true }
            style.mark = markStyle
            // The paragraph's own numbering, else its style's (a numbered
            // heading style: 65099's "1.1.1 Acronyms").
            var num: (numId: String, ilvl: Int)? = nil
            var styleLeft: Double? = nil, styleFirst: Double? = nil
            if let numPr = pPr.first("w:numPr") {
                num = (numPr.first("w:numId")?["w:val"] ?? "", Int(numPr.first("w:ilvl")?["w:val"] ?? "0") ?? 0)
            } else if let id = pPr.first("w:pStyle")?["w:val"], let n = styleNums[id] {
                num = (n.numId, n.ilvl)
                styleLeft = n.left; styleFirst = n.first
            }
            // (A numbered paragraph that holds nothing but a page break prints no label in Word for Windows:
            // zh-7488a70f's empty "六、" item before "肆、討論事項" (numId 24, only <w:br w:type="page"/>) is a
            // blank line at the paragraph's own position in the print, and ours set "六、" 8.5pt lower.)
            let onlyPageBreak = DocxFormat.wordOnWindows && p.descendant("w:br").map { $0["w:type"] == "page" } == true
                && p.descendants("w:t").allSatisfy { $0.text.allSatisfy { $0 == " " || $0 == "\n" } }
                && p.descendant("w:drawing") == nil && p.descendant("w:pict") == nil && p.descendant("w:tab") == nil
            if let (numId, ilvl) = num, !onlyPageBreak {
                if numId != "0" {
                    style.list = nums[numId]?[ilvl] ?? nums[numId]?[0] ?? .bullet
                    style.listLevel = min(8, ilvl)
                    style.listId = numId
                    // The list's own indent replaces the style's — unless
                    // the paragraph states a left of its own, which Word
                    // puts above the level's.
                    let ownLeft = style.indentLeft - indent
                    style.indentLeft = indent
                    style.listIndentLeft = styleLeft
                    style.listFirstLine = styleFirst
                    if let ind = pPr.first("w:ind"), let v = Double(ind["w:left"] ?? ind["w:start"] ?? "") {
                        style.listIndentLeft = v / 20
                    }
                    if let ind = pPr.first("w:ind") {
                        if let v = Double(ind["w:hanging"] ?? "") { style.listFirstLine = -v / 20 }
                        else if let v = Double(ind["w:firstLine"] ?? "") { style.listFirstLine = v / 20 }
                    }
                    // (A level and a paragraph that state no first line, the
                    // paragraph saying a count of none, leave the style's twips
                    // in force: zh-60173bb6's "(2)" items start 27.8pt in.)
                    if DocxFormat.wordOnWindows, style.listFirstLine == nil, style.firstLineIndent > 0,
                       pPr.first("w:ind")?["w:firstLineChars"] == "0", pPr.first("w:ind")?["w:firstLine"] == nil,
                       notes.listFormats[numId]?[ilvl]?.hanging == nil {
                        RuleTrace.hit("word-list-item-keeps-the-styles-first-line")
                        style.listFirstLine = style.firstLineIndent
                    }
                    // (Neither the paragraph nor its level giving a left,
                    // the item keeps its style's — Word takes each of the
                    // indent's attributes from where it is given: zh-ea70c30e's
                    // "(c)" items, Body Text Indent 2 at 1440 over a level
                    // of firstLine 720 alone and a paragraph of hanging 720,
                    // stand at 72pt with their labels at 36 in Word's print;
                    // ours were at the margin.)
                    if style.listIndentLeft == nil, notes.listFormats[numId]?[ilvl]?.indentLeft == nil, ownLeft != 0 {
                        style.listIndentLeft = ownLeft
                    }
                }
            }
            if pPr.first("w:pageBreakBefore") != nil, !_isOff(pPr.first("w:pageBreakBefore")!) {
                style.pageBreakBefore = true
            }
            // (Not a break before a paragraph that is only a section's end,
            // with no run in it: zh-499adba6's contents section ends in an
            // empty Heading 2, and Word's print has no page for it — the
            // next section's page is the break; ours set it on a page alone.
            // A direct w:pageBreakBefore too: zh-ae2dd08d's landscape
            // 附表三 section ends in such a paragraph, and Word goes on to
            // the portrait 附表四 with no page between; ours printed one
            // with only its footer, and every page after was one late.)
            if style.pageBreakBefore, pPr.first("w:sectPr") != nil {
                func hasRun(_ n: XNode) -> Bool { n.children.contains { $0.name == "w:r" || hasRun($0) } }
                if !p.children.contains(where: { $0.name != "w:pPr" && ($0.name == "w:r" || hasRun($0)) }) { style.pageBreakBefore = false }
            }
            // A section ending here (its sectPr sits in this paragraph's
            // properties) starts the next on a new page unless continuous;
            // the section's own headers and page size are not kept, the
            // break is — Headers.docx had come back as one page of three.
            if let sect = pPr.first("w:sectPr") {
                // Whether a page breaks here is the NEXT section's type to
                // say (noted on the node by `read`): a section's w:type is
                // how that section starts. Read off this one's own, a
                // cover section before a "continuous" body pushed the
                // body to page two (a Lin'an draft, 22% over 17 pages).
                let breaks = sect.attrs.removeValue(forKey: "x-next-breaks").map { $0 == "1" }
                    ?? ((sect.first("w:type")?["w:val"] ?? "nextPage") != "continuous")
                if breaks { sectionBreakAfter = true }
                // (An empty paragraph that ends a section the next continues on the page has no space before in Word's print, its line stays:
                // lab sec1 (24 pt before: the text under it starts 24.0 pt higher than under a plain empty paragraph; with a letter in it the
                // space stays), pt-6c544802ed's 8.9 pt.)
                func hasRunHere(_ n: XNode) -> Bool { n.children.contains { $0.name == "w:r" || hasRunHere($0) } }
                if !breaks, RichTextTheme.wordWindowsPages, style.spaceBefore > 0,
                   !p.children.contains(where: { $0.name != "w:pPr" && ($0.name == "w:r" || hasRunHere($0)) }) { style.spaceBefore = 0 }
                sectionMarginsChange = sect.attrs.removeValue(forKey: "x-next-vmargins") == "1"
                style.sectionBreaksPage = breaks
                // The section's own page size, margins and columns, kept
                // for the file (bug65649: 15 sections, some landscape);
                // with the header and footer parts it names — the sections
                // after it that name none inherit them (a Yunnan county
                // notice whose last section states no header lost the
                // letterhead line on all 18 pages).
                // (A reference to a part the package does not hold goes.)
                sect.children.removeAll { ref in
                    guard ref.name == "w:headerReference" || ref.name == "w:footerReference" else { return false }
                    guard let rel = ref["r:id"].flatMap({ notes.rels[$0] }), !rel.external else { return true }
                    return notes.part(_resolvePath("word", rel.target)) == nil
                }
                style.sectionPage = _pageSetup(sect)
                // (A paragraph's section of one column of its own width, `w:equalWidth` 0 and a single
                // `w:col`, wraps at that width, not the margins': gv-d4270b921d's title block, 9230 twips
                // under a 9357 text width, ends 6.35 pt short of the margin in Word's print.)
                if RichTextTheme.wordWindowsPages, var setup = style.sectionPage, setup.columns == 1,
                   let cols = sect.first("w:cols"), ["0", "false", "off"].contains(cols["w:equalWidth"] ?? ""),
                   cols.all("w:col").count == 1, let tw = Double(cols.first("w:col")?["w:w"] ?? ""),
                   !setup.bidiSection, tw / 20 > 20, tw / 20 < setup.contentWidth - 1 {
                    setup.columnTrim += setup.contentWidth - tw / 20
                    setup.marginRight += setup.contentWidth - tw / 20
                    style.sectionPage = setup
                }
                let named = sect.children.contains { $0.name == "w:headerReference" || $0.name == "w:footerReference" }
                if named, let frag = _keptFragment(sect, notes) {
                    style.sectionXML = frag.xml
                    style.sectionRels = frag.rels
                } else {
                    sect.children.removeAll { $0.name == "w:headerReference" || $0.name == "w:footerReference" }
                    style.sectionXML = PptxXML.serialize(sect)
                }
            }
        }

        var built: [_Built] = []
        var text = ""
        var clearsFirstLine = false
        var bookmarkMarkers: [RichBookmarkMarker] = []
        var controlMarkers: [RichControlMarker] = []
        var runs: [Run] = []
        var positionalTabs: [Int: TabStop.Alignment] = [:]
        var inlineImages: [String: ImageAttachment] = [:]
        var leadingBreak = false   // the paragraph opens with a page break
        var cellBreakOpens = false   // …in a table cell, where the break itself is dropped
        var leadingColumnBreak = false   // ... and that break is a column break
        var leadingBreakRPr: String? = nil   // ... in a run with these properties
        var splitBefore = false   // the text being read is the rest of a split w:p
        func flush(pageBreakAfter: Bool) {
            var para: RichParagraph
            if inlineImages.count == 1, text == RichParagraph.inlineImageCharacter, let only = inlineImages.values.first {
                // A paragraph that is one picture and nothing else: the
                // editor's picture paragraph, with its handles.
                para = RichParagraph(image: only, style: style)
                // A paragraph of one ANCHORED picture has no text on its
                // line: its mark's font is its height, as for an empty one
                // (bib-chernigovka's title box sat in a 16pt paragraph).
                // (The anchor is a character of that line, set in its own run's font: a run that states no size is the paragraph style's, so a
                // mark stated smaller than that is not the height. dx2 b02602d2's picture paragraph, mark sz 20 over BodyText 16 bold, is a 19.3 pt
                // Tahoma Bold line in Word's print, not 12.1.)
                let styleSize = p.first("w:pPr")?.first("w:pStyle")?["w:val"].flatMap { styleIds[$0] }.flatMap { sheet[$0]?.char.fontSize }
                // (A run that STATES its size (the anchor's own run, sz 12 under BodyText 20) is that size whatever the mark says:
                // pt-ebe6f5b3cc's 6 pt picture paragraph is 6.9 pt tall in Word's print, ours stood the 10 pt style line, 4.6 pt more.
                // In a right-to-left paragraph the picture is a complex-script character: only szCs sizes it; dx2 b02602d2's bidi picture
                // paragraphs state sz 20 and stay the 16 pt style line.)
                let runIsBidi = p.first("w:pPr")?.first("w:bidi") != nil
                let runStatesSize = p.all("w:r").first { $0.first("w:drawing") != nil }?.first("w:rPr")?.first(runIsBidi ? "w:szCs" : "w:sz") != nil
                if let mark = markStyle, only.sourceXML?.containsSubstring("<wp:anchor") == true,
                   !(para.runs[0].style.fontSize == nil && !runStatesSize && styleSize != nil && mark.fontSize != nil && styleSize! > mark.fontSize!) { para.runs[0].style = mark }
                else if only.sourceXML?.containsSubstring("<wp:anchor") == true, para.runs[0].style.fontSize == nil, !runStatesSize, let z = styleSize { para.style.mark?.fontSize = z }
            } else {
                // (An empty cell paragraph under a table style that sets the size is as tall as that
                // size, not Normal's: lo-7c394e05's 8pt cells under a 12pt Normal.)
                let emptyInStyledCell = markStyle == nil && notes.cellSizeFromTable && cellChar.fontSize != nil
                if text.isEmpty, inlineImages.isEmpty, markStyle != nil || emptyInStyledCell || !notes.openComments.isEmpty {
                    // An empty paragraph takes its mark's look as its one
                    // run's style (its height); one inside a comment range
                    // carries the range too, or the writer would close
                    // and reopen it.
                    var cs = markStyle ?? cellChar
                    if !notes.openComments.isEmpty { cs.comments = notes.openComments }
                    para = RichParagraph(text: "", charStyle: cs, style: style)
                } else {
                    para = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: style)
                }
                para.inlineImages = inlineImages
            }
            para.style.contentsStart = notes.contentsStart
            para.style.contentsEnd = notes.contentsEnd
            notes.contentsStart = nil; notes.contentsEnd = false
            para.style.positionalTabs = positionalTabs
            para.style.clearsFirstLine = clearsFirstLine
            clearsFirstLine = false
            para.style.continuesParagraph = splitBefore
            splitBefore = false
            para.normalize()
            para.bookmarks = notes.pendingBookmarks
            notes.pendingBookmarks = []
            // Word's identity for the paragraph (eight hex digits); the
            // first piece of a w:p split at a page break carries it.
            if built.isEmpty, let hex = p["w14:paraId"], let id = UInt32(hex, radix: 16), id != 0 { para.id = id }
            para.bookmarkMarkers = notes.pendingBookmarkMarkers + bookmarkMarkers
            para.controlMarkers = controlMarkers
            controlMarkers = []
            notes.pendingBookmarkMarkers = []
            bookmarkMarkers = []
            built.append(_Built(paragraph: para, pageBreakAfter: pageBreakAfter))
            text = ""
            runs = []
            positionalTabs = [:]
            inlineImages = [:]
            style.pageBreakBefore = false
        }
        /// A picture or object in the line, where the text has it.
        var runPropertiesXML: String? = nil   // of the run being walked, for a picture in it
        var runRaised: Double? = nil          // its `w:position`, for a picture or object in it
        var runRevision: RevisionMark? = nil  // the change it is in (`w:del`, `w:ins`), for a picture or object in it
        var runFrame: BorderLine? = nil   // ... and its character border, a line of one
        func addInline(_ att: ImageAttachment, run base: CharStyle? = nil) {
            var att = att
            att.sourceRunPropertiesXML = runPropertiesXML
            // (A picture in the code of `IF PAGE = NUMPAGES` is its "then" text: the last page's.)
            if notes.inHeaderFooter, let outer = notes.fields.first, !outer.result,
               outer.instr.trimmingWhitespace(newlines: true).lowercased().hasPrefix("if"), outer.instr.containsSubstring("="),
               !outer.instr.containsSubstring("<>"), notes.nestedPageFields.contains("PAGE"), notes.nestedPageFields.contains("NUMPAGES") {
                RuleTrace.hit("picture-in-if-page-numpages-is-the-last-pages")
                att.lastPageOnly = true
            }
            if att.float == nil, att.sourceXML?.containsSubstring("<wp:anchor") != true { att.frame = runFrame }
            inlineImages[att.id] = att
            // (An embedded object keeps its run's look: the size of the text its line is set by.)
            var cs = base ?? CharStyle()
            cs.inlineImage = att.id
            cs.raised = runRaised
            cs.revision = runRevision
            addText(RichParagraph.inlineImageCharacter, cs)
        }
        /// A drawing that is not a picture (a chart, a shape, a diagram), an
        /// embedded object, a VML picture: kept as the file wrote it, with
        /// the parts it names, and shown as an empty box of its size.
        func addObject(_ node: XNode, run base: CharStyle? = nil) {
            if var att = objectAttachment(node) {
                att.inset = Self._canvasInset(node)
                // (Only an ActiveX control keeps its run's look: an embedded OLE picture, an equation, is placed as before — lo f225432f.)
                att.isActiveXControl = node.descendant("w:control") != nil
                addInline(att, run: att.isActiveXControl ? base : nil)
            }
        }
        /// The kept-verbatim attachment for `node`, or nil when a part it
        /// names is missing.
        func objectAttachment(_ node: XNode) -> ImageAttachment? {
            notes.shapeTypes += node.descendants("v:shapetype")
            // (A Word drawing canvas, `wpc:wpc`, holds its groups and shapes
            // side by side, in the canvas's own units; only the first group
            // was read. They are one group of the canvas's size: zh-f47b8a74
            // p58's flowchart printed one box of its twenty.)
            if let canvas = node.descendant("wpc:wpc"), canvas.descendant("wpg:wgp") != nil || canvas.descendant("wps:wsp") != nil,
               !canvas.children.contains(where: { $0.name == "wpg:wgp" && $0.attrs["synthetic"] != nil }),
               let extent = node.descendant("wp:extent"), let cx = extent["cx"], let cy = extent["cy"] {
                // (Its groups are nested ones in the group they make: `wpg:grpSp`.)
                let kept: [XNode] = canvas.children.filter { ["wpg:wgp", "wps:wsp"].contains($0.name) }.map { child in
                    guard child.name == "wpg:wgp" else { return child }
                    let nested = XNode(name: "wpg:grpSp", attrs: child.attrs)
                    nested.children = child.children
                    return nested
                }
                if !kept.isEmpty {
                    func el(_ name: String, _ attrs: [String: String] = [:], _ children: [XNode] = []) -> XNode {
                        let n = XNode(name: name, attrs: attrs)
                        n.children = children
                        return n
                    }
                    let frame = el("a:xfrm", [:], [el("a:off", ["x": "0", "y": "0"]), el("a:ext", ["cx": cx, "cy": cy]),
                                                   el("a:chOff", ["x": "0", "y": "0"]), el("a:chExt", ["cx": cx, "cy": cy])])
                    let group = el("wpg:wgp", ["synthetic": "1"], [el("wpg:cNvGrpSpPr"), el("wpg:grpSpPr", [:], [frame])] + kept)
                    canvas.children = canvas.children.filter { !["wpg:wgp", "wps:wsp"].contains($0.name) } + [group]
                }
            }
            var w = 300.0, h = 200.0
            var isRule = false
            if let extent = node.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx >= 0, cy >= 0, cx > 0 || cy > 0 {
                // (One of them may be nothing: a level line is no height.)
                w = cx / 12700
                h = cy / 12700
            } else if let line = _vmlTop(node), line.name == "v:line", RichTextTheme.wordWindowsPages,
                      let from = line["from"], let to = line["to"] {
                // (A VML line is the box between its two ends, not the
                // 300 by 200 of a shape with no size: a header's rule from
                // (0,34pt) to (595.3pt,34pt) is no height at all, and read
                // as 200pt tall it wrapped the body's first lines to the
                // right of it: gv-cd79f1fa6b's headings.)
                func point(_ s: String) -> (Double, Double)? {
                    let c = s.split(separator: ",")
                    guard c.count == 2, let x = _length(String(c[0]).trimmingWhitespace()), let y = _length(String(c[1]).trimmingWhitespace()) else { return nil }
                    return (x, y)
                }
                if let a = point(from), let b = point(to) {
                    w = abs(b.0 - a.0)
                    h = abs(b.1 - a.1)
                }
            } else if let shape = _vmlTop(node), shape.name != "v:line", let st = shape["style"] {
                for pair in st.split(separator: ";") {
                    let kv = pair.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2, let v = _length(String(kv[1])), v >= 0 else { continue }
                    // (A height of 0 is a straight line's — a connector `v:shape` of
                    // 500pt by 0pt — not an absent one: read as absent it stood the
                    // 300 by 200 stand-in, a row 188pt too tall in es-e3d5fed41c.)
                    if kv[0].trimmingWhitespace() == "width", v > 0 { w = v } else if kv[0].trimmingWhitespace() == "height" { h = max(v, 0.01) }
                }
                // (A horizontal rule — an HTML page's <hr>, `o:hr` — is a
                // line of its height across the column, its width 0 in the
                // file; read as 300 by 200, bug57031's took a 200pt box and
                // pushed its SAS tables a page on.)
                if shape["o:hr"] == "t" {
                    // (… and its line is a line of text: Word gives the
                    // paragraph its text's height whatever the rule's —
                    // lab `hr`, rules of 1.5, 2.25 and 6pt each in a line
                    // of Arial 10's 11.5 — and draws the rule across its
                    // middle. "hr", which the layout sets no taller than
                    // its text.)
                    w = 0.01
                    h = 0.01
                    isRule = true
                }
                // (A VML picture is set at whole points: zh-64044a1d's flow
                // charts, 410.5 by 396.45 and 419.85 by 417.95 in their
                // styles, are 410 by 396 and 420 by 418 in Word's print —
                // and at 396 the first fits 22 pitches of its 18pt grid
                // exactly, where 396.45 took a 23rd and set its caption and
                // page 18pt low.)
                // (Not for Word for Windows' print, which keeps zh-64044a1d's figure at 396.3 — its cell line is
                // the 23 pitches, 414pt, that 396.45 needs, 9.3pt above the picture and 9.4 below — and 410.4 wide.)
                if !isRule, !RichTextTheme.wordWindowsPages, shape.first("v:imagedata") != nil, node.descendant("v:textbox") == nil {
                    w = max(1, (w - 0.001).rounded())
                    h = max(1, (h - 0.001).rounded())
                }
            }
            guard let frag = _keptFragment(node, notes) else { return nil }   // a part it names is missing
            var att = ImageAttachment(data: Data(), width: w, height: h, name: isRule ? "hr" : node.name)
            // (Its effect extent, as a picture's: its line holds that too.
            // zh-547fc43c's 233.75pt chart and 1.75pt of effects take 16
            // pitches of a 15.6pt grid in Word's print, not 15.)
            if let effect = node.descendant("wp:inline")?.first("wp:effectExtent") {
                att.effectLeft = max(0, (Double(effect["l"] ?? "") ?? 0) / 12700)
                att.effectRight = max(0, (Double(effect["r"] ?? "") ?? 0) / 12700)
                att.effectTop = max(0, (Double(effect["t"] ?? "") ?? 0) / 12700)
                att.effectBottom = max(0, (Double(effect["b"] ?? "") ?? 0) / 12700)
            }
            att.sourceXML = frag.xml
            att.sourceRels = frag.rels
            // (A SmartArt diagram is read as the group of shapes Word drew
            // it as, after its markup is kept for the save: zh-77079ee8's
            // organisation chart — 22 boxes and connectors in its drawing
            // part — printed nothing at all.)
            if let ids = node.descendant("dgm:relIds"), let graphic = node.descendant("a:graphicData"),
               let dm = ids["r:dm"].flatMap({ notes.rels[$0] }), !dm.external,
               let model = notes.part(_resolvePath("word", dm.target)).flatMap(XNode.parse) {
                var group: XNode? = nil
                if let rid = model.descendant("dsp:dataModelExt")?["relId"], let rel = notes.rels[rid], !rel.external,
                   let drawing = notes.part(_resolvePath("word", rel.target)).flatMap(XNode.parse) {
                    group = Self._diagramGroup(drawing, cx: w * 12700, cy: h * 12700)
                    if let g = group, let theme = notes.themeFonts { Self._resolveThemeFonts(g, theme) }
                }
                // (No drawing part, as in a file LibreOffice wrote: laid out
                // here from the data and the layout definition, as the deck
                // reader does, and read as the same group of shapes —
                // fdo79822's process diagram printed nothing.)
                if group == nil, let lo = ids["r:lo"].flatMap({ notes.rels[$0] }), !lo.external,
                   let layoutDef = notes.part(_resolvePath("word", lo.target)).flatMap(XNode.parse) {
                    func part(_ key: String) -> XNode? {
                        ids[key].flatMap { notes.rels[$0] }.flatMap { $0.external ? nil : notes.part(_resolvePath("word", $0.target)) }.flatMap(XNode.parse)
                    }
                    if let tree = DiagramLayout.render(data: model, layout: layoutDef, colors: part("r:cs"), style: part("r:qs"),
                                                       frame: Rect.fromLTWH(0, 0, w, h), word: true) {
                        func renamed(_ n: XNode) -> XNode {
                            let c = XNode(name: n.name.hasPrefix("p:") ? "dsp:" + n.name.dropFirst(2) : n.name, attrs: n.attrs)
                            c.text = n.text
                            c.children = n.children.map(renamed)
                            return c
                        }
                        let drawing = XNode(name: "dsp:drawing", attrs: [:])
                        drawing.children = [renamed(tree)]
                        group = Self._diagramGroup(drawing, cx: w * 12700, cy: h * 12700)
                        if let g = group, let theme = notes.themeFonts { Self._resolveThemeFonts(g, theme) }
                    }
                }
                if let group {
                    graphic.children = [group]
                    graphic.attrs["uri"] = "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup"
                }
            }
            att.float = _float(node)
            // (WordArt — a VML textpath — in its line, under Word for
            // Windows: the line holds more than the shape's box, by its
            // outline's weight and its shadow's drop, the larger of the
            // two; `_wordArtExtra` has lab wae's numbers, measured from
            // the box. Lab wa4's, measured from ours, put WordArt's
            // effect too high by a 1pt outline and by any shadow:
            // WordWithAttachments' p1 stood 2.5pt high after its three
            // titles and took its p2 icon.)
            if Self.wordOnWindows, att.float == nil, let shape = Self._vmlTop(node), let extra = Self._wordArtExtra(shape, types: notes.shapeTypes) {
                att.effectTop += extra
            }
            // (A VML shape's stroke, which an autofit column holds past the
            // shape's box: lab e3fit2, Word for Windows, a 500pt line in a
            // cell of no width widens its column by 1.5 at strokes of 0.25
            // and 1.25pt, by 3 and 6 at 3 and 6pt, and by none unstroked; a
            // filled rectangle by none unstroked, 2.25 at 2pt and 6 at 6pt.
            // Not a picture (`v:imagedata`), nor a DrawingML shape.)
            if att.float == nil, node.descendant("wp:inline") == nil, let shape = Self._vmlTop(node), shape.first("v:imagedata") == nil {
                let id = shape["type"].map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                let type = id.flatMap { id in notes.shapeTypes.first { $0["id"] == id } }
                let stroke = shape.first("v:stroke")
                let off = ["f", "false", "0"]
                if !off.contains(shape["stroked"] ?? type?["stroked"] ?? "t"), !off.contains(stroke?["on"] ?? "t") {
                    att.strokeReach = max(Self._length(shape["strokeweight"] ?? stroke?["weight"] ?? "") ?? 0.75, 1.5)
                }
            }
            // (A level line — no height — takes no room in the line whatever
            // its wrapping: zh-f47b8a74's red rules under its letterhead,
            // two lines wrapped top and bottom in an empty paragraph, are
            // drawn in Word's print over that paragraph's own 28pt line;
            // set in the line at their size they made it none, drew
            // nothing, and every line after stood 30pt high.)
            if h == 0, att.float?.takesRoom == true { att.float?.takesRoom = false }
            // A straight line or a plain box, drawn by the layout: its
            // line's width and colour (`a:ln`), and a solid fill.
            // (Not a group's: its first child's shape is not the group's —
            // see `WriterGroups`.)
            if node.descendant("wpg:wgp") == nil, let sp = node.descendant("wps:spPr"), let geom = sp.first("a:prstGeom")?["prst"],
               ["line", "straightConnector1", "rect"].contains(geom) {
                // (A theme's colour too: 60316's divider is accent2, grey in
                // Word's print, where ours fell back to black.)
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                let colors = ColorContext(theme: PptxTheme(notes.part(_resolvePath("word", themeTarget)).flatMap { XNode.parse($0) }))
                func rgb(_ n: XNode?) -> Color? {
                    guard let fill = n?.first("a:solidFill") else { return nil }
                    // (An `a:alpha` child is how much of it shows: 0 draws nothing.)
                    func shown(_ c: Color, _ n: XNode?) -> Color {
                        guard RichTextTheme.wordWindowsPages, let a = n?.first("a:alpha")?["val"].flatMap(Double.init) else { return c }
                        return Color((Int64((max(0, min(1, a / 100_000)) * Double(c.alpha)).rounded()) << 24) | Int64(c.value & 0xFFFFFF))
                    }
                    if let clr = fill.first("a:srgbClr"), let hex = clr["val"], let v = Int64(hex, radix: 16) { return shown(Color(0xFF00_0000 | v), clr) }
                    // (A system colour, e.g. window = white: its lastClr.)
                    if let clr = fill.first("a:sysClr"), let hex = clr["lastClr"], let v = Int64(hex, radix: 16) { return shown(Color(0xFF00_0000 | v), clr) }
                    return fill.first("a:schemeClr") != nil ? colors.color(in: fill).map { shown($0, fill.first("a:schemeClr")) } : nil
                }
                let ln = sp.first("a:ln")
                var outline = ShapeOutline(kind: geom == "rect" ? .box : .line,
                                           color: ln?.first("a:noFill") != nil ? nil : (rgb(ln) ?? (ln != nil ? Color(0xFF000000) : nil)),
                                           width: (Double(ln?["w"] ?? "") ?? 9525) / 12700)
                outline.fill = rgb(sp)
                outline.flipped = sp.first("a:xfrm")?["flipV"] == "1"
                // Its effects (F14, Word's print): a colour laid over the fill
                // and blended into it, a blur, an inner shadow.
                if geom == "rect", let effects = sp.first("a:effectLst") {
                    func effectColor(_ n: XNode?) -> Color? {
                        guard let n else { return nil }
                        if let c = n.first("a:scrgbClr") {
                            // (Linear 0-100000 per channel, to sRGB.)
                            func ch(_ k: String) -> Int64 {
                                let l = max(0, min(1, (Double(c[k] ?? "") ?? 0) / 100_000))
                                let v = l <= 0.0031308 ? 12.92 * l : 1.055 * pow(l, 1 / 2.4) - 0.055
                                return Int64((v * 255).rounded())
                            }
                            let alpha = (Double(c.first("a:alpha")?["val"] ?? "") ?? 100_000) / 100_000
                            return Color(Int64((alpha * 255).rounded()) << 24 | ch("r") << 16 | ch("g") << 8 | ch("b"))
                        }
                        return colors.color(in: n)
                    }
                    if let o = effects.first("a:fillOverlay"), let base = outline.fill, let over = effectColor(o.first("a:solidFill")) {
                        let mode = o["blend"] ?? "over"
                        func blend(_ b: Int, _ o: Int) -> Double {
                            let b = Double(b) / 255, o = Double(o) / 255
                            switch mode {
                            case "mult": return b * o
                            case "screen": return 1 - (1 - b) * (1 - o)
                            case "darken": return min(b, o)
                            case "lighten": return max(b, o)
                            default: return o
                            }
                        }
                        let a = Double(over.alpha) / 255
                        func mix(_ b: Int, _ o: Int) -> Int64 { Int64(((blend(b, o) * a + Double(b) / 255 * (1 - a)) * 255).rounded()) }
                        outline.fill = Color(Int64(base.alpha) << 24 | mix(base.red, over.red) << 16 | mix(base.green, over.green) << 8 | mix(base.blue, over.blue))
                    }
                    if let r = Double(effects.first("a:blur")?["rad"] ?? ""), r > 0 { outline.blur = r / 12700 }
                    if let sh = effects.first("a:innerShdw"), let c = effectColor(sh) {
                        let dist = (Double(sh["dist"] ?? "") ?? 0) / 12700, dir = (Double(sh["dir"] ?? "") ?? 0) / 60000 * .pi / 180
                        outline.innerShadow = (c, dist * cos(dir), dist * sin(dir), (Double(sh["blurRad"] ?? "") ?? 0) / 12700)
                    }
                }
                if outline.color != nil || outline.fill != nil { att.outline = outline }
            }
            // Warped text belongs to the shape painter, with its rotation
            // and fitted envelope. Read its styles through the same Word
            // reader, but leave the body's notes and field state alone.
            var drawingWordArt: [ObjectIdentifier: WriterGroups.DrawingWordArt] = [:]
            if !notes.inTextBox, node.descendant("wpg:wgp") != nil || att.outline == nil {
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                             notes.seenComments, notes.fieldShown)
                notes.inTextBox = true
                defer {
                    notes.inTextBox = false
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                     notes.seenComments, notes.fieldShown) = saved
                }
                for shape in node.descendants("wps:wsp") {
                    guard let warp = WriterGroups.textWarp(shape),
                          // (Word for Windows sets a slanted text box that is turned as plain glyphs, turned: zh-b24b396a's
                          // "（全宗名称）" — see `RichTextBox.Part.rotation`.)
                          !(Self.wordOnWindows && warp.preset == "textSlantDown" && shape.first("wps:spPr")?.first("a:xfrm")?["rot"] != nil),
                          let content = shape.first("wps:txbx")?.first("w:txbxContent") else { continue }
                    notes.fields = []
                    let paragraphs = content.all("w:p").flatMap {
                        _paragraphs($0, base, styleIds, styleNums, sheet, nums, rels, media, 0, notes, CharStyle(), nil).map(\.paragraph)
                    }
                    if paragraphs.contains(where: { !$0.text.isEmpty }) {
                        let body = shape.first("wps:bodyPr")
                        func inset(_ name: String, _ fallback: Double) -> Double { Double(body?[name] ?? "").map { $0 / 12700 } ?? fallback }
                        let insets = EdgeInsets.fromLTRB(inset("lIns", 7.2), inset("tIns", 3.6), inset("rIns", 7.2), inset("bIns", 3.6))
                        drawingWordArt[ObjectIdentifier(shape)] = WriterGroups.DrawingWordArt(warp: warp, paragraphs: paragraphs, styles: sheet, insets: insets)
                    }
                }
            }
            func textBoxContent(_ n: XNode) -> XNode? {
                if drawingWordArt[ObjectIdentifier(n)] != nil { return nil }
                // (The VML twin of a drawing whose text is warped is that text again, plain.)
                if n.name == "mc:Fallback", !drawingWordArt.isEmpty { return nil }
                if n.name == "w:txbxContent" { return n }
                for child in n.children { if let content = textBoxContent(child) { return content } }
                return nil
            }
            // A text box's text, for the layout to set in it: the
            // drawing's (`wps:txbx`), or its VML twin's.
            if !notes.inTextBox, let content = textBoxContent(node) {
                notes.inTextBox = true
                // (The box's markup is kept whole and written back as it
                // was: reading its text again must leave no mark on what
                // the body's own reading counts — notes, comments,
                // bookmarks, open fields.)
                let saved = (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                             notes.seenComments, notes.fieldShown)
                defer {
                    (notes.seenFootnotes, notes.seenEndnotes, notes.openComments, notes.pendingBookmarks, notes.pendingBookmarkMarkers, notes.fields,
                     notes.seenComments, notes.fieldShown) = saved
                }
                notes.fields = []
                var inside: [RichParagraph] = []
                var holdsTable = false
                func read(_ content: XNode) {
                    var stack = Array(content.children.reversed())
                    while let n = stack.popLast() {
                        if n.name == "w:p" {
                            // (A text box's paragraphs take nothing of the
                            // table its anchor stands in: zh-e2dc9dce's
                            // flow-chart boxes, anchored in cells of a table
                            // styled at 10pt, print at the defaults' 12pt —
                            // lab `ts`, Word for Mac.)
                            for b in _paragraphs(n, notes.cellBoxBase ?? base, styleIds, styleNums, sheet, nums, rels, media, 0, notes, CharStyle(), nil) { inside.append(b.paragraph) }
                        } else if n.name != "w:tbl" {
                            stack.append(contentsOf: n.children.reversed())
                        } else {
                            holdsTable = true
                        }
                    }
                }
                read(content)
                // (A group of text boxes one above another, as wide as
                // the group: each box's text from its own place in it.
                // 60316's résumé sidebar is a name box over an address box
                // whose text stands at its foot; only the first was read.)
                var parts: [RichTextBox.Part] = []
                var perPart = false
                var ownShape: XNode? = nil   // the shape in a drawing group that holds this text
                if let group = node.descendant("wpg:wgp") {
                    // (The boxes of the groups in it too, each at its place
                    // in the group: zh-ae2dd08d p21's flowchart nests its
                    // boxes two groups deep, and ours read only the first
                    // box's text, set across the whole group.)
                    let placed = Self._groupTextBoxes(group).filter { drawingWordArt[ObjectIdentifier($0.box)] == nil }
                    let boxes = placed.map(\.box)
                    ownShape = boxes.first(where: { $0.descendant("w:txbxContent") === content })
                    let gx = group.first("wpg:grpSpPr")?.first("a:xfrm")
                    let ext = Double(gx?.first("a:ext")?["cy"] ?? "") ?? 0, chExt = Double(gx?.first("a:chExt")?["cy"] ?? "") ?? 0
                    let k = chExt > 0 && ext > 0 ? ext / chExt : 1
                    let widths = placed.map(\.place.width)
                    let lefts = placed.map(\.place.left)
                    if boxes.count > 1, boxes[0].descendant("w:txbxContent") === content,
                       Set(widths).count == 1, Set(lefts).count == 1, widths[0] > 0 {
                        // (From the group's own origin, `a:chOff`: zh-799c91cd's
                        // envelope stamp box, 850 units under "掛號" in a group
                        // whose children start at 851, stood 40pt low.)
                        let oy = Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0
                        // (Each box's text under its own top inset, where the
                        // box as a whole takes the first's: the stamp box's
                        // 3.6pt under "掛號"'s none stood its text 3.8pt high.)
                        func topInset(_ b: XNode) -> Double { (Double(b.first("wps:bodyPr")?["tIns"] ?? "").map { $0 / 12700 } ?? 3.6) + Self._halfOutline(b.first("wps:spPr")) }
                        let firstInset = topInset(boxes[0])
                        for (b, place) in placed.dropFirst() {
                            let first = inside.count
                            read(b.descendant("w:txbxContent")!)
                            parts.append(RichTextBox.Part(first: first, top: (place.top - oy) * k / 12700 + topInset(b) - firstInset,
                                                          height: place.height * k / 12700,
                                                          atFoot: b.first("wps:bodyPr")?["anchor"] == "b"))
                        }
                    } else if !boxes.isEmpty, boxes.count > 1 || !drawingWordArt.isEmpty
                                // (A lone box that is not the group's whole child frame: one at the group's top edge but off its left,
                                // narrower or shorter is set from its own offset and scale as Word draws it; dx2 9d7e8c61's circled "1",
                                // lab 2 boxes G, K and L at 315 / 307.6 / 315 where the group's origin put them at 300.)
                                || (placed[0].place.top - (Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0) > 1)
                                || (placed.count == 1 && gx != nil && (
                                    abs(placed[0].place.left - (Double(gx?.first("a:chOff")?["x"] ?? "") ?? 0)) > 1
                                    || abs(placed[0].place.width - (Double(gx?.first("a:chExt")?["cx"] ?? "") ?? 0)) > 1
                                    || abs(placed[0].place.height - (Double(gx?.first("a:chExt")?["cy"] ?? "") ?? 0)) > 1)),
                              boxes[0].descendant("w:txbxContent") === content {
                        // (A single box lower in its group is one of these too:
                        // lo tdf126426's white box at the foot of a page-size
                        // photo set its line at the group's top.)
                        // (Boxes of other widths or places: each box's text
                        // in its own column of the group, from its own top —
                        // its shape's place, the preset's text rectangle and
                        // its insets. shapes-with-text's group is an arrow
                        // with "A group of shapes" in it and a text box
                        // under it: the arrow's text stood at the group's
                        // left, 85pt from Word's, and the box's was never
                        // read.)
                        perPart = true
                        var partTables: [Int: (content: XNode, left: Double, right: Double, inset: Double)] = [:]
                        defer { if !partTables.isEmpty { notes.boxPartTables[att.id] = partTables } }
                        let kx = Double(gx?.first("a:chExt")?["cx"] ?? "").flatMap { c in Double(gx?.first("a:ext")?["cx"] ?? "").map { c > 0 ? $0 / c : 1 } } ?? 1
                        let ox = Double(gx?.first("a:chOff")?["x"] ?? "") ?? 0, oy = Double(gx?.first("a:chOff")?["y"] ?? "") ?? 0
                        let groupWidth = (Double(gx?.first("a:ext")?["cx"] ?? "") ?? 0) / 12700
                        for (n, (b, place)) in placed.enumerated() {
                            let x = (place.left - ox) * kx / 12700
                            let y = (place.top - oy) * k / 12700
                            let w = place.width * kx / 12700
                            let h = place.height * k / 12700
                            let body = b.first("wps:bodyPr")
                            var l = Double(body?["lIns"] ?? "").map { $0 / 12700 } ?? 7.2, t = Double(body?["tIns"] ?? "").map { $0 / 12700 } ?? 3.6
                            var r = Double(body?["rIns"] ?? "").map { $0 / 12700 } ?? 7.2, bottom = Double(body?["bIns"] ?? "").map { $0 / 12700 } ?? 3.6
                            let half = Self._halfOutline(b.first("wps:spPr"))
                            l += half; t += half; r += half; bottom += half
                            if let geom = b.first("wps:spPr")?.first("a:prstGeom"), let prst = geom["prst"], prst != "rect", w > 0, h > 0,
                               let g = PresetGeometry.geometry(prst, width: w * 12700, height: h * 12700, adjustments: PresetGeometry.adjustments(geom)),
                               let rect = g.textRect {
                                l += rect.left * w; t += rect.top * h
                                r += (1 - rect.right) * w; bottom += (1 - rect.bottom) * h
                            } else if let geom = b.first("wps:spPr")?.first("a:custGeom"), w > 0, h > 0,
                                      // (A freeform's own text rectangle, its `a:rect` over
                                      // its guides: zh-ae2dd08d's flowchart diamonds wrap
                                      // "是否通過TTQS評核" in their middle half in Word's
                                      // print, three lines where the whole box held one.)
                                      let rect = FreeformGeometry.parse(geom, width: w * 12700, height: h * 12700)?.textRect {
                                l += rect.left * w; t += rect.top * h
                                r += (1 - rect.right) * w; bottom += (1 - rect.bottom) * h
                            }
                            let first = n == 0 ? 0 : inside.count
                            let holdsBefore = holdsTable
                            if n > 0 { holdsTable = false; read(b.descendant("w:txbxContent")!) }
                            // (A box of a table: read again with its tables where the
                            // group's text is set — lo-aeacc79b45's two score-sheet
                            // boxes side by side, 20 rows each, drew none.)
                            if holdsTable, n > 0 || holdsBefore, let own = b.descendant("w:txbxContent") {
                                partTables[n] = (own, x + l, max(0, groupWidth - (x + w) + r), r)
                            }
                            holdsTable = holdsTable || holdsBefore
                            for q in first ..< inside.count where Self.wordOnWindows && inside[q].style.rightToLeft {
                                // (A right-to-left paragraph's indents run from its right edge:
                                // the box's place is physical, so its two sides trade. bf53d2b7's
                                // footer diagram stood mirrored, "מבוא" at the left.)
                                inside[q].style.indentLeft += max(0, groupWidth - (x + w) + r)
                                inside[q].style.indentRight += x + l
                                inside[q].style.boxInsetRight = l
                            }
                            for q in first ..< inside.count where !(Self.wordOnWindows && inside[q].style.rightToLeft) {
                                inside[q].style.indentLeft += x + l
                                // (A list's number and text stand at its own left: moved with the box's.)
                                if let own = inside[q].style.listIndentLeft ?? Self._levelLeft(inside[q].style, notes) { inside[q].style.listIndentLeft = own + x + l }
                                inside[q].style.indentRight += max(0, groupWidth - (x + w) + r)
                                inside[q].style.boxInsetRight = r
                            }
                            // (Or in its middle: zh-77079ee8's organisation chart, a
                            // SmartArt whose boxes centre "工作圈" and the
                            // one-line "工作" over "服務組" in Word's print.)
                            var part = RichTextBox.Part(first: first, top: y + t, height: max(0, h - t - bottom), atFoot: body?["anchor"] == "b",
                                                        inMiddle: body?["anchor"] == "ctr")
                            // (A box turned in its group: about its middle, in the
                            // frame's place.)
                            if Self.wordOnWindows, let rot = b.first("wps:spPr")?.first("a:xfrm")?["rot"].flatMap({ Double($0) }), rot != 0 {
                                part.rotation = rot / 60000
                                part.pivotX = x + w / 2
                                part.pivotY = y + h / 2
                            }
                            parts.append(part)
                        }
                    }
                } else if let group = Self._vmlTop(node), group.name == "v:group",
                          case let places = Self._vmlTextPlaces(group, types: notes.shapeTypes), places.count > 1, places[0].content === content {
                    // (A VML group of text boxes alike: each box's text at its
                    // own place in the group. zh-6e6b9821 p3's flowchart is a
                    // group of eleven boxes and ten arrows; ours set the first
                    // box's text across the group and read no other.)
                    perPart = true
                    for (n, b) in places.enumerated() {
                        let first = n == 0 ? 0 : inside.count
                        if n > 0 { read(b.content) }
                        for q in first ..< inside.count {
                            inside[q].style.indentLeft += b.place.left
                            if let own = inside[q].style.listIndentLeft ?? Self._levelLeft(inside[q].style, notes) { inside[q].style.listIndentLeft = own + b.place.left }
                            inside[q].style.indentRight += max(0, att.width - b.place.right)
                        }
                        parts.append(RichTextBox.Part(first: first, top: b.place.top, height: max(0, b.place.height), atFoot: b.atFoot, inMiddle: b.inMiddle))
                    }
                }
                notes.inTextBox = false
                // (Or empty, where it is fitted to its text's height: as
                // tall as its empty lines — see `RichTextBox.fitsHeight`.)
                let fitsHeight = (node.descendant("v:textbox")?["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t")
                    && !(((node.name == "v:shape" ? node : node.descendant("v:shape"))?["style"] ?? "").containsSubstring("mso-wrap-style:none"))
                // (A picture or a chart is a box's content too: fdo78474's three boxes
                // hold one each and no text, and were dropped as empty.)
                if inside.contains(where: { !$0.text.isEmpty || $0.image != nil || !$0.inlineImages.isEmpty }) || (holdsTable && parts.isEmpty) || (fitsHeight && !inside.isEmpty && parts.isEmpty) {
                    var box = RichTextBox(paragraphs: inside)
                    if holdsTable, parts.isEmpty { notes.boxTables[att.id] = content }
                    box.parts = parts
                    if perPart {
                        // (Each part carries its own place: the group's
                        // box has no insets of its own.)
                        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                    } else if let body = ownShape?.first("wps:bodyPr") ?? node.descendant("wps:bodyPr") {
                        // (Its own insets, not the first shape's of the group: zh-bdae17c0 p69's outline box is
                        // a text box of none after a border line of the default 3.6pt, and its text stood 3.9 low.)
                        box.hasFixedFrame = body.first("a:noAutofit") != nil
                        if let anchor = body["anchor"], anchor == "ctr" || anchor == "b" { box.anchor = anchor }
                        // (Not where the body says `upright`: its text stays level in the turned shape, as
                        // zh-b24b396a's "（文件正面）" does in Word's print.)
                        if body["upright"] != "1", let xfrm = node.descendant("wps:spPr")?.first("a:xfrm") {
                            // (A shape flipped top to bottom turns its text over: a 180-degree shape with both flips, ja-b852b9029c's
                            // vertical boxes, reads upright in Word's print.)
                            let rot = (xfrm["rot"].flatMap { Double($0) } ?? 0) / 60000 + (xfrm["flipV"] == "1" ? 180 : 0)
                            let turn = rot.truncatingRemainder(dividingBy: 360)
                            if turn != 0 { box.shapeRotation = turn }
                        }
                        box.fitsText = body["wrap"] == "none" && body.first("a:spAutoFit") != nil
                        box.fitsOnce = box.fitsText
                        box.noWrap = body["wrap"] == "none" && body.first("a:spAutoFit") == nil && body.first("a:noAutofit") != nil
                        // (Not a group: its anchor is the whole group, text box and chart together, not the box alone: lo-40949e852ad9c2fe.)
                        box.autoHeight = body.first("a:spAutoFit") != nil && node.descendant("wpg:wgp") == nil
                        box.fitsAsDrawing = box.fitsText
                        if let v = Double(body["lIns"] ?? "") { box.insetLeft = v / 12700 }
                        if let v = Double(body["tIns"] ?? "") { box.insetTop = v / 12700 }
                        if let v = Double(body["rIns"] ?? "") { box.insetRight = v / 12700 }
                        if let v = Double(body["bIns"] ?? "") { box.insetBottom = v / 12700 }
                        // (And half its outline's width, drawn or not: lab
                        // `c60` (Word for Windows, 60316's package) moves
                        // the text of a box with no fill to its outline
                        // 0.24pt down and right for a 0.5pt one, 0.96 for
                        // 2pt, 3.96 for 8pt, and not at all with none —
                        // 60316's "Allison" line, 0.24 under the same line
                        // set in the body.)
                        let half = Self._halfOutline(ownShape?.first("wps:spPr") ?? node.descendant("wps:spPr"))
                        box.insetLeft += half; box.insetTop += half; box.insetRight += half; box.insetBottom += half
                        // (Turned text: zh-b24b396a's drawing labels "20",
                        // "36" and "297" are `vert270` boxes 10.5pt wide and
                        // 21 tall, read upward in Word's print; across, "297"
                        // wrapped in the 10.5pt.)
                        // (And `eaVert`, East Asian vertical writing: down as
                        // `vert`, an ideograph upright in it. zh-c4f2be3b's
                        // landscape pages number themselves in an `eaVert`
                        // box at the page's left, "- 33 -" reading down in
                        // Word's print; ours set it across.)
                        switch body["vert"] {
                        case "vert270": box.textDirection = .up
                        case "vert": box.textDirection = .down
                        case "eaVert": box.textDirection = .down; box.uprightIdeographs = true
                        default: break
                        }
                        // (A shape that is not a rectangle sets its text in
                        // the preset's text rectangle, as Slides does: Word
                        // wraps shapes-with-text's "An ellipse with text
                        // inside" in the ellipse's inscribed box, two lines
                        // where the whole box held one.)
                        if let geom = node.descendant("a:prstGeom"), let prst = geom["prst"], prst != "rect",
                           att.width > 0, att.height > 0,
                           let g = PresetGeometry.geometry(prst, width: att.width * 12700, height: att.height * 12700,
                                                           adjustments: PresetGeometry.adjustments(geom)),
                           let r = g.textRect {
                            box.insetLeft += r.left * att.width
                            box.insetTop += r.top * att.height
                            box.insetRight += (1 - r.right) * att.width
                            box.insetBottom += (1 - r.bottom) * att.height
                        } else if node.descendant("a:prstGeom") == nil, let geom = node.descendant("a:custGeom"),
                                  att.width > 0, att.height > 0,
                                  let r = FreeformGeometry.parse(geom, width: att.width * 12700, height: att.height * 12700)?.textRect {
                            box.insetLeft += r.left * att.width
                            box.insetTop += r.top * att.height
                            box.insetRight += (1 - r.right) * att.width
                            box.insetBottom += (1 - r.bottom) * att.height
                        }
                    } else if let group = Self._vmlTop(node), group.name == "v:group", let place = Self._vmlTextPlace(group) {
                        // (A text box in a VML group: its text at the box's
                        // own place in the group, inside its insets.)
                        if (node.descendant("v:textbox")?["style"] ?? "").containsSubstring("layout-flow:vertical") {
                            // (Turned text takes the place as the box's
                            // insets, which stay on the page's sides as the
                            // text turns; a paragraph's indents turn with it.
                            // lo-83c47ec6's sidebar, a turned text box in a
                            // group in a group, reads down at 579pt in Word's print.)
                            box.insetLeft = place.left; box.insetTop = place.top
                            box.insetRight = max(0, att.width - place.right); box.insetBottom = max(0, att.height - place.bottom)
                        } else {
                        for q in box.paragraphs.indices {
                            box.paragraphs[q].style.indentLeft += place.left
                            box.paragraphs[q].style.indentRight += max(0, att.width - place.right)
                        }
                        box.parts = [RichTextBox.Part(first: 0, top: place.top, height: max(0, place.bottom - place.top), atFoot: false)]
                        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
                        }
                    } else if let textbox = node.descendant("v:textbox"), let inset = textbox["inset"] {
                        // (A `v:rect` as well as a `v:shape`: zh-e02b0479's footer page
                        // number is a 144pt rect, centred, wrap none and fitted to its
                        // text, which Word for Windows centres as the "1" alone; ours
                        // centred the 144pt and set the "1" at its left, 72pt off.)
                        let shapeStyle = (node.name == "v:shape" || node.name == "v:rect" || (node.name == "v:oval" && RichTextTheme.wordWindowsPages) ? node
                            : node.descendant("v:shape") ?? node.descendant("v:rect") ?? (RichTextTheme.wordWindowsPages ? node.descendant("v:oval") : nil))?["style"] ?? ""
                        // (… and without it, in Word for Windows' print: lo-ff3b52d1's rect and oval,
                        // `mso-wrap-style:none` and nothing else, are drawn 77.3pt wide for a text
                        // 76.6 wide, and 102.3 for the oval's 140 declared; lab oval.)
                        box.fitsText = shapeStyle.containsSubstring("mso-wrap-style:none")
                            && ((textbox["style"] ?? "").containsSubstring("mso-fit-shape-to-text:t") || RichTextTheme.wordWindowsPages)
                        box.fitsOnce = box.fitsText   // (lab `vf`: sized once, as DrawingML's)
                        let parts = inset.split(separator: ",", omittingEmptySubsequences: false).map { _length(String($0).trimmingWhitespace()) }
                        if parts.count > 0, let v = parts[0] { box.insetLeft = v }
                        if parts.count > 1, let v = parts[1] { box.insetTop = v }
                        if parts.count > 2, let v = parts[2] { box.insetRight = v }
                        if parts.count > 3, let v = parts[3] { box.insetBottom = v }
                    }
                    // (Half the outline's width too, as DrawingML's above: sa1 5e813226's 1pt
                    // rects and rounded boxes hold their text 0.4 to 0.5 below ours.)
                    if !perPart, node.descendant("wps:bodyPr") == nil, node.descendant("v:textbox") != nil,
                       let vs = (node.name == "v:rect" || node.name == "v:oval" ? node : node.descendant("v:rect") ?? node.descendant("v:oval")
                            ?? (node.name == "v:shape" ? node : node.descendant("v:shape")).flatMap { $0["strokeweight"] != nil && (($0["type"] ?? "").hasSuffix("_x0000_t202") || ($0["o:spt"] ?? "") == "202") ? $0 : nil }),
                       (vs["stroked"] ?? "t") != "f", (vs["stroked"] ?? "t") != "false" {
                        let half = (_length(vs["strokeweight"] ?? "") ?? 0.75) / 2
                        box.insetLeft += half; box.insetTop += half; box.insetRight += half; box.insetBottom += half
                    }
                    // (Turned text in VML: the textbox's `layout-flow:vertical` reads
                    // down, as DrawingML's `vert`, and with `mso-layout-flow-alt:
                    // bottom-to-top` upward, as `vert270`; `vertical-ideographic`
                    // is `eaVert`. LibreOffice's btlr-frame-vml reads "Vertical
                    // Text" upward in Word's print; ours set it across, two lines.)
                    if !perPart, node.descendant("wps:bodyPr") == nil, let flow = node.descendant("v:textbox")?["style"] {
                        if flow.containsSubstring("layout-flow:vertical-ideographic") { box.textDirection = .down; box.uprightIdeographs = true }
                        else if flow.containsSubstring("layout-flow:vertical") {
                            box.textDirection = flow.containsSubstring("mso-layout-flow-alt:bottom-to-top") ? .up : .down
                        }
                    }
                    // (A lone VML shape that is not a rectangle sets its text
                    // in its type's text rectangle, as one in a group does —
                    // the file's `v:shapetype`, else VML's own: zh-60c80728
                    // p35's flowchart is 22 lone "alternate process" boxes
                    // (o:spt 176, inset 0, no shapetype in the file), and
                    // Word's print sets "由港区专" a line in the 54.25pt one at
                    // 10.5pt, where the whole width took "由港区专项".)
                    // (… and a lone VML shape that says `v-text-anchor:middle` or
                    // `bottom` sets its text there: lo-ff3b52d1's oval.)
                    if !perPart, node.descendant("wps:bodyPr") == nil, Self._vmlTop(node)?.name != "v:group", box.anchor == nil,
                       RichTextTheme.wordWindowsPages,
                       let shape = ["v:oval", "v:rect"].lazy.compactMap({ n in node.name == n ? node : node.descendant(n) }).first,
                       let shapeStyle = shape["style"] {
                        if shapeStyle.containsSubstring("v-text-anchor:middle") { box.anchor = "ctr"; box.hasFixedFrame = true }
                        else if shapeStyle.containsSubstring("v-text-anchor:bottom") { box.anchor = "b"; box.hasFixedFrame = true }
                    }
                    if !perPart, node.descendant("wps:bodyPr") == nil, Self._vmlTop(node)?.name != "v:group",
                       att.width > 0, att.height > 0, let r = Self._vmlTextRect(node, types: notes.shapeTypes) {
                        // (A VML ellipse's text rectangle is the inscribed one of the box already inset by the textbox's insets,
                        // so each inset counts 0.7071 of itself: 5e813226's oval, Word's lines 156 pt wide, not 152, and its
                        // first line 1.05 pt higher.)
                        let ellipse = RichTextTheme.wordWindowsPages && (node.name == "v:oval" || node.descendant("v:oval") != nil)
                        let k = ellipse ? 0.2929 : 0
                        box.insetLeft += r.left * att.width - k * box.insetLeft
                        box.insetTop += r.top * att.height - k * box.insetTop
                        box.insetRight += (1 - r.right) * att.width - k * box.insetRight
                        box.insetBottom += (1 - r.bottom) * att.height - k * box.insetBottom
                    }
                    // (A VML rounded rectangle's text rectangle is inset by 0.2929 of its corner radius, `arcsize` of the
                    // shorter side, 1/6 where it states none: 5e813226's boxes, Word's text 4.1 pt lower than the plain box.)
                    else if RichTextTheme.wordWindowsPages, !perPart, node.descendant("wps:bodyPr") == nil, Self._vmlTop(node)?.name != "v:group",
                            att.width > 0, att.height > 0, let rr = Self._vmlTop(node), rr.name == "v:roundrect" {
                        var frac = 10923.0 / 65536
                        if let raw = rr["arcsize"] {
                            let t = raw.trimmingWhitespace()
                            if t.hasSuffix("f"), let v = Double(t.dropLast()) { frac = v / 65536 } else if let v = Double(t) { frac = v }
                        }
                        let inset = 0.2929 * frac * min(att.width, att.height)
                        box.insetLeft += inset; box.insetTop += inset; box.insetRight += inset; box.insetBottom += inset
                    }
                    // (A box fitted to its text's height: zh-a78d52e7's
                    // second paragraph holds a 78.75pt one round an empty
                    // paragraph, and Word's print gives the line a text
                    // line's height.)
                    if !box.fitsText, fitsHeight { box.fitsHeight = true }
                    att.textBox = box
                    att.isDropCap = node.descendant("wp:docPr")?["name"] == "Drop cap"
                }
            }
            // An embedded object's picture, a WMF or EMF its VML names
            // (`WriterMetafiles`): the icon and caption of an attached
            // file, or the first page of a document.
            // (A drawing group's VML twin, in the Fallback, holds its arrows' pictures: not the group's own picture, or one arrow is
            // stretched over the whole group: dx2 87097d3e's grey blob.)
            if att.textBox == nil, node.descendant("wpg:wgp") == nil, let rid = node.descendant("v:imagedata")?["r:id"], let rel = notes.rels[rid], !rel.external,
               let data = notes.part(_resolvePath("word", rel.target)) {
                // (A VML picture of pixels — `w:pict`'s `v:imagedata`, a
                // PNG or JPEG — is that picture: zh-64044a1d's nine charts
                // and photos printed as nothing.)
                if !WriterMetafiles.register(data, for: att.id), !Metafile.isMetafile(data), Self._isRasterImage(data) {
                    att.data = data
                    att.name = rel.target.lastPathComponent
                    att.crop = Self._pictureCrop(node)
                }
            }
            // A group's lines and boxes, each in its place (`WriterGroups`);
            // and a shape alone that the outline above does not draw — an
            // ellipse, a triangle, a box filled from the theme
            // (shapes-with-text's, whose white text stood on nothing).
            // (And a lone line with an arrow at an end, which the outline
            // draws without: zh-2e7ef069's flowchart connectors, each a
            // `wps:wsp` line with `a:tailEnd type="arrow"`, printed as bare
            // lines.)
            let arrowed = node.descendant("wpg:wgp") == nil && (node.descendant("wps:spPr")?.first("a:ln").map { ln in
                [ln.first("a:headEnd"), ln.first("a:tailEnd")].contains { ($0?["type"]).map { $0 != "none" } ?? false }
            } ?? false)
            if arrowed, att.outline?.kind == .line { att.outline = nil }
            // A drawing the file hides (`wp:docPr hidden="1"`) is not printed:
            // lo-14656c7f's anchored rectangle was drawn over Word's first lines.
            // It is still kept and written back; it just has no outline or group to paint.
            let hiddenDrawing = ["1", "true"].contains(node.descendant("wp:docPr")?["hidden"] ?? "")
            if hiddenDrawing { att.outline = nil; RuleTrace.hit("hidden-drawing-not-painted") }
            if !hiddenDrawing, let group = node.descendant("wpg:wgp") ?? (att.outline == nil ? node.descendant("wps:wsp") : nil) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterGroups.register(group, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)), wordArt: drawingWordArt,
                                      picture: { rid in
                    guard let rel = notes.rels[rid], !rel.external, let data = notes.part(_resolvePath("word", rel.target)),
                          Self._isRasterImage(data) else { return nil }
                    return data
                })
            } else if node.descendant("wpg:wgp") == nil, let group = _vmlTop(node), group.name == "v:group" {
                // (A VML group's lines and boxes likewise: zh-6e6b9821's
                // flowchart printed its text alone, no arrows or edges.)
                WriterGroups.registerVML(group, types: notes.shapeTypes, for: att.id, picture: { rid in
                    guard let rel = notes.rels[rid], !rel.external, let data = notes.part(_resolvePath("word", rel.target)),
                          Self._isRasterImage(data) else { return nil }
                    return data
                })
            } else if node.descendant("wpg:wgp") == nil, node.descendant("wps:wsp") == nil, att.outline == nil,
                      let shape = _vmlTop(node), ["v:rect", "v:roundrect", "v:oval", "v:shape"].contains(shape.name),
                      !(shape.first("v:imagedata").map { $0["r:id"] != nil || $0["o:relid"] != nil } ?? false) {
                // (A VML shape alone: its edges and fill — zh-7773163d's
                // framed steps on p35 printed their text alone.)
                WriterGroups.registerVMLShape(shape, types: notes.shapeTypes, for: att.id)
            }
            // A chart: its part read and drawn as Slides does one
            // (`WriterCharts`), in the document's theme.
            // (A chart in a group's `wpg:graphicFrame` is the group's, drawn in
            // its place there, registered by its part: `WriterGroups`.)
            for frame in node.descendants("wpg:graphicFrame") {
                guard let rid = frame.descendant("c:chart")?["r:id"], let rel = notes.rels[rid], !rel.external,
                      let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data) else { continue }
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterCharts.register(space, for: att.id + "#" + rid, themePart: notes.part(_resolvePath("word", themeTarget)))
            }
            if node.descendant("wpg:graphicFrame") == nil, let rid = Self._ownChartRid(node), let rel = notes.rels[rid], !rel.external,
               let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                // (With the chart part's own theme override, for its faces.)
                var comps = _resolvePath("word", rel.target).split(separator: "/").map(String.init)
                let file = comps.popLast() ?? ""
                let dir = comps.joined(separator: "/")
                let over = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.relationships()
                    .first(where: { ($0["Type"] ?? "").hasSuffix("/themeOverride") && $0["TargetMode"] != "External" })?["Target"]
                    .flatMap { notes.part(_resolvePath(dir, $0)) }
                let shapes = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.relationships()
                    .first(where: { ($0["Type"] ?? "").hasSuffix("/chartUserShapes") && $0["TargetMode"] != "External" })?["Target"]
                    .flatMap { notes.part(_resolvePath(dir, $0)) }.flatMap(XNode.parse)
                // (A chart whose numbers live in a workbook it links to, not one it carries: Word prints its
                // whole-number labels with thousands separators though the cache says General. Five
                // documents of two sets (sa1 c11d31f3, dx2 f15415f0 ...: 1,030 and 11,965) against
                // sa2 db23237f, whose embedded workbook prints 10999.)
                let linkedSource = notes.part(dir + "/_rels/" + file + ".rels").flatMap(XNode.parse)?.relationships()
                    .contains(where: { ($0["Type"] ?? "").hasSuffix("/oleObject") && $0["TargetMode"] == "External" }) ?? false
                WriterCharts.register(space, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)), themeOverride: over, userShapes: shapes, linkedSource: linkedSource)
            }
            // A box-and-whisker chart (Office 2016's chartex part), drawn
            // on a column chart's axes, or a sunburst: named by `cx:chart`
            // (by `c:chart` it is read above, as chartex names its own).
            if Self._ownChartRid(node) == nil, node.descendant("c:chart") == nil, let space = boxWhisker(node) {
                let themeTarget = notes.rels.values.first(where: { $0.type.hasSuffix("/theme") && !$0.external })?.target ?? "theme/theme1.xml"
                WriterCharts.register(space, for: att.id, themePart: notes.part(_resolvePath("word", themeTarget)))
            }
            return att
        }
        /// The chartex part a drawing names (`cx:chart`, or `c:chart` in
        /// a chartex `a:graphicData`), where it is a chart this app draws
        /// (`ChartXML.readWordChartex`: box-and-whisker, sunburst).
        func boxWhisker(_ node: XNode) -> XNode? {
            guard let rid = (node.descendant("cx:chart") ?? node.descendant("c:chart"))?["r:id"], let rel = notes.rels[rid], !rel.external,
                  let data = notes.part(_resolvePath("word", rel.target)), let space = XNode.parse(data),
                  ChartXML.readWordChartex(space) != nil else { return nil }
            return space
        }
        func addImage(_ drawing: XNode) {
            // (A group of a picture and shapes — lo tdf126426's photo under a
            // white text box — is a drawing, not the picture its first
            // `a:blip` is: its boxes' text was drawn nowhere.)
            if drawing.descendant("wpg:wgp") != nil, drawing.descendant("wps:wsp") != nil, drawing.descendant("pic:pic") != nil {
                addObject(drawing)
                return
            }
            // (A text box's own picture is not the box's: tdf48658's header is
            // a transparent VML box holding a table, whose first cell has a
            // small inline picture; read as that picture, the box drew the
            // picture alone and none of its table.)
            func blipOutsideBoxes(_ n: XNode) -> XNode? {
                if n.name == "w:txbxContent" { return nil }
                if n.name == "a:blip" { return n }
                for child in n.children { if let hit = blipOutsideBoxes(child) { return hit } }
                return nil
            }
            if drawing.descendant("w:txbxContent") != nil, blipOutsideBoxes(drawing) == nil {
                RuleTrace.hit("box-picture-is-the-boxs-content")
                addObject(drawing)
                return
            }
            guard let blip = drawing.descendant("a:blip"), let rid = blip["r:embed"],
                  let target = rels[rid], let data = media(target) else { addObject(drawing); return }
            var w = 300.0, h = 200.0
            if let extent = drawing.descendant("wp:extent"),
               let cx = Double(extent["cx"] ?? ""), let cy = Double(extent["cy"] ?? ""), cx > 0, cy > 0 {
                w = cx / 12700
                h = cy / 12700
            }
            // In the line where the text has it (several to a line, text
            // around them); a paragraph of nothing else becomes the
            // editor's picture paragraph at flush.
            if drawing.first("wp:anchor") != nil, var att = objectAttachment(drawing) {
                // A floating picture: its anchor (position, wrapping,
                // behind the text) is kept as written and saved verbatim —
                // Word then lays it out as the file did (WithGIF's text
                // flowed over its picture; VariousPictures) — while the
                // editor shows the picture in the line.
                att.data = data
                att.name = target.lastPathComponent
                att.crop = Self._pictureCrop(drawing)
                att.sourceCrop = att.crop
                att.altText = drawing.descendant("wp:docPr")?["descr"] ?? ""
                att.altTitle = drawing.descendant("wp:docPr")?["title"] ?? ""
                att.sourceAltTitle = att.altTitle
                att.sourceAltText = att.altText
                if Metafile.isMetafile(data) { WriterMetafiles.register(data, for: att.id) }
                // (Turned, a photo taken sideways: a quarter turn makes
                // its box as tall as it was wide — zh-37b6536f.)
                if let rot = drawing.descendant("a:graphic")?.descendant("a:xfrm")?["rot"].flatMap({ Double($0) }) {
                    att.rotation = rot / 60000
                }
                att.sourceRotation = att.rotation
                addInline(att)
                return
            }
            // An inline picture keeps its markup too (effectExtent, docPr,
            // crop), used while the editor has not resized it.
            // (Word stands an inline picture whole twips tall, the fraction cut off: its printed heights are 17.0, 60.05,
            // 351.75 for extents of 17.008, 60.094, 351.799 pt, in nine corpus docs; es 6b74a903's header picture, 67.39
            // pt, printed 67.35 and put the body 0.055 pt too low here.)
            // (An inline picture turned a quarter occupies its turned box: sa2 d1fab599's 630 by 379 pt
            // map, turned 270 degrees, stands 379 wide and 630 tall in Word's print.)
            var inlineTurn = 0.0
            if let rot = drawing.descendant("a:graphic")?.descendant("a:xfrm")?["rot"].flatMap({ Double($0) }) {
                let deg = rot / 60000
                let r = (deg.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
                if abs(r - 90) < 1 { swap(&w, &h) }
                inlineTurn = deg
            }
            if RichTextTheme.wordWindowsPages, h > 1 { h = (h * 20 + 1e-6).rounded(.down) / 20 }
            var att = ImageAttachment(data: data, width: w, height: h, name: target.lastPathComponent)
            if inlineTurn != 0 { att.rotation = inlineTurn }
            att.sourceRotation = att.rotation
            att.crop = Self._pictureCrop(drawing)
            att.sourceCrop = att.crop
            att.altText = drawing.descendant("wp:docPr")?["descr"] ?? ""
                att.altTitle = drawing.descendant("wp:docPr")?["title"] ?? ""
                att.sourceAltTitle = att.altTitle
            att.sourceAltText = att.altText
            att.inset = Self._canvasInset(drawing)
            if let effect = drawing.descendant("wp:effectExtent") {
                att.effectLeft = max(0, (Double(effect["l"] ?? "") ?? 0) / 12700)
                att.effectRight = max(0, (Double(effect["r"] ?? "") ?? 0) / 12700)
                att.effectTop = max(0, (Double(effect["t"] ?? "") ?? 0) / 12700)
                att.effectBottom = max(0, (Double(effect["b"] ?? "") ?? 0) / 12700)
            }
            if let frag = _keptFragment(drawing, notes) {
                att.sourceXML = frag.xml
                att.sourceRels = frag.rels
                att.sourceWidth = w
                att.sourceHeight = h
            }
            // (A picture that is a WMF or EMF is played as an object's
            // is (`WriterMetafiles`); no image codec reads it. zh-8d72961c's
            // page 2 is one, its Arabic and Latin text in ExtTextOutW
            // records, and printed as the grey stand-in.)
            if Metafile.isMetafile(data) { WriterMetafiles.register(data, for: att.id) }
            addInline(att)
        }
        var ruleOpen = false   // a horizontal rule was just set: the text after it starts a line
        var pendingRefChange: (said: String, author: String)? = nil   // a comment reference whose own look was changed
        var runOriginalRPr: String? = nil   // the run being walked's own w:rPr, as written (stamped on the looks its text gets)
        var runOriginalChildren: [(name: String, xml: String)] = []
        func stamped(_ c: CharStyle) -> CharStyle {
            var c = c
            if let x = runOriginalRPr {
                // (What the fields would write for this look; the file's elements of any other name are ones they cannot say.)
                let said = Set(_rPrElementNames(_rPrXML(c, fileFonts: [])))
                let extras = runOriginalChildren.filter { !said.contains($0.name) }.map(\.xml).joined()
                c.stampOriginal(x, extras: extras.isEmpty ? nil : extras)
            }
            return c
        }
        func addText(_ s: String, _ cs: CharStyle) {
            guard !s.isEmpty else { return }
            // (Not a floating drawing's anchor mark, nor spaces: 401cd750's rules carry a line-shaped anchor after them
            // and Word keeps it on the rule's line.)
            if ruleOpen, s.unicodeScalars.contains(where: { $0 != "\u{FFFC}" && $0 != " " && $0 != "\t" }) {
                ruleOpen = false
                if !s.hasPrefix("\n") { addText("\n", cs) }
            }
            text += s
            for id in cs.comments { notes.carriedComments.insert(id) }
            var cs = cs
            if cs.field == nil, s.contains(where: { !$0.isWhitespace }), let ff = cs.fontFamily { notes.lastTextFamily = ff }
            if let r = pendingRefChange { cs.commentRefSaid = r.said; cs.commentRefAuthor = r.author; pendingRefChange = nil }
            if s == "\u{B7}" { cs.loneDot = true }
            if s == "\u{201C}" || s == "\u{201D}" || s == "\u{2018}" || s == "\u{2019}" || s == "\u{B1}" { cs.loneQuote = true }
            // (A run of circled digits that names only its ascii face is drawn from the East Asian slot of that same face in Word's print:
            // xd 4fabe1f2's ② under HY신명조, a missing Korean face, stands on Malgun's line like one that names both.)
            if DocxFormat.wordOnWindows, cs.eastAsiaFontFamily == nil, cs.fontFamily != nil,
               s.unicodeScalars.allSatisfy({ (0x2460 ... 0x2469).contains($0.value) }) {
                cs.eastAsiaFontFamily = cs.fontFamily
            }
            // (Word picks the face by character: Arabic and Hebrew letters in a run with no w:rtl still take the complex-script face,
            // as xb ara-z23060052's print sets them (the face is resolved elsewhere). Each Arabic stretch becomes its own
            // right-to-left run; the rest keeps the Latin face.)
            if DocxFormat.wordOnWindows, !cs.rightToLeft, s.unicodeScalars.contains(where: { (0x0600 ... 0x06FF).contains($0.value) || (0x0590 ... 0x05FF).contains($0.value) }) {
                var piece = "", pieceArabic = false
                func isAr(_ u: Unicode.Scalar) -> Bool { (0x0600 ... 0x06FF).contains(u.value) && !(0x0660 ... 0x0669).contains(u.value) && u.value != 0x060C && u.value != 0x061B && u.value != 0x061F || u.value == 0x200C || (0x0590 ... 0x05FF).contains(u.value) }
                func flush() {
                    guard !piece.isEmpty else { return }
                    var c = cs
                    if cs.rightToLeft { c.csLetters = true }
                    if pieceArabic { c.rightToLeft = true; c.csLetters = true; if !cs.csFlagRun { c.plainSize = true } }
                    runs.append(Run(length: piece.utf16.count, style: stamped(c))); piece = ""
                }
                for u in s.unicodeScalars {
                    let a = isAr(u)
                    if a != pieceArabic { flush(); pieceArabic = a }
                    piece.unicodeScalars.append(u)
                }
                flush()
                return
            }
            // (A right-to-left run of ASCII digits alone holds no complex-script letter: Word's print of dx2 6e7a3d11 draws "35", w:rtl and
            // cs B Mitra, in the Latin face, Calibri, beside Arial Persian.)
            // (… and with the signs a number carries: lab urdu-digits variant F, "97-96" in w:rtl runs with no w:hint, a Persian line of B Zar whose
            // number run Word sets in the Latin face, Tahoma's taller line: 29.4 pt steps, ours 28.5 on Arial's.)
            let digitsOnly = DocxFormat.wordOnWindows && s.unicodeScalars.contains { (0x30 ... 0x39).contains($0.value) }
                && s.unicodeScalars.allSatisfy { (0x30 ... 0x39).contains($0.value) || "-./:,%".unicodeScalars.contains($0) }
            // (… nor a run of ASCII punctuation and spaces in Calibri, a face Word has: dx2 99905488's '"' runs, w:rtl, cs Calibri, hint cs, step
            // the line by Calibri's own height in Word's print, where the fallback face the letters would take is a taller line.)
            let calibriPunct = DocxFormat.wordOnWindows && (cs.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "calibri"
                && s.unicodeScalars.allSatisfy { $0.isASCII && !(0x30 ... 0x39).contains($0.value) && !(0x41 ... 0x5A).contains($0.value) && !(0x61 ... 0x7A).contains($0.value) }
                && s.unicodeScalars.contains { $0.value > 0x20 }
            if (cs.rightToLeft && !digitsOnly && !calibriPunct) || s.unicodeScalars.contains(where: { (0x0590 ... 0x08FF).contains($0.value) || (0xFB1D ... 0xFDFF).contains($0.value) || (0xFE70 ... 0xFEFF).contains($0.value) }) { cs.csLetters = true }
            // (… unless the run says w:hint="cs": dx2 1ba3a908's "בדצמבר 2023", w:rtl, hint cs, Hebrew letters, steps like the Arial Hebrew line
            // around it, 13.8 pt, not Calibri's 14.65 the number's Latin face would give. Persian runs with the same hint keep the number in the Latin
            // face: xb fas-z2070387's "(1403)" and "14(2)" among B Lotus words, Mitra.)
            // (A right-to-left run of Arabic letters with ASCII numbers inside it: Word draws each number in the Latin face, and that face's line
            // raises the line it is on, Tahoma's 13.3 pt step over Arial's 12.6. dx2 491931cb page 1, Tahoma Latin and B Nazanin cs, "0011234555"
            // among Persian words: Word's lines with a number step 13.3 pt, those without 12.6, ours stayed on Arial's. The number is its own run.)
            if DocxFormat.wordOnWindows, cs.rightToLeft, !digitsOnly, !(cs.fontHint == "cs" && s.unicodeScalars.contains { (0x0590 ... 0x05FF).contains($0.value) }), cs.csLetters, s.unicodeScalars.contains(where: { (0x30 ... 0x39).contains($0.value) }),
               s.unicodeScalars.contains(where: { (0x0590 ... 0x08FF).contains($0.value) || (0xFB1D ... 0xFDFF).contains($0.value) || (0xFE70 ... 0xFEFF).contains($0.value) }) {
                let u = Array(s.unicodeScalars)
                func isDigit(_ i: Int) -> Bool { (0x30 ... 0x39).contains(u[i].value) }
                var inNumber = [Bool](repeating: false, count: u.count)
                for i in 0 ..< u.count {
                    if isDigit(i) { inNumber[i] = true }
                    else if "-./:,%".unicodeScalars.contains(u[i]), i > 0, i + 1 < u.count, isDigit(i - 1), isDigit(i + 1) { inNumber[i] = true }
                }
                var i = 0
                while i < u.count {
                    var j = i
                    while j < u.count, inNumber[j] == inNumber[i] { j += 1 }
                    var c = cs
                    if inNumber[i] { c.csLetters = false; RuleTrace.hit("word-rtl-number-in-arabic-run-is-latin-face") }
                    var piece = String.UnicodeScalarView(); piece.append(contentsOf: u[i ..< j])
                    runs.append(Run(length: String(piece).utf16.count, style: stamped(c)))
                    i = j
                }
                return
            }
            runs.append(Run(length: s.utf16.count, style: stamped(cs)))
        }
        var hyperlinkHistory = false       // the enclosing w:hyperlink's w:history
        var hyperlinkTip: String? = nil    // the enclosing w:hyperlink's w:tooltip
        var pendingCheckbox: Bool? = nil   // a FORMCHECKBOX field's state, from its begin
        var pendingDropdown: String? = nil // a FORMDROPDOWN field's chosen entry, from its begin
        func walkRun(_ r: XNode, link: String?, revision: RevisionMark? = nil) {
            // (A run nested in a run, which the schema does not allow: Word prints the inner run's text. lab gridlift2 / f42177d2's title holds
            // <w:r><w:rPr/><w:r><w:t>共感性</w:t></w:r></w:r>; ours dropped the text, so its title line was 55pt short and never wrapped.)
            if r.children.contains(where: { $0.name == "w:r" }) {
                var piece = XNode(name: r.name, attrs: r.attrs)
                func flush() {
                    if piece.children.contains(where: { $0.name != "w:rPr" }) { walkRun(piece, link: link, revision: revision) }
                    piece = XNode(name: r.name, attrs: r.attrs)
                    piece.children = r.children.filter { $0.name == "w:rPr" }
                }
                piece.children = r.children.filter { $0.name == "w:rPr" }
                for child in r.children where child.name != "w:rPr" {
                    if child.name == "w:r" { flush(); walkRun(child, link: link, revision: revision) }
                    else { piece.children.append(child) }
                }
                flush()
                return
            }
            // (Misplaced run properties, Word's own print of lab rprorder: a w:rPr applies to what
            // FOLLOWS it in the run, the last of several in a row wins, and one after the run's
            // last content is ignored. 5b9c7c3f's runs hold w:rPr after w:t, Word prints them at
            // the default size.)
            let rPrAt = r.children.indices.filter { r.children[$0].name == "w:rPr" }
            if rPrAt.count > 1 || (rPrAt.count == 1 && rPrAt[0] != 0) {
                var segments: [(rPr: XNode?, content: [XNode])] = [(nil, [])]
                for child in r.children {
                    if child.name == "w:rPr" {
                        if segments[segments.count - 1].content.isEmpty { segments[segments.count - 1].rPr = child }
                        else { segments.append((child, [])) }
                    } else { segments[segments.count - 1].content.append(child) }
                }
                for seg in segments where !seg.content.isEmpty {
                    let piece = XNode(name: r.name, attrs: r.attrs)
                    piece.children = (seg.rPr.map { [$0] } ?? []) + seg.content
                    walkRun(piece, link: link, revision: revision)
                }
                return
            }
            var cs = cellChar
            cs.link = link
            cs.linkKeepsLook = link != nil
            cs.linkHistory = link != nil && hyperlinkHistory
            cs.linkTip = link == nil ? nil : hyperlinkTip
            cs.revision = revision
            cs.comments = notes.openComments
            notes.anchoredComments.formUnion(notes.openComments)
            var missingReference: Int? = nil
            var pageResultInCodeLook = false
            // Text that is a page reference's result stays one: Word
            // brings these up to date when it prints, and a contents page
            // of plain numbers kept the ones the file was saved with (a
            // Kinmen emergency plan listed its chapters 5 to 46 pages
            // early). Other fields stay the text they show.
            if let f = notes.fields.last, f.result {
                cs.fieldResult = f.id
                let instr = f.instr.trimmingWhitespace(newlines: true)
                if Self._preservesField(instr), !(notes.inHeaderFooter && DocxFormat._isPageField(instr)) {
                    cs.preservedField = instr
                    cs.preservedFieldProperties = f.properties
                }
                if instr.uppercased().hasPrefix("PAGEREF ") {
                    cs.field = instr
                    // (A page reference to a bookmark the file does not have:
                    // Word brings the field up to date as it prints and shows
                    // its error where the number was. lo tdf164905's contents
                    // page has 39 such lines, "ERROR! BOOKMARK NOT DEFINED."
                    // in Word's print, 39 of 54 references.)
                    let target = instr.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first
                        .map { String($0.filter { $0 != "\"" }).lowercased() }
                    if let target, !target.isEmpty, !target.hasPrefix("\\"), !notes.bookmarkNames.isEmpty, !notes.bookmarkNames.contains(target) {
                        missingReference = f.id
                    }
                }
                else if notes.inHeaderFooter, DocxFormat._isPageField(instr) {
                    // (A page number Word works out again as it prints, in
                    // its code's look unless the code keeps the result's
                    // with \* MERGEFORMAT: zh-7773163d's folio, a PAGE field
                    // whose code run is Times 12pt and whose result run says
                    // nothing, prints at 12pt; ours took the result run's
                    // default, 9.2pt and 8.5pt low.)
                    if !instr.uppercased().containsSubstring("MERGEFORMAT"), let code = notes.fieldCodeStyle[f.id] {
                        let id = cs.fieldResult, link = cs.link, revision = cs.revision, comments = cs.comments
                        cs = code
                        pageResultInCodeLook = true
                        cs.fieldResult = id
                        cs.link = link
                        cs.linkKeepsLook = link != nil
                        cs.revision = revision
                        cs.comments = comments
                    }
                    cs.field = instr; notes.fieldShown = true
                }
            }
            // A HYPERLINK field's result is the link's text, whatever fields sit inside it (and across paragraphs).
            if cs.link == nil, let h = notes.fields.last(where: { $0.result && Self._isHyperlinkField($0.instr) }),
               let t = Self._hyperlinkFieldTarget(h.instr) {
                cs.link = t.target; cs.linkTip = t.tip; cs.linkKeepsLook = true
                cs.linkField = h.instr.trimmingWhitespace(newlines: true); cs.linkFieldID = h.id
            }
            // (Its style reference would name an id the save may rename.)
            runPropertiesXML = r.first("w:rPr").flatMap { $0.first("w:rStyle") == nil && !$0.children.isEmpty ? PptxXML.serialize($0) : nil }
            runFrame = r.first("w:rPr")?.first("w:bdr").flatMap(_borderLine).flatMap { $0.width > 0 ? $0 : nil }
            runRevision = revision?.kind == .deleted ? revision : nil
            defer { runPropertiesXML = nil; runFrame = nil; runRaised = nil; runRevision = nil; runOriginalRPr = nil }
            // (The result run's own properties go too: bea98273's header folio, a PAGE code run with
            // no properties and a result run at sz 24, prints at the code's 10pt, baseline 45.4.)
            runOriginalRPr = nil
            if let rPr = r.first("w:rPr"), !pageResultInCodeLook {
                if !rPr.children.contains(where: { $0.name == "w:rPrChange" }), !rPr.children.isEmpty {
                    runOriginalChildren = rPr.children.map { ($0.name, PptxXML.serialize($0)) }
                    runOriginalRPr = runOriginalChildren.map(\.xml).joined()
                }
                // The run's character style first, then its own properties.
                let runText = r.children.filter { $0.name == "w:t" }.map(\.text).joined()
                // (A run flagged w:rtl whose text is digits and marks, no letters, is complex
                // script too: Word sets heb-z5059159's "1" in the szCs 12, not the sz 11.)
                let rtlRun = _on(rPr.first("w:rtl")) && !runText.isEmpty && (rPr.first("w:szCs") != nil || !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A })
                    // (A run of marks and spaces only, no digit, takes the complex size too: xd 564a33e9's Narkisim sz 14 "(" and ": \"" runs, no szCs, print at the szCs 12 in Word.)
                    // (Only when the run itself names a complex-script size: a PAGEREF result with just webHidden and rtl, 47480880's contents list, prints in the ascii face at sz, Calibri 11 / David 12.)
                    && (!DocxFormat._bidiLangHebrew || rPr.first("w:szCs") != nil || !runText.unicodeScalars.contains { (0x30...0x39).contains($0.value) } || rPr.first("w:rFonts")?["w:cs"] != nil || rPr.first("w:rFonts")?["w:cstheme"] != nil || rPr.first("w:rFonts")?["w:hint"] == "cs" || (rPr.first("w:webHidden") == nil && notes.inHeaderFooter))
                let csFlag = _on(rPr.first("w:cs"))
                let complexSize = runText.unicodeScalars.contains {
                    // (Hebrew letters in a run with neither w:rtl nor w:cs keep the sz, Latin pieces too: xb 5dc87fc7's Arial R5 paragraph, sz 22 / szCs 44, prints at 11.)
                    ((0x0590...0x08FF).contains($0.value) && !((0x0590...0x05FF).contains($0.value) && !csFlag && !_on(rPr.first("w:rtl")))) || (0xFB1D...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value)
                        // (Devanagari, Bengali, Gurmukhi and Gujarati: 375919ba's sz 16 / szCs 14 prints at 14, Word's Mangal. Tamil and Telugu do not:
                        // cef2f7bd's Telugu title, sz 14 / szCs 10, prints at 14.)
                        // (Only with the w:cs flag: a run without it prints at sz, lab cssz; 80152175's Bengali, 87097d3e's Hindi.)
                        || (csFlag && (0x0900...0x0B7F).contains($0.value))
                        // (Lao with the w:cs flag: dx2 30f73046's title, sz 24 / szCs 32, is a 16 pt Leelawadee UI line in Word's print.)
                        || (csFlag && (0x0E80...0x0EFF).contains($0.value))
                        // (Thai with the w:cs flag: xs e17f28a6's heading, sz 16 / szCs 20, is a 20 pt TH SarabunPSK line in Word's print. A run with both sizes or neither (the style or defaults then supply szCs, dx2 27dc0c47) takes the complex size; a run with exactly one keeps the style sz.)
                        || (csFlag && (rPr.first("w:szCs") != nil) == (rPr.first("w:sz") != nil) && (0x0E00...0x0E7F).contains($0.value))
                } || rtlRun
                // (Tamil takes bCs/iCs but not szCs: da732dfb's sz 14 / szCs 20 subtitle prints at 14 in Word. Only a run with no Latin letters.)
                let tamilOnly = !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A } && runText.unicodeScalars.contains { (0x0B80...0x0BFF).contains($0.value) }
                let complex = complexSize || tamilOnly
                // (Only a Thai run: the Arabic-script docs xb fas-z22867828 and ara-z23060052 lose lines when their flagged runs take the style's szCs.)
                let thaiStyleSize = csFlag && rPr.first("w:sz") == nil && rPr.first("w:szCs") == nil && runText.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
                let indicOnly = !runText.isEmpty && !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A }
                    && runText.unicodeScalars.contains { (0x0900...0x0B7F).contains($0.value) }
                let rtlLettersOnly = !runText.isEmpty && !runText.unicodeScalars.contains { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A } && runText.unicodeScalars.contains { (0x0590...0x05FF).contains($0.value) }
                // (Not the Hyperlink character style inside a table of contents:
                // Word prints its entries in the TOC paragraph's own look, black
                // and plain, whatever the runs name.)
                let inContents = notes.fields.contains { $0.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") }
                var styleId: String? = nil
                if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id], !(inContents && id.lowercased() == "hyperlink") {
                    for styled in chain { cs = _charStyle(styled, base: cs, complexText: complex, complexSize: complexSize, thaiStyleSize: thaiStyleSize, indicOnly: indicOnly, rtlLettersOnly: rtlLettersOnly) }
                    styleId = id
                } else if inContents, let id = rPr.first("w:rStyle")?["w:val"], notes.charStyleChains[id] != nil {
                    // (The entry is drawn in the paragraph's own look, but the file's style name stays for the save.)
                    styleId = id
                }
                cs = _charStyle(rPr, base: cs, complexText: complex, complexSize: complexSize, thaiStyleSize: thaiStyleSize, indicOnly: indicOnly, rtlLettersOnly: rtlLettersOnly)
                cs.styleId = styleId
                cs.csFlagRun = csFlag
                // (A left-to-right run under the w:cs flag holding Thai, or only spaces: Word sets the whole run, its spaces and the line it stands on,
                // in the complex-script face. dx2 e7b500c9's title, ascii Times New Roman and cs Angsana New from Normal, three flagged spaces then
                // the Thai: Angsana's 22 pt line and 3.6 pt spaces in Word's print, Times' in ours; lab e7lab.)
                if DocxFormat.wordOnWindows, csFlag, !cs.rightToLeft, !runText.isEmpty,
                   runText.unicodeScalars.allSatisfy({ (0x0E00...0x0E7F).contains($0.value) || !$0.properties.isAlphabetic && !(0x30...0x39).contains($0.value) }),
                   runText.unicodeScalars.contains(where: { (0x0E01...0x0E5B).contains($0.value) }) || (runText.unicodeScalars.allSatisfy({ $0.value == 0x20 || $0.value == 0xA0 })
                        && PptxXML.serialize(p).unicodeScalars.contains(where: { (0x0E01...0x0E5B).contains($0.value) })),
                   let thaiFace = cs.complexFontFamily
                    ?? p.first("w:pPr")?.first("w:pStyle")?["w:val"].flatMap({ styleIds[$0] }).flatMap({ sheet[$0]?.char.complexFontFamily })
                    ?? sheet[RichNamedStyle.normalId]?.char.complexFontFamily,
                   (cs.fontFamily ?? "") != thaiFace || cs.hAnsiFontFamily != nil {
                    cs.fontFamily = thaiFace; cs.hAnsiFontFamily = nil
                    RuleTrace.hit("word-cs-flagged-thai-run-is-wholly-its-complex-face")
                }
                // (Only a webHidden run in a header or footer, or any body run, as in a contents list: the PAGE results of the footers of 7d58f74e, b9164bf3 and fcd0d58c, with just rtl, stay complex and print in Arial.)
                // (A run of ASCII digits flagged w:rtl with no szCs or cs font of its own is a plain Latin run to Word: 47480880's PAGEREF results.)
                // (Arabic: the same for a PAGE result in a footer, whose face is the style's ascii one at the szCs: xb ara-z5177238's "2" under cs Simplified Arabic, an installed face, is Times New Roman 14.04 in two Word prints, sz 12 / szCs 14.)
                if cs.rightToLeft, _on(rPr.first("w:rtl")), rPr.first("w:szCs") == nil, rPr.first("w:rFonts")?["w:cs"] == nil, rPr.first("w:rFonts")?["w:cstheme"] == nil, rPr.first("w:rFonts")?["w:hint"] != "cs",
                   !DocxFormat._bidiLangHebrew, !notes.normalAsciiIsCs, notes.inHeaderFooter, !runText.isEmpty, runText.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) }) {
                    cs.rightToLeft = false; RuleTrace.hit("rtl-digits-no-cs-props-arabic-footer")
                }
                // (A run flagged w:rtl whose text holds Arabic-script letters is complex script throughout: its w:hint="eastAsia" does not make the
                // marks, digits and quotes in it East Asian, so the line is not the Mincho-tall one. dx2 6e7a3d11's Persian body, every run hinted:
                // lines 0.7 pt too tall, 3.9 pt of drift by the foot of page 3.)
                if cs.rightToLeft, _on(rPr.first("w:rtl")), cs.fontHint == "eastAsia", !DocxFormat._bidiLangHebrew,
                   runText.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
                    cs.fontHint = nil; RuleTrace.hit("word-rtl-arabic-run-ignores-east-asian-hint")
                }
                if DocxFormat._bidiLangHebrew, cs.rightToLeft, _on(rPr.first("w:rtl")), rPr.first("w:szCs") == nil, rPr.first("w:rFonts")?["w:cs"] == nil, rPr.first("w:rFonts")?["w:cstheme"] == nil, (rPr.first("w:webHidden") != nil || !notes.inHeaderFooter), rPr.first("w:rFonts")?["w:hint"] != "cs",
                   !runText.isEmpty, runText.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) }) {
                    cs.rightToLeft = false; RuleTrace.hit("rtl-digits-no-cs-props")
                }
                // (The same where the weight comes from the PARAGRAPH style: dx2 f0001d05's Title (b, no bCs), a Kokila run with w:cs and no weight of its own, prints regular.)
                if indicOnly, _on(rPr.first("w:cs")), rPr.first("w:b") == nil, rPr.first("w:bCs") == nil, !cs.bold,
                   let n = style.named, sheet[n]?.char.boldWithoutBCs == true { cs.off.insert(.bold) }
                // (A right-to-left run that says neither b nor bCs takes the bCs of its paragraph style, whatever w:b that style gives: ara-z11030406-663296's Heading3, b 0 over Normal's b + bCs, prints Traditional Arabic Bold.)
                if cs.rightToLeft, _on(rPr.first("w:rtl")), rPr.first("w:b") == nil, rPr.first("w:bCs") == nil, !cs.bold,
                   let n = style.named ?? style.heading.map({ "Heading\($0)" }), sheet[n]?.char.bCsFromStyle == true, sheet[n]?.char.bold == false { cs.bold = true; cs.off.remove(.bold) }
            }
            // (A page number kept in its result's look with \* MERGEFORMAT keeps its weight and
            // loses the rest of it: lab pgf (Word for Windows, 2026-11-02) — an Arial Bold 15.5pt
            // superscript result prints Arial Bold 10pt on the baseline, only the "/" beside it
            // raised; lo-198cd200's footer.)
            if notes.inHeaderFooter, let f = notes.fields.last, f.result, DocxFormat._isPageField(f.instr), f.instr.uppercased().containsSubstring("MERGEFORMAT"),
               cs.script != .normal {
                // (A superscript's shrunk size stays, its raise does not: 15.5pt prints 10.)
                RuleTrace.hit("page-field-result-with-mergeformat-keeps-bold-only")
                cs.script = .normal
                cs.fontSize = cs.fontSize.map { $0 * 0.65 }
            }
            // (A superscript or subscript the PARAGRAPH style sets reaches a run that says nothing of its own: sa1 6d68ddbf's header title,
            // Heading 2 in Copperplate 24 pt with w:vertAlign superscript, prints 15.5 pt in Word and fits one line; ours drew it 24 pt.)
            if cs.script == .normal, let sc = sheet.resolve(style)?.char.script, sc != .normal,
               r.first("w:rPr")?.first("w:vertAlign") == nil {
                RuleTrace.hit("paragraph-style-vertalign-reaches-plain-runs")
                cs.script = sc
            }
            // A link the file does not underline (no Hyperlink character
            // style on its run, or one that says so): the save names the
            // style again, so the run has to say "none" over it —
            // bug59058's green reference numbers came back underlined.
            if link != nil, !cs.underline { cs.off.insert(.underline) }
            // (And the link stays a link, in the text's own colour.)
            if link != nil, cs.color == nil,
               notes.fields.contains(where: { $0.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") }) {
                cs.color = Color(0xFF000000)
            }
            runRaised = cs.raised
            for child in r.children {
                switch child.name {
                case "w:t":
                    // (A STYLEREF that names no style of the file — lo
                    // tdf149089's "标题 1" over a style called "heading 1" —
                    // is Word's error in bold, 9pt in its header, where
                    // the result saved with it was the heading's text.)
                    if let f = notes.fields.last, f.result, f.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("STYLEREF"),
                       let name = Self._styleRefName(f.instr), !notes.styleNames.contains(name.lowercased()) {
                        if notes.styleRefShown.insert(f.id).inserted {
                            var bold = cs
                            bold.bold = true
                            bold.off.remove(.bold)
                            addText("Error! Use the Home tab to apply \(name) to the text that you want to appear here.", bold)
                        }
                        break
                    }
                    // A reference to a bookmark the document lacks: Word brings
                    // it up to date as it prints, and the result is its error
                    // (tdf170672's two REF fields over a missing _Ref name stand
                    // as "Error! Reference source not found." twice, two lines
                    // in the cell where the file's cached "4.1" and heading took
                    // four).
                    if let f = notes.fields.last, f.result, let name = DocxFormat._missingReference(f.instr, notes.bookmarkNames, notes.keptBookmarkText) {
                        _ = name
                        if notes.referenceErrors.insert(f.id).inserted { addText("Error! Reference source not found.", cs) }
                        continue
                    }
                    if let id = missingReference {
                        if notes.missingReferenceShown.insert(id).inserted {
                            RuleTrace.hit("pageref-bookmark-not-defined")
                            addText("Error! Bookmark not defined.", cs)
                        }
                    } else if notes.fieldCodeChanged, notes.fields.last?.result == true {
                        var first = cs
                        first.fieldCodeChanged = true
                        addText(_runText(child).replacingAll("\u{F8FF}", with: "\n"), first)
                        notes.fieldCodeChanged = false
                    } else {
                        addText(_runText(child).replacingAll("\u{F8FF}", with: "\n"), cs)
                    }
                case "w:fldChar":
                    if cs.formatChange != nil, child["w:fldCharType"] != "end", notes.fields.last.map({ !$0.result }) ?? true {
                        notes.fieldCodeChanged = true
                    }
                    if child["w:fldCharType"] == "end" { notes.fieldCodeChanged = false }
                    switch child["w:fldCharType"] {
                    case "begin":
                        notes.fieldCount += 1
                        notes.fields.append((instr: "", result: false, id: notes.fieldCount,
                                             properties: child.attrs.filter { $0.key == "w:fldLock" || $0.key == "w:dirty" })); notes.fieldShown = false
                    case "separate": if !notes.fields.isEmpty { notes.fields[notes.fields.count - 1].result = true }
                    case "end":
                        if notes.fields.count == 1, let f = notes.fields.last, f.instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") { notes.contentsEnd = true }
                        if notes.fields.count >= 2, let f = notes.fields.last {
                            let word = f.instr.trimmingWhitespace(newlines: true).uppercased().split(separator: " ").first.map(String.init) ?? ""
                            if word == "PAGE" || word == "NUMPAGES" { notes.nestedPageFields.insert(word) }
                        }
                        if notes.fields.count == 1 { notes.nestedPageFields = [] }
                        // (A page field with no result yet shows a number
                        // all the same.)
                        if notes.inHeaderFooter, !notes.fieldShown, let f = notes.fields.last {
                            let instr = f.instr.trimmingWhitespace(newlines: true)
                            if DocxFormat._isPageField(instr) {
                                var shown = cs
                                shown.field = instr
                                addText("1", shown)
                            }
                        }
                        // (An EQ field that rings a number, `eq \o\ac(○,1)`,
                        // with no result written: Word draws the two
                        // overlaid, an em wide — the circled number.
                        // zh-e0ca7252's 27 "○1".."○4" open lines of its
                        // insurance clauses; dropped, each line took two
                        // characters more and its pages ran ahead.)
                        if let f = notes.fields.last, !f.result, let shownText = DocxFormat._ifFieldResult(f.instr) {
                            RuleTrace.hit("if-field-shows-its-branch")
                            var shown = cs
                            shown.field = f.instr.trimmingWhitespace(newlines: true)
                            if !shownText.isEmpty { addText(shownText, shown) }
                        }
                        // (An EQ field Word's Phonetic Guide wrote before w:ruby: `EQ \* jc0 \* "Font:.." \* hps16 \o(\s\up 19(にがつ),二月)`.
                        // The base is the text, the ruby rides over it like w:ruby's. lo-181b561b0a dropped both.)
                        if let f = notes.fields.last, !f.result, let eq = DocxFormat._eqRuby(f.instr) {
                            RuleTrace.hit("eq-ruby-like-w-ruby")
                            var look = notes.fieldCodeStyle[f.id] ?? cs
                            look.ruby = RubyText(text: eq.ruby, size: eq.size, raise: eq.raise, align: eq.align, group: text.utf16.count, xml: "")
                            addText(eq.base, look)
                        }
                        // (An overstrike stack with an item above and one below, `EQ \o(arrow,\s\up7(催化剂),\s\do7(△))`: Word sets the
                        // base's width, the over item rides 7 pt up at the base text size (RubyText size -1) and lifts its line (lo-ae4f3e8e p2 first line stands
                        // 4.8 pt lower, so the paragraph moves to the next page). The under item is not drawn yet.)
                        if let f = notes.fields.last, !f.result, let eq = DocxFormat._eqStack(f.instr) {
                            RuleTrace.hit("eq-stack-over-item-rides-up")
                            var look = notes.fieldCodeStyle[f.id] ?? cs
                            look.ruby = RubyText(text: eq.over, size: -1, raise: eq.raise, align: "center", group: text.utf16.count, xml: "")
                            addText(eq.base, look)
                        }
                        if let f = notes.fields.last, !f.result, let ringed = DocxFormat._ringedNumber(f.instr) {
                            // (The kept ring of an overstrike takes the code's own run style, 12 pt here,
                            // not the closing marker's bare one.)
                            var shown = ringed.unicodeScalars.first.map { (0x2460 ... 0x2473).contains($0.value) } == true ? cs : (notes.fieldCodeStyle[f.id] ?? cs)
                            shown.field = f.instr.trimmingWhitespace(newlines: true)
                            if let over = DocxFormat._ringOverlay(f.instr) {
                                // (The other character is drawn over the ring at the size of its own code run, 8 pt in 4fabe1f2; Word's print puts it on the ring's baseline, centred.)
                                shown.overlay = over
                                // (An eq ring's code run names no face of its own, so it takes the style's Korean face Word lacks (함초롬바탕), and Malgun's
                                // ascent moved its line's baseline 3.3 pt down while Word keeps it on the text's: 4fabe1f2 p2, three lines. A ring beside
                                // text in another Hangul-named face takes that face for the line; its width is the overlay's, as before.)
                                func hangulNamed(_ f: String?) -> Bool { f?.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) == true }
                                if shown.fontFamily == nil || hangulNamed(shown.fontFamily), hangulNamed(notes.lastTextFamily), notes.lastTextFamily != shown.fontFamily {
                                    RuleTrace.hit("eq-ring-line-takes-the-texts-hangul-face")
                                    shown.fontFamily = notes.lastTextFamily
                                    shown.eastAsiaFontFamily = notes.lastTextFamily
                                }
                                shown.overlaySize = (notes.fieldLastCodeStyle[f.id]?.fontSize ?? 0) > 0 ? notes.fieldLastCodeStyle[f.id]!.fontSize! : 8
                            }
                            addText(ringed, shown)
                        }
                        if !notes.fields.isEmpty { notes.fields.removeLast() }
                    default: break
                    }
                    // A form checkbox has no result text: it is the box
                    // itself, shown as a glyph (form_footnotes' 29 boxes).
                    // A drop-down form field shows its chosen entry, and has
                    // no result text of its own: zh-cd8987db's cover picks
                    // "（征求意见稿）", the fourth of its list, which Word
                    // prints and ours had left out.
                    if child["w:fldCharType"] == "begin", let list = child.first("w:ffData")?.first("w:ddList") {
                        let entries = list.all("w:listEntry").compactMap { $0["w:val"] }
                        let chosen = Int(list.first("w:result")?["w:val"] ?? list.first("w:default")?["w:val"] ?? "0") ?? 0
                        pendingDropdown = chosen >= 0 && chosen < entries.count ? entries[chosen] : nil
                    }
                    if child["w:fldCharType"] == "begin", let box = child.first("w:ffData")?.first("w:checkBox") {
                        let on = box.first("w:checked").map { !_isOff($0) } ?? (box.first("w:default")?["w:val"] == "1")
                        pendingCheckbox = on
                    }
                case "w:instrText":
                    // MACROBUTTON <macro> <display text>: Word draws the display
                    // text even though the field has no result part (the IA
                    // template's checklist link, where the text sits in a
                    // hyperlink's instrText run after the macro name).
                    if let f = notes.fields.last, !f.result,
                       f.instr.trimmingWhitespace(newlines: true).uppercased().hasPrefix("MACROBUTTON "),
                       f.instr.trimmingWhitespace(newlines: true).split(separator: " ").count >= 2,
                       !child.text.trimmingWhitespace(newlines: true).isEmpty {
                        addText(child.text, cs)
                    } else if let f = notes.fields.last, !f.result {
                        notes.fields[notes.fields.count - 1].instr += child.text
                        if notes.fields.count == 1, notes.fields[0].instr.uppercased().trimmingWhitespace(newlines: true).hasPrefix("TOC") {
                            notes.contentsStart = notes.fields[0].instr.trimmingWhitespace(newlines: true)
                        }
                        if notes.fieldCodeStyle[f.id] == nil, !child.text.trimmingWhitespace(newlines: true).isEmpty { notes.fieldCodeStyle[f.id] = cs }
                        if !child.text.trimmingWhitespace(newlines: true).isEmpty { notes.fieldLastCodeStyle[f.id] = cs }
                    }
                    if cs.formatChange != nil { notes.fieldCodeChanged = true }
                    if let on = pendingCheckbox, child.text.uppercased().containsSubstring("FORMCHECKBOX") {
                        var box = cs; box.formBox = true
                        addText(on ? "\u{2612}" : "\u{2610}", box)
                        pendingCheckbox = nil
                    }
                    if let entry = pendingDropdown, child.text.uppercased().containsSubstring("FORMDROPDOWN") {
                        addText(entry, cs)
                        pendingDropdown = nil
                    }
                case "w:commentReference":
                    notes.commentReferences += 1
                    // (A reference mark whose look was changed has a Formatted balloon of its own, and it parts the
                    // stretch before it from the one after: xb jpn ee9f8f's print, three balloons where the runs
                    // around the reference made one.)
                    if DocxFormat.wordOnWindows, let change = cs.formatChange, cs.revision?.kind != .deleted {
                        let said = PdfMarkup._describe(cs, was: change.oldRPrXML)
                        if !said.isEmpty { pendingRefChange = (said, change.author) }
                    }
                    // A comment with no range (comment.docx's LibreOffice
                    // comment) anchors at a point: a zero-width run carries
                    // it, so the balloon survives the save.
                    if notes.kept["word/comments.xml"] != nil, let id = child["w:id"], !notes.seenComments.contains(id) || !notes.carriedComments.contains(id) {
                        notes.seenComments.insert(id)
                        var point = cs
                        point.comments = cs.comments + [id]
                        addText("\u{200B}", point)
                    }
                case "w:delText": addText(child.text, cs)
                case "w:tab":
                    // (A tab in a field's code, between its begin and
                    // separate, is part of the instruction and shows
                    // nowhere: LibreOffice's fdo73596_RunInStyle INDEX field
                    // has `\e "<tab>"` there, and the tab took a line of its
                    // own in the paragraph that opens the field.)
                    if let f = notes.fields.last, !f.result { notes.fields[notes.fields.count - 1].instr += "\t" } else { addText("\t", cs) }
                // A positional tab (a header's or footer's "right of the
                // margin"): a tab the layout sends to its place on the
                // margins, whatever stops lie before it (bug57031's "Page
                // 2 of 14", whose right ptab is the line's first tab).
                case "w:ptab":
                    let alignment: TabStop.Alignment = child["w:alignment"] == "right" ? .right
                        : child["w:alignment"] == "center" ? .center : .left
                    if child["w:relativeTo"] != "indent" {
                        positionalTabs[text.utf16.filter { $0 == 0x09 }.count] = alignment
                    }
                    addText("\t", cs)
                case "w:br" where child["w:type"] == "page" && cellResolve != nil:
                    // A page break in a table cell is nothing: zh-8112041b's
                    // form title opens its cell with two, and Word's print
                    // sets it on the cell's first line, under the page's
                    // empty paragraphs, where ours split an empty line off.
                    if text.isEmpty, inlineImages.isEmpty, built.isEmpty { cellBreakOpens = true }
                case "w:br" where Self.wordOnWindows && revision?.kind == .deleted && !(revision?.moved ?? false) && (child["w:type"] == "page" || child["w:type"] == "column"):
                    // A page or column break inside a tracked deletion breaks
                    // nothing: Word's print of gv-ccf7f258bf holds the
                    // heading after one on the page before it.
                    break
                case "w:br":
                    // A page break ends the paragraph; a line break stays
                    // inside it, as Shift+Return's does — splitting it added a
                    // paragraph (and its spacing) on every soft break.
                    // (A column break opening a paragraph is the same on a
                    // page of one column: read as a line break, a Changhua
                    // grant notice's outline began on the page before.)
                    let opensWithColumnBreak = child["w:type"] == "column" && text.isEmpty && inlineImages.isEmpty && built.isEmpty && !leadingBreak
                    if opensWithColumnBreak { leadingColumnBreak = true }
                    if text.isEmpty, inlineImages.isEmpty, built.isEmpty, !leadingBreak { leadingBreakRPr = runPropertiesXML }
                    if child["w:type"] == "page" || opensWithColumnBreak {
                        // A break that OPENS its paragraph is the paragraph
                        // starting a page: split off, it left an empty
                        // paragraph before the break, and where the page was
                        // full that paragraph took a page of its own (a
                        // blank page three in a Fujian plan of four pages).
                        // (Decided at the paragraph's end: a paragraph that is
                        // ONLY the break keeps its line on the page before.)
                        if text.isEmpty, inlineImages.isEmpty, built.isEmpty, !leadingBreak { leadingBreak = true }
                        else {
                            flush(pageBreakAfter: true)
                            built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = runPropertiesXML
                            splitBefore = true
                        }
                    } else if child["w:type"] == "column", notes.hasColumns, !(text.isEmpty && inlineImages.isEmpty && built.isEmpty) {
                        // (In the middle of a paragraph, on a page of columns,
                        // a column break takes the rest of the paragraph to
                        // the next column — the next page from the last:
                        // LibreOffice's tdf153964_topMarginAfterBreak14.)
                        flush(pageBreakAfter: true)
                        built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = runPropertiesXML
                        built[built.count - 1].breakColumn = true
                        splitBefore = true
                    } else {
                        // (A clearing break right after the objects that open the paragraph: see `clearsFirstLine`.)
                        if Self.wordOnWindows, child["w:clear"] == "all", (child["w:type"] ?? "textWrapping") == "textWrapping",
                           !text.isEmpty, text.allSatisfy({ String($0) == RichParagraph.inlineImageCharacter }),
                           inlineImages.values.allSatisfy({ $0.float != nil }) { clearsFirstLine = true }
                        addText("\n", cs)
                    }
                case "w:noBreakHyphen": addText("\u{2011}", cs)
                case "w:softHyphen": addText("\u{00AD}", cs)
                case "w:ruby":
                    // Ruby over its base (furigana over kanji): the base is
                    // the run's text, in its own runs' looks, and the ruby
                    // rides on their style, to be drawn over them. 61470's
                    // "東京" under "とうきょう" was dropped whole, and its
                    // page came out blank.
                    guard let baseNode = child.first("w:rubyBase") else { break }
                    let pr = child.first("w:rubyPr"), rt = child.first("w:rt")
                    let rubyText = (rt?.all("w:r") ?? []).flatMap { $0.children.filter { $0.name == "w:t" } }.map(_runText).joined()
                    let ruby = RubyText(text: rubyText,
                                        size: (Double(pr?.first("w:hps")?["w:val"] ?? "") ?? 0) / 2,
                                        raise: (Double(pr?.first("w:hpsRaise")?["w:val"] ?? "") ?? 0) / 2,
                                        align: pr?.first("w:rubyAlign")?["w:val"],
                                        group: text.utf16.count,
                                        xml: [pr, rt].compactMap { $0.map { PptxXML.serialize($0) } }.joined())
                    for br in baseNode.all("w:r") {
                        var look = cs
                        if let rPr = br.first("w:rPr") {
                            if let id = rPr.first("w:rStyle")?["w:val"], let chain = notes.charStyleChains[id] {
                                for styled in chain { look = _charStyle(styled, base: look, complexText: false) }
                            }
                            look = _charStyle(rPr, base: look, complexText: false)
                        }
                        look.ruby = ruby
                        for t in br.children where t.name == "w:t" { addText(_runText(t), look) }
                    }
                case "w:sym":
                    // A symbol: the character means its glyph only in the
                    // named font (Symbol F094 is a box), so the run takes it.
                    if let code = child["w:char"], let v = UInt32(code, radix: 16), let sc = UnicodeScalar(v) {
                        var sym = cs
                        if let font = child["w:font"], !font.isEmpty { sym.fontFamily = font }
                        addText(String(Character(sc)), sym)
                    }
                case HtmlMissingPicture.element:
                    // An HTML chunk's picture Word cannot load (see `_htmlParagraphs`): its stand-in box, in the line.
                    let w = Double(child["w"] ?? "") ?? HtmlMissingPicture.side, h = Double(child["h"] ?? "") ?? HtmlMissingPicture.side
                    RuleTrace.hit("html-chunk-picture-not-loaded-is-a-stand-in-box")
                    addInline(ImageAttachment(data: HtmlMissingPicture.png, width: w, height: h, name: "missing-picture.png",
                                              naturalWidth: w, naturalHeight: h), run: cs)
                case "w:drawing", "w:pict":
                    // (An empty one is nothing: bug59058's `<w:pict/>`
                    // before a table is no mark on Word's print and takes
                    // no room there, where its 300 by 200 stand-in set
                    // the table 187pt low.)
                    guard !child.children.isEmpty else { break }
                    // (A VML pict of shape types only is definitions, not a shape: pt-408a10293d's first paragraph holds two and nothing else;
                    // read as a picture it stood a grey 300 by 200 box 187 pt tall on page 1, none in Word's print.)
                    if child.name == "w:pict", child.children.allSatisfy({ $0.name == "v:shapetype" }) { break }
                    // (A VML polyline alone — LibreOffice's FDO76248, a
                    // vertical rule over a table, `points` and no size —
                    // is not a box: read as the 300 by 200 stand-in it
                    // wrapped the text beside it in a grey square and sent
                    // 10 lines of page 3 to the right. It takes no room and
                    // wraps nothing in Word's print.)
                    // (A pict holding only a shape TYPE — a `v:shapetype` and no shape
                    // of it — draws nothing and takes no room: es-28716e1db6's header
                    // carried one and stood 164.7 pt tall on every page.)
                    if child.name == "w:pict", child.children.allSatisfy({ $0.name == "v:shapetype" }) { break }
                    if child.name == "w:pict", child.descendant("v:polyline") != nil,
                       child.descendant("v:textbox") == nil, child.descendant("v:imagedata") == nil { break }
                    // (A horizontal rule is a block: after text in the same paragraph Word sets it on a line of its own,
                    // numbered and a line tall. fd00b5's four, 47.8 to 79.2 by a break before each, no rebuild.)
                    if DocxFormat.wordOnWindows, child.name == "w:pict", child.descendant("v:rect")?["o:hr"] == "t",
                       !(text.isEmpty && inlineImages.isEmpty && built.isEmpty), !text.hasSuffix("\n") { addText("\n", cs) }
                    addImage(child)
                    // (And the text after it, in the same paragraph, on the next: 7f0539's
                    // "1. Introduction" stands a line below its rule in Word's print.)
                    if DocxFormat.wordOnWindows, child.name == "w:pict", child.descendant("v:rect")?["o:hr"] == "t" { ruleOpen = true }
                case "w:object":
                    addObject(child, run: cs)
                case "mc:AlternateContent":
                    // A Choice this app cannot draw — Word 2016's charts,
                    // `cx` — is the picture of it the Fallback holds:
                    // chartex's six charts took no room at all.
                    // A box-and-whisker chart or a sunburst is drawn as Word
                    // draws it, its text text (chartex's: 8 lines of Word's
                    // print, and the sunburst's 16).
                    let requires = (child.first("mc:Choice")?["Requires"] ?? "").split(separator: " ")
                    if child.first("mc:Choice")?.first("w16se:symEx") != nil, let fb = child.first("mc:Fallback") {
                        // (A symbol Word 2016 saves as w16se:symEx is a character, not an
                        // object: its Fallback holds the same character as text. Read as an
                        // object it stood a grey box 250 pt wide in the middle of 30775350's
                        // route line and pushed the rest of it down the page.)
                        for t in fb.children where t.name == "w:t" { addText(t.text, cs) }
                    } else if requires.contains(where: { $0 == "cx" }), let drawing = child.first("mc:Choice")?.first("w:drawing"),
                       boxWhisker(drawing) != nil {
                        addObject(drawing)
                    } else if requires.contains(where: { $0 == "cx" }), let drawing = child.first("mc:Fallback")?.first("w:drawing"),
                       drawing.descendant("a:blip") != nil {
                        addImage(drawing)
                    } else {
                        addObject(child)
                    }
                case "w:footnoteReference", "w:endnoteReference":
                    // The mark: its number as superscript text, tagged with
                    // the note it stands for so the writer puts the
                    // reference back. Word numbers marks in order of
                    // appearance; a custom mark (customMarkFollows) is the
                    // run's own text and needs no number.
                    let footnote = child.name == "w:footnoteReference"
                    guard footnote ? notes.footnotes : notes.endnotes, let id = Int(child["w:id"] ?? "") else { break }
                    // (Raised as its run says — its "footnote reference"
                    // style, most often: zh-7a16a243's marks are in runs
                    // that name no style, and Word's print sets "5" at the
                    // text's size on the line, 9.6pt wide where ours, raised
                    // and small, took 5.8 and a character more a line.)
                    var mark = cs
                    mark.note = NoteReference(kind: footnote ? .footnote : .endnote, id: id)
                    if child["w:customMarkFollows"] == "1" || child["w:customMarkFollows"] == "true" {
                        addText("\u{200B}", mark)
                        if !notes.inTextBox { if footnote { notes.customFootnotes.insert(id) } else { notes.customEndnotes.insert(id) } }
                    } else {
                        let n = notes.next(footnote: footnote, id: id)
                        if footnote, !notes.inTextBox, notes.footnoteNumbers[id] == nil { notes.footnoteNumbers[id] = n }
                        if !footnote, !notes.inTextBox, notes.endnoteNumbers[id] == nil { notes.endnoteNumbers[id] = n }
                        addText(notes.label(n, footnote: footnote), mark)
                    }
                case "w:footnoteRef":
                    // A note's own mark, in the note: its number.
                    if let n = notes.currentNote { addText(String(n), cs) }
                case "w:endnoteRef":
                    if let label = notes.currentNoteLabel { addText(label, cs) }
                default: break
                }
            }
        }
        func walkInline(_ node: XNode, link: String?, revision: RevisionMark? = nil) {
            let outerTip = hyperlinkTip, outerHistory = hyperlinkHistory
            defer { hyperlinkTip = outerTip; hyperlinkHistory = outerHistory }
            for child in node.children {
                switch child.name {
                case "w:r": walkRun(child, link: link, revision: revision)
                case "w:br" where DocxFormat.wordOnWindows:
                    // A break set straight in the paragraph, outside any run,
                    // still breaks the line in Word's print (dx2 zh 6ddc0960:
                    // the URL under the title); read as a run holding it.
                    let run = XNode(name: "w:r", attrs: [:])
                    run.children = [child]
                    walkRun(run, link: link, revision: revision)
                case "w:hyperlink":
                    // Word appends the bookmark to an external Target URL
                    // (MS-OI29500 2.1.521), even with r:id present.
                    let external = child["r:id"].flatMap { rels[$0] }
                    let target = external.map { $0 + (child["w:anchor"].map { "#\($0)" } ?? "") }
                        ?? child["w:anchor"].map { "#\($0)" }
                    hyperlinkTip = child["w:tooltip"]
                    hyperlinkHistory = ["1", "true", "on"].contains(child["w:history"] ?? "")
                    walkInline(child, link: target, revision: revision)
                case "w:ins", "w:del":
                    // Tracked changes stay tracked: the text with its mark,
                    // written back as the insertion or deletion it was.
                    // (Text moved away stays moved away, whatever was done
                    // to it before.)
                    // (Both changes are kept, as Tika-792 prints them: an
                    // insertion moved away is gone, a deletion in moved
                    // text's new place leaves the place marked.)
                    if var r = revision, r.moved, r.kind == .deleted {
                        if child.name == "w:ins" { r.nested = true }
                        walkInline(child, link: link, revision: r); break
                    }
                    let mark = RevisionMark(kind: child.name == "w:ins" ? .inserted : .deleted,
                                            author: child["w:author"] ?? "", date: child["w:date"] ?? "",
                                            nested: child.name == "w:del" && revision?.moved == true && revision?.kind == .inserted,
                                            segment: child.name == "w:del" ? notes.commentReferences : 0)
                    walkInline(child, link: link, revision: mark)
                case "w:moveTo", "w:moveFrom":
                    // Moved text: at its new place an insertion, at its old
                    // one a deletion, as Word shows them (Tika-792's; they
                    // were skipped, and the text was gone from the page and
                    // from a save).
                    let mark = RevisionMark(kind: child.name == "w:moveTo" ? .inserted : .deleted,
                                            author: child["w:author"] ?? "", date: child["w:date"] ?? "", moved: true)
                    walkInline(child, link: link, revision: mark)
                case "w:fldSimple" where Self._preservesField(child["w:instr"] ?? "") || notes.inHeaderFooter && DocxFormat._isPageField(child["w:instr"] ?? ""):
                    notes.fieldCount += 1
                    notes.fields.append((instr: child["w:instr"] ?? "", result: true, id: notes.fieldCount,
                                         properties: child.attrs.filter { $0.key == "w:fldLock" || $0.key == "w:dirty" }))
                    walkInline(child, link: link, revision: revision)
                    notes.fields.removeLast()
                case "w:smartTag", "w:sdtContent", "w:sdt", "w:fldSimple", "w:customXml":
                    // (A simple field with no result, a PAGEREF a table of contents left unupdated: Word's line still holds the field's own
                    // empty result in the paragraph's default face, so a 21 half-point Vazirmatn line with Times New Roman 12 defaults is
                    // 22.8 pt, not 22.34 (lab fas1 A/B: dropping the field gives 22.34), and its first baseline 0.48 pt lower.)
                    if child.name == "w:fldSimple", RichTextTheme.wordWindowsPages, child.children.isEmpty, !notes.inHeaderFooter {
                        RuleTrace.hit("empty-simple-field-leaves-a-default-face-strut")
                        addText("\u{2060}\u{2060}\u{2060}", cellChar)
                    }
                    // A content control over runs keeps its properties whole (W-RV-3), so a save writes it back.
                    if child.name == "w:sdt", let pr = child.first("w:sdtPr"), child.first("w:sdtContent") != nil,
                       let kept = Self._keptFragment(pr, notes) {
                        notes.controlCount += 1
                        let id = notes.controlCount
                        controlMarkers.append(RichControlMarker(id: id, properties: kept.xml, offset: text.utf16.count))
                        walkInline(child, link: link, revision: revision)
                        controlMarkers.append(RichControlMarker(id: id, offset: text.utf16.count))
                    } else {
                        walkInline(child, link: link, revision: revision)
                    }
                case "m:oMathPara", "m:oMath":
                    // (A comment whose reference stands inside the equation, its
                    // range empty, anchors at the equation: tdf170236's
                    // "Commented [A1]: Hello World!" balloon is in Word's print.)
                    if notes.kept["word/comments.xml"] != nil {
                        var stack: [XNode] = child.children.reversed()
                        while let n = stack.popLast() {
                            if n.name == "w:commentReference", let id = n["w:id"], !notes.anchoredComments.contains(id) {
                                notes.anchoredComments.insert(id)
                                RuleTrace.hit("comment-in-equation")
                                var point = cellChar
                                point.comments = [id]
                                addText("\u{200B}", point)
                            } else { stack.append(contentsOf: n.children.reversed()) }
                        }
                    }
                    // An equation: kept as the file wrote it, and drawn by
                    // `WriterMath` at the size it lays out to.
                    // (Word breaks an inline equation after a relation: its pieces are objects of their own.)
                    for piece in (child.name == "m:oMath" && RichTextTheme.wordWindowsPages ? WriterMath.splitAtRelations(child) : [child]) {
                        if let frag = _keptFragment(piece, notes) {
                            var att = ImageAttachment(data: Data(), width: 1, height: 1, name: piece.name)
                            att.sourceXML = frag.xml
                            att.sourceRels = frag.rels
                            // (Its runs' size where they say none: the paragraph's —
                            // its mark's, its style's, Normal's. zh-db07d44e's
                            // cell equation is 12pt in Word's print, Normal's, and
                            // breaks where 11 would hold a piece more.)
                            var mathSize: Double = 11
                            if let n = sheet["Normal"]?.char.fontSize { mathSize = n }
                            if let named = style.named, let n = sheet[named]?.char.fontSize { mathSize = n }
                            if let n = cellChar.fontSize { mathSize = n }
                            // An inline equation takes the style's size, not the mark's (xb jpn 6fca0f: style 12, mark 11, Word draws 12). A display equation (m:oMathPara) takes the style's too in compatibility mode 14 and up (ce4069f1 mode 14, 8b9d4558 mode 15), and the mark's below that (zh-8186c98d mode 12: mark 15, Word draws 15).
                            if child.name == "m:oMathPara", notes.compatMode < 14, let n = markStyle?.fontSize { mathSize = n }
                            var whole: (Double, Double)? = nil
                            var inkWhole: (Double, Double)? = nil
                            if let m = WriterMath.register(piece, for: att.id, size: mathSize, natural: { whole = $0 }, ink: { inkWhole = $0 }) {
                                if piece.name == "m:oMath", let w = whole { att.naturalExtent = (w.0, w.1) 
                                    if let k = inkWhole, frag.xml.containsSubstring("<m:f>"), !["<m:rad", "<m:nary", "<m:m>", "<m:eqArr>", "<m:limLow>", "<m:limUpp>"].contains(where: { frag.xml.containsSubstring($0) }) { att.naturalInk = (k.0, k.1) }
                                    att.stackedEquation = ["<m:f>", "<m:f ", "<m:rad>", "<m:rad ", "<m:nary>", "<m:nary ", "<m:m>", "<m:eqArr>", "<m:limLow>", "<m:limUpp>"].contains { frag.xml.containsSubstring($0) }
                                }
                                att.width = m.width
                                att.height = m.height
                                att.baseline = m.baseline
                            }
                            addInline(att)
                        }
                    }
                case "w:commentRangeStart":
                    if notes.kept["word/comments.xml"] != nil, let id = child["w:id"] { notes.openComments.append(id); notes.seenComments.insert(id) }
                case "w:commentRangeEnd":
                    if let id = child["w:id"] { notes.openComments.removeAll { $0 == id } }
                case "w:bookmarkStart":
                    if let name = child["w:name"], name != "_GoBack" {
                        notes.pendingBookmarks.append(name)
                        if let id = child["w:id"] { bookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: text.utf16.count)) }
                    }
                case "w:bookmarkEnd":
                    if let id = child["w:id"] { bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: text.utf16.count)) }
                case "w:pPr", "w:proofErr":
                    break
                default: break
                }
            }
        }
        walkInline(p, link: nil)
        // (A run of tabs that opens the paragraph, in a size of its own: the
        // line takes the text's, not the tab's. lo tdf164905's contents
        // entries open with a tab run of Calibri 11 and set their text in
        // 9pt Arial; Word's lines stand 16.35pt apart, the 9pt line and the
        // 6pt between, where ours took the 11pt tab's taller line and ran
        // 0.2pt a paragraph long.)
        if runs.count > 1, runs[0].style.fontSize != nil, runs[0].style.fontSize != runs[1].style.fontSize,
           runs[1].style.inlineImage == nil, text.utf16.prefix(runs[0].length).allSatisfy({ $0 == 0x09 }),
           !text.utf16.dropFirst(runs[0].length).prefix(runs[1].length).contains(0x09) {
            RuleTrace.hit("leading-tab-takes-text-size")
            runs[0].style.fontSize = runs[1].style.fontSize
            runs[0].style.fontFamily = runs[1].style.fontFamily
        }
        // (A display equation stands centred — Word's `m:jc` centerGroup,
        // its default — whatever its paragraph's own alignment.)
        // (An equation that is a line break alone, the paragraph's picture and
        // caption after it: only its own line is centred, and the rest keeps the
        // paragraph's alignment. xb jpn 7f0539's Figure 5 caption stands at the
        // left margin in Word's print, 85.1, and stood centred at 232.3 in ours.)
        let breakOnlyMath = RichTextTheme.wordWindowsPages && p.first("m:oMathPara").map { d in
            d.descendants("m:t").isEmpty && !d.descendants("w:br").isEmpty
                && p.children.contains { $0.name == "w:r" }
        } ?? false
        if breakOnlyMath { RuleTrace.hit("break-only-equation-leaves-its-paragraphs-alignment") }
        if let display = p.first("m:oMathPara"), !breakOnlyMath {
            switch display.first("m:oMathParaPr")?.first("m:jc")?["m:val"] ?? _mathDefaultJc {
            case "left": style.alignment = .left
            case "right": style.alignment = .right
            default: style.alignment = .center
            }
        }
        else if p.children.contains(where: { $0.name == "m:oMath" }),
                p.children.allSatisfy({ ["w:pPr", "w:proofErr", "w:bookmarkStart", "w:bookmarkEnd", "m:oMath"].contains($0.name) }) {
            // (A paragraph that holds nothing but a bare `m:oMath` is a
            // display equation to Word too, centred like an `m:oMathPara`:
            // LibreOffice's tdf169843, whose ℝ stands at the page's middle
            // in Word's print and at the left margin in ours.)
            style.alignment = .center
        }
        if cellBreakOpens { style.cellBreakOpens = true }
        if leadingBreak {
            // (A break followed by floating objects alone is a break too:
            // the objects stand with the paragraph's start, on the page
            // before, and the new page shows nothing for the mark — lab
            // `ab` (Word 16, zh-021b8feb's p14 paragraph: a page break and
            // a box "附表" 16.5pt down) sets the box at p14's foot, and the
            // next paragraph where it stands after a break alone; ours set
            // the box on p15 over a line of the mark, 20.7pt, and the
            // table after it ran onto a 19th page.)
            let floatsOnly = !inlineImages.isEmpty && inlineImages.values.allSatisfy { $0.float.map { !$0.takesRoom } ?? false }
            // (Not after a COLUMN break with objects: the paragraph's own line opens the
            // next column, its objects with it — lo tdf153592's three columns
            // each open with the break and a text box's anchor, and Word's
            // print gives the 2nd and 3rd a line before their text, and draws
            // the boxes, which ours dropped.)
            let pageBreakAlone = built.isEmpty && text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }) && (inlineImages.isEmpty || floatsOnly)
            let columnWithObjects = leadingColumnBreak && !inlineImages.isEmpty
            if pageBreakAlone, columnWithObjects { RuleTrace.hit("column-break-keeps-its-paragraph-line") }
            if pageBreakAlone, !columnWithObjects {
                flush(pageBreakAfter: true)
                built[built.count - 1].breakCharacter = true; built[built.count - 1].breakRPr = leadingBreakRPr
                built[built.count - 1].breakColumn = leadingColumnBreak
                splitBefore = true   // (what follows the break is the same paragraph's: see where the body is written)
            }
            else if built.isEmpty { style.pageBreakBefore = true; style.pageBreakInline = true; style.columnBreak = leadingColumnBreak; style.breakRunPropertiesXML = leadingBreakRPr }
            else {
                built[0].paragraph.style.pageBreakBefore = true; built[0].paragraph.style.pageBreakInline = true
                built[0].paragraph.style.columnBreak = leadingColumnBreak; built[0].paragraph.style.breakRunPropertiesXML = leadingBreakRPr
            }
        }
        if text.isEmpty, inlineImages.isEmpty, let last = built.last, last.pageBreakAfter,
           !(notes.marksFollowBreaks && last.breakCharacter && !last.breakColumn),
           !(Self.wordOnWindows && notes.hasColumns && notes.columnMarksFollow && last.breakCharacter && last.breakColumn) {
            // The paragraph ended with its page break: Word shows nothing
            // for its mark on the new page (SampleDoc's page two began
            // a line down), so no empty paragraph for it — the break
            // still lands on the next paragraph.
            // (Unless the file says the mark goes there, as Word's
            // `w:splitPgBreakAndParaMark` does before 2013's layout:
            // zh-64044a1d's annexes each follow a paragraph of a page
            // break alone, and Word's print opens their pages with the
            // mark's empty line — ours stood a line high, 36pt with the
            // heading's space before.)
            if sectionBreakAfter { built[built.count - 1].pageBreakAfter = true }
        } else {
            let markFollows = text.isEmpty && inlineImages.isEmpty && notes.marksFollowBreaks && (built.last.map { $0.pageBreakAfter && $0.breakCharacter && !$0.breakColumn } ?? false)
            flush(pageBreakAfter: sectionBreakAfter)
            if markFollows, built.count > 1 { built[built.count - 1].paragraph.style.markFollowsBreak = true }
        }
        if sectionMarginsChange, !built.isEmpty { built[built.count - 1].sectionMarginsChange = true }
        if built.count > 1 { for k in 0 ..< built.count - 1 { Self._sectionMarkStaysOnTheLastPiece(&built[k].paragraph) } }
        return built
    }
}
