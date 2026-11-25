// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(iOS)
import UIKit
import XCTest
@testable import Flutter
@testable import FlutterUIKit

/// Headless check of the VoiceOver bridge: the elements it builds for a view, no VoiceOver needed.
/// Runs on the iOS simulator.
final class UIKitAccessibilityTests: XCTestCase {
    private func node(_ label: String, tap: (() -> Void)?, y: Double) -> SemanticsSnapshotNode {
        SemanticsSnapshotNode(label: label, hint: "", value: "", isButton: true, isTextField: false,
                              isHeader: false, isChecked: nil, isToggled: nil, isSelected: nil,
                              isEnabled: true, isFocused: nil, canTap: tap != nil, tap: tap,
                              frame: (x: 10, y: y, width: 80, height: 20))
    }

    @MainActor func testViewWithTwoButtonsGivesTwoActivatableElements() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let view = UIView(frame: window.bounds)
        window.addSubview(view)
        var pressed: [String] = []
        let nodes = [node("Save", tap: { pressed.append("Save") }, y: 10),
                     node("Cancel", tap: { pressed.append("Cancel") }, y: 40)]

        let elements = UIKitAccessibility.elements(for: nodes, in: view)
        view.accessibilityElements = elements

        let kids = try XCTUnwrap(view.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids.map { $0.accessibilityLabel }, ["Save", "Cancel"])
        XCTAssertTrue(kids.allSatisfy { $0.accessibilityTraits.contains(.button) && $0.isAccessibilityElement })
        XCTAssertTrue(kids[0].accessibilityContainer as AnyObject === view)
        let f0 = kids[0].accessibilityFrame, f1 = kids[1].accessibilityFrame
        XCTAssertEqual(f0.size.width, 80); XCTAssertEqual(f0.size.height, 20)
        XCTAssertLessThan(f0.minY, f1.minY, "UIKit screen y points down, so the first button is higher")
        XCTAssertTrue(kids[1].accessibilityActivate())
        XCTAssertTrue(kids[0].accessibilityActivate())
        XCTAssertEqual(pressed, ["Cancel", "Save"])
    }

    @MainActor func testNodeWithoutTapCannotBeActivated() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let e = UIKitAccessibility.elements(for: [node("Info", tap: nil, y: 0)], in: view)
        XCTAssertFalse(e[0].accessibilityActivate())
    }
}
#endif
