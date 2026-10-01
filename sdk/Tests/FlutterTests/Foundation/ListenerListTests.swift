import XCTest
@testable import Flutter

/// `ListenerList` and the keyed `Listenable` API: closures have no identity,
/// so removal by owner is the only exact removal there is.
final class ListenerListTests: XCTestCase {

    func testKeyedRemovalTakesOnlyTheOwnersEntries() {
        let ownerA = NSObject(), ownerB = NSObject()
        var list = ListenerList()
        var fired: [String] = []
        list.append({ fired.append("plain") })
        list.append({ fired.append("a") }, owner: ownerA)
        list.append({ fired.append("b") }, owner: ownerB)
        list.append({ fired.append("a2") }, owner: ownerA)

        XCTAssertEqual(list.remove(owner: ownerA), 2)
        for call in list { call() }
        XCTAssertEqual(fired, ["plain", "b"])
        XCTAssertEqual(list.remove(owner: ownerA), 0)
    }

    func testUnkeyedPopSkipsKeyedEntries() {
        let owner = NSObject()
        var list = ListenerList()
        var fired: [String] = []
        list.append({ fired.append("plain") })
        list.append({ fired.append("keyed") }, owner: owner)

        XCTAssertTrue(list.removeLast())     // the unkeyed one, not the newest
        for call in list { call() }
        XCTAssertEqual(fired, ["keyed"])
        XCTAssertFalse(list.removeLast())    // nothing unkeyed left
        XCTAssertEqual(list.count, 1)
    }

    func testIterationIsASnapshot() {
        var list = ListenerList()
        var count = 0
        list.append { count += 1 }
        for call in list {
            list.append { count += 10 }   // must not run in this pass
            call()
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(list.count, 2)
    }

    func testChangeNotifierRoundTrip() {
        final class Owner {}
        let owner = Owner(), other = Owner()
        let notifier = ChangeNotifier()
        var hits = 0
        notifier.addListener({ hits += 1 }, owner: owner)
        notifier.addListener({ hits += 100 }, owner: other)
        notifier.notifyListeners()
        XCTAssertEqual(hits, 101)

        notifier.removeListeners(owner: owner)
        notifier.notifyListeners()
        XCTAssertEqual(hits, 201)
        XCTAssertTrue(notifier.hasListeners)

        notifier.removeListeners(owner: other)
        XCTAssertFalse(notifier.hasListeners)
    }

    func testPostFrameCallbacksDrainOnce() {
        let scheduler = FrameCallbackScheduler.shared
        _ = scheduler.takePostFrameCallbacks()   // start clean
        var seen: [Duration] = []
        scheduler.addPostFrameCallback { seen.append($0) }
        XCTAssertTrue(scheduler.hasPostFrameCallbacks)
        let first = scheduler.takePostFrameCallbacks()
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(scheduler.hasPostFrameCallbacks)
        first.forEach { $0(.milliseconds(16)) }
        XCTAssertEqual(seen, [.milliseconds(16)])
        XCTAssertTrue(scheduler.takePostFrameCallbacks().isEmpty)
    }
}
