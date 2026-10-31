// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// SmartArt laid out by this app. A diagram in a .pptx is data (the text and
// its hierarchy), a layout definition (an algorithm for arranging it), a
// colour scheme and a style — and, when PowerPoint saved it, a cached
// drawing of the result. A deck saved by LibreOffice carries no drawing, so
// the diagram has to be laid out here: this is an interpreter for the
// layout definition language (`dgm:layoutDef`), reduced to what the
// built-in layouts use — forEach over the data by axis, choose/if on
// counts, depths and variables, constraints on sizes and positions, and
// the composite, linear, snake, cycle, hierarchy and connector algorithms.
// The result is a tree of ordinary `p:sp` elements, which the slide reader
// then reads like a drawing part's.

import Foundation
import Flutter
import OfficeText
import FlutterSwiftBridge

/// One point of a diagram's data model (`dgm:pt`): a node with text, the
/// document root, or a transition (the space or connector between a parent
/// and a child, or between siblings).
final class DgmPoint {
    let id: String
    /// "node", "asst", "doc", "parTrans", "sibTrans" (presentation points
    /// are kept aside, in `DgmModel.pres`).
    let type: String
    let text: XNode?
    let spPr: XNode?
    let prSet: XNode?
    var children: [DgmPoint] = []
    weak var parent: DgmPoint?
    /// A node's transitions: the one before it (from its parent) and the one
    /// after it (to its next sibling).
    var parTrans: DgmPoint?
    var sibTrans: DgmPoint?
    /// A transition's ends: the connection's source and destination nodes.
    var cxnSrc: String?
    var cxnDst: String?
    var depth = 0
    var index = 0

    init(id: String, type: String, text: XNode?, spPr: XNode?, prSet: XNode?) {
        self.id = id
        self.type = type
        self.text = text
        self.spPr = spPr
        self.prSet = prSet
    }

    var isNode: Bool { type == "node" || type == "asst" }
    var descendants: [DgmPoint] { children.flatMap { [$0] + $0.descendants } }
    var ancestors: [DgmPoint] { parent.map { [$0] + $0.ancestors } ?? [] }
    /// The parent's children with their transitions, in order: parTrans,
    /// node, sibTrans, parTrans, node, sibTrans…
    var siblingSequence: [DgmPoint] {
        (parent?.children ?? [self]).flatMap { [$0.parTrans, $0, $0.sibTrans].compactMap { $0 } }
    }
}

/// A diagram's data model: the tree of points, and PowerPoint's
/// presentation points (which say which style label a shape got).
struct DgmModel {
    var root: DgmPoint
    var points: [String: DgmPoint] = [:]
    /// Presentation properties by "\(data point id)|\(layout node name)".
    var pres: [String: XNode] = [:]
    /// A presentation point's own shape properties, by the same key: what
    /// the user set on that one shape (lo-smartart-missing-bullet's frame,
    /// filled with tx2 over the colour scheme's tint of accent1).
    var presSpPr: [String: XNode] = [:]

    init?(_ data: XNode) {
        var points: [String: DgmPoint] = [:]
        var order: [DgmPoint] = []
        var root: DgmPoint? = nil
        for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] {
            guard let id = pt["modelId"] else { continue }
            let type = pt["type"] ?? "node"
            if type == "pres" {
                if let pr = pt.first("dgm:prSet"), let assoc = pr["presAssocID"], let name = pr["presName"] {
                    pres[assoc + "|" + name] = pr
                    if let sp = pt.first("dgm:spPr"), !sp.children.isEmpty { presSpPr[assoc + "|" + name] = sp }
                }
                continue
            }
            let p = DgmPoint(id: id, type: type, text: pt.first("dgm:t"), spPr: pt.first("dgm:spPr"), prSet: pt.first("dgm:prSet"))
            points[id] = p
            order.append(p)
            if type == "doc" && root == nil { root = p }
        }
        guard let root else { return nil }
        // Parent-child connections (no type, or "parOf"), in source order,
        // each naming the transitions on either side of the child.
        var cxns: [(src: DgmPoint, dst: DgmPoint, ord: Int, par: DgmPoint?, sib: DgmPoint?)] = []
        for cxn in data.first("dgm:cxnLst")?.all("dgm:cxn") ?? [] {
            let type = cxn["type"] ?? "parOf"
            guard type == "parOf", let s = cxn["srcId"].flatMap({ points[$0] }), let d = cxn["destId"].flatMap({ points[$0] }) else { continue }
            let par = cxn["parTransId"].flatMap { points[$0] }, sib = cxn["sibTransId"].flatMap { points[$0] }
            par?.cxnSrc = s.id; par?.cxnDst = d.id
            sib?.cxnSrc = s.id; sib?.cxnDst = d.id
            cxns.append((s, d, cxn["srcOrd"].flatMap(Int.init) ?? cxns.count, par, sib))
        }
        for c in cxns.sorted(by: { $0.ord < $1.ord }) where c.dst.parent == nil && c.dst !== c.src {
            c.dst.parent = c.src
            c.dst.parTrans = c.par
            c.dst.sibTrans = c.sib
            c.dst.index = c.src.children.count
            c.src.children.append(c.dst)
        }
        func depths(_ p: DgmPoint, _ d: Int) {
            p.depth = d
            for c in p.children { depths(c, d + 1) }
        }
        depths(root, 0)
        self.root = root
        self.points = points
    }
}

/// One node of the presentation tree: a layout node instantiated for a
/// data point, with what the definition chose for it and where it landed.
final class DgmPresNode {
    let name: String
    let point: DgmPoint
    weak var parent: DgmPresNode?
    var children: [DgmPresNode] = []
    var styleLbl: String?
    var algType = ""
    var params: [String: String] = [:]
    var shapeType: String?
    var shapeRot = 0.0
    var hideGeom = false
    var zOrderOff = 0
    var adjustments: [(Int, Double)] = []
    var presOf: [DgmPoint] = []
    var constraints: [XNode] = []
    var rules: [XNode] = []
    var vars: [String: String] = [:]
    var iterIndex = 0
    var iterCount = 1
    var order = 0
    // Layout
    var vals: [String: Double] = [:]
    var caps: [String: Double] = [:]
    var floors: [String: Double] = [:]
    /// Sizes the node's own constraints set (not its parent's preference
    /// for it), which shrink the slot it was given.
    var selfSet: Set<String> = []
    /// Its `w`/`h` given in font sizes: a box that came out smaller than
    /// that was squeezed, and the layout's text should shrink instead.
    var fontSized: Set<String> = []
    /// The shapes one `op="equ"` font-size constraint ties together end at
    /// one size; this names the constraint (nil: none ties it).
    var sizeGroup: String? = nil
    /// The node a size was taken from (a space 0.14 as wide as its
    /// neighbour follows the neighbour when that shrinks).
    var sizeRef: [String: String] = [:]
    /// Its height capped by its own width (`h` ≤ a share of `w`): a box
    /// whose text the layout shrinks to fit (accent-process's heading).
    var heightCappedByWidth = false
    /// A size that follows the node's other size (h = 0.6 w): kept in step
    /// when the layout scales the node.
    var derived: [String: (ref: String, fact: Double)] = [:]
    var rect = Rect.zero
    var rotation = 0.0
    var laidOut = false
    /// A shape the algorithm draws itself (a pyramid's level), as a
    /// polygon in absolute points.
    var polygon: [Offset]? = nil

    init(name: String, point: DgmPoint, parent: DgmPresNode?) {
        self.name = name
        self.point = point
        self.parent = parent
    }

    var isSpace: Bool { algType == "sp" }
    var isConnector: Bool { algType == "conn" }
    var descendants: [DgmPresNode] { children.flatMap { [$0] + $0.descendants } }

    func variable(_ name: String) -> String? {
        var n: DgmPresNode? = self
        while let node = n {
            if let v = node.vars[name] { return v }
            n = node.parent
        }
        return nil
    }

    /// A size or position, as constrained; a size unconstrained is the
    /// parent's.
    func value(_ type: String) -> Double? {
        var v: Double?
        let px = parent?.rect.left ?? 0, py = parent?.rect.top ?? 0
        switch type {
        // Once laid out, a node is as big as the slot it got (its
        // constraint was the preference that slot was fitted from), and
        // sits where it was put.
        case "w": v = laidOut ? rect.width : (vals["w"] ?? parent?.value("w"))
        case "h": v = laidOut ? rect.height : (vals["h"] ?? parent?.value("h"))
        // (A node placed by its centre or its far edge has its near edge
        // there too: vProcess5's middle box, set by `ctrX`, and its arrow,
        // by `r`, read as at 0, and the text boxes measured from them
        // collapsed to nothing — smartart-cnt's "a", "b", "c" at 5 pt.)
        case "l":
            if laidOut { v = rect.left - px }
            else if let left = vals["l"] { v = left }
            else if let center = vals["ctrX"] { v = center - (value("w") ?? 0) / 2 }
            else if let right = vals["r"] { v = right - (value("w") ?? 0) }
            else { v = 0 }
        case "t":
            if laidOut { v = rect.top - py }
            else if let top = vals["t"] { v = top }
            else if let center = vals["ctrY"] { v = center - (value("h") ?? 0) / 2 }
            else if let bottom = vals["b"] { v = bottom - (value("h") ?? 0) }
            else { v = 0 }
        case "r": v = laidOut ? rect.right - px : (vals["r"] ?? (value("l")! + (value("w") ?? 0)))
        case "b": v = laidOut ? rect.bottom - py : (vals["b"] ?? (value("t")! + (value("h") ?? 0)))
        case "ctrX": v = laidOut ? rect.center.dx - px : (vals["ctrX"] ?? (value("l")! + (value("w") ?? 0) / 2))
        case "ctrY": v = laidOut ? rect.center.dy - py : (vals["ctrY"] ?? (value("t")! + (value("h") ?? 0) / 2))
        default: v = vals[type]
        }
        guard var x = v else { return nil }
        if let c = caps[type] { x = min(x, c) }
        if let f = floors[type] { x = max(x, f) }
        return x
    }
}

/// The interpreter: builds the presentation tree, lays it out, emits shapes.
struct DiagramLayout {
    let model: DgmModel
    let layout: XNode
    let colors: XNode?
    let style: XNode?
    private var forEachByName: [String: XNode] = [:]
    private var nextOrder = 0
    /// No font size is set above this (points): how a layout's
    /// `primFontSz` rule shrinks the text, and every size tied to it.
    private var fontCap = Double.infinity

    init?(data: XNode, layout: XNode, colors: XNode?, style: XNode?) {
        guard let model = DgmModel(data) else { return nil }
        self.model = model
        self.layout = layout
        self.colors = colors
        self.style = style
        func index(_ n: XNode) {
            for c in n.children {
                if c.name == "dgm:forEach", let name = c["name"] { forEachByName[name] = c }
                index(c)
            }
        }
        index(layout)
    }

    /// The diagram as a `p:spTree` of `p:sp` elements in EMU, the frame's
    /// origin at 0,0.
    static func render(data: XNode, layout: XNode, colors: XNode?, style: XNode?, frame: Rect) -> XNode? {
        guard let first = DiagramLayout(data: data, layout: layout, colors: colors, style: style),
              let rootDef = layout.first("dgm:layoutNode") else { return nil }
        let box = Rect.fromLTWH(0, 0, frame.width, frame.height)
        func laidOut(fontCap: Double) -> (DiagramLayout, DgmPresNode) {
            var engine = first
            engine.fontCap = fontCap
            let root = engine.build(rootDef, point: engine.model.root, iter: (0, 1), parent: nil)
            root.rect = box
            engine.layoutNode(root)
            return (engine, root)
        }
        func fits(_ root: DgmPresNode) -> Bool {
            // Nothing outside the frame, and no box sized in font sizes
            // squeezed smaller than that by the room it was given.
            func squeezed(_ n: DgmPresNode) -> Bool {
                // A text box held under its font-sized height by a cap, too
                // short for its text at the font size: its lines (one a
                // paragraph) at 1.2 of the size, and its top and bottom
                // margins — accent-process's heading, capped at 0.4 of its
                // width, holds "a" at 33 pt in PowerPoint's print, and
                // every box sized in font sizes follows.
                if n.algType == "tx", n.heightCappedByWidth, n.rect.height > 0, let cap = n.caps["h"], let asked = n.vals["h"], asked > cap + 0.5 {
                    let lines = n.presOf.compactMap { $0.text }.flatMap { $0.all("a:p") }
                        .filter { p in p.all("a:r").contains { !($0.first("a:t")?.text ?? "").isEmpty } }.count
                    if lines > 0 {
                        let prim = n.value("primFontSz") ?? 65
                        // (A size the text states is the text's: fill-color-
                        // list's 18 pt headings, whatever the rule's.)
                        let stated = n.presOf.compactMap { $0.text }.flatMap { $0.all("a:p") }.flatMap { $0.all("a:r") }
                            .compactMap { $0.first("a:rPr")?["sz"].flatMap(Double.init) }.max().map { $0 / 100 }
                        let size = stated ?? prim
                        let need = Double(lines) * 1.2 * size + (n.value("tMarg") ?? 0.56 * prim) + (n.value("bMarg") ?? 0.56 * prim)
                        if need > n.rect.height + 0.5 { return true }
                    }
                }
                if n.shapeType != nil, !n.hideGeom {
                    // (The size asked for: once laid out, `value` is the slot.)
                    func asked(_ d: String) -> Double? { n.vals[d].map { min($0, n.caps[d] ?? .infinity) } }
                    if n.fontSized.contains("h"), let h = asked("h"), n.rect.height < h - 0.5 { return true }
                    if n.fontSized.contains("w"), let w = asked("w"), n.rect.width < w - 0.5 { return true }
                }
                return n.children.contains(where: squeezed)
            }
            if squeezed(root) { return false }
            guard let u = first.union(of: root.children) else { return true }
            return u.width <= box.width + 0.5 && u.height <= box.height + 0.5
        }
        var (engine, root) = laidOut(fontCap: .infinity)
        // A layout that lets its text shrink (`rule type="primFontSz"`,
        // down to the rule's value) and does not fit at its own sizes is
        // laid out again at the largest whole font size that does: what
        // PowerPoint does, keeping the widths its algorithms give, where
        // scaling the whole tree down narrowed every box with the text
        // (hList1 at 31 pt, hProcess3 at 50 — both PowerPoint's). If no
        // size fits, the sizes do not decide the fit (an org chart drawn
        // at ten times its frame), and the tree is scaled as before.
        if !fits(root), let floor = Self.fontFloor(layout) {
            var lo = Int(floor.rounded(.up)), hi = 64
            var best: (DiagramLayout, DgmPresNode)? = nil
            while lo <= hi {
                let mid = (lo + hi) / 2
                let attempt = laidOut(fontCap: Double(mid))
                if fits(attempt.1) { best = attempt; lo = mid + 1 } else { hi = mid - 1 }
            }
            if let best { (engine, root) = best }
        }
        engine.fit(root, into: box)
        #if !os(WASI)
        if ProcessInfo.processInfo.environment["STARLING_DIAGRAM_DEBUG"] != nil {
            func dump(_ n: DgmPresNode, _ d: Int) {
                let text = n.presOf.compactMap { $0.text?.descendant("a:t")?.text }.joined(separator: "/")
                let r = n.rect
                var line = String(repeating: "  ", count: d)
                line += "\(n.name) [\(n.algType)] \(n.shapeType ?? "-") "
                line += "[\(whole(r.left)),\(whole(r.top)) \(whole(r.width))x\(whole(r.height))] "
                let vals: [String] = n.vals.map { "\($0.key)=\(whole($0.value))" }
                line += vals.sorted().joined(separator: " ")
                let caps: [String] = n.caps.map { "\($0.key)<=\(whole($0.value))" }
                if !caps.isEmpty { line += " caps:" + caps.joined(separator: ",") }
                if !text.isEmpty { line += " \"" + text + "\"" }
                line += "\n"
                FileHandle.standardError.write(Data(line.utf8))
                for c in n.children { dump(c, d + 1) }
            }
            dump(root, 0)
        }
        #endif
        return engine.emit(root)
    }

    /// The smallest font size a layout's rules let its text shrink to, or
    /// nil when it has no such rule.
    private static func fontFloor(_ layout: XNode) -> Double? {
        var floor: Double? = nil
        func walk(_ n: XNode) {
            if n.name == "dgm:rule", let t = n["type"], t == "primFontSz" || t == "secFontSz" {
                let v = n["val"].flatMap(Double.init) ?? 5
                floor = min(floor ?? v, v.isFinite ? max(1, v) : 5)
            }
            n.children.forEach(walk)
        }
        walk(layout)
        return floor
    }

    // MARK: - Building the presentation tree

    private mutating func build(_ def: XNode, point: DgmPoint, iter: (Int, Int), parent: DgmPresNode?) -> DgmPresNode {
        let node = DgmPresNode(name: def["name"] ?? "", point: point, parent: parent)
        node.styleLbl = def["styleLbl"]
        node.iterIndex = iter.0
        node.iterCount = iter.1
        node.order = nextOrder
        nextOrder += 1
        // The data model's presentation variables for this node win over
        // the definition's (a diagram flipped right-to-left).
        for v in def.first("dgm:varLst")?.children ?? [] { node.vars[String(v.name.dropFirst(4))] = v["val"] ?? "" }
        if let pr = model.pres[point.id + "|" + node.name], let lv = pr.first("dgm:presLayoutVars") {
            for v in lv.children { node.vars[String(v.name.dropFirst(4))] = v["val"] ?? "" }
        }
        process(def.children, into: node, point: point, iter: iter)
        return node
    }

    private mutating func process(_ elements: [XNode], into node: DgmPresNode, point: DgmPoint, iter: (Int, Int)) {
        for el in elements {
            switch el.name {
            case "dgm:alg":
                node.algType = el["type"] ?? ""
                for p in el.all("dgm:param") { if let t = p["type"], let v = p["val"] { node.params[t] = v } }
            case "dgm:shape":
                node.shapeType = el["type"]
                node.shapeRot = el["rot"].flatMap(Double.init) ?? 0
                node.hideGeom = el["hideGeom"] == "1" || el["hideGeom"] == "true"
                node.zOrderOff = el["zOrderOff"].flatMap(Int.init) ?? 0
                node.adjustments = (el.first("dgm:adjLst")?.all("dgm:adj") ?? []).compactMap { a in
                    guard let i = a["idx"].flatMap(Int.init), let v = a["val"].flatMap(Double.init) else { return nil }
                    return (i, v)
                }
            case "dgm:presOf":
                node.presOf = select(from: point, axis: el["axis"], ptType: el["ptType"], st: el["st"], cnt: el["cnt"],
                                     step: el["step"], hideLastTrans: true, iter: iter)
            case "dgm:constrLst":
                node.constraints += el.all("dgm:constr")
            case "dgm:ruleLst":
                node.rules += el.all("dgm:rule")
            case "dgm:choose":
                var taken = false
                for branch in el.children where branch.name == "dgm:if" || branch.name == "dgm:else" {
                    if branch.name == "dgm:if" && !condition(branch, point: point, node: node, iter: iter) { continue }
                    process(branch.children, into: node, point: point, iter: iter)
                    taken = true
                    break
                }
                _ = taken
            case "dgm:forEach":
                let fe = el["ref"].flatMap { forEachByName[$0] } ?? el
                let points = select(from: point, axis: fe["axis"], ptType: fe["ptType"], st: fe["st"], cnt: fe["cnt"],
                                    step: fe["step"], hideLastTrans: fe["hideLastTrans"] != "0", iter: iter)
                for (i, p) in points.enumerated() {
                    process(fe.children, into: node, point: p, iter: (i, points.count))
                }
            case "dgm:layoutNode":
                let child = build(el, point: point, iter: iter, parent: node)
                node.children.append(child)
            default:
                break
            }
        }
    }

    /// The points an axis reaches from `point`, by type, sliced by st/cnt/step.
    private func select(from point: DgmPoint, axis: String?, ptType: String?, st: String?, cnt: String?, step: String?,
                        hideLastTrans: Bool, iter: (Int, Int)) -> [DgmPoint] {
        let axes = (axis ?? "self").split(separator: " ").map(String.init)
        let types = (ptType ?? "all").split(separator: " ").map(String.init)
        let starts = (st ?? "").split(separator: " ").map(String.init)
        let counts = (cnt ?? "").split(separator: " ").map(String.init)
        let steps = (step ?? "").split(separator: " ").map(String.init)
        var set = [point]
        // Each step of the axis has its own slice (`axis="ch desOrSelf"
        // st="1 1" cnt="1 0"`: the first child, then all of its subtree).
        for (i, ax) in axes.enumerated() {
            let type = i < types.count ? types[i] : (types.last ?? "all")
            set = set.flatMap { walk(ax, from: $0, type: type, hideLastTrans: hideLastTrans) }
            set = Self.slice(set, st: i < starts.count ? starts[i] : nil, cnt: i < counts.count ? counts[i] : nil,
                             step: i < steps.count ? steps[i] : nil)
        }
        return set
    }

    private static func slice(_ set: [DgmPoint], st: String?, cnt: String?, step: String?) -> [DgmPoint] {
        var start = Int(st ?? "1") ?? 1
        let count = Int(cnt ?? "0") ?? 0
        let stride = max(1, Int(step ?? "1") ?? 1)
        if start < 0 { start = set.count + start + 1 }
        start = max(1, start)
        var out: [DgmPoint] = []
        var i = start - 1
        while i < set.count {
            out.append(set[i])
            if count > 0 && out.count >= count { break }
            i += stride
        }
        return out
    }

    private func walk(_ axis: String, from q: DgmPoint, type: String, hideLastTrans: Bool) -> [DgmPoint] {
        // Transitions live in the sibling sequence; nodes in the tree.
        let transitions = type == "sibTrans" || type == "parTrans"
        var base: [DgmPoint]
        switch axis {
        case "self": base = [q]
        case "ch":
            base = transitions ? q.children.flatMap { [$0.parTrans, $0.sibTrans].compactMap { $0 } } : q.children
        case "des": base = q.descendants
        case "desOrSelf": base = [q] + q.descendants
        case "par": base = q.parent.map { [$0] } ?? []
        case "ancst": base = q.ancestors
        case "ancstOrSelf": base = [q] + q.ancestors
        case "followSib", "precedSib":
            let seq = q.siblingSequence
            guard let i = seq.firstIndex(where: { $0 === q }) else { return [] }
            base = axis == "followSib" ? Array(seq[(i + 1)...]) : Array(seq[..<i])
        case "root": base = [model.root]
        default: base = []
        }
        if transitions && hideLastTrans && type == "sibTrans" {
            // The last sibling's transition goes nowhere: hidden.
            base = base.filter { t in
                guard let d = t.cxnDst.flatMap({ model.points[$0] }), let par = d.parent else { return true }
                return par.children.last !== d
            }
        }
        return base.filter { matches($0, type) }
    }

    private func matches(_ p: DgmPoint, _ type: String) -> Bool {
        switch type {
        case "all": return true
        case "node": return p.isNode
        case "asst": return p.type == "asst"
        case "nonAsst": return p.type == "node"
        case "nonNorm": return p.type == "asst"
        case "doc": return p.type == "doc"
        default: return p.type == type
        }
    }

    private func condition(_ el: XNode, point: DgmPoint, node: DgmPresNode, iter: (Int, Int)) -> Bool {
        let fn = el["func"] ?? "cnt"
        let op = el["op"] ?? "equ"
        let val = el["val"] ?? ""
        let points = select(from: point, axis: el["axis"], ptType: el["ptType"], st: el["st"], cnt: el["cnt"],
                            step: el["step"], hideLastTrans: true, iter: iter)
        var lhs: String
        switch fn {
        case "cnt": lhs = String(points.count)
        case "pos": lhs = String(iter.0 + 1)
        case "revPos": lhs = String(iter.1 - iter.0)
        case "posEven": lhs = (iter.0 + 1) % 2 == 0 ? "1" : "0"
        case "posOdd": lhs = (iter.0 + 1) % 2 == 1 ? "1" : "0"
        case "depth": lhs = String(point.depth)
        case "maxDepth": lhs = String(points.map { $0.depth - point.depth }.max() ?? 0)
        case "var":
            let arg = el["arg"] ?? ""
            lhs = node.variable(arg) ?? Self.defaultVar(arg)
            // A variable named without a value has its default: an org
            // chart's `<dgm:hierBranch/>` is "std", not nothing (which matched
            // no branch, and drew a standard block with hanging connectors).
            if lhs.isEmpty { lhs = Self.defaultVar(arg) }
            if arg == "hierBranch", lhs == "init" {
                // "init" is PowerPoint's own choice, not one the definition
                // has a branch for: a node whose children are all leaves hangs
                // them to its right, any other — and the top of the chart —
                // sets them side by side (org-chart2 against its picture).
                var declaring: DgmPresNode? = node
                while let d = declaring, d.vars[arg] == nil { declaring = d.parent }
                let p = (declaring ?? node).point
                let kids = p.children.filter { $0.type == "node" }
                let top = p.parent == nil || p.parent?.type == "doc"
                let leaves = kids.allSatisfy { k in !k.children.contains { $0.type == "node" || $0.type == "asst" } }
                lhs = !top && kids.count >= 2 && leaves ? "r" : "std"
            }
        default: lhs = ""
        }
        if let a = Double(lhs), let b = Double(val) {
            switch op {
            case "equ": return a == b
            case "neq": return a != b
            case "gt": return a > b
            case "gte": return a >= b
            case "lt": return a < b
            case "lte": return a <= b
            default: return false
            }
        }
        // Booleans spell themselves "true"/"1".
        let truth: [String: String] = ["true": "1", "false": "0"]
        let l = truth[lhs] ?? lhs, r = truth[val] ?? val
        return op == "neq" ? l != r : l == r
    }

    private static func defaultVar(_ name: String) -> String {
        switch name {
        case "dir": return "norm"
        case "hierBranch": return "std"
        case "animLvl", "animOne": return "none"
        case "bulletEnabled": return "0"
        case "chMax", "chPref": return "-1"
        case "resizeHandles": return "rel"
        case "orgChart": return "0"
        default: return ""
        }
    }

    // MARK: - Constraints

    private static let margins: Set<String> = ["lMarg", "tMarg", "rMarg", "bMarg"]

    /// The constraint types that are lengths on the diagram (margins are not).
    private static let lengths: Set<String> = ["w", "h", "l", "t", "r", "b", "ctrX", "ctrY",
                                               "lOff", "tOff", "rOff", "bOff", "ctrXOff", "ctrYOff",
                                               "wOff", "hOff", "diam", "sp", "sibSp", "secSibSp", "begPad", "endPad"]

    private func targets(_ node: DgmPresNode, for scope: String?, name: String?, ptType: String?) -> [DgmPresNode] {
        var list: [DgmPresNode]
        switch scope ?? "self" {
        case "ch": list = node.children
        case "des": list = node.descendants
        default: list = [node]
        }
        if let name { list = list.filter { $0.name == name } }
        if let ptType {
            let types = ptType.split(separator: " ").map(String.init)
            list = list.filter { n in types.contains { matches(n.point, $0) } }
        }
        return list
    }

    private func applyConstraints(_ node: DgmPresNode, selfOnly: Bool = false, proportionCapsOnly: Bool = false) {
        for c in node.constraints {
            guard let type = c["type"] else { continue }
            let scope = c["for"] ?? "self"
            if selfOnly && scope != "self" { continue }
            if proportionCapsOnly && !(scope == "self" && c["op"] == "lte" && c["refFor"] == nil
                                       && ["w", "h"].contains(type) && ["w", "h"].contains(c["refType"] ?? "")) { continue }
            let fact = c["fact"].flatMap(Double.init) ?? 1
            let op = c["op"] ?? "equ"
            if type.hasSuffix("FontSz"), c["op"] == "equ" {
                // Every shape under it is of the group, whatever its point
                // type: cycleMatrix's quadrants end at 43 together and its
                // side boxes at 12, where one smallest size for all the
                // diagram's 65 pt text made them all 16.
                // (Keyed by the constraint, not the node that holds it: an org
                // chart's every box repeats one definition, and all end at
                // PowerPoint's one 30 pt.)
                var group = "\(ObjectIdentifier(c).hashValue)"
                // Equal to another shape's size: one group with that shape
                // (process3's text under its heading, both PowerPoint's 34).
                if let refType = c["refType"], refType.hasSuffix("FontSz"), c["refFor"] != nil || c["refForName"] != nil {
                    let refs = targets(node, for: c["refFor"], name: c["refForName"], ptType: nil)
                    if let g = refs.lazy.compactMap(\.sizeGroup).first { group = g }
                    for r in refs { r.sizeGroup = group }
                }
                for t in targets(node, for: scope, name: c["forName"], ptType: nil) { t.sizeGroup = group }
            }
            let ts = targets(node, for: scope, name: c["forName"], ptType: c["ptType"])
            if ts.isEmpty { continue }
            if let refType = c["refType"] {
                let refs = targets(node, for: c["refFor"], name: c["refForName"], ptType: c["refPtType"])
                for t in ts {
                    // The referred node: the first match, or the target itself
                    // when the reference names its own kind (h = 0.6 w).
                    let ref = refs.first { $0 === t } ?? refs.first ?? node
                    // A sibling measured from is held to its own proportions
                    // first: hList1's body starts under a heading capped at
                    // 0.4 of its width, not under the height the font asked
                    // for. (Only those: hProcess3's text is capped by a user
                    // variable that PowerPoint lets it outgrow.)
                    if ref !== t, ref !== node, !ref.laidOut { applyConstraints(ref, proportionCapsOnly: true) }
                    guard var base = ref.value(refType) ?? (refType == "primFontSz" ? min(65, fontCap) : nil), base.isFinite else { continue }
                    // A size or place given as a multiple of a font size is
                    // that many millimetres: hProcess3's arrow is twice its
                    // 50 pt text, and 100 mm tall in PowerPoint's export
                    // (lo-smartart-linear-rule). Read as points, every such
                    // box was 2.8 times too small and its text shrunk into it.
                    // (A margin is not: desTx's 0.3 of 65 pt is 19.5 pt in.)
                    if refType.hasSuffix("FontSz"), Self.lengths.contains(type) {
                        base *= 72 / 25.4
                        if op == "equ", type == "w" || type == "h" { t.fontSized.insert(type) }
                    }
                    set(t, type, base * fact, op)
                    if t === node, op == "equ" { t.selfSet.insert(type) }
                    if ref !== t, op == "equ" { t.sizeRef[type] = ref.name }
                    if op == "lte", ref === t, type == "h", refType == "w" { t.heightCappedByWidth = true }
                    // (A factor of a thousand is not a proportion: `h` = 1000 `w`
                    // is how a layout says "as tall as it needs", and kept in
                    // step with it, a step as tall as the frame was a third
                    // of a point wide — accent-process's boxes, gone.)
                    if ref === t, ["w", "h"].contains(type), ["w", "h"].contains(refType), type != refType, op == "equ",
                       fact < 100, fact > 0.01 {
                        t.derived[type] = (refType, fact)
                    }
                }
            } else if let v = c["val"].flatMap(Double.init), v.isFinite {
                for t in ts {
                    set(t, type, v * fact, op)
                    if t === node, op == "equ" { t.selfSet.insert(type) }
                }
            } else if c["val"] == "INF" {
                // No bound at all: the contents' size (no room to spare —
                // `layoutLinear`).
            } else if c["val"] == nil, Self.margins.contains(type) {
                // A margin named with no value is the schema's 0 — not the
                // default a margin no constraint names gets (`textBody`).
                for t in ts { set(t, type, 0, op) }
            }
        }
    }

    /// A child's natural size along `dim` before it is laid out: its
    /// constraint, or — a container with none — what its children add up
    /// to (a row of shapes is as tall as its tallest); a shape with none
    /// fills what it is offered.
    private func measure(_ c: DgmPresNode, _ dim: String, avail: Double) -> Double {
        applyConstraints(c, selfOnly: true)
        if let v = c.vals[dim], v.isFinite {
            // (A row or column of no shape of its own is at least what its
            // children add up to along it, or the widest across: smartart-children's each parent as wide
            // as the frame by its constraint, holding two children as wide
            // and a space — PowerPoint scales the whole, nested, at once,
            // its outer space 0.168 of a child, the inner half that; held
            // to the frame, the parent's row was squeezed twice over.)
            if let content = settledContent(c, dim) { return min(max(v, content), c.caps[dim] ?? .infinity) }
            return min(v, c.caps[dim] ?? .infinity)
        }
        if c.isSpace || c.isConnector { return 0 }
        // (A container with nothing in it — hierarchy4's row of children
        // under a node that has none — takes no room: counted as the whole
        // height, it left the boxes above a third of theirs.)
        if c.shapeType == nil, c.children.isEmpty, c.algType == "lin" { return 0 }
        if c.shapeType != nil || c.children.isEmpty { return min(avail, c.caps[dim] ?? .infinity) }
        let dir = c.params["linDir"] ?? "fromL"
        let along = c.algType == "lin" && ((dim == "w") == (dir == "fromL" || dir == "fromR"))
        var total = 0.0
        for k in c.children {
            let m = measure(k, dim, avail: avail)
            total = along ? total + m : max(total, m)
        }
        return min(total, c.caps[dim] ?? .infinity)
    }

    /// What a row or column of no shape of its own holds along `dim`
    /// when every child's size there is settled by a constraint (or is a
    /// space with none): the sum along it, the widest across. Nil when
    /// any child only fills what it is offered, or is sized below nothing.
    private func settledContent(_ c: DgmPresNode, _ dim: String) -> Double? {
        guard c.algType == "lin", c.shapeType == nil, !c.children.isEmpty else { return nil }
        let dir = c.params["linDir"] ?? "fromL"
        let along = (dim == "w") == (dir == "fromL" || dir == "fromR")
        var sizes: [Double] = []
        for k in c.children {
            if let v = k.vals[dim], v.isFinite {
                sizes.append(max(v, settledContent(k, dim) ?? 0))
            } else if k.isSpace || k.isConnector {
                sizes.append(0)
            } else if let inner = settledContent(k, dim) {
                sizes.append(inner)
            } else {
                return nil
            }
        }
        // (A negative size is an overlap — linear-rule's arrow drawn back
        // under its row, `w` = −1 × the row's — not room the row holds.)
        guard sizes.allSatisfy({ $0 >= 0 }) else { return nil }
        return along ? sizes.reduce(0, +) : sizes.max()
    }

    private func set(_ t: DgmPresNode, _ type: String, _ v: Double, _ op: String) {
        let v = type.hasSuffix("FontSz") ? min(v, fontCap) : v
        switch op {
        case "lte":
            t.caps[type] = min(t.caps[type] ?? v, v)
            // A size tied to the other (h = w) takes the other with it when
            // it is capped: the circle stays round, as small as its row.
            if let d = t.derived[type], d.fact > 0 {
                t.caps[d.ref] = min(t.caps[d.ref] ?? .infinity, v / d.fact)
                if let w = t.vals[d.ref], w > v / d.fact { t.vals[d.ref] = v / d.fact }
                if let h = t.vals[type], h > v { t.vals[type] = v }
            }
        case "gte": t.floors[type] = max(t.floors[type] ?? v, v)
        default: t.vals[type] = v
        }
    }

    // MARK: - Layout

    /// Lays `node` out within its rect, placing its children.
    private func layoutNode(_ node: DgmPresNode) {
        node.laidOut = true
        applyConstraints(node)
        if node.parent != nil {
            // The node's own caps (h at most 0.4 w) can only make the slot
            // its parent gave it smaller.
            var w = min(node.rect.width, node.caps["w"] ?? .infinity), h = min(node.rect.height, node.caps["h"] ?? .infinity)
            // (A size of 1 is a unit for the node's proportions, `w` = 1
            // and `h` = 1.06 `w`, not a point: taken as a width, a snake's
            // item collapsed to a line down its middle and its contents were
            // laid out from there, half an item too low.)
            if node.selfSet.contains("w"), let v = node.vals["w"], v > 1.5 { w = min(w, v) }
            if node.selfSet.contains("h"), let v = node.vals["h"], v > 1.5, (node.vals["w"] ?? 2) > 1.5 { h = min(h, v) }
            if w < node.rect.width - 0.01 || h < node.rect.height - 0.01 {
                // (A turned one about its middle, where it was placed: a
                // cycle's arrows, set on the chord between their nodes and
                // capped after, stood half their height above it.)
                node.rect = node.rotation != 0 ? Rect.fromCenter(center: node.rect.center, width: w, height: h)
                    : Rect.fromLTWH(node.rect.left, node.rect.top, w, h)
            }
        }
        if let ar = node.params["ar"].flatMap(Double.init), ar > 0, node.rect.width > 0, node.rect.height > 0 {
            // A fixed aspect (a radial diagram's square), centred.
            var w = node.rect.width, h = node.rect.height
            if w / h > ar { w = h * ar } else { h = w / ar }
            if abs(w - node.rect.width) > 0.01 || abs(h - node.rect.height) > 0.01 {
                node.rect = Rect.fromCenter(center: node.rect.center, width: w, height: h)
                // Its children's sizes are of the square, not of the slot it
                // was cut from: cycleMatrix's quadrants are 0.433 of the
                // circle each way, and were 208 × 139 where PowerPoint's are
                // 138.6 square.
                applyConstraints(node)
            }
        }
        switch node.algType {
        case "lin": layoutLinear(node)
        case "snake": layoutSnake(node)
        case "cycle": layoutCycle(node)
        case "hierRoot": layoutHierRoot(node)
        case "hierChild": layoutHierChild(node)
        case "pyra": layoutPyramid(node)
        case "sp", "tx", "conn", "space":
            // A connector's own text sits in its box.
            for c in node.children {
                c.rect = node.rect
                layoutNode(c)
            }
        default: layoutComposite(node)
        }
    }

    private func size(_ c: DgmPresNode, _ dim: String, within avail: Double) -> Double {
        if c.isSpace || c.isConnector { return c.vals[dim] ?? 0 }
        return measure(c, dim, avail: avail)
    }

    private func layoutComposite(_ node: DgmPresNode) {
        for c in node.children {
            var w = measure(c, "w", avail: node.rect.width), h = measure(c, "h", avail: node.rect.height)
            var x = 0.0, y = 0.0
            // Two edges given size it between them (l and r: w = r - l).
            if let l = c.vals["l"], let r = c.vals["r"], c.vals["w"] == nil { w = r - l }
            if let t = c.vals["t"], let b = c.vals["b"], c.vals["h"] == nil { h = b - t }
            if let l = c.vals["l"] { x = l } else if let cx = c.vals["ctrX"] { x = cx - w / 2 } else if let r = c.vals["r"] { x = r - w }
            if let t = c.vals["t"] { y = t } else if let cy = c.vals["ctrY"] { y = cy - h / 2 } else if let b = c.vals["b"] { y = b - h }
            // An edge's offset moves that edge — or, where the size is given
            // and the box hangs from one edge, the whole box: cycleMatrix's
            // quadrants keep their 0.433 and stand 1% off the middle, as
            // PowerPoint's 138.6-point squares do.
            let fixedW = c.vals["w"] != nil && !(c.vals["l"] != nil && c.vals["r"] != nil)
            let fixedH = c.vals["h"] != nil && !(c.vals["t"] != nil && c.vals["b"] != nil)
            if let o = c.vals["lOff"] { x += o; if !fixedW { w -= o } }
            if let o = c.vals["rOff"] { if fixedW { x += o } else { w += o } }
            if let o = c.vals["tOff"] { y += o; if !fixedH { h -= o } }
            if let o = c.vals["bOff"] { if fixedH { y += o } else { h += o } }
            // A rule letting a size grow without bound (`val="INF"`) lets it
            // take what is left of the composite, within its own cap.
            func unbounded(_ type: String) -> Bool { c.rules.contains { $0["type"] == type && $0["val"] == "INF" } }
            // (A composite that is itself only "as tall as it needs" — `h`
            // a thousand `w` — has no height to hand out: its children keep
            // the ones their constraints gave them.)
            let nominalH = node.vals["h"].map { $0 > 50 * max(1, node.rect.width) } ?? false
            // (Not a size a constraint gave: that rule is leave to grow for
            // its text, and hList1's empty body is its 1.22 × 65 mm in
            // PowerPoint, not the rest of the column.)
            if unbounded("h"), !nominalH, c.vals["h"] == nil { h = max(h, min(c.caps["h"] ?? .infinity, node.rect.height - y)) }
            if unbounded("w"), c.vals["w"] == nil { w = max(w, min(c.caps["w"] ?? .infinity, node.rect.width - x)) }
            // The author's own resizing (`custScaleX`/`Y`), about the
            // box's middle and after the constraints: composite-infer-right's
            // picture is 70.8% of its fifth, its text where it was.
            if let pr = model.pres[c.point.id + "|" + c.name] {
                if let sx = pr["custScaleX"].flatMap(Double.init), sx > 0 { x += w * (1 - sx / 100_000) / 2; w *= sx / 100_000 }
                if let sy = pr["custScaleY"].flatMap(Double.init), sy > 0 { y += h * (1 - sy / 100_000) / 2; h *= sy / 100_000 }
            }
            c.rect = Rect.fromLTWH(node.rect.left + x, node.rect.top + y, w, h)
            layoutNode(c)
            // A child that came out smaller than its slot keeps the
            // anchoring it was placed by (centred on ctrY, or against the
            // right or bottom edge).
            if let box = extent(of: [c]), box.width > 0, box.height > 0 {
                var d = Offset.zero
                if c.vals["l"] == nil, let cx = c.vals["ctrX"] { d = Offset(node.rect.left + cx - box.center.dx, d.dy) }
                else if c.vals["l"] == nil, let r = c.vals["r"] { d = Offset(node.rect.left + r - box.right, d.dy) }
                if c.vals["t"] == nil, let cy = c.vals["ctrY"] { d = Offset(d.dx, node.rect.top + cy - box.center.dy) }
                else if c.vals["t"] == nil, let b = c.vals["b"] { d = Offset(d.dx, node.rect.top + b - box.bottom) }
                if abs(d.dx) > 0.01 || abs(d.dy) > 0.01 { shift(c, d) }
            }
        }
        // A composite is as big as what it holds (its slot stays where its
        // parent put it; the size is for alignment).
        if node.parent != nil, let u = extent(of: node.children) { node.rect = u }
    }

    /// The box round the visible children (a hidden text box does not count).
    private func union(of nodes: [DgmPresNode]) -> Rect? {
        var r: Rect? = nil
        for c in nodes where !(c.isSpace && c.shapeType == nil) && !c.hideGeom && !(c.isConnector && c.rect.isEmpty) {
            let box = c.shapeType == nil ? union(of: c.children) : c.rect
            guard let box, box.width > 0 || box.height > 0 else { continue }
            r = r.map { Rect.fromLTRB(min($0.left, box.left), min($0.top, box.top), max($0.right, box.right), max($0.bottom, box.bottom)) } ?? box
        }
        return r
    }

    /// The box the children take up, spaces included (what a container
    /// is, for its own parent to place): a space is real room, even if
    /// nothing is drawn in it. So is a shape drawn as nothing (`hideGeom`):
    /// pList2's invisiNode holds the top of each item, and left out, the
    /// item was centred in its row 8 pt above PowerPoint's.
    private func extent(of nodes: [DgmPresNode]) -> Rect? {
        var r: Rect? = nil
        for c in nodes where !(c.isConnector && c.rect.isEmpty) {
            let box: Rect?
            if c.shapeType == nil && !c.isSpace {
                // A line knows its own run (spaces included) once laid out.
                box = c.algType == "lin" && c.laidOut ? c.rect : extent(of: c.children)
            } else if c.isSpace && c.shapeType == nil {
                // A space has no box of its own; the line it sits in counts
                // it along its direction (`layoutLinear`).
                box = nil
            } else { box = c.rect }
            guard let box, box.width > 0 || box.height > 0 else { continue }
            let l = min(box.left, box.right), t = min(box.top, box.bottom), rr = max(box.left, box.right), b = max(box.top, box.bottom)
            r = r.map { Rect.fromLTRB(min($0.left, l), min($0.top, t), max($0.right, rr), max($0.bottom, b)) } ?? Rect.fromLTRB(l, t, rr, b)
        }
        return r
    }

    private func layoutLinear(_ node: DgmPresNode, forceDir: String? = nil) {
        let dir = forceDir ?? node.params["linDir"] ?? "fromL"
        let horizontal = dir == "fromL" || dir == "fromR"
        let P = horizontal ? "w" : "h", S = horizontal ? "h" : "w"
        let availP = horizontal ? node.rect.width : node.rect.height
        let availS = horizontal ? node.rect.height : node.rect.width
        var primary: [Double] = [], secondary: [Double] = []
        for c in node.children {
            if c.shapeType == nil && c.children.isEmpty && !c.isSpace && !c.isConnector {
                // A container with nothing in it (a leaf's children row).
                primary.append(0); secondary.append(0)
                continue
            }
            var p = size(c, P, within: availP)
            var s = c.isSpace || c.isConnector ? (c.vals[S] ?? availS)
                : min(size(c, S, within: availS), availS)
            // A size following the other (h = 0.6 w) stays in step, and
            // within the slot.
            if let d = c.derived[S], d.ref == P { s = p * d.fact; if s > availS { s = availS; p = s / d.fact } }
            if let d = c.derived[P], d.ref == S { p = s * d.fact }
            primary.append(p); secondary.append(s)
        }
        // Too long for the slot: everything shrinks together, spaces too —
        // unless the rules name what may shrink (`rule type="w" val="0"`
        // on the process steps, never on the arrow behind them).
        let sum = primary.reduce(0, +)
        let shrinkable = Set(node.rules.filter { $0["type"] == P && $0["val"] == "0" }.compactMap { $0["forName"] })
        if sum > availP + 0.01, sum > 0 {
            var flexible = node.children.indices.filter {
                shrinkable.contains(node.children[$0].name) || shrinkable.contains(node.children[$0].sizeRef[P] ?? "")
            }
            if flexible.isEmpty { flexible = Array(node.children.indices) }
            let fixed = node.children.indices.filter { !flexible.contains($0) }.map { primary[$0] }.reduce(0, +)
            let flex = flexible.map { primary[$0] }.reduce(0, +)
            let k = flex > 0 ? max(0, (availP - fixed) / flex) : 1
            for i in flexible {
                primary[i] *= k
                let c = node.children[i]
                if c.isSpace || c.isConnector { continue }
                if let d = c.derived[S], d.ref == P { secondary[i] = min(availS, primary[i] * d.fact) }
            }
        }
        // (Room to spare is not handed to the children a rule lets grow
        // without bound, `rule type="h" val="INF"`: the rule lets them grow
        // for their text, and PowerPoint sets list1's one short item at
        // its constraints' 0.82 and 0.7 × 65 mm, centred, where shared out
        // it filled the frame — vertical-box-list, linear-rule-vert.)
        let total = primary.reduce(0, +)
        let align = horizontal ? (node.params["horzAlign"] ?? "ctr") : (node.params["vertAlign"] ?? "mid")
        var cursor: Double
        switch align {
        case "l", "t": cursor = 0
        case "r", "b": cursor = availP - total
        default: cursor = (availP - total) / 2
        }
        let nodeAlign = horizontal ? (node.params["nodeVertAlign"] ?? "mid") : (node.params["nodeHorzAlign"] ?? "ctr")
        let reversed = dir == "fromR" || dir == "fromB"
        let order = reversed ? Array(node.children.indices.reversed()) : Array(node.children.indices)
        let startP = cursor
        var endP = cursor
        for i in order {
            let c = node.children[i]
            let p = primary[i], s = secondary[i]
            var offS: Double
            switch nodeAlign {
            case "l", "t": offS = 0
            case "r", "b": offS = availS - s
            default: offS = (availS - s) / 2
            }
            c.rect = horizontal
                ? Rect.fromLTWH(node.rect.left + cursor, node.rect.top + offS, p, s)
                : Rect.fromLTWH(node.rect.left + offS, node.rect.top + cursor, s, p)
            cursor += p
            endP = max(endP, cursor)
            layoutNode(c)
        }
        // What a child turned out to hold is what gets aligned across the
        // line (a chevron shorter than its slot sits in the middle of it),
        // and the line is as big as its contents.
        for c in node.children where !c.isSpace {
            let box = extent(of: [c]) ?? c.rect
            let size = horizontal ? box.height : box.width
            let current = horizontal ? box.top - node.rect.top : box.left - node.rect.left
            let wanted: Double
            switch nodeAlign {
            case "l", "t": wanted = 0
            case "r", "b": wanted = availS - size
            default: wanted = (availS - size) / 2
            }
            if abs(wanted - current) > 0.01 { shift(c, horizontal ? Offset(0, wanted - current) : Offset(wanted - current, 0)) }
        }
        // A connector that names the nodes it joins (`srcNode`, `dstNode`)
        // stands midway between those two, not in the middle of its slot:
        // accent-process's arrow runs between the headers "a" and "cc", in
        // PowerPoint's print, where it sat level with the whole columns.
        for (i, c) in node.children.enumerated() where c.isConnector {
            guard let src = c.params["srcNode"], let dst = c.params["dstNode"] else { continue }
            let before = node.children[..<i].last { !$0.isConnector && !$0.isSpace }
            let after = node.children[(i + 1)...].first { !$0.isConnector && !$0.isSpace }
            func named(_ n: DgmPresNode?, _ name: String) -> Rect? {
                guard let n else { return nil }
                if n.name == name, n.rect.width > 0 { return n.rect }
                for k in n.children { if let r = named(k, name) { return r } }
                return nil
            }
            guard let a = named(before, src), let b = named(after, dst) else { continue }
            let mid = horizontal ? Offset((a.right + b.left) / 2, (a.center.dy + b.center.dy) / 2)
                                 : Offset((a.center.dx + b.center.dx) / 2, (a.bottom + b.top) / 2)
            shift(c, Offset(mid.dx - c.rect.center.dx, mid.dy - c.rect.center.dy))
        }
        // The line is as long as its run of children, spaces included, and
        // as deep as what they hold.
        if node.parent != nil, let u = extent(of: node.children) {
            node.rect = horizontal
                ? Rect.fromLTRB(min(u.left, node.rect.left + startP), u.top, max(u.right, node.rect.left + endP), u.bottom)
                : Rect.fromLTRB(u.left, min(u.top, node.rect.top + startP), u.right, max(u.bottom, node.rect.top + endP))
        }
    }

    private func layoutSnake(_ node: DgmPresNode) {
        let items = node.children.filter { !$0.isSpace && !$0.isConnector }
        guard let first = items.first else { return }
        let spaces = node.children.filter { $0.isSpace || $0.isConnector }
        let W = node.rect.width, H = node.rect.height
        // The item's own constraints first, for its proportions (`h` = 1.06
        // `w` under a `w` of 1: a shape, not a size) — the width this grid
        // gave it stands.
        let given = first.vals["w"]
        applyConstraints(first, selfOnly: true)
        if let given { first.vals["w"] = given }
        var w = first.value("w") ?? W, h = first.value("h") ?? H
        if let d = first.derived["h"], d.ref == "w" { h = w * d.fact } else if let d = first.derived["w"], d.ref == "h" { w = h * d.fact }
        // An item of a fixed aspect (its composite's `ar`) is that shape
        // in the grid, whatever the frame's: PictureStrips' strips are
        // three times as wide as tall, and PowerPoint stacks three of
        // them in one column, where sized as the frame two fit across.
        if let ar = first.params["ar"].flatMap(Double.init), ar > 0 {
            let side = min(w, h * ar)
            w = side; h = side / ar
        }
        let hs = spaces.first?.vals["w"] ?? 0
        let vs = node.vals["sp"] ?? hs
        let n = items.count
        let byRow = (node.params["flowDir"] ?? "row") == "row"
        // The column count whose grid is largest in the frame.
        var best = 1, bestScore = Double.infinity
        for c in 1 ... n {
            let r = (n + c - 1) / c
            let gw = Double(c) * w + Double(c - 1) * hs, gh = Double(r) * h + Double(r - 1) * vs
            // The grid that comes out largest when scaled into the frame
            // (six tall boxes: three across, not four and two — snake-rows).
            let fit = byRow ? min(W / gw, H / gh) : min(W / gh, H / gw)
            let score = -fit
            if score < bestScore - 1e-9 { best = c; bestScore = score }
        }
        let cols = best, rows = (n + cols - 1) / cols
        let gw = Double(cols) * w + Double(cols - 1) * hs, gh = Double(rows) * h + Double(rows - 1) * vs
        let k = byRow ? min(W / gw, H / gh) : min(W / gh, H / gw)
        let reverse = (node.params["contDir"] ?? "sameDir") == "revDir"
        let grDir = node.params["grDir"] ?? "tL"
        let ox = node.rect.left + (W - (byRow ? gw : gh) * k) / 2, oy = node.rect.top + (H - (byRow ? gh : gw) * k) / 2
        // A last line short of the others stands centred under them
        // (`off="ctr"`, the default: smartart1's fifth box, alone under
        // two).
        let centred = (node.params["off"] ?? "ctr") == "ctr"
        for (i, item) in items.enumerated() {
            var row = i / cols, col = i % cols
            if reverse && row % 2 == 1 { col = cols - 1 - col }
            let inLine = min(cols, n - row * cols)
            let shift = centred && inLine < cols ? Double(cols - inLine) / 2 * (byRow ? (w + hs) : (h + vs)) * k : 0
            if !byRow { swap(&row, &col) }
            var x = Double(col) * (w + hs) * k, y = Double(row) * (h + vs) * k
            if byRow { x += shift } else { y += shift }
            if grDir == "tR" || grDir == "bR" { x = (byRow ? gw : gh) * k - x - w * k }
            if grDir == "bL" || grDir == "bR" { y = (byRow ? gh : gw) * k - y - h * k }
            item.rect = Rect.fromLTWH(ox + x, oy + y, w * k, h * k)
            layoutNode(item)
        }
    }

    private func layoutCycle(_ node: DgmPresNode) {
        let items = node.children.filter { !$0.isSpace && !$0.isConnector }
        let conns = node.children.filter { $0.isConnector }
        guard !items.isEmpty else { return }
        let W = node.rect.width, H = node.rect.height
        let stAng = Double(node.params["stAng"] ?? "0") ?? 0
        let spanAng = Double(node.params["spanAng"] ?? "360") ?? 360
        let centreFirst = node.params["ctrShpMap"] == "fNode"
        let ring = centreFirst ? Array(items.dropFirst()) : items
        let m = ring.count
        func sizes(_ c: DgmPresNode) -> (Double, Double) {
            // The node's own constraints first: its `h` = `w` is what makes
            // cycle2's nodes circles. (Left to its own layout, the rule could
            // only shrink the slot given here, and a slot in the frame's
            // proportions is too flat to shrink into a circle.)
            applyConstraints(c, selfOnly: true)
            var w = c.value("w") ?? W, h = c.value("h") ?? H
            if let d = c.derived["h"], d.ref == "w" { h = w * d.fact } else if let d = c.derived["w"], d.ref == "h" { w = h * d.fact }
            return (w, h)
        }
        var (w, h) = sizes(ring.first ?? items[0])
        let preferredW = w
        let full = abs(abs(spanAng) - 360) < 0.01
        let step = m > 1 ? (full ? spanAng / Double(m) : spanAng / Double(m - 1)) : 0
        var radius = 0.0
        // A spacing between siblings decides the ring by itself: the chord
        // between neighbours is a node and that space, and the whole is
        // scaled into the frame below. (cycle7 also gives `diam` = the
        // frame's width, with nodes that wide and a space 0.65 of one —
        // proportions, not lengths: held to that ring with the space at its
        // unscaled length, its boxes came out a third of PowerPoint's.)
        if let d = node.vals["diam"], node.vals["sibSp"] == nil || m < 2 {
            radius = d / 2
            if m > 1 {
                let chord = 2 * radius * sin(abs(step) / 2 * .pi / 180)
                let room = chord - (node.vals["sibSp"] ?? 0)
                if room > 0, w > room { h *= room / w; w = room }
            }
        } else if centreFirst {
            // The ring touches the centre shape, less the overlap asked for.
            let (cw, _) = sizes(items[0])
            radius = (cw + w) / 2 + (node.vals["sp"] ?? node.vals["sibSp"] ?? 0)
        } else if m > 1 {
            let chord = max(w, h) + (node.vals["sibSp"] ?? 0)
            radius = chord / (2 * sin(abs(step) / 2 * .pi / 180))
        }
        func pos(_ deg: Double) -> Offset { Offset(radius * sin(deg * .pi / 180), -radius * cos(deg * .pi / 180)) }
        // The natural extent, then scaled to fit and centred.
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        var placed: [(DgmPresNode, Offset, Double, Double, Double)] = []
        for (i, c) in ring.enumerated() {
            let a = stAng + Double(i) * step
            var (cw, ch) = sizes(c)
            if cw > w { ch *= w / cw; cw = w }
            placed.append((c, pos(a), cw, ch, (node.params["rotPath"] == "alongPath") ? a : 0))
        }
        if centreFirst {
            let (cw, ch) = sizes(items[0])
            placed.append((items[0], Offset.zero, cw, ch, 0))
        }
        for (i, c) in conns.enumerated() where ring.count > 1 {
            let a = stAng + (Double(i) + 0.5) * step
            // Sized against the nodes as they ended up, not as preferred.
            let cw = (c.value("w") ?? preferredW * 0.25) * (preferredW > 0 ? w / preferredW : 1)
            var ch = (c.value("h") ?? cw) * (preferredW > 0 ? w / preferredW : 1)
            if let d = c.derived["h"], d.ref == "w" { ch = cw * d.fact }
            // Between its two neighbours, on the straight line from one to
            // the other — nearer the centre than the ring by the chord's sag.
            let at = pos(a), sag = cos(abs(step) / 2 * .pi / 180)
            placed.append((c, Offset(at.dx * sag, at.dy * sag), cw, ch, spanAng < 0 ? a + 180 : a))
        }
        for p in placed {
            minX = min(minX, p.1.dx - p.2 / 2); maxX = max(maxX, p.1.dx + p.2 / 2)
            minY = min(minY, p.1.dy - p.3 / 2); maxY = max(maxY, p.1.dy + p.3 / 2)
        }
        guard maxX > minX, maxY > minY else { return }
        let k = min(1, min(W / (maxX - minX), H / (maxY - minY)))
        let cx = node.rect.left + W / 2 - (minX + maxX) / 2 * k, cy = node.rect.top + H / 2 - (minY + maxY) / 2 * k
        for (c, at, cw, ch, rot) in placed {
            c.rect = Rect.fromLTWH(cx + at.dx * k - cw * k / 2, cy + at.dy * k - ch * k / 2, cw * k, ch * k)
            c.rotation = rot
            layoutNode(c)
        }
    }

    /// A pyramid: one band per child, a triangle from the top down, each
    /// band's `level` shape a trapezoid of it; a child with text of its own
    /// (the `acctTx`) gets the strip to the right.
    private func layoutPyramid(_ node: DgmPresNode) {
        let items = node.children.filter { !$0.isSpace && !$0.isConnector }
        guard !items.isEmpty else { return }
        let n = Double(items.count)
        let ratio = node.vals["pyraAcctRatio"] ?? 0
        let hasAccounts = items.contains { $0.children.contains { $0.name == node.params["pyraAcctTxNode"] ?? "acctTx" } }
        let pyramidWidth = node.rect.width * (hasAccounts ? 1 - ratio : 1)
        let apex = Offset(node.rect.left + pyramidWidth / 2, node.rect.top)
        let bandH = node.rect.height / n
        let fromBottom = (node.params["linDir"] ?? "fromB") == "fromB"
        _ = fromBottom
        for (i, item) in items.enumerated() {
            let top = node.rect.top + Double(i) * bandH, bottom = top + bandH
            let wTop = pyramidWidth * Double(i) / n, wBottom = pyramidWidth * Double(i + 1) / n
            let band = Rect.fromLTRB(apex.dx - wBottom / 2, top, apex.dx + wBottom / 2, bottom)
            item.rect = band
            item.laidOut = true
            for c in item.children {
                c.rect = band
                switch c.name {
                case node.params["pyraLvlNode"] ?? "level":
                    c.polygon = wTop > 0.01
                        ? [Offset(apex.dx - wTop / 2, top), Offset(apex.dx + wTop / 2, top), Offset(apex.dx + wBottom / 2, bottom), Offset(apex.dx - wBottom / 2, bottom)]
                        : [apex, Offset(apex.dx + wBottom / 2, bottom), Offset(apex.dx - wBottom / 2, bottom)]
                case node.params["pyraAcctTxNode"] ?? "acctTx":
                    c.rect = Rect.fromLTRB(node.rect.left + pyramidWidth, top, node.rect.right, bottom)
                case node.params["pyraAcctBkgdNode"] ?? "acctBkgd":
                    c.rect = Rect.fromLTRB(node.rect.left + pyramidWidth, top, node.rect.right, bottom)
                    c.hideGeom = true
                default: break
                }
                layoutNode(c)
            }
        }
    }

    /// A hierarchy's root: its shape (a composite) above its children's
    /// block, both laid out at their natural size; the top of the tree is
    /// scaled to the frame afterwards (`fit`).
    private func layoutHierRoot(_ node: DgmPresNode) {
        let gap = node.vals["sp"] ?? node.parent?.vals["sp"] ?? 0
        var y = node.rect.top
        var blocks: [DgmPresNode] = []
        // The shape, then its children's block, then its assistants' — but
        // the assistants stand between the two, beside the line that goes
        // down to the children (an org chart's `hierChild3` with something
        // in it), so they are laid out, and stacked, second.
        var order = Array(node.children)
        let hasAssistants = order.count >= 3 && order[2].algType == "hierChild"
            && order[2].children.contains { !$0.isConnector }
        if hasAssistants { order.swapAt(1, 2) }
        for c in order {
            let w = c.value("w") ?? node.rect.width, h = c.value("h") ?? node.rect.height
            c.rect = Rect.fromLTWH(node.rect.left, y, w, h)
            layoutNode(c)
            let box = extent(of: [c]) ?? c.rect
            c.rect = box.width > 0 ? box : c.rect
            if c.rect.height > 0 || c === order.first { y = c.rect.bottom + gap }
            blocks.append(c)
        }
        if hasAssistants { blocks.swapAt(1, 2) }
        // Centre each block on the widest; a hanging block (children
        // stacked, `linDir=fromT`) hangs to the right of the shape's middle.
        let width = blocks.map(\.rect.width).max() ?? 0
        for b in blocks {
            let dx = node.rect.left + (width - b.rect.width) / 2 - b.rect.left
            if abs(dx) > 0.01 { shift(b, Offset(dx, 0)) }
        }
        // Over its children (`hierAlign="tCtrCh"`, the default): the shape
        // centred between its first and last child's own boxes, not over
        // the width of everything below — smartart-recursion's A stands
        // between B1 and B2, though B1 has two under it and B2 one.
        if (node.params["hierAlign"] ?? "tCtrCh") == "tCtrCh", blocks.count >= 2, let shape = blocks.first,
           blocks[1].algType == "hierChild", ["fromL", "fromR"].contains(blocks[1].params["linDir"] ?? "fromL") {
            let kids = blocks[1].children.filter { !$0.isConnector }.compactMap { shapeRects($0).first }
            if let first = kids.first, let last = kids.last {
                let lo = min(first.center.dx, last.center.dx), hi = max(first.center.dx, last.center.dx)
                let dx = (lo + hi) / 2 - shape.rect.center.dx
                if abs(dx) > 0.01 { shift(shape, Offset(dx, 0)) }
            }
        }
        if blocks.count >= 2, let shape = blocks.first, blocks[1].algType == "hierChild", blocks[1].params["linDir"] == "fromT",
           blocks[1].children.filter({ !$0.isConnector }).count >= 2 {
            // (One child alone sits straight below, as PowerPoint puts it.)
            let hang = blocks[1]
            let childWidth = hang.children.first { !$0.isConnector }?.rect.width ?? hang.rect.width
            let dx = shape.rect.center.dx - 0.25 * childWidth - hang.rect.left
            if abs(dx) > 0.01 { shift(hang, Offset(dx, 0)) }
        }
        if hasAssistants, let shape = blocks.first {
            // An assistant's right edge a little left of the shape's middle.
            let asst = blocks[2]
            let dx = shape.rect.center.dx - 0.11 * shape.rect.width - asst.rect.right
            if abs(dx) > 0.01 { shift(asst, Offset(dx, 0)) }
        }
        if let u = union(of: node.children) { node.rect = u }
    }

    /// A hierarchy's children side by side (or stacked, `linDir=fromT`), at
    /// their natural size, with the connectors between them placed later.
    private func layoutHierChild(_ node: DgmPresNode) {
        let dir = node.params["linDir"] ?? "fromL"
        let horizontal = dir == "fromL" || dir == "fromR"
        let gap = node.vals["sibSp"] ?? node.vals["sp"] ?? node.parent?.vals["sp"] ?? 0
        var cursor = horizontal ? node.rect.left : node.rect.top
        var blocks: [DgmPresNode] = []
        for c in node.children {
            if c.isConnector { continue }
            let w = c.value("w") ?? node.rect.width, h = c.value("h") ?? node.rect.height
            c.rect = horizontal ? Rect.fromLTWH(cursor, node.rect.top, w, h) : Rect.fromLTWH(node.rect.left, cursor, w, h)
            layoutNode(c)
            let box = extent(of: [c]) ?? c.rect
            if box.width > 0 { c.rect = box }
            if horizontal, !blocks.isEmpty {
                // Side by side by their outlines, not their bounding boxes:
                // a sibling comes in as far as a gap from the shapes
                // already placed at the heights it has shapes at. An org
                // chart's second manager, with no one under it, stands
                // beside the first, over the first one's staff
                // (lo-smartart-org-chart, as PowerPoint draws it).
                let placed = blocks.flatMap(shapeRects), mine = shapeRects(c)
                var need = -Double.infinity
                for m in mine {
                    for q in placed where m.top < q.bottom - 0.01 && q.top < m.bottom - 0.01 {
                        need = max(need, q.right + gap - m.left)
                    }
                }
                if need.isFinite, need < 0 {
                    shift(c, Offset(need, 0))
                    c.rect = extent(of: [c]) ?? c.rect
                }
            }
            cursor = (horizontal ? c.rect.right : c.rect.bottom) + gap
            blocks.append(c)
        }
        if let u = union(of: blocks) { node.rect = u }
        if dir == "fromR", let u = union(of: blocks) {
            // Mirrored order: the first child on the right.
            for b in blocks { shift(b, Offset(2 * (u.center.dx - b.rect.center.dx), 0)) }
        }
    }

    /// The boxes of the shapes drawn under `node` (itself included).
    private func shapeRects(_ node: DgmPresNode) -> [Rect] {
        var out: [Rect] = []
        if node.shapeType != nil, !node.hideGeom, !node.isConnector, node.rect.width > 0, node.rect.height > 0 {
            out.append(node.rect)
        }
        for c in node.children { out += shapeRects(c) }
        return out
    }

    private func shift(_ node: DgmPresNode, _ d: Offset) {
        node.rect = node.rect.shift(d)
        for c in node.children { shift(c, d) }
    }

    /// Scales a tree laid out at its natural size into the frame, centred
    /// (hierarchies; anything that grew past the frame).
    private func fit(_ root: DgmPresNode, into frame: Rect) {
        guard let u = union(of: root.children), u.width > 0, u.height > 0 else { return }
        let k = min(frame.width / u.width, frame.height / u.height)
        if abs(k - 1) < 1e-6 && frame.contains(u.center) && u.left >= frame.left - 0.01 && u.top >= frame.top - 0.01 { return }
        let scale = min(1, k)
        let dx = frame.left + (frame.width - u.width * scale) / 2, dy = frame.top + (frame.height - u.height * scale) / 2
        func apply(_ n: DgmPresNode) {
            n.rect = Rect.fromLTWH(dx + (n.rect.left - u.left) * scale, dy + (n.rect.top - u.top) * scale,
                                   n.rect.width * scale, n.rect.height * scale)
            // The font sizes and the margins (fractions of them) are not
            // scaled with the tree: an org chart is defined at ten times the
            // frame (`w` = 10 x the width) and brought down by this very
            // scale, and its 65 pt cap is meant for the boxes as they end
            // up — scaled along, every label was 2.3 pt. The reader fits
            // the text to its shape from the cap down.
            for c in n.children { apply(c) }
        }
        for c in root.children { apply(c) }
    }

    // MARK: - Shapes

    private struct Look {
        var fill: XNode?
        var line: XNode?
        var text: XNode?
        var lineWidth = 9525
        var fillRef = 1
        var lineRef = 2
    }

    /// The colours and style references for a style label, by its index
    /// among the shapes with that label.
    private func look(_ label: String, index: Int, count: Int) -> Look {
        var l = Look()
        func pick(_ list: XNode?) -> XNode? {
            guard let list, !list.children.isEmpty else { return nil }
            let n = list.children.count
            switch list["meth"] ?? "repeat" {
            case "span": return list.children[min(n - 1, count > 1 ? index * n / max(1, count) : 0)]
            case "cycle":
                let period = max(1, 2 * n - 2)
                let i = index % period
                return list.children[i < n ? i : period - i]
            default: return list.children[index % n]
            }
        }
        var lbl = colors?.all("dgm:styleLbl").first { $0["name"] == label }
        if lbl == nil { lbl = colors?.all("dgm:styleLbl").first { $0["name"] == "node1" } }
        l.fill = pick(lbl?.first("dgm:fillClrLst")).map(clone)
        l.line = pick(lbl?.first("dgm:linClrLst")).map(clone)
        l.text = pick(lbl?.first("dgm:txFillClrLst")).map(clone)
        var st = style?.all("dgm:styleLbl").first { $0["name"] == label }
        if st == nil { st = style?.all("dgm:styleLbl").first { $0["name"] == "node1" } }
        if let s = st?.first("dgm:style") {
            l.fillRef = s.first("a:fillRef")?["idx"].flatMap(Int.init) ?? 1
            l.lineRef = s.first("a:lnRef")?["idx"].flatMap(Int.init) ?? 2
            if l.text == nil, let f = s.first("a:fontRef")?.children.first { l.text = clone(f) }
        }
        l.lineWidth = [0: 0, 1: 9525, 2: 25400, 3: 38100][l.lineRef] ?? 12700
        return l
    }

    private func clone(_ n: XNode) -> XNode {
        let c = XNode(name: n.name, attrs: n.attrs)
        c.text = n.text
        c.children = n.children.map(clone)
        return c
    }

    /// A value as a whole number, or 0 when the layout produced none (a
    /// division by a zero size somewhere must not trap).
    static func whole(_ v: Double) -> Int { v.isFinite ? Int(max(-1e12, min(1e12, v)).rounded()) : 0 }
    private static func emu(_ pt: Double) -> String { String(whole(pt * 12700)) }

    private func emit(_ root: DgmPresNode) -> XNode {
        let tree = XNode(name: "p:spTree", attrs: [:])
        let nv = XNode(name: "p:nvGrpSpPr", attrs: [:])
        nv.children = [XNode(name: "p:cNvPr", attrs: ["id": "1", "name": ""]), XNode(name: "p:cNvGrpSpPr", attrs: [:]), XNode(name: "p:nvPr", attrs: [:])]
        tree.children.append(nv)
        tree.children.append(XNode(name: "p:grpSpPr", attrs: [:]))
        // Every shape, in document order, then by its z-order offset.
        let all = [root] + root.descendants
        var labelled: [(DgmPresNode, String)] = []
        for n in all {
            guard n.shapeType != nil || n.isConnector else { continue }
            labelled.append((n, styleLabel(n)))
        }
        var counts: [String: Int] = [:]
        for (_, lbl) in labelled { counts[lbl, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var shapes: [(Int, Int, Int, Int, XNode)] = []
        var id = 100
        for (i, (n, lbl)) in labelled.enumerated() {
            let idx = model.pres[n.point.id + "|" + n.name]?["presStyleIdx"].flatMap(Int.init) ?? seen[lbl, default: 0]
            let cnt = model.pres[n.point.id + "|" + n.name]?["presStyleCnt"].flatMap(Int.init) ?? counts[lbl, default: 1]
            seen[lbl, default: 0] += 1
            let sps = shape(n, look: look(lbl, index: idx, count: cnt), id: id, root: root)
            guard !sps.isEmpty else { continue }
            id += 1
            // `zOrderOff` moves a shape that many places in the stack (-1:
            // behind the shape before it; -99999: behind everything).
            // A shape moved onto another's place goes past it, the way it
            // was heading: +1 lands above the next shape, not still under it
            // (accent-process's label, which was behind its own box).
            for (k, sp) in sps.enumerated() { shapes.append((i + n.zOrderOff, n.zOrderOff.signum(), i, k, sp)) }
        }
        for s in shapes.sorted(by: { ($0.0, $0.1, $0.2, $0.3) < ($1.0, $1.1, $1.2, $1.3) }) { tree.children.append(s.4) }
        return tree
    }

    private func styleLabel(_ n: DgmPresNode) -> String {
        if let pr = model.pres[n.point.id + "|" + n.name], let l = pr["presStyleLbl"] { return l }
        if let l = n.styleLbl { return l }
        if n.isConnector { return n.params["dim"] == "1D" ? "parChTrans1D\(max(1, n.point.depth))" : "sibTrans2D1" }
        return "node\(max(1, n.point.depth))"
    }

    /// The shape for `n` — and, when it is turned a quarter round, its text
    /// as a second, upright shape over where its text area turned to.
    private func shape(_ n: DgmPresNode, look: Look, id: Int, root: DgmPresNode) -> [XNode] {
        let sp = XNode(name: "p:sp", attrs: [:])
        let nvSpPr = XNode(name: "p:nvSpPr", attrs: [:])
        nvSpPr.children = [XNode(name: "p:cNvPr", attrs: ["id": String(id), "name": n.name]),
                           XNode(name: "p:cNvSpPr", attrs: [:]), XNode(name: "p:nvPr", attrs: [:])]
        sp.children.append(nvSpPr)
        let spPr = XNode(name: "p:spPr", attrs: [:])
        sp.children.append(spPr)
        var r = n.rect
        var rot = n.shapeRot + n.rotation
        var flipH = false, flipV = false
        if abs(abs(n.shapeRot) - 180) < 0.01 {
            // Turned round: mirrored instead, so its text stays upright.
            // (Both ways: one mirror is not a half turn — cycleMatrix's third
            // quadrant had its curve and its text in the wrong corner.)
            flipH = true
            flipV = true
            rot -= n.shapeRot
        } else if abs(abs(n.shapeRot) - 90) < 0.01 {
            // Turned on its side: the box the definition sized is the
            // visible one, so the shape's own box is the other way round.
            r = Rect.fromCenter(center: r.center, width: r.height, height: r.width)
        }
        var geometry: XNode
        if let poly = n.polygon, poly.count >= 3 {
            var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
            for p in poly { minX = min(minX, p.dx); maxX = max(maxX, p.dx); minY = min(minY, p.dy); maxY = max(maxY, p.dy) }
            r = Rect.fromLTRB(minX, minY, max(maxX, minX + 0.01), max(maxY, minY + 0.01))
            geometry = Self.path(poly, in: r, closed: true)
            rot = 0
        } else if n.isConnector && n.params["dim"] == "1D" {
            // A line from the parent's shape to the child's, bent halfway —
            // or, for a child hanging below, down from the parent's middle
            // and across to the child's side.
            guard let (a, b) = connectorEnds(n, root: root) else { return [] }
            var from = Offset(a.center.dx, a.bottom)
            if (n.params["endPts"] ?? "").hasPrefix("mid"), abs(b.center.dx - a.center.dx) > 1 {
                let right = b.center.dx >= a.center.dx
                let side = right ? b.left : b.right
                // The line comes down clear of the children it serves, a
                // little outside their edge, not through them.
                let clear = side + (right ? -1 : 1) * 0.16 * b.width
                if right ? side < from.dx : side > from.dx { from = Offset(clear, a.bottom) }
                let to = Offset(side, b.center.dy)
                r = Rect.fromLTRB(min(from.dx, to.dx), min(from.dy, to.dy), max(from.dx, to.dx) + 0.01, max(from.dy, to.dy) + 0.01)
                geometry = Self.path([from, Offset(from.dx, to.dy), to], in: r)
            } else if n.params["connRout"] == "bend" || n.params["endPts"] == "tCtr" {
                let to = Offset(b.center.dx, b.top)
                r = Rect.fromLTRB(min(from.dx, to.dx), min(from.dy, to.dy), max(from.dx, to.dx) + 0.01, max(from.dy, to.dy) + 0.01)
                // Bent halfway — or, `bendPt="end"`, half a level's space
                // above the child, however far up the parent is (assistants
                // may stand in between).
                var mid = (from.dy + to.dy) / 2
                if n.params["bendPt"] == "end" { mid = max(mid, to.dy - 0.105 * b.width) }
                geometry = Self.path([from, Offset(from.dx, mid), Offset(to.dx, mid), to], in: r)
            } else {
                let to = Offset(b.center.dx, b.top)
                r = Rect.fromLTRB(min(from.dx, to.dx), min(from.dy, to.dy), max(from.dx, to.dx) + 0.01, max(from.dy, to.dy) + 0.01)
                geometry = Self.path([from, to], in: r)
            }
            rot = 0
        } else {
            var prst = n.shapeType ?? "rect"
            if prst == "conn" {
                // Arrowheads at both ends make it the two-headed arrow.
                prst = n.params["begSty"] == "arr" && n.params["endSty"] == "arr" ? "leftRightArrow" : "rightArrow"
            }
            geometry = XNode(name: "a:prstGeom", attrs: ["prst": prst])
            let av = XNode(name: "a:avLst", attrs: [:])
            for (i, v) in n.adjustments {
                av.children.append(XNode(name: "a:gd", attrs: ["name": "adj\(i)", "fmla": "val \(Self.whole(v * 100000))"]))
                // (A preset with one adjustment calls it plain "adj":
                // hierarchy4's boxes, `adj idx="1" val="0.1"`, had the
                // rounded rectangle's default corners, two-thirds again
                // as round as PowerPoint's.)
                if i == 1 { av.children.append(XNode(name: "a:gd", attrs: ["name": "adj", "fmla": "val \(Self.whole(v * 100000))"])) }
            }
            geometry.children = [av]
        }
        guard r.width > 0.01 || r.height > 0.01 else { return [] }
        var xfrmAttrs: [String: String] = [:]
        if rot != 0 { xfrmAttrs["rot"] = String(Self.whole(rot * 60000)) }
        if flipH { xfrmAttrs["flipH"] = "1" }
        if flipV { xfrmAttrs["flipV"] = "1" }
        let xfrm = XNode(name: "a:xfrm", attrs: xfrmAttrs)
        xfrm.children = [XNode(name: "a:off", attrs: ["x": Self.emu(r.left), "y": Self.emu(r.top)]),
                         XNode(name: "a:ext", attrs: ["cx": Self.emu(max(0, r.width)), "cy": Self.emu(max(0, r.height))])]
        spPr.children = [xfrm, geometry]
        // Fill and line: the point's own, else the colour scheme's.
        // (The presentation point's first: it is this shape's alone.)
        let own = model.presSpPr[n.point.id + "|" + n.name] ?? n.presOf.first?.spPr ?? n.point.spPr
        let fillNames = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill"]
        if n.hideGeom {
            spPr.children.append(XNode(name: "a:noFill", attrs: [:]))
            let ln = XNode(name: "a:ln", attrs: [:])
            ln.children = [XNode(name: "a:noFill", attrs: [:])]
            spPr.children.append(ln)
        } else if n.isConnector && n.params["dim"] == "1D" {
            spPr.children.append(XNode(name: "a:noFill", attrs: [:]))
            let ln = XNode(name: "a:ln", attrs: ["w": String(max(9525, look.lineWidth))])
            if let c = look.line ?? look.fill { let f = XNode(name: "a:solidFill", attrs: [:]); f.children = [c]; ln.children = [f] }
            spPr.children.append(ln)
        } else {
            if let f = own?.children.first(where: { fillNames.contains($0.name) }) {
                spPr.children.append(clone(f))
            } else if let c = look.fill, look.fillRef > 0 {
                let f = XNode(name: "a:solidFill", attrs: [:])
                f.children = [c]
                spPr.children.append(f)
            } else {
                spPr.children.append(XNode(name: "a:noFill", attrs: [:]))
            }
            if let l = own?.first("a:ln") {
                spPr.children.append(clone(l))
            } else {
                let ln = XNode(name: "a:ln", attrs: ["w": String(look.lineWidth)])
                if let c = look.line, look.lineRef > 0 { let f = XNode(name: "a:solidFill", attrs: [:]); f.children = [c]; ln.children = [f] }
                else { ln.children = [XNode(name: "a:noFill", attrs: [:])] }
                spPr.children.append(ln)
            }
            // The point's own effects (fill-color-list's shadow under
            // each heading).
            if let e = own?.first("a:effectLst") { spPr.children.append(clone(e)) }
        }
        // The style: references with the scheme's colours, the text's colour.
        let style = XNode(name: "p:style", attrs: [:])
        func ref(_ name: String, _ idx: Int, _ c: XNode?) -> XNode {
            let r = XNode(name: name, attrs: ["idx": String(idx)])
            r.children = [c.map(clone) ?? XNode(name: "a:schemeClr", attrs: ["val": "accent1"])]
            return r
        }
        style.children = [ref("a:lnRef", look.lineRef, look.line), ref("a:fillRef", look.fillRef, look.fill),
                          ref("a:effectRef", 0, look.fill)]
        let font = XNode(name: "a:fontRef", attrs: ["idx": "minor"])
        font.children = [look.text.map(clone) ?? XNode(name: "a:schemeClr", attrs: ["val": "lt1"])]
        style.children.append(font)
        sp.children.append(style)
        guard n.algType == "tx", let body = textBody(n) else { return [sp] }
        var turn = rot.truncatingRemainder(dividingBy: 360)
        if turn < 0 { turn += 360 }
        // The text's own turn, by the text algorithm's `autoTxRot`
        // (autoTxRot's three pages, in PowerPoint's print): "upr", the
        // default, turns it whole quarters back to within 45° of level —
        // half-way rounding to the even quarter, so 135° reads at -45° and
        // 225° at 45° — "grav" only turns text the other way up that would
        // stand on its head (past 90°, short of 270°), and "none" leaves it
        // with its shape. (smartart-rotation's arrows at 120° and 240° read
        // at 30° and -30°; cycleMatrix's quadrants and a vertical block
        // list's side tabs, a quarter round, upright.)
        let textTurn: Double
        switch n.params["autoTxRot"] ?? "upr" {
        case "none": textTurn = turn
        case "grav": textTurn = turn > 90.01 && turn < 269.99 ? turn - 180 : turn
        default: textTurn = turn - 90 * (turn / 90).rounded(.toNearestOrEven)
        }
        var apart = (turn - textTurn).truncatingRemainder(dividingBy: 360)
        if apart < 0 { apart += 360 }
        // (A shape turned round, drawn mirrored both ways, keeps its text
        // upright in its text area mirrored too: cycleMatrix's third
        // quadrant set "C1" in the wedge's outer corner, PowerPoint near
        // the circle's centre.)
        let mirrored = flipH && flipV
        guard (abs(apart) > 0.01 && abs(apart - 360) > 0.01) || mirrored, geometry.name == "a:prstGeom" else {
            sp.children.append(body)
            return [sp]
        }
        // Otherwise a second shape holds the text: the text area as the
        // shape turned it, centred where its centre went — the other way
        // round when the text turned a quarter from the shape.
        var tr = Rect.fromLTRB(0, 0, 1, 1)
        if let prst = geometry["prst"], let g = PresetGeometry.geometry(prst, width: r.width * 12700, height: r.height * 12700,
                                                                         adjustments: PresetGeometry.adjustments(geometry)),
           let t = g.textRect { tr = t }
        if mirrored { tr = Rect.fromLTRB(1 - tr.right, 1 - tr.bottom, 1 - tr.left, 1 - tr.top) }
        let a = turn * .pi / 180, c = r.center
        let lt = Offset(r.left + tr.left * r.width, r.top + tr.top * r.height)
        let rb = Offset(r.left + tr.right * r.width, r.top + tr.bottom * r.height)
        let mid = Offset((lt.dx + rb.dx) / 2 - c.dx, (lt.dy + rb.dy) / 2 - c.dy)
        let centre = Offset(c.dx + mid.dx * cos(a) - mid.dy * sin(a), c.dy + mid.dx * sin(a) + mid.dy * cos(a))
        let across = abs(apart - 90) < 0.01 || abs(apart - 270) < 0.01
        let box = across ? Rect.fromCenter(center: centre, width: rb.dy - lt.dy, height: rb.dx - lt.dx)
            : Rect.fromCenter(center: centre, width: rb.dx - lt.dx, height: rb.dy - lt.dy)
        let tx = XNode(name: "p:sp", attrs: [:])
        let tnv = XNode(name: "p:nvSpPr", attrs: [:])
        tnv.children = [XNode(name: "p:cNvPr", attrs: ["id": String(id + 100000), "name": n.name + " text"]),
                        XNode(name: "p:cNvSpPr", attrs: [:]), XNode(name: "p:nvPr", attrs: [:])]
        let tPr = XNode(name: "p:spPr", attrs: [:])
        let txf = XNode(name: "a:xfrm", attrs: textTurn != 0 ? ["rot": String(Self.whole(textTurn * 60000))] : [:])
        txf.children = [XNode(name: "a:off", attrs: ["x": Self.emu(box.left), "y": Self.emu(box.top)]),
                        XNode(name: "a:ext", attrs: ["cx": Self.emu(box.width), "cy": Self.emu(box.height)])]
        let rectGeom = XNode(name: "a:prstGeom", attrs: ["prst": "rect"])
        rectGeom.children = [XNode(name: "a:avLst", attrs: [:])]
        let noLine = XNode(name: "a:ln", attrs: [:])
        noLine.children = [XNode(name: "a:noFill", attrs: [:])]
        tPr.children = [txf, rectGeom, XNode(name: "a:noFill", attrs: [:]), noLine]
        tx.children = [tnv, tPr, clone(style), body]
        return [sp, tx]
    }

    /// The shapes a connector joins: the text shapes presenting the
    /// transition's source and destination points.
    private func connectorEnds(_ n: DgmPresNode, root: DgmPresNode) -> (Rect, Rect)? {
        guard let s = n.point.cxnSrc, let d = n.point.cxnDst else { return nil }
        let all = [root] + root.descendants
        func box(_ id: String) -> Rect? {
            all.first { $0.shapeType != nil && !$0.isConnector && !$0.hideGeom && $0.presOf.contains { $0.id == id } }?.rect
                ?? all.first { $0.shapeType != nil && !$0.isConnector && $0.point.id == id }?.rect
        }
        guard let a = box(s), let b = box(d) else { return nil }
        return (a, b)
    }

    private static func path(_ points: [Offset], in r: Rect, closed: Bool = false) -> XNode {
        let geom = XNode(name: "a:custGeom", attrs: [:])
        let w = max(1, whole(r.width * 12700)), h = max(1, whole(r.height * 12700))
        let pathLst = XNode(name: "a:pathLst", attrs: [:])
        var attrs = ["w": String(w), "h": String(h)]
        if !closed { attrs["fill"] = "none" }
        let path = XNode(name: "a:path", attrs: attrs)
        for (i, p) in points.enumerated() {
            let pt = XNode(name: "a:pt", attrs: ["x": String(whole((p.dx - r.left) * 12700)), "y": String(whole((p.dy - r.top) * 12700))])
            let seg = XNode(name: i == 0 ? "a:moveTo" : "a:lnTo", attrs: [:])
            seg.children = [pt]
            path.children.append(seg)
        }
        if closed { path.children.append(XNode(name: "a:close", attrs: [:])) }
        pathLst.children = [path]
        geom.children = [XNode(name: "a:avLst", attrs: [:]), XNode(name: "a:gdLst", attrs: [:]), XNode(name: "a:ahLst", attrs: [:]),
                         XNode(name: "a:cxnLst", attrs: [:]), XNode(name: "a:rect", attrs: ["l": "0", "t": "0", "r": "r", "b": "b"]), pathLst]
        return geom
    }

    /// The node's text: the points it presents, the node's own paragraphs
    /// first and its descendants' as bulleted levels below, at the font
    /// size the constraints allow (shrunk to fit by the reader).
    private func textBody(_ n: DgmPresNode) -> XNode? {
        let points = n.presOf.filter { $0.text != nil }
        guard !points.isEmpty else { return nil }
        // Levels count from the shallowest point the shape shows, not from
        // the point it stands for: cycleMatrix's quadrants show their
        // node's children, each the quadrant's first level — 43 pt,
        // centred, no bullet in PowerPoint, where they were bulleted at the
        // second size, top left.
        let top = points.map(\.depth).min() ?? n.point.depth
        let bullets = n.variable("bulletEnabled") == "1"
        // Bullets from the second level unless the algorithm says otherwise
        // (`stBulletLvl="1"`: the bracket list's "•A", alone in its shape).
        let startLevel = Int(n.params["stBulletLvl"] ?? "2") ?? 2
        let prim = min(n.value("primFontSz") ?? 65, fontCap)
        // A lower level under a higher one, in one shape, is 78% of its size
        // when nothing says otherwise: PowerPoint's 51 under 65
        // (lo-smartart-bullet-list) and 33 under 42 (lo-smartart-missing-
        // bullet).
        let sec = min(n.value("secFontSz") ?? prim * 0.78, fontCap)
        var paragraphs: [XNode] = []
        var listed = false
        for p in points {
            let level = max(0, p.depth - top)
            let bulleted = bullets && level + 1 >= startLevel
            if level > 0 || bulleted { listed = true }
            for para in p.text?.all("a:p") ?? [] {
                let runs = para.children.filter { ["a:r", "a:fld", "a:br"].contains($0.name) }
                if runs.allSatisfy({ $0.name == "a:br" || ($0.first("a:t")?.text ?? "").isEmpty }) && points.count > 1 { continue }
                let out = XNode(name: "a:p", attrs: [:])
                let pPr = XNode(name: "a:pPr", attrs: [:])
                if level > 0 { pPr.attrs["lvl"] = String(min(8, level)) }
                if bulleted {
                    pPr.attrs["marL"] = String(171450 * (level + 2 - startLevel))
                    pPr.attrs["indent"] = "-171450"
                    pPr.children = [XNode(name: "a:buChar", attrs: ["char": "•"])]
                } else {
                    pPr.children = [XNode(name: "a:buNone", attrs: [:])]
                }
                // Lines at 90%, and 35% after a first-level paragraph, 15%
                // after a lower one: every paragraph of PowerPoint's own
                // diagram drawings in the corpus (369 of 371).
                func pct(_ name: String, _ v: Int) -> XNode {
                    let n = XNode(name: name, attrs: [:])
                    n.children = [XNode(name: "a:spcPct", attrs: ["val": String(v)])]
                    return n
                }
                pPr.children.insert(contentsOf: [pct("a:lnSpc", 90000), pct("a:spcBef", 0),
                                                 pct("a:spcAft", level > 0 ? 15000 : 35000)], at: 0)
                out.children = [pPr]
                for run in runs {
                    let r = clone(run)
                    if run.name != "a:br" {
                        let rPr = r.first("a:rPr") ?? { let x = XNode(name: "a:rPr", attrs: [:]); r.children.insert(x, at: 0); return x }()
                        if rPr["sz"] == nil { rPr.attrs["sz"] = String(max(100, Self.whole((level > 0 ? sec : prim) * 100))) }
                    }
                    out.children.append(r)
                }
                paragraphs.append(out)
            }
        }
        guard !paragraphs.isEmpty else { return nil }
        let anchor: String
        switch n.params["txAnchorVert"] ?? (listed ? (n.params["txAnchorVertCh"] ?? "t") : "mid") {
        case "t": anchor = "t"
        case "b": anchor = "b"
        default: anchor = "ctr"
        }
        let align = listed ? (n.params["shpTxLTRAlignCh"] ?? "l") : (n.params["parTxLTRAlign"] ?? "ctr")
        for p in paragraphs { p.first("a:pPr")?.attrs["algn"] = align }
        let body = XNode(name: "p:txBody", attrs: [:])
        // (The margins are fractions of the font size; `starling:insScale`
        // tells the reader they shrink with the text.)
        // A margin no constraint names is 0.56 of the font size: PowerPoint's
        // own drawing of pList2 has 256032 EMU (20.2 pt) round 36 pt text.
        let inset = 0.56 * prim
        // Text the author sized (every run with its own `sz`, the point's
        // `custT`): the margins are fractions of THAT size, not of the
        // layout's — snake-rows' 16 pt children sat 22 pt down, where
        // PowerPoint's are 5.
        let fileRuns = points.flatMap { $0.text?.all("a:p") ?? [] }.flatMap { $0.children }
            .filter { $0.name == "a:r" && !($0.first("a:t")?.text ?? "").isEmpty }
        let ownSizes = fileRuns.compactMap { $0.first("a:rPr")?["sz"].flatMap(Double.init) }
        let k = !fileRuns.isEmpty && ownSizes.count == fileRuns.count && prim > 0 ? min(1, (ownSizes.max() ?? 0) / 100 / prim) : 1
        func margin(_ name: String) -> String { Self.emu((n.value(name) ?? inset) * k) }
        let bodyPr = XNode(name: "a:bodyPr", attrs: ["anchor": anchor, "wrap": "square", "starling:insScale": "1",
                                                     "lIns": margin("lMarg"), "tIns": margin("tMarg"),
                                                     "rIns": margin("rMarg"), "bIns": margin("bMarg")])
        // (Text the author sized — every point it shows `custT`, every run
        // its own `sz` — keeps that size, out of the shared fit: autofit-
        // sync's third column, 16 and 14 pt in PowerPoint, was taken down
        // with the other two's fit to 2.)
        let authored = !fileRuns.isEmpty && ownSizes.count == fileRuns.count
        if authored, points.allSatisfy({ $0.prSet?["custT"] == "1" }) {
            bodyPr.children = []
        } else {
            if let g = n.sizeGroup { bodyPr.attrs["starling:sizeGroup"] = g }
            bodyPr.children = [XNode(name: "a:normAutofit", attrs: [:])]
        }
        body.children = [bodyPr, XNode(name: "a:lstStyle", attrs: [:])] + paragraphs
        return body
    }
}
