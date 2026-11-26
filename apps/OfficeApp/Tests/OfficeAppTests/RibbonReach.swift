import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

extension WidgetTester {
    /// Whether the ribbon puts `label` within reach: a control on screen with that caption, an icon-only one with
    /// that tooltip, or one inside the popup of a group that gave way (`RibbonFit` folds a tab wider than its window
    /// from the right, so what a 1280 pt window shows is not every control's caption). A test that means "this
    /// control is on the tab" asks this; a test that means "this command does its job" gives its window room instead.
    func ribbonReaches(_ label: String, width: Double) -> Bool {
        func here() -> Bool {
            if let c = centre(ofText: label), c.dx > 0, c.dx < width - 10 { return true }
            return tips().contains(label)
        }
        pump(); pump()
        if here() { return true }
        for group in tips().filter({ $0.hasSuffix(" group") }) {
            guard tap(tip: group) else { continue }
            pump()
            let found = here()
            tap(at: Offset(4, 790))      // the popup's barrier closes it
            pump()
            if found { return true }
        }
        return false
    }
}
