import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// A drawn shape or text box gets the Shape Format tab; a picture keeps Picture Format.
final class ShapeFormatTabTests: XCTestCase {
    func testAShapeGetsShapeFormat() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(900, 600))
        let shell = try XCTUnwrap(ui.state(OfficeShellState.self))
        let c = shell.session.controller
        c.insertImage(try XCTUnwrap(TextBoxInsert.make(text: "one")))
        let i = try XCTUnwrap(c.document.paragraphs.firstIndex { $0.image?.textBox != nil })
        c.selectImage(at: i)
        for _ in 0 ..< 3 { ui.pump(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(shell.session.selectedImageTab, .shapeFormat)
        XCTAssertTrue(ui.has(text: "Shape Format"))
        XCTAssertFalse(ui.has(text: "Picture Format"))
    }
}
