import XCTest
import Flutter
import Foundation

/// Text layouts join and leave the fonts notifier as they are made and dropped, and a PDF export does that off the
/// main thread while the screen does it on the main one. Unguarded, the list was corrupted and a later notification
/// crashed (signal 11 in SlideTextCacheFontsTests, now and then, in a full unit run).
final class SystemFontsNotifierThreadTests: XCTestCase {
    func testListenersJoinAndLeaveFromManyThreads() {
        let notifier = SystemFontsNotifier()
        final class Owner {}
        let keep = Owner()
        var calls = 0
        notifier.addListener({ calls += 1 }, owner: keep)
        DispatchQueue.concurrentPerform(iterations: 8) { lane in
            for i in 0 ..< 2_000 {
                let owner = Owner()
                notifier.addListener({ _ = owner }, owner: owner)
                if lane == 0, i % 50 == 0 { notifier.notifyListeners() }
                notifier.removeListeners(owner: owner)
            }
        }
        XCTAssertEqual(notifier.listenerCount, 1, "every owner that left took its listener with it")
        calls = 0
        notifier.notifyListeners()
        XCTAssertEqual(calls, 1)
    }
}
