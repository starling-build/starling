// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// S-SH-1: the Shapes gallery, in PowerPoint's groups. Every entry is a preset the app can draw (`PresetGeometry`).
enum ShapeGallery {
    struct Group {
        let name: String
        let presets: [ShapePreset]
    }

    private static func g(_ name: String, _ raw: String) -> Group {
        Group(name: name, presets: raw.split(separator: " ").map { ShapePreset(rawValue: String($0)) }
            .filter { $0.isLine || draws($0.rawValue) })
    }

    /// Whether the preset draws anything: our definitions of the accent callouts close a path and then draw on, which
    /// drops the whole shape (see `FreeformGeometry.parse`), and a gallery cell for them would be a blank gap.
    static func draws(_ name: String) -> Bool {
        PresetGeometry.geometry(name, width: 914_400, height: 914_400).map { !$0.subpaths.isEmpty } ?? false
    }

    static let groups: [Group] = [
        g("Lines", "line straightConnector1 bentConnector3 curvedConnector3"),
        g("Rectangles", "rect roundRect snip1Rect snip2SameRect snip2DiagRect snipRoundRect round1Rect round2SameRect round2DiagRect"),
        g("Basic Shapes", "ellipse triangle rtTriangle parallelogram trapezoid diamond pentagon hexagon heptagon octagon decagon dodecagon "
            + "pie chord teardrop frame halfFrame corner diagStripe plus plaque can cube bevel donut noSmoking blockArc foldedCorner "
            + "smileyFace heart lightningBolt sun moon cloud arc bracketPair bracePair leftBracket rightBracket leftBrace rightBrace"),
        g("Block Arrows", "rightArrow leftArrow upArrow downArrow leftRightArrow upDownArrow quadArrow leftRightUpArrow bentArrow "
            + "uturnArrow leftUpArrow bentUpArrow curvedRightArrow curvedLeftArrow curvedUpArrow curvedDownArrow stripedRightArrow "
            + "notchedRightArrow homePlate chevron rightArrowCallout downArrowCallout leftArrowCallout upArrowCallout "
            + "leftRightArrowCallout quadArrowCallout circularArrow"),
        g("Equation Shapes", "mathPlus mathMinus mathMultiply mathDivide mathEqual mathNotEqual"),
        g("Flowchart", "flowChartProcess flowChartAlternateProcess flowChartDecision flowChartInputOutput flowChartPredefinedProcess "
            + "flowChartInternalStorage flowChartDocument flowChartMultidocument flowChartTerminator flowChartPreparation "
            + "flowChartManualInput flowChartManualOperation flowChartConnector flowChartOffpageConnector flowChartCard "
            + "flowChartPunchedTape flowChartSummingJunction flowChartOr flowChartCollate flowChartSort flowChartExtract "
            + "flowChartMerge flowChartStoredData flowChartDelay flowChartSequentialAccessStorage flowChartMagneticDisk "
            + "flowChartDirectAccessStorage flowChartDisplay"),
        g("Stars and Banners", "irregularSeal1 irregularSeal2 star4 star5 star6 star7 star8 star10 star12 star16 star24 star32 "
            + "ribbon2 ribbon ellipseRibbon2 ellipseRibbon verticalScroll horizontalScroll wave doubleWave"),
        g("Callouts", "wedgeRectCallout wedgeRoundRectCallout wedgeEllipseCallout cloudCallout borderCallout1 borderCallout2 "
            + "borderCallout3 accentCallout1 accentCallout2 accentCallout3 callout1 callout2 callout3 accentBorderCallout1 "
            + "accentBorderCallout2 accentBorderCallout3"),
        g("Action Buttons", "actionButtonBlank actionButtonHome actionButtonHelp actionButtonInformation actionButtonForwardNext "
            + "actionButtonBackPrevious actionButtonEnd actionButtonBeginning actionButtonReturn actionButtonDocument "
            + "actionButtonSound actionButtonMovie"),
    ]

    /// "flowChartPredefinedProcess" as words: "Flowchart: Predefined Process".
    static func title(_ raw: String) -> String {
        var rest = raw
        var prefix = ""
        for (p, t) in [("flowChart", "Flowchart: "), ("actionButton", "Action Button: ")] where raw.hasPrefix(p) && raw.count > p.count {
            rest = String(raw.dropFirst(p.count)); prefix = t
        }
        var words: [String] = []
        var cur = ""
        for ch in rest {
            if ch.isUppercase || ch.isNumber && !(cur.last?.isNumber ?? false), !cur.isEmpty { words.append(cur); cur = "" }
            cur.append(ch)
        }
        if !cur.isEmpty { words.append(cur) }
        return prefix + words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
