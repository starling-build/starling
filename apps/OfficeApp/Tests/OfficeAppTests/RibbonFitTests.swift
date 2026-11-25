import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A ribbon tab wider than its window gives way from the right: a group's buttons lose their captions, then the group
/// becomes one button that opens its controls. Every control stays reachable: on screen, or inside such a button.
final class RibbonFitTests: XCTestCase {
    override func setUp() { KeyboardTraversal.shared.reset(); _ = TestText.icuLoaded }
    override func tearDown() { KeyboardTraversal.shared.reset() }

    // MARK: The fit

    func testNothingGivesWayWhenTheRowFits() {
        let w: [[Double]] = [[100, 80, 40], [200, 150, 40], [100, 80, 40]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 400), [0, 0, 0])
    }

    func testTheRightmostGroupGivesWayFirst() {
        let w: [[Double]] = [[100, 80, 40], [200, 150, 40], [100, 80, 40]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 390), [0, 0, 1])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 360), [0, 0, 2])
    }

    func testAGroupGoesAllTheWayBeforeTheNextOneStarts() {
        let w: [[Double]] = [[100, 80, 40], [200, 150, 40], [100, 80, 40]]
        // The right-hand group is a button (40) before the middle one loses a caption.
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 335), [0, 1, 2])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 250), [0, 2, 2])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 120), [2, 2, 2])
    }

    func testWhatIsNotAGroupIsLeftAlone() {
        let w: [[Double]] = [[100, 80, 40], [300, 300, 300], [100, 80, 40]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, false, true], available: 100), [2, 0, 2])
    }

    // MARK: Every control is reachable

    private static let widths: [Double] = [1280, 1024]
    /// Narrower still, standing for a wider UI font (the fit is measured, so it holds for any font). Below this a tab
    /// of a dozen groups is a row of buttons wider than the window, and scrolls.
    private static let stress: [Double] = [800]

    private func writer(_ width: Double, table: Bool = false) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(width, 800))
        if table { ui.state(OfficeShellState.self)!.session.controller.insertTable(rows: 2, columns: 2); ui.pump() }
        return ui
    }
    private func sheets(_ width: Double) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(width, 800))
    }
    private func slides(_ width: Double) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"), size: Size(width, 800))
    }

    /// Lets the ribbon measure itself and settle on a width.
    private func settle(_ ui: WidgetTester) { for _ in 0 ..< 6 { ui.pump() } }

    private func name(of e: Element) -> String? {
        if let tip = (e.widget as? FlatButton)?.tip, !tip.isEmpty { return tip }
        var found: String?
        func walk(_ e: Element) {
            if found != nil { return }
            // (An icon is a Text of one private-use glyph: not a name while the button has a caption.)
            if let t = e.widget as? Text, let d = t.data, !d.isEmpty, !(d.unicodeScalars.first!.value >= 0xE000 && d.unicodeScalars.first!.value <= 0xF8FF) { found = d; return }
            e.visitChildElements(walk)
        }
        walk(e)
        return found
    }

    /// The ribbon controls whose centre a pointer would reach (the hit test lands on them).
    private func reachable(_ ui: WidgetTester) -> Set<String> {
        var out = Set<String>()
        for e in ui.elements() where e.widget is FlatButton {
            guard let n = name(of: e), let box = e.findRenderObject() as? RenderBox, box.attached, box.hasSize else { continue }
            let p = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2))
            var hit = HitTestResult()
            _ = ui.renderView.hitTest(hit, position: p)
            if hit.path.contains(where: { ($0.target as? AnyHitTestTarget)?.base === box }) { out.insert(n) }
        }
        return out
    }

    /// Everything reachable on the current tab: what is on screen, and what each collapsed group's button opens.
    private func everythingReachable(_ ui: WidgetTester, width: Double) -> Set<String> {
        var out = reachable(ui)
        for tip in ui.tips().filter({ $0.hasSuffix(" group") }) {
            out.insert(tip)
            XCTAssertTrue(ui.tap(tip: tip), tip)
            ui.pump()
            let r = reachable(ui)
            out.formUnion(r)
            ui.tap(at: Offset(4, 790))      // the barrier closes it
            ui.pump()
        }
        return out
    }

    /// What the tab holds when nothing needs to give way: the names of its controls.
    private func census(_ make: (Double) -> WidgetTester, tab: String) -> Set<String> {
        let ui = make(3200)
        XCTAssertTrue(ui.tap(text: tab), tab)
        settle(ui)
        XCTAssertTrue(ui.tips().filter { $0.hasSuffix(" group") }.isEmpty, "wide: no group is collapsed")
        return reachable(ui)
    }

    private func check(_ label: String, tab: String, make: @escaping (Double) -> WidgetTester, widths: [Double]) {
        let all = census(make, tab: tab)
        XCTAssertGreaterThan(all.count, 5, "\(label): the tab has controls")
        for width in widths {
            let ui = make(width)
            XCTAssertTrue(ui.tap(text: tab), "\(label) \(tab)")
            settle(ui)
            let got = everythingReachable(ui, width: width)
            let missing = all.subtracting(got).sorted().map { $0.unicodeScalars.allSatisfy { $0.value > 0xE000 || $0.value < 0x20 } ? "glyph U+" + $0.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: ",") : $0 }
            // A group that opens, opens the controls the wide ribbon shows; its own name stands in for them.
            XCTAssertEqual(missing, [], "\(label) \(tab) at \(Int(width)): controls out of reach")
        }
    }

    func testWriterHomeIsReachable() { check("Writer", tab: "Home", make: { self.writer($0) }, widths: Self.widths + Self.stress) }
    func testWriterInsertIsReachable() { check("Writer", tab: "Insert", make: { self.writer($0) }, widths: Self.widths + Self.stress) }
    func testWriterTableLayoutIsReachable() { check("Writer", tab: "Table Layout", make: { self.writer($0, table: true) }, widths: Self.widths + Self.stress) }
    func testSheetsHomeIsReachable() { check("Sheets", tab: "Home", make: { self.sheets($0) }, widths: Self.widths + Self.stress) }
    func testSlidesHomeIsReachable() { check("Slides", tab: "Home", make: { self.slides($0) }, widths: Self.widths + Self.stress) }

    func testAGroupThatGaveWayIsAKeyStopAndAnAccessibleButton() {
        let ui = writer(640)
        XCTAssertTrue(ui.tap(text: "Home"))
        settle(ui)
        let groups = ui.tips().filter { $0.hasSuffix(" group") }
        XCTAssertFalse(groups.isEmpty, "a 640 pt window cannot hold the Home tab")
        let stops = KeyboardTraversal.shared.reachable(inRegion: "ribbon").compactMap { $0.label() }
        let names = ui.semantics().filter { $0.isButton }.map(\.label)
        for g in groups {
            XCTAssertTrue(stops.contains(g), "\(g) is reached by Tab")
            XCTAssertTrue(names.contains(g), "\(g) is a named button to a screen reader")
        }
    }

    func testTheNarrowRibbonStillScrollsWhenEvenTheButtonsDoNotFit() {
        let ui = writer(200)
        XCTAssertTrue(ui.tap(text: "Home"))
        settle(ui)
        XCTAssertFalse(ui.tips().filter { $0.hasSuffix(" group") }.isEmpty)
    }
}
