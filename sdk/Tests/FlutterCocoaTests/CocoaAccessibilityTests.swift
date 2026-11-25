// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)
import AppKit
import XCTest
@testable import Flutter
@testable import FlutterCocoa

/// Headless check of the VoiceOver bridge: the element tree it builds for a window, no VoiceOver needed.
final class CocoaAccessibilityTests: XCTestCase {
    private func node(_ label: String, tap: (() -> Void)?, y: Double) -> SemanticsSnapshotNode {
        SemanticsSnapshotNode(label: label, hint: "", value: "", isButton: true, isTextField: false,
                              isHeader: false, isChecked: nil, isToggled: nil, isSelected: nil,
                              isEnabled: true, isFocused: nil, canTap: tap != nil, tap: tap,
                              frame: (x: 10, y: y, width: 80, height: 20))
    }

    @MainActor func testWindowWithTwoButtonsGivesTwoPressableElements() throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = view
        var pressed: [String] = []
        let nodes = [node("Save", tap: { pressed.append("Save") }, y: 10),
                     node("Cancel", tap: { pressed.append("Cancel") }, y: 40)]

        let elements = CocoaAccessibility.elements(for: nodes, in: view)
        view.setAccessibilityChildren(elements)

        let kids = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids.map { $0.accessibilityLabel() }, ["Save", "Cancel"])
        XCTAssertEqual(kids.map { $0.accessibilityRole() }, [.button, .button])
        XCTAssertTrue(kids[0].accessibilityParent() === view)
        // Each element sits inside the window on screen, the first above the second.
        let f0 = kids[0].accessibilityFrame(), f1 = kids[1].accessibilityFrame()
        XCTAssertEqual(f0.size.width, 80); XCTAssertEqual(f0.size.height, 20)
        XCTAssertTrue(window.frame.contains(f0))
        XCTAssertGreaterThan(f0.minY, f1.minY, "screen y points up, so the first button is higher")
        // Pressing runs the button's tap.
        XCTAssertTrue(kids[1].accessibilityPerformPress())
        XCTAssertTrue(kids[0].accessibilityPerformPress())
        XCTAssertEqual(pressed, ["Cancel", "Save"])
    }

    @MainActor func testNodeWithoutTapCannotBePressed() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let e = CocoaAccessibility.elements(for: [node("Info", tap: nil, y: 0)], in: view)
        XCTAssertFalse(e[0].accessibilityPerformPress())
    }
}
#endif
