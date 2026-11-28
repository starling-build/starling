// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// Where the app placed its labelled controls, in view points: the one list both the Linux UI harness and the Mac
/// script driver (`marks PATH`) write, so a driver point measured on one can be checked against the other line by
/// line instead of by eye on a screenshot. One line per visible Text or Tooltip:
/// `text|tip <TAB> label <TAB> centre-x centre-y <TAB> width height`, plus a first `view W H` line.
enum ScreenMarks {
    static func lines(root: Element?, view: Size) -> [String] {
        var out = ["view\t\(r(view.width)) \(r(view.height))"]
        func walk(_ e: Element) {
            let label: (String, String)?
            if let t = e.widget as? Text, let d = t.data, !d.isEmpty { label = ("text", d) }
            else if let t = e.widget as? Tooltip, let m = t.message, !m.isEmpty { label = ("tip", m) }
            else { label = nil }
            if let (kind, text) = label, let box = e.findRenderObject() as? RenderBox, box.hasSize, box.attached {
                let c = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
                // What lies outside the view cannot be clicked and is left out.
                if c.dx >= 0, c.dy >= 0, c.dx <= view.width, c.dy <= view.height {
                    out.append("\(kind)\t\(text.replacingAll("\t", with: " ").replacingAll("\n", with: " "))\t\(r(c.dx)) \(r(c.dy))\t\(r(box.size.width)) \(r(box.size.height))")
                }
            }
            e.visitChildElements(walk)
        }
        if let root { walk(root) }
        return out
    }

    /// Half-point rounding: enough to place a click, and stable across platforms' float noise.
    private static func r(_ v: Double) -> String {
        let h = (v * 2).rounded() / 2
        return h == h.rounded() ? String(Int(h)) : String(h)
    }
}
