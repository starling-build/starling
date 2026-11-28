// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

extension SlideContext {
    /// A run's text as read: a symbol face's private-range codes (`a:sym`, or the run's own face) as the glyphs they show.
    /// (Shared with `PptxTextPatch`, which must see a run's text as the model holds it.)
    static func symbolsShown(_ t: String, _ rPr: XNode?) -> String {
        guard t.unicodeScalars.contains(where: { (0xF020 ... 0xF0FF).contains($0.value) }),
              let face = rPr?.first("a:sym")?["typeface"] ?? rPr?.first("a:latin")?["typeface"] else { return t }
        return String(t.map { ch -> Character in
            guard let v = ch.unicodeScalars.first?.value, (0xF020 ... 0xF0FF).contains(v) else { return ch }
            let shown = Metafile.symbols(String(ch), face: face)
            return shown == String(ch) ? ch : (shown.first ?? ch)
        })
    }

    /// The complex script a character is written in (the theme's key for
    /// it), nil for any other.
    static func complexScript(_ v: UInt32) -> String? {
        switch v {
        case 0x0590 ... 0x05FF, 0xFB1D ... 0xFB4F: return "Hebr"
        case 0x0600 ... 0x06FF, 0x0750 ... 0x077F, 0xFB50 ... 0xFDFF, 0xFE70 ... 0xFEFF: return "Arab"
        case 0x0E00 ... 0x0E7F: return "Thai"
        default: return nil
        }
    }

    /// A face PowerPoint does not kern, whatever `kern` says: it kerns
    /// by a face's `kern` table, and these have none — Work Sans and
    /// Poppins kern only in their OpenType layout (tdf140852's "Training"
    /// and lo-master-slides' "Avoid" at their plain widths in
    /// PowerPoint's print, where ours were 4 and 1.5 pt shorter), Tahoma
    /// Bold too, and Century Gothic not at all (its stand-in does).
    static func _unkerned(_ family: String?, bold: Bool) -> Bool {
        guard let n = family?.trimmingWhitespace().lowercased() else { return false }
        return n.hasPrefix("work sans") || n.hasPrefix("poppins") || n.hasPrefix("century gothic") || (bold && n == "tahoma")
    }

    /// Whether the first strong letter of `text` is Hebrew or Arabic
    /// (a letter, not a digit or a mark, before any Latin one).
    static func _startsRightToLeft(_ text: String) -> Bool {
        for u in text.unicodeScalars {
            switch u.value {
            case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF:
                if u.properties.isAlphabetic { return true }
            default:
                if u.properties.isAlphabetic { return false }
            }
        }
        return false
    }

    /// A run's Latin face. A Latin slot that points at the theme's East Asian face (+mn-ea) where that names nothing is
    /// the theme's face for the run's language script, as for its East Asian letters: ja 24b61c69 p8's runs (lang ja-JP,
    /// latin and ea both +mn-ea over a theme with an empty ea and Jpan MS PGothic) set their digits and （，） in MS PGothic.
    func _font(_ f: String?, lang: String?, altLang: String? = nil) -> String {
        if f == "+mn-ea" || f == "+mj-ea" {
            let table = f == "+mj-ea" ? theme.majorScript : theme.minorScript
            // (A run tagged en-US over altLang ja-JP, a digit run in Japanese text, is the same: 5f748a0e p5's "466" in +mj-ea is HGPGothicE in the print, not the theme's Latin face.)
            let l = (lang ?? "").lowercased().hasPrefix("ja") || (altLang ?? "").lowercased().hasPrefix("ja") ? "ja" : (lang ?? "").lowercased()
            if (table["ea"] ?? "").isEmpty, l.hasPrefix("ja"), let j = table["Jpan"], !j.isEmpty { return j }
            // (Not a Japanese run: PowerPoint prints the Latin slot's +mj-ea over a theme with an empty East Asian face in Arial, not the theme's Latin face: 1892a5a76df6 p201's bold digits are Arial's 8.9 pt at 16 pt, Constantia's 7.3 in ours.)
            // (A run tagged en-US over altLang zh-TW, a digit run in Traditional Chinese text, is the theme's Hant face: 3c1f2c4d820b p7's "4" after "總人次：" is PMingLiU's 4.0 pt at 8 pt in the print, so it fits the line where Arial's 4.4 wrapped.)
            if (table["ea"] ?? "").isEmpty, !l.hasPrefix("ja") {
                let alt = (altLang ?? "").lowercased()
                if alt == "zh-tw" || alt == "zh-hk" || alt == "zh-mo", let h = table["Hant"], !h.isEmpty { return h }
                return "Arial"
            }
        }
        return _font(f)
    }

    /// A percent of spacing is of the line: 1.2 em, or in a SmartArt paragraph in an East Asian face Word's line of it.
    func _spacingLine(_ p: XNode) -> Double {
        guard inDiagram, let r = p.first("a:r")?.first("a:rPr") else { return 1.2 }
        let lang = r["lang"]
        let f = r.first("a:ea")?["typeface"].map { _font($0, lang: lang) } ?? r.first("a:latin")?["typeface"].map { _font($0, lang: lang) }
        return f.flatMap { SlideFonts.diagramEastAsianLine($0)?.height } ?? 1.2
    }

    func _font(_ f: String?) -> String {
        switch f {
        case nil, "+mn-lt", "+mn-ea", "+mn-cs": return theme.minor
        case "+mj-lt", "+mj-ea", "+mj-cs": return theme.major
        default: return f!
        }
    }

    func _text(_ sp: XNode, ph: XNode?, inherited: (layout: XNode?, master: XNode?),
                       kind: ShapeKind) -> TextBody {
        // The shape style's text colour (fontRef), under any the text says.
        let styleColor = sp.first("p:style")?.first("a:fontRef").flatMap(colors.color(in:))
        let tx1 = styleColor ?? colors.scheme("tx1")
        let body = sp.first("p:txBody")
        // Body properties: the shape's, else its layout's, else the master's.
        let bodies = [body?.first("a:bodyPr"),
                      inherited.layout?.first("p:txBody")?.first("a:bodyPr"),
                      inherited.master?.first("p:txBody")?.first("a:bodyPr")]
        let noWrapBody = bodies.compactMap { $0?["wrap"] }.first == "none"
        func attr(_ name: String) -> String? { bodies.lazy.compactMap { $0?[name] }.first }
        let anchor: TextAnchor = {
            switch attr("anchor") {
            case "ctr": return .middle
            case "b": return .bottom
            // Absent everywhere means top, for every kind of shape: PowerPoint
            // writes anchor="ctr" when it wants a drawn shape centred.
            default: return .top
            }
        }()
        func inset(_ n: String, _ d: Double) -> Double { attr(n).flatMap(Double.init).map { $0 / Pptx.emu } ?? d }
        let insets = EdgeInsets(left: inset("lIns", 7.2), top: inset("tIns", 3.6),
                                right: inset("rIns", 7.2), bottom: inset("bIns", 3.6))
        // normAutofit's fontScale: PowerPoint shrank the text to fit. The
        // sizes stay the file's; the shape draws them at the scale.
        let scale = (body?.first("a:bodyPr")?.first("a:normAutofit")?["fontScale"].flatMap(Double.init)).map { $0 / 100000 } ?? 1
        let reduction = (body?.first("a:bodyPr")?.first("a:normAutofit")?["lnSpcReduction"].flatMap(Double.init)).map { $0 / 100000 } ?? 0
        let fitRule = bodies.lazy.compactMap { b in
            b?.children.first { ["a:normAutofit", "a:spAutoFit", "a:noAutofit"].contains($0.name) }?.name
        }.first
        let list = body?.first("a:lstStyle")

        // The style's text colour (fontRef) beats what the layout and master
        // say, not what the shape's own list style or paragraph says.
        // So does its face (`fontRef idx`): customGeo's boxes say "minor"
        // (Calibri) over a deck default of Arial, and PowerPoint sets them
        // in Calibri.
        let styleFont: String? = sp.first("p:style")?.first("a:fontRef")?["idx"].flatMap {
            $0 == "major" ? "+mj-lt" : $0 == "minor" ? "+mn-lt" : nil
        }
        func styled(_ l: LevelStyle, _ n: Int, _ pPr: XNode?) -> LevelStyle {
            var l = l
            let own = LevelStyle.paragraph(pPr, colors), listed = LevelStyle.paragraph(list?.first("a:lvl\(n + 1)pPr"), colors)
            if let sf = styleFont, own.font == nil, listed.font == nil { l.font = sf }
            guard let sc = styleColor, own.color == nil, listed.color == nil else { return l }
            l.color = sc
            return l
        }
        let level0 = styled(_level(0, shapeList: list, ph: ph, inherited: inherited), 0, nil)
        // The list slot the layout indents by, per level: the text edge
        // level 0 declares (marL), or — for a shape whose level 0 has none, a
        // SmartArt's text — the hang of its first bulleted paragraph, so the
        // bullet has a slot to be drawn in rather than none.
        var listIndent = level0.marL.flatMap { $0 > 0 ? $0 : nil }
        if listIndent == nil {
            for p in body?.all("a:p") ?? [] {
                guard let pPr = p.first("a:pPr"), pPr.has("a:buChar") || pPr.has("a:buAutoNum") else { continue }
                if let ind = pPr["indent"].flatMap(Double.init), ind < 0 { listIndent = -ind / Pptx.emu; break }
                if let m = pPr["marL"].flatMap(Double.init), m > 0 {
                    listIndent = m / Pptx.emu / Double((pPr["lvl"].flatMap(Int.init) ?? 0) + 1)
                    break
                }
            }
        }
        let shapeIndent = listIndent ?? 18
        var runLooks: [[RunLook]] = []
        var paragraphs: [RichParagraph] = []
        let allParagraphs = body?.all("a:p") ?? []
        // Each paragraph's level and numbering scheme, for the runs of
        // numbers below.
        var paragraphLevels: [Int] = []
        var paragraphDefTab: Double? = nil
        var numbering: [(type: String, start: Int)?] = []
        for p in allParagraphs {
            let pPr = p.first("a:pPr")
            let lvl = pPr?["lvl"].flatMap(Int.init) ?? 0
            let picture: (String) -> ImageAttachment? = { rid in
                guard let rel = self.package.rels(self.part).first(where: { $0.id == rid }), !rel.external,
                      self.package.parts[rel.target] != nil else { return nil }
                return self.images.attachment(rel.target, self.package)
            }
            let level = styled(LevelStyle.paragraph(pPr, colors, picture: picture).filled(from: _level(lvl, shapeList: list, ph: ph, inherited: inherited)), lvl, pPr)
            // What a percentage of spacing is a percentage of: the size the
            // paragraph's runs are actually set in (a SmartArt label is 31 pt
            // by its runs under a level that says nothing), else the level's.
            let runSizes = p.all("a:r").compactMap { $0.first("a:rPr")?["sz"].flatMap(Double.init).map { $0 / 100 } }
            // (An empty paragraph's by its end mark: alterman's 24 pt blank
            // lines under a 28 pt level, each 1.3 pt further apart.)
            let endSize = p.all("a:r").isEmpty ? p.first("a:endParaRPr")?["sz"].flatMap(Double.init).map { $0 / 100 } : nil
            let size = runSizes.max() ?? endSize ?? level.size ?? 18
            // (PowerPoint for Windows sets the space before and after and an exact line spacing on whole points:
            // labs p3b and p3c, 5.67 pt -> 6, 17.01 -> 17, 27.5 -> 28. Not under its shrink to fit, where the
            // spacing is scaled and lo-font-scale's 6.41 stands as it is.)
            let whole: (Double) -> Double = { $0.rounded() }
            var style = RichParagraphStyle(spaceAfter: level.afterPoints.map(whole) ?? 0, lineSpacing: 1.0)
            switch level.algn {
            case "ctr": style.alignment = .center
            case "r": style.alignment = .right
            case "just": style.alignment = .justify
            // (A distributed paragraph spreads its last line across the width too, as Word's does:
            // zh-142399e8a3 p10's "退休時領取", five characters down a 204 pt column, in PowerPoint's print 64.7 pt apart.)
            case "dist": style.alignment = .justify; style.eastAsian["w:jc"] = "distribute"
            default: style.alignment = .left
            }
            if let hp = p.first("a:pPr")?["hangingPunct"] ?? level.hangingPunct, hp == "0" || hp == "1" { style.eastAsian["a:hangingPunct"] = hp }
            if let b = level.latinLnBrk { style.eastAsian["a:latinLnBrk"] = b }
            else if p.all("a:r").contains(where: { ($0.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("ko") }) {
                // (Lab ko-latinlnbrk round 2: with latinLnBrk stated nowhere, a run that names Korean holds its Hangul words whole at
                // the line end, one that names no language parts them mid-word.)
                style.eastAsian["a:latinLnBrk"] = "0"
            }
            // (PowerPoint hangs every closing mark, ) ] and the like, a full em past the margin in Chinese text: lab zhhang, four
            // faces in zh-TW and zh-CN. It follows the language of the run that holds the mark.)
            // (A Latin ")" in an en-US run that closes a Chinese phrase hangs as well when the paragraph names Chinese: 1d619a8046f0 p2
            // title "…課題(一)" holds on one 604 pt line with the ")" 11 pt past the margin.)
            let paraZh = p.all("a:r").contains(where: { ($0.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("zh") || ($0.first("a:rPr")?["altLang"] ?? "").lowercased().hasPrefix("zh") })
            if paraZh, p.all("a:r").contains(where: { ($0.first("a:t")?.text ?? "") == ")" }) {
                style.eastAsian["a:hangClosingZh"] = "1"
            }
            // (PowerPoint prints an East Asian face it does not have as Microsoft JhengHei when the run says Traditional Chinese; its
            // exact lines stand on that face's metrics: 7fc5fcbcda59 p31, 80 pt lines of 辰宇落雁體.)
            if p.all("a:r").contains(where: { r in ["lang", "altLang"].contains { ["zh-tw", "zh-hk", "zh-mo", "zh-hant"].contains((r.first("a:rPr")?[$0] ?? "").lowercased()) } }) {
                style.eastAsian["a:missingFaceJhenghei"] = "1"
            }
            if p.all("a:r").contains(where: { r in
                (r.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("zh")
                    && (r.first("a:t")?.text ?? "").unicodeScalars.contains(where: { [0xFF09, 0x300D, 0x300F, 0x3011, 0x3015, 0x300B, 0x3009, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F].contains($0.value) }) }) {
                style.eastAsian["a:hangClosingZh"] = "1"
            }
            if (p.first("a:pPr")?["eaLnBrk"] ?? level.eaLnBrk) == "0" { style.eastAsian["a:eaLnBrk"] = "0" }
            // (A paragraph whose runs are all tagged en-US, with no East Asian language anywhere, gets no East Asian line rules in PowerPoint's print: a3e81ffb3c9d p8
            // opens lines with ， and 」 where ours kept them with the ideograph before.)
            let runLangs = p.all("a:r").compactMap { $0.first("a:rPr")?["lang"]?.lowercased() }
            if !runLangs.isEmpty, runLangs.allSatisfy({ $0.hasPrefix("en") }), !p.all("a:r").contains(where: { ($0.first("a:rPr")?["altLang"] ?? "").lowercased().hasPrefix("zh") }) { style.eastAsian["a:eaLnBrk"] = "0" }
            // (A Simplified Chinese paragraph (zh-CN, zh-SG) keeps a mark with the ideograph before it even with East Asian line breaking off: 9e09a947a0fd p77 breaks 集合。 before 合, never
            // before 。; the lab that set a mark alone at a line start was Japanese, and PowerPoint's Traditional Chinese (zh-TW) prints also set a mark alone, 2ecd39405f78 p9.)
            if p.all("a:r").contains(where: { ($0.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("zh-c") || ($0.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("zh-s") }) { style.eastAsian["a:zhText"] = "1" }
            if looseKinsoku { style.eastAsian["a:looseKinsoku"] = "1" }
            if let m = level.lineMultiple { style.lineSpacing = m } else if let pts = level.linePoints {
                // Exactly that many points, whatever the runs' sizes.
                style.lineHeightPoints = whole(pts)
            } else {
                style.lineSpacingUnstated = true
            }
            // (A percentage is of the text as drawn: under PowerPoint's own
            // shrink to fit, `fontScale` of it — bug62513's 20% before its
            // 77.5% list items is 6 pt in the print, ours was 7.7.)
            // (PowerPoint draws a shrunk run at a whole number of points, so the percentage is of that size: 60810's 20% before
            // its 16 pt items at 92.5% is 3.6 pt in the print, 0.2 * 1.2 * 15, ours was 3.55.)
            let drawnSize = scale == 1 ? size : max(1, (size * scale).rounded())
            style.spaceBefore = level.beforePoints.map(whole) ?? (level.beforePercent.map { $0 * drawnSize * _spacingLine(p) } ?? 0)
            // A percentage after, as before: of the line, taken as 1.2 of the
            // size — but not under the last paragraph, where PowerPoint adds
            // nothing: counted there, a one-line SmartArt label (35% after,
            // every one) measured taller than its box and was shrunk to fit.
            if level.afterPoints == nil, let pct = level.afterPercent, p !== allParagraphs.last {
                style.spaceAfter = pct * drawnSize * _spacingLine(p)
            }
            // (Nor in points: bnc904423's centred boxes, 11.5 pt after their
            // one paragraph, stood 5.75 high.)
            // (`spcFirstLastPara="1"` keeps it: SlidePainter's anchor counts it.)
            if p === allParagraphs.last, !(["1", "true"].contains(attr("spcFirstLastPara") ?? "")) { style.spaceAfter = 0 }
            paragraphLevels.append(lvl)
            if paragraphDefTab == nil { paragraphDefTab = level.defTab }
            if let t = level.defTab, t != (paragraphDefTab ?? level0.defTab ?? 72) { style.defaultTab = t }
            numbering.append(level.bullet == .number ? (level.autoNumType ?? "arabicPeriod", level.autoNumStart ?? 1) : nil)
            switch level.bullet {
            case .char?, .number?:
                style.list = level.bullet == .char ? .bullet : .numbered
                style.listLevel = lvl
                if level.bullet == .char { style.bulletText = level.bulletGlyph; style.bulletInk = level.bulletInk }
                if level.bullet == .char { style.bulletPicture = level.bulletPicture }
                style.bulletColor = level.bulletColor
                style.bulletScale = level.bulletScale
                // A bullet of so many points is that share of this text's size
                // (ab07bcf5: the layout's 16 pt × before 40 pt headings).
                if let pts = level.bulletPoints, size > 0 { style.bulletScale = pts / size }
                // The bullet's own face — but not a symbol face, whose codes
                // were turned into the glyphs they show and are set in the
                // text's.
                if level.bullet == .char, let f = level.bulletFont,
                   !["wingdings", "symbol", "webdings"].contains(where: { f.lowercased().hasPrefix($0) }) {
                    style.bulletFontFamily = _font(f)
                }
                // Wingdings' round bullet, the commonest of them (46 decks),
                // is 0.565 of an em across and stands 0.09 above the
                // baseline: Carlito's "●" at 1.23 times is that, where the
                // text's own was three quarters of its size.
                if level.bullet == .char, level.bulletFont?.lowercased() == "wingdings", style.bulletText == "●" {
                    style.bulletStandInFamily = OfficeFonts.calibri
                    style.bulletStandInScale = 0.565 / 0.46
                }
                // The Symbol face's asterisk (code 2A) is 0.36 of an em across and 0.40 high, while the stand-in "∗" is 0.58 across
                // and stands 0.28 em (of the smaller marker) low (3c310d53 p8, 28 pt: PowerPoint's ink 10.0 x 11.3 pt, 176.9 to 188.0).
                if level.bullet == .char, level.bulletFont?.lowercased().hasPrefix("symbol") == true, style.bulletText == "∗" {
                    style.bulletStandInScale = 0.36 / 0.58
                    style.bulletStandInRaise = 0.28
                }
                // The file's own text edge (marL) and bullet offset (indent):
                // the text placed where the file puts it, both written back
                // as read. The layout indents a list by the shape's list
                // indent per level; indentLeft carries the difference.
                if let marL = level.marL { style.indentLeft = marL - shapeIndent * Double(lvl + 1) }
                // As an offset from the usual hang (-shapeIndent), so 0 is
                // "the usual" and a file's indent="0" survives as itself.
                // A bullet that would stand left of the text area (marL + indent below 0) stands at the area's edge:
                // PowerPoint's print of pt ca992b5b p4 (marL 0, indent -18) puts it at the box's text edge, the text after it. Only for a marL the paragraph states: lo-bullet-indent's
                // unstated marL (text 25.5 in, indent -25.5) already lands right on the layout's own rule.
                // (A blank bullet, the master's " ", is left to the layout's slot rule, which mirrors a hang past the margin.)
                if let indent = level.indent {
                    let blank = style.bulletText.map { !$0.isEmpty && $0.allSatisfy { $0 == " " } } ?? false
                    // (No layer states a left edge and the paragraph has no bullet: the edge is 0, and a hang past it stands at it, ko-2a9e73116d p2 "2. 로그인…".)
                    let edge = level.marL ?? ((level.bullet ?? Bullet.none) == .none && !blank ? 0 : nil)
                    style.firstLineIndent = (blank || edge == nil ? indent : max(indent, -(edge ?? 0))) + shapeIndent
                    if !blank, let marL = level.marL, marL + indent < 0 { style.firstTextLead = -indent - marL }
                }
                // A text edge with no offset said anywhere is offset 0, as
                // the format's default: aascu 5864's text boxes' "•" at
                // marL 0 stands at the edge with its text after it, where
                // it hung in the margin.
                else if level.marL != nil { style.firstLineIndent = shapeIndent }
                // Neither said anywhere (an export with no default text
                // style, ececapstone's): PowerPoint's own, half an inch a
                // level and no hang — the bullet at the edge, the text
                // after it.
                if level.marL == nil, level.indent == nil {
                    style.indentLeft = 36 * Double(lvl) - shapeIndent * Double(lvl + 1)
                    style.firstLineIndent = shapeIndent
                }
                // (The bullet PowerPoint's own body style gives, in a deck whose master has no text styles at
                // all: its print of lo-subtitle-animation-save puts the text 17.6 pt from the bullet's left,
                // the bullet's 9.8 and an Arial space after it. A bullet the paragraph names, ececapstone's,
                // has the text right after it.)
                if level.marL == nil, level.indent == nil, lvl == 0, master?.first("p:txStyles") == nil,
                   pPr?.first("a:buChar") == nil, pPr?.first("a:buAutoNum") == nil, ["body", "subTitle"].contains(ph?["type"] ?? "") {
                    style.indentLeft = 17.6 - shapeIndent
                    style.firstLineIndent = shapeIndent - 17.6
                }
                SlideContext.hangPositiveIndent(&style, own: pPr?["indent"].flatMap(Double.init), indent: level.indent,
                                                marL: level.marL, shapeIndent: shapeIndent, level: lvl)
            default:
                style.indentLeft = level.marL ?? 0
                // (A hang past the text area's edge stands at the edge: ko-2a9e73116d p2, indent -18 with no left edge, line 1 at the edge.)
                style.firstLineIndent = max(level.indent ?? 0, -(level.marL ?? 0))
            }
            // The paragraph's right margin (marR): the line breaks that far short of the box's edge.
            if let marR = level.marR, marR > 0 { style.indentRight = marR }
            if let tabs = level.tabs { style.tabStops = tabs }

            var text = ""
            var runs: [Run] = []
            var looks: [RunLook] = []
            var plainMarks: [Int] = []
            var koParens: [Int] = []
            var arabicTailFace: String? = nil   // (the Latin face of a run whose last piece is Arabic: the paragraph mark's, where it states none)
            var mathImages: [String: ImageAttachment] = [:]
            func add(_ t0: String, _ r: LevelStyle, _ rPr: XNode? = nil, inline: String? = nil) {
                guard !t0.isEmpty else { return }
                // A symbol face's private-range codes as the glyphs they show
                // (`a:sym` Symbol, or the run's own face): GeomLec1's U+F0DE
                // is Symbol's "⇒", and drew as nothing.
                let t = Self.symbolsShown(t0, rPr)
                let symbolRun = t != t0 && (rPr?.first("a:sym")?["typeface"] ?? "").lowercased() == "symbol"
                var look = _runLook(rPr) ?? RunLook()
                look.length = t.utf16.count
                looks.append(look)
                let s = r.filled(from: level)
                var cs = CharStyle(bold: s.bold ?? false, italic: s.italic ?? false,
                                   underline: s.underline ?? false, strikethrough: s.strike ?? false,
                                   fontFamily: _font(s.font, lang: s.lang, altLang: s.altLang), fontSize: ((s.size ?? 18) * 10).rounded() / 10,
                                   color: s.color ?? tx1)
                if s.underline == true { cs.underlineKind = s.underlineKind }
                if let b = s.baseline { cs.script = b > 0 ? .superscript : b < 0 ? .subscript : .normal }
                if let spc = s.spc, spc != 0 { cs.letterSpacing = spc }
                // Kerned from the size `kern` says up (PowerPoint's own
                // masters say 12 pt); none where it says nothing.
                if Self._unkerned(cs.fontFamily, bold: cs.bold) { cs.kerningFrom = 0 } else { cs.kerningFrom = s.kern ?? unsaidKern }
                if symbolRun { cs.symbolFace = "Symbol" }
                let click = package.clickAction(rPr?.first("a:hlinkClick"), part: part)
                cs.link = click.link; cs.linkTip = click.tip
                let plain = cs
                Self.faceSpacing(&cs)
                cs.shadow = s.shadow
                cs.highlight = s.highlight
                // (WordArt draws its own outline: `RunLook`.)
                if body?.first("a:bodyPr")?.first("a:prstTxWarp") == nil, (cs.color?.alpha ?? 255) == 255 { cs.outline = s.outline; cs.noFill = s.noFill && s.outline != nil }
                if s.caps == "all" { cs.caps = true } else if s.caps == "small" { cs.smallCaps = true }
                if let inline { cs.inlineImage = inline }
                // (A 、。，． in a run tagged with a language that is not East Asian (an untagged run inherits the deck's) does not hang:
                // 505a93a9 p14's untagged 。 opens the next line alone.)
                if let l = (s.lang ?? defaults?.first("a:defPPr")?.first("a:defRPr")?["lang"])?.lowercased(), !l.isEmpty, !["ja", "ko", "zh"].contains(where: { l.hasPrefix($0) }), !(s.altLang ?? "").lowercased().hasPrefix("zh") {
                    var at = text.utf16.count
                    for u in t.utf16 { if u == 0x3001 || u == 0x3002 || u == 0xFF0C || u == 0xFF0E { plainMarks.append(at) }; at += 1 }
                }
                // (A ")" after a Latin letter in a run tagged Korean hangs like one after Hangul: ko-4f5289a9 p6 keeps "(전류원 DB, CB Counter)"
                // whole in PowerPoint's print, its ")" 0.8 pt past the cell. In a ja run it does not (lab hang3 slide 6).)
                koParens += Self.koParenOffsets(s, t, before: text)
                text += t
                // Hebrew, Arabic and Thai letters in the complex-script
                // face, as PowerPoint sets them: tdf98603's Hebrew title is
                // in the theme's Times New Roman for Hebrew (one line), not
                // Calibri Light's fallback (two). Spaces, digits and
                // punctuation go with the letters before them.
                let runsBefore = runs.count
                var pieces: [(length: Int, script: String?)] = []
                let explicitLatin = rPr?.first("a:latin")?["typeface"].map { !$0.isEmpty && !$0.hasPrefix("+") } ?? false
                // (A run whose Latin slot is the theme's East Asian font (+mn-ea) sets its spaces in that face.)
                let latinIsEastAsianFace = rPr?.first("a:latin")?["typeface"].map { $0.hasSuffix("-ea") } ?? false
                var sawLetter = false
                let latinName = plain.fontFamily ?? ""
                for ch in t.unicodeScalars {
                    let n = ch.utf16.count
                    var script = Self.complexScript(ch.value) ?? (Self.isEastAsian(ch.value) && ch.value != 0x3000 ? "ea" : nil)
                    // (A symbol the run's Latin face lacks (by its measured coverage: ℃ ℉ № and the like, in the letterlike, arrow and math blocks) that Cambria Math holds is drawn in Cambria Math, as PowerPoint's print
                    // does: 998cb8 p9's "65℃" step is 0.906 em, the fallback face's 1.125.)
                    if script == nil, ch.value >= 0x2100, ch.value < 0x2400, RichLayout._latinFaceLacks(latinName, ch.value) == true, OfficeFonts.cambriaMathScript[ch.value] != nil { script = "cmath" }
                    let letter = script != nil || ch.properties.isAlphabetic
                    if pieces.isEmpty {
                        pieces.append((n, script))
                        sawLetter = letter
                    } else if ch.value == 0x20, explicitLatin, pieces[pieces.count - 1].script == "ea" {
                        // (A run that names its own Latin face sets the space between East Asian words in it, not in the East Asian face:
                        // ko-3d95d35b's Times New Roman runs, 5.0 pt a space at 20 pt in PowerPoint's print, Malgun's is 7.0.)
                        pieces.append((n, nil))
                    } else if ch.value < 0x80, !letter, pieces[pieces.count - 1].script == "ea", ch.value != 0x20 || explicitLatin {
                        // (An ASCII character is set in the Latin slot's face, between Hangul too: the "(" and ")" of a run naming Batang
                        // as Latin only are Batang's 4.50 pt at 12, not the theme Hangul face's 3.62; ko-d8f0a8af p5.)
                        if pieces[pieces.count - 1].script == nil { pieces[pieces.count - 1].length += n } else { pieces.append((n, nil)) }
                    } else if letter, !sawLetter, script == "ea", pieces[pieces.count - 1].script == nil,
                              Array(t.utf16.prefix(pieces[pieces.count - 1].length)).allSatisfy({ $0 < 0x80 }) {
                        // (An ASCII mark ahead of the first East Asian letter keeps the Latin slot too: the "(" of "(一)封面" is 8.2 pt at 25.56 in
                        // PowerPoint's print, not the East Asian face's 12.8; zh dcf0f34a8d3a p11.)
                        pieces.append((n, script))
                        sawLetter = true
                    } else if letter, !sawLetter {
                        // The first letter claims what came before it.
                        pieces[pieces.count - 1].script = script
                        pieces[pieces.count - 1].length += n
                        sawLetter = true
                    } else if letter, script != pieces[pieces.count - 1].script {
                        pieces.append((n, script))
                    } else {
                        pieces[pieces.count - 1].length += n
                    }
                }
                // (A run of spaces and punctuation alone, tagged with a right-to-left language, is set in that script's face, not the
                // Latin one: 7854f160's " (" and ")" runs (fa-IR) take B Nazanin's stand-in, 14 pt for the pair, where Georgia's took 19.6.)
                if pieces.count == 1, pieces[0].script == nil, !sawLetter,
                   !t.unicodeScalars.contains(where: { $0.properties.isAlphabetic }),
                   // (Digits too where the complex face is an installed one that keeps them: 6f97f2ee p9's "(1689-1755)" in an ar-IQ run
                   // is set in Sakkal Majalla Bold in PowerPoint's print, 216 pt wide, not in the Latin face, 241. "Majalla UI" is that face.)
                   !t.unicodeScalars.contains(where: { $0.value >= 0x30 && $0.value <= 0x39 })
                    || ["majalla ui"].contains((_csFont(s.csFont, script: "Arab", lang: s.lang, arabicCharset: s.csArabicCharset) ?? "").lowercased())
                    || OfficeFonts.complexFaceKeepsDigits(_csFont(s.csFont, script: "Arab", lang: s.lang, arabicCharset: s.csArabicCharset) ?? "")
                    || SlideFonts.embeddedFaceKeepsDigits(_csFont(s.csFont, script: "Arab", lang: s.lang, arabicCharset: s.csArabicCharset) ?? "") {
                    let l = (s.lang ?? "").lowercased()
                    if ["ar", "fa", "ur", "ps", "sd", "ug", "ku"].contains(where: { l.hasPrefix($0) }) { pieces[0].script = "Arab" }
                    else if l.hasPrefix("he") || l.hasPrefix("yi") { pieces[0].script = "Hebr" }
                }
                let utf16 = Array(t.utf16)
                // Ordinary spaces ahead of East Asian letters stay in the Latin face (5c820695 p2: an ideographic space and 57
                // spaces before 予防が重要; the spaces step Calibri's 0.226 em, not the East Asian face's 0.305, and the
                // line is one line, as printed); ideographic spaces go with the letters (505a93a9 p1).
                var split: [(length: Int, script: String?)] = []
                var at = 0
                for piece in pieces {
                    if piece.script == "ea" {
                        var k = at
                        while k < at + piece.length, utf16[k] == 0x20 || utf16[k] == 0x3000 { k += 1 }
                        if k > at, k < at + piece.length, utf16[at ..< k].contains(0x20) {
                            var m = at
                            while m < k {
                                var e = m + 1
                                while e < k, (utf16[e] == 0x20) == (utf16[m] == 0x20) { e += 1 }
                                split.append((e - m, utf16[m] == 0x20 ? nil : "ea"))
                                m = e
                            }
                            split.append((at + piece.length - k, "ea"))
                            at += piece.length
                            continue
                        }
                    }
                    if piece.script == "ea", !latinIsEastAsianFace, utf16[at ..< at + piece.length].contains(0x20) {
                        // (A run of two or more ordinary spaces between East Asian letters is set in the Latin face too: a874c38f10a1 p63's
                        // five spaces between 最高 and 最低 step 5.6 pt at 20 pt in PowerPoint's print, 0.28 em, not SimSun's 10.)
                        // (PMingLiU is not on PowerPoint's print box: a single space between ideographs of a run in it steps the Latin face's
                        // 0.25 em, 0b068d237320 p45's 6.7 pt at 28 pt, not the fallback's 14.)
                        let proportionalMing = ["pmingliu", "新細明體"].contains((_eaFont(s.eaFont ?? s.font, scalar: 0x4E00, lang: s.lang, latin: s.font) ?? "").lowercased())
                        var out: [(length: Int, script: String?)] = []
                        var m = at
                        let end = at + piece.length
                        var changed = false
                        while m < end {
                            var e = m + 1
                            if utf16[m] == 0x20 {
                                while e < end, utf16[e] == 0x20 { e += 1 }
                                if e - m >= 2 || proportionalMing { out.append((e - m, nil)); changed = true; m = e; continue }
                            }
                            while e < end, !(utf16[e] == 0x20 && e + 1 < end && utf16[e + 1] == 0x20) { e += 1 }
                            out.append((e - m, "ea"))
                            m = e
                        }
                        if changed { split.append(contentsOf: out); at = end; continue }
                    }
                    if piece.script == nil, utf16[at ..< at + piece.length].contains(0x3000), utf16[at ..< at + piece.length].allSatisfy({ $0 == 0x3000 || $0 == 0x20 }) {
                        // An ideographic space is East Asian wherever it stands, also in a run of spaces alone
                        // (505a93a9 p1: 30 of them ahead of 西部教育事務所, 0.664 em of MS PGothic each, not a full em).
                        var m = at
                        while m < at + piece.length {
                            var e = m + 1
                            while e < at + piece.length, (utf16[e] == 0x3000) == (utf16[m] == 0x3000) { e += 1 }
                            split.append((e - m, utf16[m] == 0x3000 ? "ea" : nil))
                            m = e
                        }
                        at += piece.length
                        continue
                    }
                    split.append(piece)
                    at += piece.length
                }
                // (A Korean run's ○ □ ① and the other symbols Malgun Gothic sets an em wide are East Asian characters: PowerPoint draws them
                // in the East Asian face, a full circle, not in the Latin stand-in's smaller one. ko-ca2dc787 p18's "○ " in HY헤드라인M
                // is Malgun's 18.0 pt circle in the print, the Liberation Sans one 10.9 pt.)
                if [s.lang, s.altLang].contains(where: { ($0 ?? "").lowercased().hasPrefix("ko") }), OfficeFonts.cjkFallback.first != nil,
                   t.unicodeScalars.contains(where: { SlideFonts.malgunEmSymbolSet.contains($0.value) }) {
                    var out: [(length: Int, script: String?)] = []
                    var pos = 0
                    for piece in split {
                        let slice = String(decoding: utf16[pos ..< pos + piece.length], as: UTF16.self)
                        pos += piece.length
                        guard piece.script == nil || piece.script == "ea", slice.unicodeScalars.contains(where: { SlideFonts.malgunEmSymbolSet.contains($0.value) }) else { out.append(piece); continue }
                        var run = 0
                        var runIsSymbol = false
                        for u in slice.unicodeScalars {
                            let isSym = SlideFonts.malgunEmSymbolSet.contains(u.value)
                            if run > 0, isSym != runIsSymbol { out.append((run, runIsSymbol ? "sym" : piece.script)); run = 0 }
                            runIsSymbol = isSym; run += u.utf16.count
                        }
                        if run > 0 { out.append((run, runIsSymbol ? "sym" : piece.script)) }
                    }
                    split = out
                }
                pieces = split
                var consumed = 0
                for piece in pieces {
                    defer { consumed += piece.length }
                    var c = cs
                    // (Not where the complex face is one the deck embeds: its own line already holds the paragraph as PowerPoint draws it, and the
                    // Latin mark would lower it 1.3 pt: 7854f160 p1, 5a8cce85 p1 and p2 in B Nazanin and B Titr stand where the print has them.)
                    arabicTailFace = piece.script == "Arab" && !SlideFonts.isEmbedded(_csFont(s.csFont, script: "Arab", lang: s.lang, arabicCharset: s.csArabicCharset) ?? "") ? plain.fontFamily : nil
                    if piece.script == "cmath" {
                        c = plain
                        c.fontFamily = "Cambria Math"
                        c.shadow = cs.shadow; c.outline = cs.outline; c.highlight = cs.highlight; c.caps = cs.caps; c.smallCaps = cs.smallCaps
                    } else if piece.script == "sym", let cjk = OfficeFonts.cjkFallback.first {
                        c = plain
                        c.fontFamily = cjk
                        c.shadow = cs.shadow; c.outline = cs.outline; c.highlight = cs.highlight; c.caps = cs.caps; c.smallCaps = cs.smallCaps
                    } else if piece.script == "ea" {
                        // (The first letter of the piece names its script.)
                        let slice = String(decoding: utf16[consumed ..< min(utf16.count, consumed + piece.length)], as: UTF16.self)
                        let first = slice.unicodeScalars.first { Self.isEastAsian($0.value) }?.value ?? 0x4E00
                        if let face = _eaFont(s.eaFont ?? s.font, scalar: first, lang: s.lang, latin: s.font),
                           face != plain.fontFamily {
                            c = plain
                            c.fontFamily = face
                            c.shadow = cs.shadow; c.outline = cs.outline; c.highlight = cs.highlight; c.caps = cs.caps; c.smallCaps = cs.smallCaps
                        }
                    } else if let script = piece.script, let face = _csFont(s.csFont, script: script, lang: s.lang, arabicCharset: s.csArabicCharset), face != plain.fontFamily {
                        c = plain
                        c.fontFamily = face
                        c.shadow = cs.shadow; c.outline = cs.outline; c.highlight = cs.highlight; c.caps = cs.caps; c.smallCaps = cs.smallCaps
                    }
                    if let last = runs.last, last.style == c, runs.count > runsBefore {
                        runs[runs.count - 1].length += piece.length
                    } else {
                        runs.append(Run(length: piece.length, style: c))
                    }
                }
            }
            for child in p.children {
                switch child.name {
                case "a:r": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle(), child.first("a:rPr"))
                case "a:br":
                    // In a box that does not wrap, a space just before the
                    // break is part of its line as PowerPoint centres and
                    // right-aligns it: cooper's "OVERVIEW OF THE ", 32 pt
                    // and centred, stands half a space left of where the
                    // engine, trimming it, put it. Kept as a no-break space,
                    // as wide, which it keeps. A wrapping box hangs it past
                    // the edge as at any wrap (cooper's slide 11 title, the
                    // same XML in a wrapping box, stands where trimmed).
                    if noWrapBody, text.hasSuffix(" ") { text = String(text.dropLast()) + "\u{00A0}" }
                    // (A break that opens a line holding nothing else is that line's whole height: an empty line has no glyph to
                    // give the engine its size, so it is given a zero-width one in the break's run. 2b078099 p3's title opens on
                    // a 28 pt break; PowerPoint's print has that blank line 30 pt tall, ours was 3.8 and the title 14.5 pt high.)
                    if text.isEmpty || text.hasSuffix("\n") {
                        add("\u{200B}", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                    }
                    add("\n", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle())
                case "a:fld": add(child.first("a:t")?.text ?? "", child.first("a:rPr").map { LevelStyle.run($0, colors) } ?? LevelStyle(), child.first("a:rPr"))
                case "a14:m":
                    // An equation, laid out and drawn by `WriterMath` as real text (PowerPoint prints Cambria Math glyphs).
                    // (An equation alone in its paragraph is a display equation in PowerPoint's print: centred, fractions full size,
                    // a sum's limits over and under it. A bare m:oMath is set as one, as an m:oMathPara is.)
                    let alone = p.children.filter { $0.name != "a:pPr" && $0.name != "a:endParaRPr" && !($0.name == "a:r" && ($0.first("a:t")?.text ?? "").isEmpty) }.count == 1
                    for var piece in child.children where piece.name == "m:oMath" || piece.name == "m:oMathPara" {
                        if alone, piece.name == "m:oMath", child.children.count == 1 {
                            let para = XNode(name: "m:oMathPara", attrs: [:])
                            para.children.append(piece)
                            piece = para
                        }
                        let first = piece.descendants("m:r").first?.first("a:rPr")
                        let look = first.map { LevelStyle.run($0, colors) } ?? LevelStyle()
                        let size = look.filled(from: level).size ?? 18
                        WriterMath.slideScope = true; WriterMath.slideInk = look.filled(from: level).color
                        defer { WriterMath.slideScope = false; WriterMath.slideInk = nil }
                        var att = ImageAttachment(data: Data(), width: 1, height: 1, name: piece.name)
                        guard let m = WriterMath.register(piece, for: att.id, size: size) else { continue }
                        att.width = m.width; att.height = m.height; att.baseline = m.baseline
                        mathImages[att.id] = att
                        add(RichParagraph.inlineImageCharacter, look, first, inline: att.id)
                    }
                default: continue
                }
            }
            // (The empty line after a trailing break is the paragraph mark's, in the size it states or the level's, not the break's:
            // 3a3f59a1 p1's box ends in an 18 pt break over an 8 pt mark, and PowerPoint's print stands its text 6 pt lower.)
            if text.hasSuffix("\n") {
                let s = (p.first("a:endParaRPr").map { LevelStyle.run($0, colors) } ?? LevelStyle()).filled(from: level)
                let mark = CharStyle(
                    bold: s.bold ?? false, italic: s.italic ?? false, fontFamily: _font(s.font),
                    fontSize: ((s.size ?? 18) * ((s.baseline ?? 0) != 0 ? 2.0 / 3 : 1) * 10).rounded() / 10, color: s.color ?? tx1)
                // (A raised or lowered mark is two thirds of its size: bab9be95 p14's 14 pt mark over a break stands its next paragraph 28.1 pt on, not 33.6.)
                if runs.last != nil {
                    text += "\u{200B}"
                    runs.append(Run(length: 1, style: mark))
                }
            }
            if text.isEmpty {
                let end = p.first("a:endParaRPr").map { LevelStyle.run($0, colors) } ?? LevelStyle()
                let s = end.filled(from: level)
                // (A mark whose Latin slot names the theme's East Asian face (+mj-ea, +mn-ea) is set in that face, as its
                // text would be: PowerPoint's print of a SmartArt node's empty paragraphs, 5c820695 and lab sa5c, has them a
                // full East Asian line tall, where Calibri's was 2.2 pt short.)
                let markFace: String = (s.font?.hasSuffix("-ea") ?? false) ? (_eaFont(s.font, scalar: 0x3042, lang: s.lang, latin: nil) ?? _font(s.font)) : _font(s.font)
                paragraphs.append(RichParagraph(text: "", runs: [Run(length: 0, style: CharStyle(
                    bold: s.bold ?? false, italic: s.italic ?? false, fontFamily: markFace,
                    fontSize: ((s.size ?? 18) * 10).rounded() / 10, color: s.color ?? tx1))],
                    style: style))
            } else {
                // A bullet before a link is in the text's own colour, not
                // the link's: customGeo's resources list has black bullets
                // before its blue links in PowerPoint's print.
                if style.list != nil, style.bulletColor == nil,
                   let first = p.children.first(where: { $0.name == "a:r" })?.first("a:rPr"),
                   let link = first.first("a:hlinkClick"), link.descendant("ahyp:hlinkClr")?["val"] != "tx" {
                    style.bulletColor = first.first("a:solidFill").flatMap { colors.color(in: $0) } ?? level.color ?? tx1
                }
                // Right to left where the paragraph says so, or where its
                // first strong letter is Hebrew or Arabic and it says
                // nothing itself: tdf98603's quoted Hebrew under a master
                // that says left to right, its opening quote at the right
                // in PowerPoint's print.
                let own = p.first("a:pPr")?["rtl"]
                // (A paragraph that says rtl="1" over Latin text alone, no list: PowerPoint's print
                // keeps the letters' order, its closing colon at the right end, aligned as algn says
                // — e311341c p8 'Different west bank governorates:'. Nothing there is right to left.)
                let hasRtlLetter = text.unicodeScalars.contains { u in
                    (0x0590 ... 0x08FF ~= u.value || 0xFB1D ... 0xFDFF ~= u.value || 0xFE70 ... 0xFEFF ~= u.value) && u.properties.isAlphabetic }
                if (own == "1" && (hasRtlLetter || style.list != nil)) || (own == nil && Self._startsRightToLeft(text)) {
                    style.rightToLeft = true
                    // (DrawingML's algn l and r are the page's left and right, rtl or not: PowerPoint prints lo-rightToLeftParagraph's
                    // algn="r" rtl="1" at the right. The layout swaps them for a right-to-left paragraph as Word's jc start/end,
                    // so hand it the opposite pair.)
                    if style.alignment == .left { style.alignment = .right } else if style.alignment == .right { style.alignment = .left }
                    if style.list != nil { style.bulletAtEnd = true }
                    // (A right-to-left paragraph's marL is its margin at the START edge, the right: PowerPoint's print stands eb7ab2c5's
                    // algn="r" lines marL 6.48 pt in from the box's inset, 690 pt, ours 696.)
                    if style.list == nil, own == "1", style.indentLeft != 0 || style.indentRight != 0 {
                        swap(&style.indentLeft, &style.indentRight)
                    }
                }
                // A master level that says rtl="1" moves the bullet and the
                // list indent to the right and nothing else (GeomLec1's body:
                // PowerPoint's print keeps the text's order and its alignment).
                else if own == nil, level.rtl == "1", style.list != nil { style.bulletAtEnd = true }
                if let e = p.first("a:endParaRPr").map({ LevelStyle.run($0, colors).filled(from: level) }) {
                    // (A paragraph that ends in East Asian letters has its end mark in the East Asian face the same way.)
                    var mark = _font(e.font)
                    if let last = text.unicodeScalars.last(where: { $0.value != 0x0A && $0.value != 0x0B }), Self.isEastAsian(last.value), last.value != 0x3000,
                       let ea = _eaFont(e.eaFont ?? e.font, scalar: last.value, lang: e.lang, latin: e.font) { mark = ea }
                    if mark != runs.last?.style.fontFamily { style.endMarkFace = mark }
                    // (A paragraph that ends in a line break ends with an empty line of its end mark's size, not the last run's:
                    // efe520c1 p4's title, 36 pt lines ending in a break over a 32 pt mark at 90%, stands 3.7 pt lower in PowerPoint's print.)
                    if text.hasSuffix("\n") {
                        var cs = CharStyle(bold: e.bold ?? false, italic: e.italic ?? false, fontFamily: mark,
                                           fontSize: ((e.size ?? 18) * 10).rounded() / 10, color: e.color ?? tx1)
                        cs.kerningFrom = 0
                        style.mark = cs
                    }
                }
                // (A paragraph of Arabic alone with no end mark of its own: PowerPoint holds the line at the run's Latin face, as it does
                // with a Latin run after the Arabic, not at the complex-script face's own height. rtl/6f97f2ee p3's bare Arabic names in
                // Tahoma 22 pt, 50% before, stand 39.6 pt apart in PowerPoint's print, ours 25.5.)
                if p.first("a:endParaRPr") == nil, !inDiagram, let face = arabicTailFace, face != runs.last?.style.fontFamily { style.endMarkFace = face }
                // (A paragraph with no end mark of its own that ends in East Asian letters: the mark takes the last run's Latin face, and
                // PowerPoint's last line is set by it beside the East Asian face; lab num2, ja 18 and 24 pt in MS Gothic and HGS Mincho
                // under Palatino, Century Gothic and the theme face: the last line of each paragraph 0.076 em higher, the lines before it as
                // the East Asian face alone.)
                else if p.first("a:endParaRPr") == nil, !inDiagram, style.endMarkFace == nil, attr("vert") == nil || attr("vert") == "horz",
                        let lastRun = p.all("a:r").last, let rp = lastRun.first("a:rPr"),
                    // (Only where the run names its East Asian face: every box of lab lift2 does. Where the face comes from the theme's script font, as in 24b61c69cd1c (lift3), PowerPoint's line stands 0.08 em lower than ours, lifted or not: not understood yet.)
                        let eaNamed = rp.first("a:ea")?["typeface"], !eaNamed.isEmpty, !eaNamed.hasPrefix("+"),
                        let last = text.unicodeScalars.last(where: { $0.value != 0x0A && $0.value != 0x0B }), Self.isEastAsian(last.value), last.value != 0x3000 {
                    let ls = LevelStyle.run(rp, colors).filled(from: level)
                    let latin = _font(ls.font)
                    if latin != runs.last?.style.fontFamily { style.endMarkFace = latin; style.endMarkLastOnly = true }
                }
                // (A diagram paragraph with no end mark of its own, ending in East Asian letters, ends in the East Asian face as well:
                // PowerPoint's print of lab sa5c sets its last line as the lines that have an end mark.)
                else if inDiagram, let last = text.unicodeScalars.last(where: { $0.value != 0x0A && $0.value != 0x0B }), Self.isEastAsian(last.value), last.value != 0x3000,
                        let ea = _eaFont(level.eaFont ?? level.font, scalar: last.value, lang: level.lang, latin: level.font), ea != runs.last?.style.fontFamily {
                    style.endMarkFace = ea
                }
                // (A right-aligned paragraph in a box that does not wrap keeps its closing spaces in the line, as PowerPoint right-aligns it:
                // ko-4f5289a9 p8-10's "①" + 30 spaces is drawn from x 485 to the margin at 672.6 in its print, the digit at the left of the
                // run; ours hung the spaces and set it at the margin. Kept as no-break spaces, as wide, which the engine keeps.)
                var text = text
                if noWrapBody, style.alignment == .right, text.hasSuffix(" "), let at = text.lastIndex(where: { $0 != " " }) {
                    text = String(text[...at]) + String(repeating: "\u{00A0}", count: text.distance(from: at, to: text.endIndex) - 1)
                }
                var made = RichParagraph(text: text, runs: runs, style: style)
                made.inlineImages = mathImages
                // (Lab mixrun, PowerPoint's print: outside a table too, fontAlgn t, ctr or b stands each run's glyph box in the 1.2 em line, as in a cell
                // (lab tbl-rows7): the lines of Arial 35 pt with t print 2.4 pt higher than with none, Book Antiqua 1.0 lower, PMingLiU 4.7 higher. The
                // face of the most characters stands for the line; a run of another face in it, which PowerPoint sets by its own box, is not moved.)
                if !text.isEmpty, let algn = p.first("a:pPr")?["fontAlgn"], algn == "t" || algn == "ctr" || algn == "b" {
                    // (Each run stands on its own glyph box: `alignTop` is where its baseline falls below the line's top and `alignNatural` where
                    // the engine's own line puts it, both in ems of the run's size. A line of runs of one face and size is moved as a whole by
                    // `cellFontAlignDrop`; a line that mixes them is set run by run in RichLayout (lab mixrun, 97ff p6/p7).)
                    func box(_ r: Run) -> (top: Double, natural: Double)? {
                        guard let face = r.style.fontFamily, let m = SlideFonts.windowsAscentDescent(face) else { return nil }
                        let target: Double
                        switch algn { case "t": target = m.ascent; case "ctr": target = (1.2 - (m.ascent + m.descent)) / 2 + m.ascent; default: target = 1.2 - m.descent }
                        return (target, 1.2 * (1 - m.descent / (m.ascent + m.descent)))
                    }
                    var seen = Set<String>()
                    for r in runs where r.length > 0 { if let b = box(r) { seen.insert("\(b.top)/\(b.natural)/\(r.style.fontSize ?? 0)") } else { seen.insert("none") } }
                    if seen.count > 1, !seen.contains("none") {
                        for k in made.runs.indices where made.runs[k].length > 0 {
                            if let b = box(made.runs[k]) { made.runs[k].style.alignTop = b.top; made.runs[k].style.alignNatural = b.natural }
                        }
                        made.style.alignPerRun = true
                    } else if let lead = zip(runs, runs.indices).max(by: { $0.0.length != $1.0.length ? $0.0.length < $1.0.length : $0.1 > $1.1 })?.0, let b = box(lead) {
                        made.style.cellFontAlignDrop = b.top - b.natural
                    }
                }
                if !koParens.isEmpty { made.style.eastAsian["a:hangParens"] = koParens.map(String.init).joined(separator: ",") }
                if !plainMarks.isEmpty { made.style.eastAsian["a:noHangMarks"] = plainMarks.map(String.init).joined(separator: ",") }
                // (A display equation sits by its own `m:jc` (centred by default), whatever the paragraph says.)
                let bareAlone = p.children.filter { $0.name != "a:pPr" && $0.name != "a:endParaRPr" && !($0.name == "a:r" && ($0.first("a:t")?.text ?? "").isEmpty) }.count == 1
                    && p.first("a14:m")?.children.count == 1 && p.first("a14:m")?.first("m:oMath") != nil
                if !mathImages.isEmpty, let para = p.all("a14:m").first?.first("m:oMathPara") ?? (bareAlone ? XNode(name: "m:oMathPara", attrs: [:]) : nil), p.all("a:r").filter({ !($0.first("a:t")?.text ?? "").isEmpty }).isEmpty {
                    switch para.first("m:oMathParaPr")?.first("m:jc")?["m:val"] {
                    case "left": made.style.alignment = .left
                    case "right": made.style.alignment = .right
                    default: made.style.alignment = .center
                    }
                    // (A display equation paragraph stands no space before: 51f605f6 p22's equation, under a 10 pt space-before, has
                    // its baseline 24 pt under the line above in PowerPoint's print, one line of the text, where ours stood 34.)
                    made.style.spaceBefore = 0
                }
                paragraphs.append(made)
            }
            runLooks.append(looks)
        }
        // Looks matter only where some run has one.
        if !runLooks.contains(where: { $0.contains { !$0.isPlain } }) { runLooks = [] }
        let warp: TextWarp? = (body?.first("a:bodyPr")?.first("a:prstTxWarp")).flatMap { w in
            guard let preset = w["prst"], preset != "textNoShape" else { return nil }
            let adjust = (w.first("a:avLst")?.all("a:gd") ?? []).compactMap { gd -> Double? in
                guard let f = gd["fmla"], f.hasPrefix("val ") else { return nil }
                return Double(f.dropFirst(4))
            }
            // (A plain, unslanted warp on text that wraps in its box (no wrap="none") is no WordArt: PowerPoint sets it as ordinary text,
            // letter spacing and all; KYWA's header boxes (textPlain, no adjust) wrapped a word early when fitted as WordArt.)
            if preset == "textPlain", adjust.first.map({ $0 == 50000 }) ?? true, (body?.first("a:bodyPr")?["wrap"] ?? "square") != "none" { return nil }
            // (A plain warp on one unwrapped line in a box that sizes itself to its text (spAutoFit) still fits the text to the stored box:
            // PowerPoint's print of ko-e114b968 and ko-c03ed80e's layout footers (18 pt text in a 7.8 pt tall box) sets them small,
            // not at 18 pt running off the page; an earlier rule set them as plain text for the text layer's sake and was wrong on the page.)
            var tw = TextWarp(preset: preset, adjust: adjust, xml: PptxXML.serialize(w))
            tw.fromWordArt = ["1", "true"].contains(body?.first("a:bodyPr")?["fromWordArt"] ?? "")
            return tw
        }
        if paragraphs.isEmpty {
            var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: level0.lineMultiple ?? 1.0)
            style.alignment = level0.algn == "ctr" ? .center : level0.algn == "r" ? .right : .left
            if level0.bullet == .char { style.list = .bullet }
            paragraphs = [RichParagraph(text: "", style: style)]
        }
        // Tabs go to the next stop a default distance apart (`defTabSz`,
        // an inch unless the level says otherwise) from the text's left.
        var bodyDocument = RichDocument(paragraphs: paragraphs)
        Self._numberRuns(&bodyDocument, levels: paragraphLevels, numbering: numbering)
        bodyDocument.defaultTabStop = paragraphDefTab ?? level0.defTab ?? 72
        // (An eaVert column's places are the face's vmtx advance, not an em: Malgun Gothic 2176/2048 = 21.25 pt at 20 pt, printed 21.24 in lab vface;
        // set as the spacing after each ideograph, which stands centred in its place.)
        if attr("vert") == "eaVert" {
            // (A Japanese column hangs its closing full-width marks past the column end; a horizontal Japanese line does not, 9 ja decks.)
            for pi in bodyDocument.paragraphs.indices where bodyDocument.paragraphs[pi].text.unicodeScalars.contains(where: { [0xFF09, 0x300D, 0x300F, 0x3011, 0x3015, 0x300B, 0x3009, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F].contains($0.value) }) {
                bodyDocument.paragraphs[pi].style.eastAsian["a:hangClosingZh"] = "1"
            }
            for pi in bodyDocument.paragraphs.indices { for ri in bodyDocument.paragraphs[pi].runs.indices {
                let st = bodyDocument.paragraphs[pi].runs[ri].style
                if let m = SlideFonts.uprightMetrics(st.fontFamily ?? "", bold: st.bold == true), m.step != 1, let size = st.fontSize {
                    bodyDocument.paragraphs[pi].runs[ri].style.letterSpacing = (st.letterSpacing ?? 0) + (m.step - 1) * size
                }
            } }
            // (MS PGothic's places are its vmtx advances, kana and marks narrower than an em: each such character takes the spacing that
            // sets its place, as its own run; ja-4d99f560bb p14 steps 15-17 pt at 18 pt where an em set 18.)
            for pi in bodyDocument.paragraphs.indices {
                let units = Array(bodyDocument.paragraphs[pi].text.utf16)
                var out: [Run] = [], at = 0
                for r in bodyDocument.paragraphs[pi].runs {
                    guard SlideFonts.proportionalUprightFace(r.style.fontFamily ?? ""), let size = r.style.fontSize else { out.append(r); at += r.length; continue }
                    var k = at
                    while k < at + r.length {
                        let v = SlideVerticalAdvances.pgothicAdvance(units[k])
                        var j = k + 1
                        while j < at + r.length, SlideVerticalAdvances.pgothicAdvance(units[j]) == v { j += 1 }
                        var piece = r; piece.length = j - k
                        if let v { piece.style.letterSpacing = (r.style.letterSpacing ?? 0) + (Double(v) / 256 - 1) * size }
                        out.append(piece); k = j
                    }
                    at += r.length
                }
                bodyDocument.paragraphs[pi].runs = out
            }
        }
        var body0 = TextBody(document: bodyDocument, anchor: anchor, insets: insets,
                        font: _font(level0.font), size: level0.size ?? 18,
                        color: level0.color ?? tx1 ?? Color(0xFF000000),
                        listIndent: shapeIndent,
                        autofit: fitRule == "a:normAutofit", fontScale: fitRule == "a:normAutofit" ? scale : 1,
                        lineReduction: fitRule == "a:normAutofit" ? min(1, max(0, reduction)) : 0,
                        insetsFollowFont: body?.first("a:bodyPr")?["starling:insScale"] == "1",
                        noWrap: bodies.compactMap { $0?["wrap"] }.first == "none",
                        columns: max(1, min(16, attr("numCol").flatMap(Int.init) ?? 1)),
                        columnGap: attr("spcCol").flatMap(Double.init).map { $0 / Pptx.emu } ?? 0,
                        warp: warp, runLooks: runLooks)
        body0.sizeGroup = body?.first("a:bodyPr")?["starling:sizeGroup"]
        body0.keepsSize = body?.first("a:bodyPr")?["starling:keepsSize"] == "1"
        body0.wordLines = body?.first("a:bodyPr")?["compatLnSpc"] == "0"
        body0.generatedHang = body?.first("a:bodyPr")?["starling:generatedHang"] == "1"
        body0.anchorCentred = ["1", "true"].contains(attr("anchorCtr") ?? "")
        body0.bodyVert = attr("vert")
        body0.bodyWrap = attr("wrap")
        body0.fitRule = fitRule
        body0.keepsFirstSpace = ["1", "true"].contains(attr("spcFirstLastPara") ?? "")
        switch attr("vert") {
        case "vert", "mongolianVert": body0.textTurn = 1
        case "eaVert":
            body0.textTurn = 1
            // (A column in a face whose vertical header has a negative descent (Meiryo...) is one sideways run in PowerPoint's print.)
            body0.uprightIdeographs = !bodyDocument.paragraphs.contains { $0.runs.contains { $0.length > 0 && SlideFonts.setsEastAsianVerticalSideways($0.style.fontFamily ?? "") } }
            // (The column's ideographs are one sideways run there, but its one or two digits beside one still stand upright: 44a86430c67f p10.)
            body0.sidewaysDigits = !body0.uprightIdeographs
        case "vert270": body0.textTurn = -1
        case "wordArtVert": body0.textStacked = 1
        case "wordArtVertRtl": body0.textStacked = -1
        default: break
        }
        // A flat camera turned about its axis (`rev`, lat and lon nought)
        // turns the text the other way about its own middle: tdf128213's
        // "Vertical it should be!" at rev 90° reads upward from the box,
        // tdf128206's at 270° down its arrow.
        if let rot = body?.first("a:bodyPr")?.first("a:scene3d")?.first("a:camera")?.first("a:rot"),
           (rot["lat"].flatMap(Double.init) ?? 0) == 0, (rot["lon"].flatMap(Double.init) ?? 0) == 0,
           let rev = rot["rev"].flatMap(Double.init), rev != 0 {
            body0.textRev = -rev / 60000
        }
        // `bodyPr rot`: the text turned about the middle of its lines, any
        // angle (tdf149551's "a b c…" in a right triangle at 12°).
        // (Not with `vert`: PowerPoint's pivot for the pair is none of the text's
        // middle, the frame's or the text area's — vert270AndTextRot's lines
        // land 11 pt off with each — so that deck keeps the unturned text.)
        if let turn = attr("rot").flatMap(Double.init), turn != 0 { body0.textSpin += turn / 60000 }
        if let bp = body?.first("a:bodyPr"), bp.first("a:scene3d") != nil, body0.warp != nil || (bp.first("a:sp3d")?["extrusionH"].flatMap(Double.init) ?? 0) > 0 {
            body0.textScene = Extrusion.read(bp, colors: colors, text: true)
        }
        return body0
    }

    /// A run's WordArt look: a gradient or picture fill, no fill, an
    /// outline. Nil for a run that is plain coloured text.
    /// PowerPoint's runs of numbers: a level numbers on past deeper
    /// paragraphs, and starts again after a paragraph at its own level or
    /// shallower that is not numbered (or numbered another way) —
    /// NumberedList-12ab-ab-34's outer 3 and 4 after its sub-lists, whose
    /// second "a, b" follows an unnumbered line. Each run is a list of its
    /// own, in its scheme's format (a, b / i, ii / 1)…), from `startAt`.
    /// An empty paragraph shows no number and neither counts nor breaks.
    static func _numberRuns(_ doc: inout RichDocument, levels: [Int], numbering: [(type: String, start: Int)?],
                            prefix: String = "pptx") {
        guard numbering.contains(where: { $0 != nil }), levels.count == doc.paragraphs.count else { return }
        var broken = Array(repeating: true, count: 9), run = Array(repeating: 0, count: 9)
        var scheme = Array(repeating: "", count: 9)
        for i in doc.paragraphs.indices {
            let lvl = min(8, max(0, levels[i]))
            for deeper in (lvl + 1) ..< 9 { broken[deeper] = true }
            guard doc.paragraphs[i].style.list == .numbered, let n = numbering[i] else { broken[lvl] = true; continue }
            if doc.paragraphs[i].text.isEmpty {
                doc.paragraphs[i].style.listId = "\(prefix)-empty-\(i)"
                continue
            }
            let key = "\(n.type)/\(n.start)"
            if broken[lvl] || scheme[lvl] != key { run[lvl] += 1; broken[lvl] = false; scheme[lvl] = key }
            let id = "\(prefix)-\(lvl)-\(run[lvl])"
            doc.paragraphs[i].style.listId = id
            if doc.listFormats[id] == nil {
                let t = n.type.lowercased()
                let format: ListNumberFormat = t.hasPrefix("alphalc") ? .lowerLetter : t.hasPrefix("alphauc") ? .upperLetter
                    : t.hasPrefix("romanlc") ? .lowerRoman : t.hasPrefix("romanuc") ? .upperRoman : .decimal
                let counter = "%\(lvl + 1)"
                let text = t.hasSuffix("parenboth") ? "(\(counter))" : t.hasSuffix("parenr") ? "\(counter))"
                    : t.hasSuffix("plain") ? counter : "\(counter)."
                var levelsOf: [Int: ListLevelFormat] = [:]
                var levelFormat = ListLevelFormat(text: text, format: format)
                // East Asian schemes: PowerPoint counts 一. 二. 三. (ea1Cht/ea1Chs), ① (circleNumDb), １． (arabicDb).
                if t.hasPrefix("ea1cht") || t.hasPrefix("ea1chs") { levelFormat.rawFormat = "taiwaneseCountingThousand" }
                else if t.hasPrefix("ea1jpnchsdb") { levelFormat.rawFormat = "japaneseCounting" }
                else if t.hasPrefix("circlenumdbplain") { levelFormat.rawFormat = "decimalEnclosedCircle" }
                else if t.hasPrefix("arabicdb") { levelFormat.rawFormat = "decimalFullWidth" }
                levelsOf[lvl] = levelFormat
                doc.listFormats[id] = levelsOf
                if n.start != 1 { doc.listRestarts[id] = [lvl: n.start] }
            }
        }
    }

    func _runLook(_ rPr: XNode?) -> RunLook? {
        guard let rPr else { return nil }
        var look = RunLook()
        var any = false
        if rPr.has("a:noFill") { look.noFill = true; any = true }
        if let g = rPr.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors), f.stops.count >= 2 {
            look.fill = f; any = true
        } else if let b = rPr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
                  let rel = package.rels(part).first(where: { $0.id == rid }), !rel.external,
                  package.parts[rel.target] != nil {
            var f = SlideFill(image: images.attachment(rel.target, package, blip: blip))
            (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
            f.imageLevels = PptxReader.blipLevels(blip)
            if b.first("a:tile") != nil || b.first("a:stretch") == nil {
                PptxReader.tile(b.first("a:tile"), image: package.parts[rel.target], into: &f)
            }
            look.fill = f; any = true
        }
        if let ln = rPr.first("a:ln"), !ln.has("a:noFill"), let c = ln.first("a:solidFill").flatMap(colors.color(in:)), c.alpha > 0 {
            look.outline = c
            look.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            look.outlineDash = PptxReader.dash(ln)
            look.outlineRound = ln["cap"] == "rnd"
            look.outlineJoin = PptxReader.join(ln)
            any = true
        }
        return any ? look : nil
    }

    // MARK: Notes

    func notes() -> RichDocument {
        guard let notesPart = package.rel(part, kind: "notesSlide")?.target, let notes = package.xml(notesPart),
              let tree = notes.first("p:cSld")?.first("p:spTree") else { return RichDocument() }
        for sp in tree.all("p:sp") where _ph(sp)?["type"] == "body" {
            let paras: [RichParagraph] = (sp.first("p:txBody")?.all("a:p") ?? []).map { p in
                // Each run keeps the look it states itself (bold, italic, underline, strike, size, face, colour); the notes master supplies the rest.
                var text = "", runs: [Run] = []
                for c in p.children {
                    var piece: String
                    switch c.name {
                    case "a:r", "a:fld": piece = c.first("a:t")?.text ?? ""
                    case "a:br": piece = "\n"
                    default: continue
                    }
                    if piece.isEmpty { continue }
                    var st = CharStyle.plain
                    if let r = c.first("a:rPr") {
                        st.bold = r["b"] == "1"
                        st.italic = r["i"] == "1"
                        st.underline = r["u"].map { $0 != "none" } ?? false
                        st.underlineKind = RichTextTheme.drawingMLUnderline(r["u"])
                        st.strikethrough = r["strike"].map { $0 != "noStrike" } ?? false
                        st.fontSize = r["sz"].flatMap(Double.init).map { $0 / 100 }
                        if let f = r.first("a:latin")?["typeface"], !f.hasPrefix("+") { st.fontFamily = f }
                        if let fill = r.first("a:solidFill") { st.color = colors.color(in: fill) }
                    }
                    text += piece
                    if let last = runs.last, last.style == st { runs[runs.count - 1].length += piece.utf16.count }
                    else { runs.append(Run(length: piece.utf16.count, style: st)) }
                }
                return RichParagraph(text: text, runs: runs.isEmpty ? [Run(length: 0)] : runs, style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
            }
            return RichDocument(paragraphs: paras.isEmpty ? [RichParagraph()] : paras)
        }
        return RichDocument()
    }
}
