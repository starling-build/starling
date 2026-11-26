import XCTest
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
@testable import OfficeApp

final class SemanticsWidgetTests: XCTestCase {
    private func ui(_ child: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Center(child: child)))
    }

    func testSemanticsWidgetNamesItsChild() {
        let t = ui(Semantics(label: "Save", button: true, child: SizedBox(width: 10, height: 10, child: nil)))
        let n = t.semantics().first { $0.label == "Save" }
        XCTAssertNotNil(n)
        XCTAssertEqual(n?.isButton, true)
        t.dispose()
    }

    func testExcludeSemanticsHidesTheSubtree() {
        let t = ui(ExcludeSemantics(child: Semantics(label: "Hidden", child: SizedBox(width: 4, height: 4, child: nil))))
        XCTAssertFalse(t.semantics().contains { $0.label == "Hidden" })
        t.dispose()
    }

    func testMergeSemanticsMakesOneNodeOfALabelAndItsTap() {
        var taps = 0
        let t = ui(MergeSemantics(child: Row(mainAxisSize: .min, children: [
            Semantics(button: true, onTap: { taps += 1 }, child: SizedBox(width: 4, height: 4, child: nil)),
            Text("Open file"),
        ])))
        let nodes = t.semantics().filter { $0.label == "Open file" }
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?.isButton, true)
        nodes.first?.tap?()
        XCTAssertEqual(taps, 1)
        t.dispose()
    }

    func testIconButtonIsNamedByItsTip() {
        let t = ui(Chrome.icon(FluentSystemIcons.textBold, "Bold", OfficeAppearance.theme(.light)) {})
        let n = t.semantics().first { $0.label == "Bold" }
        XCTAssertEqual(n?.isButton, true)
        XCTAssertEqual(n?.canTap, true)
        t.dispose()
    }

    func testToggleReportsItsState() {
        let t = ui(Chrome.toggle(FluentSystemIcons.textBold, "Bold", true, OfficeAppearance.theme(.light)) {})
        XCTAssertEqual(t.semantics().first { $0.label == "Bold" }?.isToggled, true)
        t.dispose()
    }

    /// An off toggle is still a toggle ("Bold, switch, off"), not a plain button; a plain button has no state.
    func testAnOffToggleIsStillAToggleAndAPlainButtonIsNot() {
        let off = ui(Chrome.toggle(FluentSystemIcons.textBold, "Bold", false, OfficeAppearance.theme(.light)) {})
        XCTAssertEqual(off.semantics().first { $0.label == "Bold" }?.isToggled, false)
        off.dispose()
        let plain = ui(Chrome.icon(FluentSystemIcons.textBold, "Bold", OfficeAppearance.theme(.light)) {})
        XCTAssertNil(plain.semantics().first { $0.label == "Bold" }?.isToggled)
        plain.dispose()
    }

    func testTextButtonReadsItsOwnText() {
        let t = ui(FlatButton(child: Text("Review"), width: nil, action: {}))
        XCTAssertTrue(t.semantics().contains { $0.label == "Review" && $0.isButton })
        t.dispose()
    }

    func testDialogTitleIsAHeader() {
        let t = ui(DialogShell(title: "Hyperlink", page: SizedBox(width: 10, height: 10, child: nil), onOK: {}, onCancel: {}))
        XCTAssertTrue(t.semantics().contains { $0.label == "Hyperlink" && $0.isHeader })
        t.dispose()
    }

    func testTextBoxIsATextFieldWithItsPlaceholderAndValue() {
        let c = TextEditingController(text: "abc")
        let t = ui(SizedBox(width: 200, height: 32, child: FluentTextBox(controller: c, placeholderText: "Address")))
        let n = t.semantics().first { $0.isTextField }
        XCTAssertEqual(n?.label, "Address")
        XCTAssertEqual(n?.value, "abc")
        t.dispose()
    }
}
