import XCTest
import FlutterSwiftBridge
@testable import Flutter

/// What a test driver (and a host with several windows) can see of the text-input plugin's one channel:
/// who holds it and what the plugin was last told (docs/plans/ipad-multi-window.md, step 4).
@MainActor
final class TextInputChannelTests: XCTestCase {
    private final class Owner {}

    func testListenRecordsTheActiveClientAndUnlistenClearsIt() {
        let a = Owner(), b = Owner()
        TextInputChannel.listen(owner: a, client: 4) { _ in }
        XCTAssertEqual(TextInputChannel.activeClient, 4)
        // A second window's editor takes the channel from the first (one client at a time).
        TextInputChannel.listen(owner: b, client: 6) { _ in }
        XCTAssertEqual(TextInputChannel.activeClient, 6)
        // The first one letting go afterwards must not clear the second's claim.
        TextInputChannel.unlisten(owner: a)
        XCTAssertEqual(TextInputChannel.activeClient, 6)
        TextInputChannel.unlisten(owner: b)
        XCTAssertEqual(TextInputChannel.activeClient, -1)
    }

    func testTheLastEditingStateSentIsKept() {
        TextInputChannel.send("TextInput.setEditingState", ["text": "abc", "selectionBase": 1, "selectionExtent": 1] as [String: Any])
        XCTAssertEqual(TextInputChannel.lastEditingState?["text"] as? String, "abc")
        XCTAssertEqual(TextInputChannel.lastEditingState?["selectionBase"] as? Int, 1)
    }
}
