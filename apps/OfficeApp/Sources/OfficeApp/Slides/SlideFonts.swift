// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import Foundation

/// A slide's faces as PowerPoint stands in for them: the shared
/// stand-ins (`OfficeFonts.substitute`), except for a name they do not
/// know. The shared rule sets that in the Cambria clone (Word on a Mac's
/// way); PowerPoint, printing a face its machine lacks, used Calibri —
/// tdf168835's "Marianne", bug65228's "Graphik" and tdf119187's
/// "BentonSans" are Calibri in its prints. (Sweep 106: ten decks
/// nearer, n862510_4's "Segoe UI Light" — a weight we have no face for
/// either way — and tdf98603's Hebrew FrankRuehl a little further.)
enum SlideFonts {
    /// The free faces bundled for families decks name (Resources/fonts/
    /// README.md): the font itself (Poppins, Work Sans) or the nearest free
    /// design (Selawik for Segoe UI, Libre Franklin, TeX Gyre's Courier,
    /// Avant Garde and Palatino).
    static let freeFaces: [String: String] = [
        "poppins": "Poppins", "poppins light": "Poppins Light", "poppins medium": "Poppins Medium",
        "poppins semibold": "Poppins SemiBold", "poppins black": "Poppins Black",
        "work sans": "Work Sans", "work sans light": "Work Sans Light", "work sans medium": "Work Sans Medium",
        "segoe ui": "Selawik Doc", "segoe ui light": "Selawik Doc Light", "segoe ui semilight": "Selawik Doc Semilight",
        "segoe ui semibold": "Selawik Doc Semibold",
        // (Myriad Pro, which PowerPoint's Mac sets in Segoe UI: HowWeRefactor.)
        "myriad pro": "Selawik Doc",
        "franklin gothic book": "Libre Franklin", "franklin gothic medium": "Libre Franklin Medium",
        "courier new": "TeX Gyre Cursor", "courier": "TeX Gyre Cursor",
        "century gothic": "TeX Gyre Adventor",
        "palatino linotype": "TeX Gyre Pagella", "palatino": "TeX Gyre Pagella", "book antiqua": "TeX Gyre Pagella",
        // (Arial Black in Archivo Black, its widths Arial Black's and its
        // strokes as heavy, where Liberation Sans Bold's letters stood thin
        // and apart at Arial Black's widths: ThemeColorTransparency.)
        "arial black": "Archivo Black",
        // (Lucida Sans Unicode in Liberation Sans's regular and bold under a
        // name of their own, with no italic: PowerPoint slants the regular,
        // and so does the engine. aascu 5864's p34 quote, `i="1"`, is the
        // regular slanted in PowerPoint's print, where Liberation Sans
        // Italic's letters are another design.)
        "lucida sans unicode": "Starling Lucida Sans",
    ]

    static func resolve(_ family: String) -> String {
        // (The machine's own face, where it has it and the user takes it:
        // `OfficeFonts.installed`.)
        if let own = OfficeFonts.installed(family) { return own }
        if let free = freeFaces[family.trimmingWhitespace().lowercased()] { return free }
        let face = OfficeFonts.substitute(family)
        guard face == OfficeFonts.cambria else { return face }
        let n = family.trimmingWhitespace().lowercased()
        guard !n.hasPrefix("cambria"), n != "caladea" else { return face }
        return OfficeFonts.calibri
    }

    /// The face a slide's run is set in where its widths are not the
    /// stand-in's: Lucida Sans Unicode, drawn in Liberation Sans, at its
    /// own widths — 9% wider (GeomLec1's lines wrapped a word late).
    /// Its bold and italic are made from the regular, as wide.
    static func face(_ family: String?, _ eastAsian: Bool) -> RichResolvedFace? {
        // (None of a stand-in's widths for the machine's own face.)
        guard !eastAsian, let family, OfficeFonts.installed(family) == nil else { return nil }
        switch family.trimmingWhitespace().lowercased() {
        case "lucida sans unicode":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.lucidaSansUnicodeAdvances
            face.boldAdvances = OfficeFonts.lucidaSansUnicodeAdvances
            face.otherAdvances = OfficeFonts.lucidaSansUnicodeOtherAdvances
            face.boldOtherAdvances = OfficeFonts.lucidaSansUnicodeOtherAdvances
            return face
        case "verdana":
            // (Verdana in DejaVu Sans, at Verdana's widths: its space is
            // 0.35 em to DejaVu's 0.32, and pptx2svg's words stood closer
            // together than PowerPoint's.)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.verdanaAdvances
            face.boldAdvances = OfficeFonts.verdanaBoldAdvances
            face.otherAdvances = OfficeFonts.verdanaOtherAdvances
            face.boldOtherAdvances = OfficeFonts.verdanaBoldOtherAdvances
            return face
        case "segoe ui", "segoe ui light", "segoe ui semilight", "tahoma", "trebuchet ms", "franklin gothic book",
             "franklin gothic medium", "century gothic", "gill sans mt", "candara", "palatino linotype":
            // (Windows' own widths, `SlideFontWidths`: the bold where the
            // face has one, else the stand-in's bold.)
            let n = family.trimmingWhitespace().lowercased()
            let tables: [String: ([Double], [Double]?)] = [
                "segoe ui": (SlideFontWidths.segoeUI, SlideFontWidths.segoeUIBold),
                "segoe ui light": (SlideFontWidths.segoeUILight, nil),
                "segoe ui semilight": (SlideFontWidths.segoeUISemilight, nil),
                "tahoma": (SlideFontWidths.tahoma, SlideFontWidths.tahomaBold),
                "trebuchet ms": (SlideFontWidths.trebuchet, SlideFontWidths.trebuchetBold),
                "franklin gothic book": (SlideFontWidths.franklinGothicBook, nil),
                "franklin gothic medium": (SlideFontWidths.franklinGothicMedium, nil),
                "century gothic": (SlideFontWidths.centuryGothic, SlideFontWidths.centuryGothicBold),
                "gill sans mt": (SlideFontWidths.gillSans, SlideFontWidths.gillSansBold),
                "candara": (SlideFontWidths.candara, SlideFontWidths.candaraBold),
                "palatino linotype": (SlideFontWidths.palatino, SlideFontWidths.palatinoBold),
            ]
            guard let t = tables[n] else { return nil }
            var face = RichResolvedFace(family: resolve(family))
            face.advances = t.0
            face.boldAdvances = t.1
            return face
        case "times new roman", "calibri":
            // (Hebrew at the face's own widths: tdf98603's title and quote
            // are a fifth narrower in PowerPoint's print than the stand-ins
            // set them, and broke a word early.)
            var face = RichResolvedFace(family: resolve(family))
            let hebrew = family.trimmingWhitespace().lowercased() == "calibri" ? SlideFontWidths.calibriHebrew : SlideFontWidths.timesHebrew
            face.otherAdvances = hebrew
            face.boldOtherAdvances = hebrew
            return face
        case "arial black":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.arialBlackAdvances
            face.boldAdvances = OfficeFonts.arialBlackAdvances
            return face
        default:
            // (A face no one knows is Calibri in PowerPoint's print, its
            // Hebrew too: tdf98603's FrankRuehl quote, a fifth narrower
            // than Carlito's own Hebrew.)
            guard resolve(family) == OfficeFonts.calibri else { return nil }
            var face = RichResolvedFace(family: OfficeFonts.calibri)
            face.otherAdvances = SlideFontWidths.calibriHebrew
            face.boldOtherAdvances = SlideFontWidths.calibriHebrew
            return face
        }
    }

    /// The share of the line below the baseline for a face we draw with
    /// a stand-in of other proportions — its Windows ascent and descent
    /// (Verdana 2059 and 430 of 2048, Tahoma 2049 and 423, Segoe UI 2210
    /// and 514, Lucida Sans Unicode 2246 and 901, Arial 1854 and 434,
    /// Times New Roman 1825 and 443). PowerPoint sets the
    /// baseline by them: the AES deck's Verdana stood 0.04 of its size
    /// high in DejaVu Sans's, HowWeRefactor's Segoe UI as much in its
    /// stand-in's, and GeomLec1's Lucida Sans Unicode 0.1 low.
    /// The single line, in ems, of a face drawn by a stand-in of another
    /// height (its Windows ascent, descent and gap): what a diagram's
    /// lines step at (`DeckController.naturalLines`). nil: the stand-in's
    /// own is the face's (Calibri in Carlito, the free faces themselves).
    static func ownNaturalHeight(_ family: String) -> Double? {
        guard OfficeFonts.installed(family) == nil else { return nil }
        switch family.trimmingWhitespace().lowercased() {
        case "courier new", "courier": return 2320.0 / 2048
        case "segoe ui", "segoe ui light", "segoe ui semilight", "segoe ui semibold": return 2724.0 / 2048
        case "franklin gothic book", "franklin gothic medium": return 2322.0 / 2048
        case "century gothic": return 2440.0 / 2048
        case "palatino linotype", "palatino": return 2763.0 / 2048
        case "verdana": return 2489.0 / 2048
        case "tahoma": return 2472.0 / 2048
        case "trebuchet ms": return 2378.0 / 2048
        case "gill sans mt": return 2375.0 / 2048
        case "lucida sans unicode": return 3147.0 / 2048
        default: return nil
        }
    }

    /// The same by the face that draws it (what the layout knows a run
    /// by): a stand-in answers for the face it stands for.
    static func drawnNaturalHeight(_ drawn: String) -> Double? {
        switch drawn {
        case "TeX Gyre Cursor", OfficeFonts.mono: return 2320.0 / 2048
        case "Selawik Doc", "Selawik Doc Light", "Selawik Doc Semilight", "Selawik Doc Semibold": return 2724.0 / 2048
        case "Libre Franklin", "Libre Franklin Medium": return 2322.0 / 2048
        case "TeX Gyre Adventor": return 2440.0 / 2048
        case "TeX Gyre Pagella": return 2763.0 / 2048
        case OfficeFonts.verdana: return 2489.0 / 2048
        default: return nil
        }
    }

    static func ownDescentShare(_ family: String) -> Double? {
        guard OfficeFonts.installed(family) == nil else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        if n == "verdana" { return 430.0 / 2489 }
        if n.hasPrefix("tahoma") { return 423.0 / 2472 }
        if n.hasPrefix("segoe ui") { return 514.0 / 2724 }
        if n == "lucida sans unicode" { return 901.0 / 3147 }
        if n == "courier new" || n == "courier" { return 615.0 / 2320 }
        // (Helvetica by the Mac's, 1577 over and 471 under of 2048: slide-
        // sections' 36 pt titles stand a point higher in PowerPoint's
        // print than Liberation Sans's share set them.)
        if n == "helvetica" { return 471.0 / 2048 }
        // (Consolas by its own, 1884 over and 514 under, where Liberation
        // Mono's deeper share set clusterfuzz 4986's code 1 to 2 pt high.)
        if n == "consolas" { return 514.0 / 2398 }
        // (Poppins by its ascent and descent, its line gap not counted —
        // the engine puts half of it under the baseline; Work Sans by its
        // Windows ascent and descent.)
        if n.hasPrefix("poppins") { return 0.35 / 1.4 }
        if n.hasPrefix("work sans") { return 0.343 / 1.448 }
        if n == "trebuchet ms" { return 455.0 / 2378 }
        if n.hasPrefix("franklin gothic") { return 445.0 / 2322 }
        if n == "century gothic" { return 451.0 / 2440 }
        if n == "gill sans mt" { return 472.0 / 2375 }
        if n == "palatino linotype" { return 613.0 / 2763 }
        // (Aptos, drawn in a clone of other proportions. Its twelve decks'
        // lines stood 0.02 em low; 0.21 puts ten of them within 0.016 em
        // of PowerPoint's. The `hhea` the prints' embedded copies keep,
        // 1923 over 577 — 0.23 — put them 0.02 em high: the Windows
        // metrics it goes by are stripped from those copies.)
        if n.hasPrefix("aptos") { return 0.21 }
        // (And Arial and Times New Roman by theirs, no line gap counted:
        // their clones' gap — a thirtieth and a twenty-fourth of an em —
        // put a share of it under the baseline in the engine's line, and
        // Arial's 43 decks stood 0.011 em high.)
        if n == "arial" { return 434.0 / 2288 }
        if n == "times new roman" { return 443.0 / 2268 }
        return nil
    }
}
