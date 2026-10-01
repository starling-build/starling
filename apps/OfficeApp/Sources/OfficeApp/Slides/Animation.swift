// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Entrance animations (docs/plans/slides.md, S7): PowerPoint's five
// everyday ones — Appear, Fade, Fly In, Wipe, Zoom — each started on a
// click, with the previous one, or after it. A slide's list is read from
// its `p:timing` when that holds nothing else, written back as read while
// unchanged, and otherwise written as PowerPoint's own timing tree. The
// show plays it a click at a time (`AnimationPlan`).

import Flutter
import FlutterSwiftBridge
import Foundation

struct ShapeAnimation: Equatable {
    enum Effect: String, CaseIterable {
        case appear, fade, flyIn, wipe, zoom

        var name: String {
            switch self {
            case .appear: return "Appear"
            case .fade: return "Fade"
            case .flyIn: return "Fly In"
            case .wipe: return "Wipe"
            case .zoom: return "Zoom"
            }
        }

        /// PowerPoint's preset number for the effect.
        var presetID: Int {
            switch self {
            case .appear: return 1
            case .flyIn: return 2
            case .fade: return 10
            case .wipe: return 22
            case .zoom: return 53
            }
        }

        var hasDirection: Bool { self == .flyIn || self == .wipe }
        var defaultDuration: Double { self == .appear ? 0 : 0.5 }
    }

    enum Start: String, CaseIterable {
        case onClick, withPrevious, afterPrevious

        var name: String {
            switch self {
            case .onClick: return "On Click"
            case .withPrevious: return "With Previous"
            case .afterPrevious: return "After Previous"
            }
        }

        var nodeType: String {
            switch self {
            case .onClick: return "clickEffect"
            case .withPrevious: return "withEffect"
            case .afterPrevious: return "afterEffect"
            }
        }
    }

    /// Where the shape comes in from (Fly In, Wipe).
    enum Direction: String, CaseIterable {
        case bottom, left, right, top

        var name: String { "From " + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        /// PowerPoint's presetSubtype for the direction.
        var subtype: Int {
            switch self {
            case .top: return 1
            case .right: return 2
            case .bottom: return 4
            case .left: return 8
            }
        }

        init?(subtype: Int) {
            switch subtype {
            case 1: self = .top
            case 2: self = .right
            case 4: self = .bottom
            case 8: self = .left
            default: return nil
            }
        }
    }

    /// The deck's id of the shape that comes in.
    var shapeId: Int
    /// One paragraph of its text (a build "by paragraph"), or nil for the
    /// whole shape.
    var paragraph: Int? = nil
    var effect: Effect
    var start: Start = .onClick
    var direction: Direction = .bottom
    /// Seconds.
    var duration: Double
    var delay: Double = 0

    init(shapeId: Int, paragraph: Int? = nil, effect: Effect, start: Start = .onClick,
         direction: Direction = .bottom, duration: Double? = nil, delay: Double = 0) {
        self.shapeId = shapeId
        self.paragraph = paragraph
        self.effect = effect
        self.start = start
        self.direction = direction
        self.duration = duration ?? effect.defaultDuration
        self.delay = delay
    }
}

// MARK: - Playing

/// A slide's animations as the show plays them: groups, one per click
/// (the first may start by itself), each animation at an offset in its
/// group.
struct AnimationPlan: Equatable {
    struct Step: Equatable {
        var animation: ShapeAnimation
        /// Seconds from the group's start.
        var begin: Double
        var end: Double { begin + animation.delay + animation.duration }
    }

    var groups: [[Step]] = []
    /// The first group starts with the slide, without a click.
    var autoStart = false

    init(_ animations: [ShapeAnimation]) {
        var groupStart: [Step] = []
        var subgroupBegin = 0.0
        var previousEnd = 0.0
        for (i, a) in animations.enumerated() {
            switch a.start {
            case .onClick:
                if !groupStart.isEmpty { groups.append(groupStart) }
                groupStart = []
                subgroupBegin = 0
                previousEnd = 0
            case .withPrevious:
                if i == 0 { autoStart = true }
            case .afterPrevious:
                if i == 0 { autoStart = true }
                subgroupBegin = previousEnd
            }
            let step = Step(animation: a, begin: subgroupBegin)
            groupStart.append(step)
            previousEnd = max(previousEnd, step.end)
        }
        if !groupStart.isEmpty { groups.append(groupStart) }
    }

    func length(_ group: Int) -> Double { groups[group].map(\.end).max() ?? 0 }

    /// How every animated shape (or paragraph) is drawn with `played`
    /// groups done and group `played` `elapsed` seconds in (nil: not
    /// started): hidden ones at progress 0.
    func reveals(played: Int, elapsed: Double?) -> ShapeReveals {
        var out = ShapeReveals()
        for (g, group) in groups.enumerated() where g >= played {
            for step in group {
                var progress = 0.0
                if g == played, let t = elapsed {
                    let start = step.begin + step.animation.delay
                    progress = step.animation.duration <= 0
                        ? (t >= start ? 1 : 0)
                        : min(1, max(0, (t - start) / step.animation.duration))
                }
                let r = ShapeReveal(effect: step.animation.effect, direction: step.animation.direction, progress: progress)
                out.set(r, shape: step.animation.shapeId, paragraph: step.animation.paragraph)
            }
        }
        return out
    }

    /// The click number each animation shows in the editor ("1", "2"…;
    /// 0 for one that starts with the slide).
    static func clickNumbers(_ animations: [ShapeAnimation]) -> [Int] {
        var n = 0
        var out: [Int] = []
        for a in animations {
            if a.start == .onClick { n += 1 }
            out.append(n)
        }
        return out
    }
}

/// How far into its entrance a shape is drawn: hidden at 0, whole at 1.
struct ShapeReveal {
    var effect: ShapeAnimation.Effect
    var direction: ShapeAnimation.Direction
    var progress: Double
}

/// The reveals for a slide: whole shapes, and paragraphs of text shapes.
/// Anything absent is drawn as it is.
struct ShapeReveals {
    var whole: [Int: ShapeReveal] = [:]
    var paragraphs: [Int: [Int: ShapeReveal]] = [:]

    var isEmpty: Bool { whole.isEmpty && paragraphs.isEmpty }

    mutating func set(_ r: ShapeReveal, shape: Int, paragraph: Int?) {
        // The earliest entrance wins: a later one never shows a shape sooner.
        if let p = paragraph {
            if paragraphs[shape]?[p] == nil { paragraphs[shape, default: [:]][p] = r }
        } else if whole[shape] == nil {
            whole[shape] = r
        }
    }
}

// MARK: - File

enum AnimationXML {
    /// The entrance effects in a `p:timing`, by the file's shape ids — or
    /// nil when it holds anything this app does not model (exits, emphasis,
    /// motion paths, triggers, text by paragraph, other entrances), in which
    /// case the slide keeps it as read.
    static func read(_ timing: XNode) -> [(spid: Int, animation: ShapeAnimation)]? {
        guard let root = timing.first("p:tnLst")?.first("p:par")?.first("p:cTn"),
              root["nodeType"] == "tmRoot" else { return nil }
        // PowerPoint writes an empty root on a slide with no animations.
        if (root.first("p:childTnLst")?.children ?? []).isEmpty { return [] }
        let seqs = root.first("p:childTnLst")?.all("p:seq") ?? []
        guard seqs.count == 1, let main = seqs[0].first("p:cTn"), main["nodeType"] == "mainSeq",
              (root.first("p:childTnLst")?.children.count ?? 0) == 1 else { return nil }
        var out: [(Int, ShapeAnimation)] = []
        for click in main.first("p:childTnLst")?.all("p:par") ?? [] {
            for sub in click.first("p:cTn")?.first("p:childTnLst")?.all("p:par") ?? [] {
                for effect in sub.first("p:cTn")?.first("p:childTnLst")?.all("p:par") ?? [] {
                    guard let ctn = effect.first("p:cTn"), ctn["presetClass"] == "entr",
                          let preset = ctn["presetID"].flatMap(Int.init),
                          let kind = ShapeAnimation.Effect.allCases.first(where: { $0.presetID == preset }),
                          let node = ctn["nodeType"],
                          let start = ShapeAnimation.Start.allCases.first(where: { $0.nodeType == node }) else { return nil }
                    // Every behaviour aims at one shape, or one paragraph of it.
                    let targets = _all(ctn, "p:spTgt")
                    guard let spid = targets.first?["spid"].flatMap(Int.init) else { return nil }
                    func paragraph(_ t: XNode) -> Int?? {
                        guard let el = t.first("p:txEl") else { return t.children.isEmpty ? .some(nil) : nil }
                        guard el.children.count == 1, let rg = el.first("p:pRg"), let st = rg["st"].flatMap(Int.init),
                              rg["end"].flatMap(Int.init) == st else { return nil }
                        return .some(st)
                    }
                    guard let first = paragraph(targets[0]),
                          targets.allSatisfy({ $0["spid"].flatMap(Int.init) == spid && paragraph($0) == first }) else { return nil }
                    let durations = _all(ctn, "p:cTn").compactMap { $0["dur"].flatMap(Double.init) }
                    let duration = kind == .appear ? 0 : (durations.max() ?? 500) / 1000
                    let delay = (ctn.first("p:stCondLst")?.first("p:cond")?["delay"].flatMap(Double.init) ?? 0) / 1000
                    let direction = ctn["presetSubtype"].flatMap(Int.init).flatMap(ShapeAnimation.Direction.init(subtype:)) ?? .bottom
                    out.append((spid, ShapeAnimation(shapeId: 0, paragraph: first, effect: kind, start: start,
                                                    direction: kind.hasDirection ? direction : .bottom,
                                                    duration: duration, delay: delay)))
                }
            }
        }
        return out
    }

    private static func _all(_ node: XNode, _ name: String) -> [XNode] {
        node.children.flatMap { ($0.name == name ? [$0] : []) + _all($0, name) }
    }

    /// PowerPoint's timing tree for `animations`, naming shapes by
    /// `spid(shapeId)`; `textShapes` are the ids that get a build entry.
    static func write(_ animations: [ShapeAnimation], spid: (Int) -> Int?, textShapes: Set<Int>) -> String {
        var next = 3
        func id() -> Int { defer { next += 1 }; return next }
        let plan = AnimationPlan(animations)
        var clicks = ""
        var built: [(spid: Int, byParagraph: Bool)] = []
        for (g, group) in plan.groups.enumerated() {
            // Steps that begin together share a sub-group.
            var subgroups: [(begin: Double, steps: [AnimationPlan.Step])] = []
            for step in group {
                if let last = subgroups.last, abs(last.begin - step.begin) < 1e-9 {
                    subgroups[subgroups.count - 1].steps.append(step)
                } else {
                    subgroups.append((step.begin, [step]))
                }
            }
            let clickId = id()
            var inner = ""
            for sub in subgroups {
                let subId = id()
                var effects = ""
                for step in sub.steps {
                    guard let target = spid(step.animation.shapeId) else { continue }
                    let text = textShapes.contains(step.animation.shapeId)
                    let byParagraph = step.animation.paragraph != nil
                    if text, let i = built.firstIndex(where: { $0.spid == target }) {
                        built[i].byParagraph = built[i].byParagraph || byParagraph
                    } else if text {
                        built.append((target, byParagraph))
                    }
                    effects += _effect(step.animation, target: target, grp: text, id: id)
                }
                inner += "<p:par><p:cTn id=\"\(subId)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(_ms(sub.begin))\"/></p:stCondLst>"
                    + "<p:childTnLst>\(effects)</p:childTnLst></p:cTn></p:par>"
            }
            let auto = g == 0 && plan.autoStart ? "<p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>" : ""
            clicks += "<p:par><p:cTn id=\"\(clickId)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"indefinite\"/>\(auto)</p:stCondLst>"
                + "<p:childTnLst>\(inner)</p:childTnLst></p:cTn></p:par>"
        }
        let builds = built.map { "<p:bldP spid=\"\($0.spid)\" grpId=\"0\"\($0.byParagraph ? " build=\"p\"" : " animBg=\"1\"")/>" }.joined()
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
            + "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(clicks)</p:childTnLst></p:cTn>"
            + "<p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
            + "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>"
            + "</p:childTnLst></p:cTn></p:par></p:tnLst>"
            + (builds.isEmpty ? "" : "<p:bldLst>\(builds)</p:bldLst>") + "</p:timing>"
    }

    private static func _ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }

    private static func _effect(_ a: ShapeAnimation, target: Int, grp: Bool, id: () -> Int) -> String {
        let tgt = a.paragraph.map { "<p:tgtEl><p:spTgt spid=\"\(target)\"><p:txEl><p:pRg st=\"\($0)\" end=\"\($0)\"/></p:txEl></p:spTgt></p:tgtEl>" }
            ?? "<p:tgtEl><p:spTgt spid=\"\(target)\"/></p:tgtEl>"
        let dur = max(1, _ms(a.duration))
        func visible() -> String {
            "<p:set><p:cBhvr><p:cTn id=\"\(id())\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst></p:cTn>\(tgt)"
                + "<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"visible\"/></p:to></p:set>"
        }
        func anim(_ attr: String, _ from: String, _ to: String) -> String {
            "<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr additive=\"base\"><p:cTn id=\"\(id())\" dur=\"\(dur)\" fill=\"hold\"/>\(tgt)"
                + "<p:attrNameLst><p:attrName>\(attr)</p:attrName></p:attrNameLst></p:cBhvr><p:tavLst>"
                + "<p:tav tm=\"0\"><p:val><p:strVal val=\"\(from)\"/></p:val></p:tav><p:tav tm=\"100000\"><p:val><p:strVal val=\"\(to)\"/></p:val></p:tav></p:tavLst></p:anim>"
        }
        func filter(_ f: String) -> String {
            "<p:animEffect transition=\"in\" filter=\"\(f)\"><p:cBhvr><p:cTn id=\"\(id())\" dur=\"\(dur)\"/>\(tgt)</p:cBhvr></p:animEffect>"
        }
        let effectId = id()
        var subtype = 0
        var body = ""
        switch a.effect {
        case .appear:
            body = visible()
        case .fade:
            body = visible() + filter("fade")
        case .flyIn:
            subtype = a.direction.subtype
            let (x, y): (String, String) = {
                switch a.direction {
                case .bottom: return ("#ppt_x", "1+#ppt_h/2")
                case .top: return ("#ppt_x", "0-#ppt_h/2")
                case .left: return ("0-#ppt_w/2", "#ppt_y")
                case .right: return ("1+#ppt_w/2", "#ppt_y")
                }
            }()
            body = visible() + anim("ppt_x", x, "#ppt_x") + anim("ppt_y", y, "#ppt_y")
        case .wipe:
            subtype = a.direction.subtype
            let towards: String = {
                switch a.direction {
                case .bottom: return "up"
                case .top: return "down"
                case .left: return "right"
                case .right: return "left"
                }
            }()
            body = visible() + filter("wipe(\(towards))")
        case .zoom:
            subtype = 16
            body = visible() + anim("ppt_w", "0", "#ppt_w") + anim("ppt_h", "0", "#ppt_h") + filter("fade")
        }
        let grpId = grp ? " grpId=\"0\"" : ""
        return "<p:par><p:cTn id=\"\(effectId)\" presetID=\"\(a.effect.presetID)\" presetClass=\"entr\" presetSubtype=\"\(subtype)\" fill=\"hold\"\(grpId) nodeType=\"\(a.start.nodeType)\">"
            + "<p:stCondLst><p:cond delay=\"\(_ms(a.delay))\"/></p:stCondLst><p:childTnLst>\(body)</p:childTnLst></p:cTn></p:par>"
    }
}
