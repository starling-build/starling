import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The framework's Draggable and DragTarget: a press moved past the slop drags, and the target under the pointer takes the data.
final class DraggableTests: XCTestCase {
    private func ui(_ log: Log) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: Column(children: [
            Draggable<String>(data: "a", child: SizedBox(width: 120, height: 40, child: Text("drag me")),
                              feedback: Text("ghost"), childWhenDragging: SizedBox(width: 120, height: 40, child: Text("gap")),
                              onDragStarted: { log.events.append("start") },
                              onDragEnd: { log.events.append("end \($0)") }),
            SizedBox(height: 80),
            DragTarget<String>(builder: { _, cand, _ in SizedBox(width: 120, height: 40, child: Text(cand.isEmpty ? "drop here" : "over")) },
                               onWillAccept: { $0 != "no" }, onAccept: { log.events.append("got \($0)") },
                               onLeave: { _ in log.events.append("left") }),
            Draggable<String>(data: "no", child: SizedBox(width: 120, height: 40, child: Text("refused")), feedback: Text("ghost2")),
        ]), title: "Test"), size: Size(600, 600))
    }

    final class Log { var events: [String] = [] }

    func testDropOnATakesTheData() throws {
        let log = Log(), t = ui(log)
        let from = try XCTUnwrap(t.centre(ofText: "drag me")), to = try XCTUnwrap(t.centre(ofText: "drop here"))
        t.drag(from: from, to: to)
        XCTAssertEqual(log.events, ["start", "got a", "end true"])
        XCTAssertTrue(t.has(text: "drag me"), "the widget is back after the drop")
    }

    func testReleaseOutsideAnyTargetCancels() throws {
        let log = Log(), t = ui(log)
        let from = try XCTUnwrap(t.centre(ofText: "drag me"))
        t.drag(from: from, to: Offset(from.dx + 300, from.dy + 20))
        XCTAssertEqual(log.events, ["start", "end false"])
    }

    func testSmallMovementIsNotADrag() throws {
        let log = Log(), t = ui(log)
        let from = try XCTUnwrap(t.centre(ofText: "drag me"))
        t.drag(from: from, to: Offset(from.dx + 2, from.dy))
        XCTAssertEqual(log.events, [])
    }

    func testTargetCanRefuse() throws {
        let log = Log(), t = ui(log)
        let from = try XCTUnwrap(t.centre(ofText: "refused")), to = try XCTUnwrap(t.centre(ofText: "drop here"))
        t.drag(from: from, to: to)
        XCTAssertFalse(log.events.contains { $0.hasPrefix("got") })
    }
}
