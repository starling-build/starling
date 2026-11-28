// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-OB-5: Chart Design > Change Colors (Word and PowerPoint). Office's palettes are its chart colour styles
// (`cs:colorStyle`, the colorsN.xml part beside a chart), numbered 10 to 26. Picking one writes every series (a pie's
// every slice) its own fill, as theme colours, so a new theme recolours it. The palettes and the fills are read from
// the corpus' own parts: 2,398 colour parts, with the series fills of the charts that name them.
//   10-13  Colorful Palette 1-4: the accents 1-6, 1/3/5, 2/4/6 and 6/5/4 in turn; past the last, the round's
//          variation (none, lumMod 60, lumMod 80 + lumOff 20, lumMod 80, ... nine in all).
//   14-19  Monochromatic Palette 1-6: one accent (1-6), dark to light ("withinLinear"). Item i of n is the accent at
//          v = (i + 1) / (n + 1) x 1.4 - 0.7: a shade of 1 + v below 0, a tint of 1 - v above, written in whole
//          percents, shades rounded down and tints up (n 2: shade 76 tint 77; n 4: shade 58 86, tint 86 58;
//          n 7: shade 47 65 82, plain, tint 83 65 48; n 31: shade 34 ... tint 35).
//   20     Monochromatic Palette 7: dk1 at tint 88.5, 55, 75, 98.5, 30, 60, 80 in turn (a cycle, no plain round).
//   21-26  Monochromatic Palette 8-13: 14-19 light to dark ("withinLinearReversed").

import Foundation
import Flutter
import OfficeText
import FlutterSwiftBridge

struct ChartPalette: Equatable {
    let id: Int

    static let all: [ChartPalette] = (10 ... 26).map(ChartPalette.init)
    static var colorful: [ChartPalette] { all.filter(\.isColorful) }
    static var monochromatic: [ChartPalette] { all.filter { !$0.isColorful } }

    var isColorful: Bool { id <= 13 }
    var name: String { isColorful ? "Colorful Palette \(id - 9)" : "Monochromatic Palette \(id - 13)" }

    /// The accents a colourful palette cycles through.
    private var cycle: [Int] {
        switch id {
        case 11: return [1, 3, 5]
        case 12: return [2, 4, 6]
        case 13: return [6, 5, 4]
        default: return [1, 2, 3, 4, 5, 6]
        }
    }

    private static let rounds = ["", "<a:lumMod val=\"60000\"/>", "<a:lumMod val=\"80000\"/><a:lumOff val=\"20000\"/>",
                                 "<a:lumMod val=\"80000\"/>", "<a:lumMod val=\"60000\"/><a:lumOff val=\"40000\"/>",
                                 "<a:lumMod val=\"50000\"/>", "<a:lumMod val=\"70000\"/><a:lumOff val=\"30000\"/>",
                                 "<a:lumMod val=\"70000\"/>", "<a:lumMod val=\"50000\"/><a:lumOff val=\"50000\"/>"]
    private static let greys = [88500, 55000, 75000, 98500, 30000, 60000, 80000]

    /// The colour element of item `i` of `n` (a series, or a pie's slice), as Office writes it.
    func element(_ i: Int, of n: Int) -> String {
        func scheme(_ slot: String, _ mods: String) -> String {
            mods.isEmpty ? "<a:schemeClr val=\"\(slot)\"/>" : "<a:schemeClr val=\"\(slot)\">\(mods)</a:schemeClr>"
        }
        if isColorful {
            let k = cycle.count
            return scheme("accent\(cycle[i % k])", Self.rounds[(i / k) % Self.rounds.count])
        }
        if id == 20 { return scheme("dk1", "<a:tint val=\"\(Self.greys[i % Self.greys.count])\"/>") }
        let accent = id >= 21 ? id - 20 : id - 13
        let at = id >= 21 ? n - 1 - i : i
        let v = Double(at + 1) / Double(n + 1) * 1.4 - 0.7
        // (Whole percents: shades down, tints up. 1e-9 keeps 0.58 x 100 from flooring to 57.)
        let mods: String
        if abs(v) < 1e-9 { mods = "" }
        else if v < 0 { mods = "<a:shade val=\"\(Int(((1 + v) * 100 + 1e-9).rounded(.down)) * 1000)\"/>" }
        else { mods = "<a:tint val=\"\(Int(((1 - v) * 100 - 1e-9).rounded(.up)) * 1000)\"/>" }
        return scheme("accent\(accent)", mods)
    }

    /// What element `xml` comes to against the theme's `accents` (1-6) and `dark` (dk1).
    static func resolve(_ xml: String, accents: [Color], dark: Color) -> Color? {
        guard let node = MiniXML.parse(Array(xml.utf8)), let slot = node["val"] else { return nil }
        let base: Color
        if slot == "dk1" || slot == "tx1" { base = dark }
        else if slot.hasPrefix("accent"), let n = Int(slot.dropFirst(6)), (1 ... 6).contains(n), accents.count >= n { base = accents[n - 1] }
        else { return nil }
        return ColorContext.modify(base, node)
    }

    /// `chart` in this palette: every series (a pie's or doughnut's every slice) its own fill.
    func applied(to chart: Chart, accents: [Color], dark: Color) -> Chart {
        var c = chart
        if c.type.isPie {
            let n = c.categories.count
            for p in 0 ..< n {
                let xml = element(p, of: n)
                c.pointColorXML[p] = xml
                c.pointColors[p] = Self.resolve(xml, accents: accents, dark: dark)
            }
        } else {
            let n = c.series.count
            for i in 0 ..< n {
                let xml = element(i, of: n)
                c.series[i].colorXML = xml
                c.series[i].scheme = nil
                c.series[i].color = Self.resolve(xml, accents: accents, dark: dark)
            }
        }
        return c
    }

    /// Whether `chart` is drawn in this palette (each series' or slice's colour is this palette's).
    func matches(_ chart: Chart, accents: [Color], dark: Color) -> Bool {
        let mine = applied(to: chart, accents: accents, dark: dark)
        if chart.type.isPie {
            let n = chart.categories.count
            return n > 0 && (0 ..< n).allSatisfy { chart.pointColor($0, accents: accents) == mine.pointColors[$0] }
        }
        let n = chart.series.count
        return n > 0 && (0 ..< n).allSatisfy { chart.color(series: $0, accents: accents) == mine.series[$0].color }
    }
}
