import XCTest
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
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
        // The right-hand group goes first, and the middle one when that was not enough; what was folded more than the room
        // needed comes back (at 335 the right-hand group is icons only, not a button; at 250 it is whole again).
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 335), [0, 1, 1])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 250), [0, 2, 0])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 120), [2, 2, 2])
    }

    func testAGroupWhoseButtonIsWiderThanItsIconsStopsAtTheIcons() {
        // Editing: icons only 54, one button 73. Folding it to the button would grow the row.
        let w: [[Double]] = [[300, 200, 90], [101, 54, 73]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true], available: 300), [1, 1])
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true], available: 260), [1, 1])
    }

    func testAFoldTheRoomDidNotNeedIsUndone() {
        // The right-hand group went first, but the middle one's fold alone makes room: only that one stays folded.
        let w: [[Double]] = [[100, 80, 40], [300, 200, 40], [60, 55, 50]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, true, true], available: 200), [0, 2, 0])
    }

    func testWhatIsNotAGroupIsLeftAlone() {
        let w: [[Double]] = [[100, 80, 40], [300, 300, 300], [100, 80, 40]]
        XCTAssertEqual(RibbonFit.levels(widths: w, collapsible: [true, false, true], available: 100), [2, 0, 2])
    }

    /// The widths Linux's fonts measured (amd-8's run, a 1240 pt ribbon): three tabs wider than the window. The fit gives
    /// way only as far as it must: the rightmost groups, no more than needed, and the left ones stay whole.
    func testWhatLinuxMeasuredFoldsOnlyAsFarAsItMust() {
        let tabs: [(name: String, widths: [[Double]], levels: [Int])] = [
            ("Slides Home", [[138, 97, 87], [223, 155, 68], [379, 379, 61], [305, 255, 89], [241, 101, 80], [128, 54, 73]], [0, 0, 0, 0, 1, 1]),
            ("Writer Home", [[184, 97, 87], [407, 407, 61], [317, 255, 89], [339, 339, 67], [101, 54, 73]], [0, 0, 0, 2, 0]),
            ("Writer Table Layout", [[117, 61, 68], [234, 103, 122], [337, 233, 80], [269, 242, 90], [159, 154, 131], [149, 115, 92]], [0, 0, 0, 0, 0, 1]),
        ]
        for tab in tabs {
            let collapsible = [Bool](repeating: true, count: tab.widths.count)
            let got = RibbonFit.levels(widths: tab.widths, collapsible: collapsible, available: 1240)
            XCTAssertEqual(got, tab.levels, tab.name)
            func total(_ l: [Int]) -> Double { l.indices.reduce(0) { $0 + tab.widths[$1][l[$1]] } }
            XCTAssertLessThanOrEqual(total(got), 1240, "\(tab.name): the row fits")
            // Minimal: undoing the last step (the rightmost group that gave way, one level back) would overflow.
            if let last = got.indices.last(where: { got[$0] > 0 }) {
                var back = got; back[last] -= 1
                XCTAssertGreaterThan(total(back), 1240, "\(tab.name): nothing folded that did not have to")
            }
            // And the tab's full width is what makes it fold at all.
            XCTAssertGreaterThan(tab.widths.reduce(0) { $0 + $1[0] }, 1240, tab.name)
        }
        // Were the window wide enough for the whole of a tab, nothing would give way.
        XCTAssertEqual(RibbonFit.levels(widths: tabs[0].widths, collapsible: [Bool](repeating: true, count: 6), available: 1416), [0, 0, 0, 0, 0, 0])
    }

    /// A titled menu that gives up its caption (Arrange, Shape Effects) is still named for it: its tooltip says what it does
    /// ("Order and align"), and the caption is its name for assistive technology, the keyboard ring and `ribbonReaches`.
    func testAnIconOnlyMenuKeepsItsCaptionAsItsName() throws {
        let fluent = OfficeAppearance.theme(.light)
        let menu = Chrome.menuButton(FluentSystemIcons.grid, "Arrange", "Order and align", fluent, items: [])
        let ui = WidgetTester(FluentApp(theme: fluent, home: Row(children: [RibbonDensity(iconsOnly: true, child: menu)]), title: "Test"), size: Size(400, 200))
        ui.pump()
        let button = try XCTUnwrap(ui.elements().compactMap { $0.widget as? FlatButton }.first)
        XCTAssertEqual(button.name, "Arrange")
        XCTAssertEqual(button.tip, "Order and align", "the tooltip still says what it does")
        XCTAssertFalse(ui.has(text: "Arrange"), "and it shows no caption")
        XCTAssertTrue(ui.ribbonReaches("Arrange", width: 400), "found by its caption")
        XCTAssertFalse(ui.ribbonReaches("Rearrange", width: 400))
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

    // MARK: The popup

    private func foldedHome(_ width: Double = 800) -> WidgetTester {
        let ui = writer(width)
        XCTAssertTrue(ui.tap(text: "Home"))
        settle(ui)
        return ui
    }

    func testACommandInAFoldedGroupClosesItsPopup() throws {
        let ui = foldedHome()
        let c = try XCTUnwrap(ui.state(OfficeShellState.self)).session.controller
        XCTAssertTrue(ui.tap(tip: "Paragraph group"))
        ui.pump()
        XCTAssertTrue(ui.has(tip: "Center"), "the popup holds the Paragraph controls")
        XCTAssertTrue(ui.tap(tip: "Center"))
        ui.pump(); ui.pump()
        XCTAssertFalse(ui.has(tip: "Center"), "a command that has run closes the popup")
        XCTAssertEqual(c.document.paragraphs.first?.style.alignment, .center, "and it ran")
    }

    func testAControlThatKeepsEditingLeavesItsPopupOpen() {
        let ui = foldedHome(640)
        XCTAssertTrue(ui.tap(tip: "Font group"))
        ui.pump()
        let grow = "Grow Font (⌘])".keys, shrink = "Shrink Font (⌘[)".keys
        XCTAssertTrue(ui.tap(tip: grow))
        ui.pump()
        XCTAssertTrue(ui.has(tip: shrink), "Grow Font steps and the popup stays for the next press")
        XCTAssertTrue(ui.tap(tip: grow), "and takes the next press")
        ui.pump()
        XCTAssertTrue(ui.has(tip: shrink))
        XCTAssertTrue(ui.tap(tip: "Bold (⌘B)".keys))
        ui.pump(); ui.pump()
        XCTAssertFalse(ui.has(tip: shrink), "Bold is a command: the popup closes")
    }

    func testAMenuChoiceInAFoldedGroupClosesItsPopup() {
        let ui = foldedHome()
        XCTAssertTrue(ui.tap(tip: "Paragraph group"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Borders"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Bottom Border"))
        ui.pump(); ui.pump()
        XCTAssertFalse(ui.has(tip: "Center"), "choosing from a menu in the popup closes the popup too")
    }

    func testEscapeClosesAPopupAndTheRingReturnsToItsButton() throws {
        let ui = foldedHome()
        let kt = KeyboardTraversal.shared
        let button = try XCTUnwrap(kt.reachable(inRegion: "ribbon").first { $0.label() == "Paragraph group" })
        kt.focus(button)
        ui.press(.enter)
        ui.pump(); ui.pump()
        XCTAssertTrue(ui.has(tip: "Center"), "Enter opens it")
        XCTAssertEqual(kt.focused?.region, "ribbon-group", "the ring goes in, to the first control")
        ui.press(.escape)
        ui.pump(); ui.pump()
        XCTAssertFalse(ui.has(tip: "Center"), "Escape closes it")
        XCTAssertEqual(kt.focused?.label(), "Paragraph group", "and the ring is back on the button")
    }

    func testClosingWithThePointerLeavesTheKeyboardAlone() {
        let ui = foldedHome()
        XCTAssertTrue(ui.tap(tip: "Paragraph group"))
        ui.pump()
        ui.tap(at: Offset(4, 790))
        ui.pump(); ui.pump()
        XCTAssertFalse(ui.has(tip: "Center"))
        XCTAssertNil(KeyboardTraversal.shared.focused, "a click is not the keyboard: no ring appears")
    }
}
