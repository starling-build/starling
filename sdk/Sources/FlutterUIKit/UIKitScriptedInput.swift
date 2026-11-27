// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A test driver: STARLING_SPIKE_INPUT=<script file> injects pointer and key events into named views, from
// inside the app, so a second window can be exercised with nothing moving the Mac's mouse
// (docs/plans/ipad-multi-window.md, step 4). Events enter where the engine's own do - the framework's
// PlatformDispatcher.onPointerDataPacket and onKeyData - so view routing, hit testing, gestures, focus and
// key dispatch are all exercised; the engine's packet converter and the UIKit responders are not.
//
// One command a line; '#' starts a comment; coordinates are logical pixels in the named view. The host pins view 0 to
// the safe area (fluikit_host.m), so on an iPad it starts 24 pt below the screen's top (the status bar): a point on a
// simulator screenshot (2 px per pt) is the view's y plus 24, and a UIKit touch arrives in the same view coordinates.
//   <ms> tap  <view> <x> <y>
//   <ms> drag <view> <x0> <y0> <x1> <y1> [steps]
//   <ms> dtap <view> <x> <y>          (two taps back to back: a double tap)
//   <ms> hold <view> <x> <y> [ms]     (one finger held still, default 700 ms: a long press)
//   <ms> twotap <view> <x1> <y1> <x2> <y2>   (two fingers down and up together, in place)
//   <ms> twist <view> <x> <y> <radius> <degrees>   (two fingers either side of x y, turned together)
//   <ms> type <view> <text...>        (text up to end of line; \n is Return)
//   <ms> key  <view> <keysym>         (decimal or 0x..; 0xFF08 Backspace, 0xFF0D Enter)
//   <ms> log  <message...>            (a marker in the output)
// <ms> counts from when the script is loaded. Each command logs "[input] ..." with the focus it found.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import Foundation

enum UIKitScriptedInput {
    nonisolated(unsafe) private static var _nextPointer: Int64 = 1000

    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["STARLING_SPIKE_INPUT"], !path.isEmpty else { return }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            fputs("[input] cannot read \(path)\n", stderr)
            return
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2, let ms = Int(parts[0]) else { fputs("[input] bad line: \(line)\n", stderr); continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { run(parts, line) }
        }
        fputs("[input] script loaded: \(path)\n", stderr)
    }

    private static func run(_ p: [String], _ line: String) {
        let cmd = p[1]
        let rest = p.dropFirst(2).joined(separator: " ")
        let nums = rest.split(separator: " ").compactMap { Double($0) }
        switch cmd {
        case "log":
            fputs("[input] \(rest)\n", stderr)
        case "caret":
            if let o = TextInputChannel.lastEditableOrigin {
                fputs("[input] editable origin sent to the plugin: \(o.x),\(o.y); client=\(TextInputChannel.activeClient)\n", stderr)
            } else { fputs("[input] no editable transform sent yet\n", stderr) }
        case "insets" where !nums.isEmpty:
            // The bottom inset (physical pixels) and size the framework has for a view: what the keyboard covers.
            let v = Int(nums[0])
            if let fv = PlatformDispatcher.instance.view(id: v) {
                fputs("[input] view \(v) viewInsets.bottom=\(fv.viewInsets.bottom) physicalSize=\(fv.physicalSize.width)x\(fv.physicalSize.height)\n", stderr)
            } else { fputs("[input] view \(v) does not exist\n", stderr) }
        case "tap" where nums.count >= 3:
            let v = Int(nums[0])
            report("tap view \(v) at \(nums[1]),\(nums[2])")
            let id = pointerId()
            post(v, [(.add, nums[1], nums[2], id), (.down, nums[1], nums[2], id)])
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) {
                post(v, [(.up, nums[1], nums[2], id), (.remove, nums[1], nums[2], id)])
                report("after tap")
            }
        case "dtap" where nums.count >= 3:
            // Two taps back to back, posted in one go: a slow frame between two `tap` commands can run the second
            // one's press before the first one's release, which the app reads as a two-finger tap.
            let v = Int(nums[0])
            report("dtap view \(v) at \(nums[1]),\(nums[2])")
            for _ in 0 ..< 2 {
                let id = pointerId()
                post(v, [(.add, nums[1], nums[2], id), (.down, nums[1], nums[2], id)])
                post(v, [(.up, nums[1], nums[2], id), (.remove, nums[1], nums[2], id)])
            }
        case "hold" where nums.count >= 3:
            // A finger held still: down, then up after `nums[3]` ms (default 700), for long-press paths.
            let v = Int(nums[0]), ms = nums.count > 3 ? Int(nums[3]) : 700
            report("hold view \(v) at \(nums[1]),\(nums[2]) for \(ms) ms")
            let id = pointerId()
            post(v, [(.add, nums[1], nums[2], id), (.down, nums[1], nums[2], id)])
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
                post(v, [(.up, nums[1], nums[2], id), (.remove, nums[1], nums[2], id)])
                report("after hold")
            }
        case "twotap" where nums.count >= 5:
            // Two fingers down and up together in place: view x1 y1 x2 y2.
            let v = Int(nums[0])
            report("twotap view \(v) at \(nums[1]),\(nums[2]) and \(nums[3]),\(nums[4])")
            let a = pointerId(), b = pointerId()
            post(v, [(.add, nums[1], nums[2], a), (.down, nums[1], nums[2], a)])
            post(v, [(.add, nums[3], nums[4], b), (.down, nums[3], nums[4], b)])
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
                post(v, [(.up, nums[1], nums[2], a), (.remove, nums[1], nums[2], a)])
                post(v, [(.up, nums[3], nums[4], b), (.remove, nums[3], nums[4], b)])
                report("after twotap")
            }
        case "twist" where nums.count >= 5:
            // Two fingers down on either side of x y, `r` points from it, then turned together by `degrees`: view x y r degrees.
            let v = Int(nums[0]), cx = nums[1], cy = nums[2], r = nums[3], deg = nums[4]
            let steps = 12
            report("twist view \(v) at \(cx),\(cy) radius \(r) by \(deg) degrees")
            let a = pointerId(), b = pointerId()
            func at(_ f: Double) -> ((Double, Double), (Double, Double)) {
                let t = deg * f * .pi / 180
                return ((cx - r * cos(t), cy - r * sin(t)), (cx + r * cos(t), cy + r * sin(t)))
            }
            let s = at(0)
            post(v, [(.add, s.0.0, s.0.1, a), (.down, s.0.0, s.0.1, a)])
            post(v, [(.add, s.1.0, s.1.1, b), (.down, s.1.0, s.1.1, b)])
            for i in 1...steps {
                let p = at(Double(i) / Double(steps))
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30 * i)) {
                    post(v, [(.move, p.0.0, p.0.1, a)])
                    post(v, [(.move, p.1.0, p.1.1, b)])
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30 * steps + 30)) {
                let e = at(1)
                post(v, [(.up, e.0.0, e.0.1, a), (.remove, e.0.0, e.0.1, a)])
                post(v, [(.up, e.1.0, e.1.1, b), (.remove, e.1.0, e.1.1, b)])
                report("after twist")
            }
        case "drag" where nums.count >= 5:
            let v = Int(nums[0]), steps = nums.count > 5 ? max(1, Int(nums[5])) : 12
            report("drag view \(v) \(nums[1]),\(nums[2]) -> \(nums[3]),\(nums[4])")
            let id = pointerId()
            post(v, [(.add, nums[1], nums[2], id), (.down, nums[1], nums[2], id)])
            for s in 1...steps {
                let f = Double(s) / Double(steps)
                let x = nums[1] + (nums[3] - nums[1]) * f, y = nums[2] + (nums[4] - nums[2]) * f
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16 * s)) {
                    post(v, [(.move, x, y, id)])
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16 * steps + 16)) {
                post(v, [(.up, nums[3], nums[4], id), (.remove, nums[3], nums[4], id)])
                report("after drag")
            }
        case "type" where p.count >= 4:
            let v = p[2]
            let s = p[3].replacingOccurrences(of: "\\n", with: "\n")
            report("type view \(v) \"\(p[3])\" (text client \(TextInputChannel.activeClient))")
            // An editor attached to the text-input plugin takes its text from the plugin, not from key events
            // (RichEditable declines characters then), so play the plugin: the editing state with the text inserted.
            if TextInputChannel.activeClient >= 0, var st = TextInputChannel.lastEditingState {
                let text = (st["text"] as? String) ?? ""
                let u16 = Array(text.utf16)
                let a = min(u16.count, max(0, st["selectionBase"] as? Int ?? u16.count))
                let b = min(u16.count, max(0, st["selectionExtent"] as? Int ?? u16.count))
                let lo = min(a, b), hi = max(a, b)
                let ins = Array(s.utf16)
                let out = String(decoding: Array(u16[..<lo]) + ins + Array(u16[hi...]), as: UTF16.self)
                st["text"] = out; st["selectionBase"] = lo + ins.count; st["selectionExtent"] = lo + ins.count
                let body: [String: Any] = ["method": "TextInputClient.updateEditingState", "args": [TextInputChannel.activeClient, st]]
                if let data = try? JSONSerialization.data(withJSONObject: body) {
                    MainActor.assumeIsolated { channelBuffers.push(TextInputChannel.name, data) { _ in } }
                }
            } else {
                for ch in s {
                    if ch == "\n" { key(0xFF0D, nil) } else { key(Int64(ch.unicodeScalars.first!.value), String(ch)) }
                }
            }
            report("after type")
        case "key" where p.count >= 4:
            let code = p[3].hasPrefix("0x") ? Int64(p[3].dropFirst(2), radix: 16) : Int64(p[3])
            if let code { report("key view \(p[2]) \(p[3])"); key(code, nil) }
        default:
            fputs("[input] unknown command: \(line)\n", stderr)
        }
    }

    /// A finger down and up at (x, y) in view `viewId`'s own coordinates (logical pixels).
    static func tap(view viewId: Int, x: Double, y: Double) {
        let id = pointerId()
        post(viewId, [(.add, x, y, id), (.down, x, y, id)])
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) {
            post(viewId, [(.up, x, y, id), (.remove, x, y, id)])
        }
    }

    private static func report(_ what: String) {
        let node = FocusManager.instance.focusedNode
        fputs("[input] \(what); focus=\(node?.debugLabel ?? (node == nil ? "none" : "unlabelled")) \(FocusManager.instance.debugSummary)\n", stderr)
    }

    private static func pointerId() -> Int64 { _nextPointer += 1; return _nextPointer }

    private static func post(_ viewId: Int, _ events: [(PointerChange, Double, Double, Int64)]) {
        let dpr = PlatformDispatcher.instance.view(id: viewId)?.devicePixelRatio ?? 2.0
        let data = events.map { e in
            PointerData(viewId: Int64(viewId), timeStamp: .seconds(ProcessInfo.processInfo.systemUptime),
                        change: e.0, kind: .touch, device: e.3, pointerIdentifier: e.3,
                        physicalX: e.1 * dpr, physicalY: e.2 * dpr, buttons: e.0 == .down || e.0 == .move ? 1 : 0)
        }
        PlatformDispatcher.instance.onPointerDataPacket?(PointerDataPacket(data: data))
    }

    private static func key(_ logical: Int64, _ character: String?) {
        guard let sink = PlatformDispatcher.instance.onKeyData else { return }
        for type in [KeyEventType.down, .up] {
            _ = sink(KeyData(timeStamp: Date().timeIntervalSince1970, type: type, physical: 0, logical: logical,
                             character: type == .up ? nil : character, synthesized: false))
        }
    }
}
#endif
