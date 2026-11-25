// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The multi-view self-test: STARLING_SELFTEST=multiview runs the iOS host through add / tap / resize / remove
// of extra views, on the simulator, and exits with the number of failures. It tests the real thing end to end -
// the Objective-C views and CAMetalLayers, the engine's per-view surfaces, the frame loop that builds and tears
// down a tree per view, the hit test by view id - which no Mac or Linux unit test can reach. Run it with
// test/ios-selftest.sh. Taps enter at the framework's pointer hook (UIKitScriptedInput), not through UIKit touches.
//
// Output: one "[selftest] PASS|FAIL <name>" line per step, then "[selftest] DONE pass=N fail=M".

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import FlutterUIKitBridge
import Darwin
import Foundation

enum UIKitSelfTest {
    // What the probe trees report; the steps read it.
    nonisolated(unsafe) static var mounted: [Int: Int] = [:]
    nonisolated(unsafe) static var nodes: [Int: FocusNode] = [:]
    nonisolated(unsafe) static var disposed: [Int: Int] = [:]
    nonisolated(unsafe) static var taps: [Int: Int] = [:]
    nonisolated(unsafe) static var sizes: [Int: Size] = [:]
    nonisolated(unsafe) static var viewOf: [Int: Int] = [:]   // View.maybeOf(context)'s id, from each tree's own build
    nonisolated(unsafe) static var composited: Set<Int> = []
    nonisolated(unsafe) static var addAnswers: [Int: Bool] = [:]
    nonisolated(unsafe) static var removeAnswers: [Int: Bool] = [:]
    nonisolated(unsafe) static var pass = 0
    nonisolated(unsafe) static var fail = 0

    typealias Done = (String?) -> Void   // nil passes; a message fails
    struct Step { let name: String; let run: (@escaping Done) -> Void }

    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["STARLING_SELFTEST"] == "multiview" else { return }
        multiViewFirstComposite = { id in composited.insert(id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { next(steps(), 0) }
    }

    private static func next(_ list: [Step], _ i: Int) {
        guard i < list.count else {
            fputs("[selftest] DONE pass=\(pass) fail=\(fail)\n", stderr)
            exit(fail == 0 ? 0 : 1)
        }
        let step = list[i]
        step.run { problem in
            if let problem { fail += 1; fputs("[selftest] FAIL \(step.name): \(problem)\n", stderr) }
            else { pass += 1; fputs("[selftest] PASS \(step.name)\n", stderr) }
            next(list, i + 1)
        }
    }

    // MARK: Helpers

    /// Polls `cond` every 50 ms until it holds or `timeout` seconds pass.
    private static func until(_ cond: @escaping () -> Bool, timeout: Double = 8, _ then: @escaping (Bool) -> Void) {
        let end = Date().addingTimeInterval(timeout)
        func poll() {
            if cond() { then(true) } else if Date() > end { then(false) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() } }
        }
        poll()
    }

    private static var scale: Double { fluikit_screen_scale() }
    private static func view(_ id: Int) -> FlutterView? { PlatformDispatcher.instance.view(id: id) }

    private static func add(_ id: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        runView(id: id) { Probe(viewId: id) }
        fluikit_view_add(Int64(id), x, y, w, h, { vid, ok, _ in DispatchQueue.main.async { UIKitSelfTest.addAnswers[Int(vid)] = ok } }, nil)
    }

    private static func remove(_ id: Int) {
        fluikit_view_remove(Int64(id), { vid, ok, _ in DispatchQueue.main.async { UIKitSelfTest.removeAnswers[Int(vid)] = ok } }, nil)
    }

    private static func heapMB() -> Double {
        var st = malloc_statistics_t()
        malloc_zone_statistics(nil, &st)
        return Double(st.size_in_use) / 1_048_576
    }

    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1.0 }

    // MARK: Steps

    private static func steps() -> [Step] { [
        Step(name: "the first view is up") { done in
            until({ view(0) != nil }) { ok in done(ok ? nil : "no view 0") }
        },
        Step(name: "two views added at once are both taken, built and composited") { done in
            add(1, 700, 100, 260, 180)
            add(2, 700, 320, 300, 200)
            until({ addAnswers[1] != nil && addAnswers[2] != nil && mounted[1] == 1 && mounted[2] == 1
                    && composited.contains(1) && composited.contains(2) }) { ok in
                guard ok else { return done("answers \(addAnswers) mounted \(mounted) composited \(composited)") }
                guard addAnswers[1] == true, addAnswers[2] == true else { return done("the engine refused an add: \(addAnswers)") }
                let live = Set(liveSecondaryViewIds)
                guard live == [1, 2] else { return done("live views \(live), wanted [1, 2]") }
                done(nil)
            }
        },
        Step(name: "each view has its own size and scale") { done in
            guard let v1 = view(1), let v2 = view(2) else { return done("a view is missing") }
            guard near(v1.physicalSize.width, 260 * scale), near(v1.physicalSize.height, 180 * scale) else {
                return done("view 1 is \(v1.physicalSize) at scale \(scale)") }
            guard near(v2.physicalSize.width, 300 * scale), near(v2.physicalSize.height, 200 * scale) else {
                return done("view 2 is \(v2.physicalSize)") }
            guard near(v1.devicePixelRatio, scale) else { return done("scale \(v1.devicePixelRatio) != \(scale)") }
            guard let s1 = sizes[1], let s2 = sizes[2], near(s1.width, 260), near(s1.height, 180), near(s2.width, 300), near(s2.height, 200) else {
                return done("the trees laid out at \(sizes), wanted 260x180 and 300x200") }
            done(nil)
        },
        Step(name: "View.maybeOf(context) finds the view a tree is in, not the first view") { done in
            guard viewOf[1] == 1, viewOf[2] == 2 else { return done("the trees found views \(viewOf), wanted [1: 1, 2: 2]") }
            done(nil)
        },
        Step(name: "a tap goes to the view it is in, and only that one") { done in
            UIKitScriptedInput.tap(view: 1, x: 130, y: 90)
            until({ taps[1] == 1 }) { ok in
                guard ok else { return done("view 1 got \(taps[1] ?? 0) taps") }
                guard (taps[2] ?? 0) == 0 else { return done("view 2 got a tap meant for view 1") }
                UIKitScriptedInput.tap(view: 2, x: 150, y: 100)
                until({ taps[2] == 1 }) { ok2 in
                    guard ok2 else { return done("view 2 got \(taps[2] ?? 0) taps") }
                    done(taps[1] == 1 ? nil : "view 1 got \(taps[1] ?? 0) taps after view 2's")
                }
            }
        },
        Step(name: "a tap outside the view's bounds hits nothing") { done in
            UIKitScriptedInput.tap(view: 1, x: 400, y: 90)   // view 1 is 260 wide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                done((taps[1] ?? 0) == 1 ? nil : "a tap off the view's edge arrived: view 1 has \(taps[1] ?? 0)")
            }
        },
        Step(name: "a focus request made later from a window that is not the key one stays in its own scope") { done in
            FocusManager.instance.viewTouched(0)
            guard let node = nodes[2] else { return done("no probe node in view 2") }
            // Not a touch, not a mount: a plain callback, as a timer or a completion handler would be.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                node.requestFocus()
                let m = FocusManager.instance
                guard m.keyScope == 0, !node.hasFocus, m.debugSummary.contains("2: probe 2"), !m.debugSummary.contains("0: probe 2") else {
                    return done("key scope \(m.keyScope), has focus \(node.hasFocus), \(m.debugSummary)")
                }
                m.viewTouched(2)
                guard m.keyScope == 2, node.hasFocus else { return done("touching view 2 did not give it the keys: \(m.debugSummary)") }
                m.viewTouched(0)
                done(node.hasFocus ? "view 2's node kept the keys after view 0 was touched" : nil)
            }
        },
        Step(name: "a resize reaches the engine's metrics and the tree's layout, for that view only") { done in
            fluikit_view_resize(1, 320, 240)
            until({ near(sizes[1]?.width ?? 0, 320) && near(sizes[1]?.height ?? 0, 240) }) { ok in
                guard ok else { return done("view 1's tree is \(String(describing: sizes[1])), wanted 320x240") }
                guard let v1 = view(1), near(v1.physicalSize.width, 320 * scale) else { return done("metrics \(String(describing: view(1)?.physicalSize))") }
                guard near(sizes[2]?.width ?? 0, 300) else { return done("view 2 changed too: \(String(describing: sizes[2]))") }
                done(nil)
            }
        },
        Step(name: "removing one view disposes its tree and leaves the other working") { done in
            remove(1)
            until({ removeAnswers[1] != nil && view(1) == nil && !liveSecondaryViewIds.contains(1)
                    && viewContentBuilders[1] == nil && disposed[1] == 1 }) { ok in
                guard ok else { return done("answers \(removeAnswers) view \(String(describing: view(1))) live \(liveSecondaryViewIds) disposed \(disposed)") }
                guard removeAnswers[1] == true else { return done("the engine refused the remove") }
                guard liveSecondaryViewIds == [2], (disposed[2] ?? 0) == 0 else { return done("view 2 went too: live \(liveSecondaryViewIds)") }
                UIKitScriptedInput.tap(view: 2, x: 150, y: 100)
                until({ taps[2] == 2 }) { ok2 in done(ok2 ? nil : "view 2 stopped taking taps after view 1 went") }
            }
        },
        Step(name: "removing the last extra view leaves only the first") { done in
            remove(2)
            until({ view(2) == nil && liveSecondaryViewIds.isEmpty && disposed[2] == 1 }) { ok in
                done(ok ? nil : "live \(liveSecondaryViewIds) disposed \(disposed)")
            }
        },
        Step(name: "twenty add / remove cycles leave no tree, view or growth behind") { done in
            let heap0 = heapMB()
            func cycle(_ n: Int) {
                guard n < 20 else {
                    let leaked = (10..<30).filter { (mounted[$0] ?? 0) != (disposed[$0] ?? 0) }
                    let growth = heapMB() - heap0
                    fputs("[selftest] heap grew \(String(format: "%.1f", growth)) MB over 20 cycles\n", stderr)
                    if !leaked.isEmpty { return done("views mounted but not disposed: \(leaked)") }
                    if !liveSecondaryViewIds.isEmpty { return done("live views left: \(liveSecondaryViewIds)") }
                    if growth > 60 { return done("the heap grew \(growth) MB") }
                    return done(nil)
                }
                let id = 10 + n
                add(id, 700, 100, 260, 180)
                until({ mounted[id] == 1 && composited.contains(id) }) { ok in
                    guard ok else { return done("view \(id) never came up: answers \(addAnswers)") }
                    remove(id)
                    until({ disposed[id] == 1 && view(id) == nil }) { ok2 in
                        guard ok2 else { return done("view \(id) was not torn down: disposed \(disposed)") }
                        cycle(n + 1)
                    }
                }
            }
            cycle(0)
        },
    ] }
}

/// The tree each extra view shows: counts its mounts, disposals and taps, records its layout size.
private final class Probe: StatefulWidget {
    let viewId: Int
    init(viewId: Int) { self.viewId = viewId; super.init(key: nil) }
    override func createState() -> State<StatefulWidget> { ProbeState() }
}

private final class ProbeState: State<StatefulWidget> {
    private var id: Int { (widget as! Probe).viewId }
    private var node: FocusNode!
    override func initState() {
        super.initState()
        UIKitSelfTest.mounted[id, default: 0] += 1
        node = FocusNode(debugLabel: "probe \(id)")
        bind(node)
        UIKitSelfTest.nodes[id] = node
    }
    override func dispose() {
        UIKitSelfTest.disposed[id, default: 0] += 1
        UIKitSelfTest.nodes[id] = nil
        node.dispose()
        super.dispose()
    }
    override func build(_ context: any BuildContext) -> Widget {
        let id = self.id
        UIKitSelfTest.viewOf[id] = View.maybeOf(context).map { Int($0.viewId) }
        return Directionality(textDirection: .ltr, child:
            GestureDetector(onTap: { UIKitSelfTest.taps[id, default: 0] += 1 }, behavior: .opaque, child:
                ProbeLeaf(viewId: id)))
    }
}

private final class ProbeLeaf: LeafRenderObjectWidget {
    let viewId: Int
    init(viewId: Int) { self.viewId = viewId; super.init(key: nil) }
    override func createRenderObject(_ context: any BuildContext) -> RenderObject { ProbeBox(viewId: viewId) }
}

private final class ProbeBox: RenderBox {
    let viewId: Int
    init(viewId: Int) { self.viewId = viewId; super.init() }
    override var sizedByParent: Bool { true }
    override func performResize() { size = boxConstraints.biggest }
    override func performLayout() { UIKitSelfTest.sizes[viewId] = size }
    override func hitTestSelf(_ position: Offset) -> Bool { true }
}
#endif
