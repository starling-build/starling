// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// DrawingML's preset shapes (`a:prstGeom`), drawn from their definitions
/// (`PresetDefinitions`) the way a freeform is drawn from its `custGeom`:
/// the guides evaluated for the shape's size, with the shape's own adjust
/// values (`a:avLst`) over the preset's defaults — so a pie's angles, a
/// rounded rectangle's corner, a callout's pointer and an arrow's head all
/// come out as the file sets them.
enum PresetGeometry {
    private static let definitions: [String: XNode] = {
        guard let root = XNode.parse(Data(PresetDefinitions.xml.utf8)) else { return [:] }
        var out: [String: XNode] = [:]
        for c in root.children { out[c.name] = c }
        return out
    }()

    /// Whether the preset is defined.
    static func has(_ name: String) -> Bool { definitions[name] != nil }

    /// The preset's outline for a shape `width` by `height` EMU, at its
    /// adjust values (`adjustments`, by guide name — "adj1"…) over the
    /// defaults; nil for a preset that is not defined.
    static func geometry(_ name: String, width: Double, height: Double,
                         adjustments: [String: Double] = [:]) -> FreeformGeometry? {
        guard let def = definitions[name], width > 0, height > 0 else { return nil }
        return FreeformGeometry.parse(def, width: width, height: height, adjustments: adjustments)
    }

    /// The adjust values a shape sets (`a:prstGeom/a:avLst`), by name.
    static func adjustments(_ prstGeom: XNode?) -> [String: Double] {
        var out: [String: Double] = [:]
        for gd in prstGeom?.first("a:avLst")?.all("a:gd") ?? [] {
            guard let name = gd["name"], let fmla = gd["fmla"] else { continue }
            let parts = fmla.split(separator: " ")
            if parts.count == 2, parts[0] == "val", let v = Double(parts[1]) { out[name] = v }
        }
        return out
    }

    /// The preset's outline as one path in `r` (every filled contour, holes
    /// cut), at its default adjust values; nil when undefined.
    static func path(_ name: String, in r: Rect, adjustments: [String: Double] = [:]) -> Path? {
        guard let g = geometry(name, width: max(1, r.width) * Pptx.emu, height: max(1, r.height) * Pptx.emu,
                               adjustments: adjustments) else { return nil }
        return SlidePainter.combinedPath(g, r)
    }
}
