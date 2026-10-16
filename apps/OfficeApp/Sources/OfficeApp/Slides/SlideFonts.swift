// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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
    static func resolve(_ family: String) -> String {
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
        guard !eastAsian, let family else { return nil }
        switch family.trimmingWhitespace().lowercased() {
        case "lucida sans unicode":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.lucidaSansUnicodeAdvances
            face.boldAdvances = OfficeFonts.lucidaSansUnicodeAdvances
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
        case "arial black":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.arialBlackAdvances
            face.boldAdvances = OfficeFonts.arialBlackAdvances
            return face
        default:
            return nil
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
    static func ownDescentShare(_ family: String) -> Double? {
        let n = family.trimmingWhitespace().lowercased()
        if n == "verdana" { return 430.0 / 2489 }
        if n.hasPrefix("tahoma") { return 423.0 / 2472 }
        if n.hasPrefix("segoe ui") { return 514.0 / 2724 }
        if n == "lucida sans unicode" { return 901.0 / 3147 }
        // (And Arial and Times New Roman by theirs, no line gap counted:
        // their clones' gap — a thirtieth and a twenty-fourth of an em —
        // put a share of it under the baseline in the engine's line, and
        // Arial's 43 decks stood 0.011 em high.)
        if n == "arial" { return 434.0 / 2288 }
        if n == "times new roman" { return 443.0 / 2268 }
        return nil
    }
}
