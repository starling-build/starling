import XCTest
@testable import OfficeApp
import OfficeText

/// `BigStack.run` is how layout and the readers get the stack their recursion needs (see its doc comment).
final class BigStackTests: XCTestCase {
    /// ~24 MB of stack: a Mac main thread has 8 MB, an iPad's 1 MB, so a plain call would be signal 11.
    @inline(never)
    private func descend(_ depth: Int) -> Int {
        var pad = [UInt8](repeating: UInt8(truncatingIfNeeded: depth), count: 6000)
        withUnsafeMutableBytes(of: &pad) { _ = $0.count }   // keep the array on the stack in a debug build
        if depth == 0 { return Int(pad[0]) }
        return descend(depth - 1) &+ Int(pad[depth % pad.count] & 1)
    }

    func testDeepRecursionFinishesOnTheBigStack() {
        let r = BigStack.run { self.descend(3_800) }
        XCTAssertGreaterThanOrEqual(r, 0)
    }

    func testItRunsOffTheCallingThreadAndNestedCallsStayOnIt() {
        let caller = Thread.current
        var inner: Thread?
        let outer = BigStack.run { () -> Thread in
            BigStack.run { inner = Thread.current }
            return Thread.current
        }
        XCTAssertFalse(outer === caller)
        XCTAssertTrue(inner === outer, "a nested call must not spawn a second thread")
    }

    #if canImport(Darwin)
    // `runIfSmall` reads the calling thread's stack size with `pthread_get_stacksize_np`, so only Darwin hops from a small
    // stack; elsewhere it runs the body where it is (a Linux thread has 512 KB too, and recursing 24 MB on it is signal 11).
    /// A thread with a small stack (an iPad's main thread has 1 MB) hops; one with a big stack (a Mac's) does not.
    func testRunIfSmallHopsOnlyFromASmallStack() {
        let caller = Thread.current
        var ranOn: Thread?
        BigStack.runIfSmall { ranOn = Thread.current }
        XCTAssertTrue(ranOn === caller, "an 8 MB thread keeps the work")

        let small = expectation(description: "small thread")
        let thread = Thread {
            let me = Thread.current
            var inner: Thread?
            let depth = BigStack.runIfSmall { () -> Int in
                inner = Thread.current
                return self.descend(3_800)   // ~24 MB: signal 11 on this thread's 512 KB
            }
            XCTAssertFalse(inner === me, "a 512 KB thread hops")
            XCTAssertGreaterThanOrEqual(depth, 0)
            small.fulfill()
        }
        thread.stackSize = 512 << 10
        thread.start()
        wait(for: [small], timeout: 60)
    }

    /// The hop from a small stack is one long-lived thread, not a thread per call: a paint every frame must not pay for a
    /// 64 MB mapping each time.
    func testRunIfSmallReusesOneWorkerThread() {
        let done = expectation(description: "small thread")
        let thread = Thread {
            var seen: [ObjectIdentifier] = []
            for _ in 0 ..< 20 { seen.append(ObjectIdentifier(BigStack.runIfSmall { Thread.current })) }
            XCTAssertEqual(Set(seen).count, 1, "every hop lands on the same worker thread")
            done.fulfill()
        }
        thread.stackSize = 512 << 10
        thread.start()
        wait(for: [done], timeout: 60)
    }
    #endif

    func testAThrownErrorComesBack() {
        struct Boom: Error {}
        XCTAssertThrowsError(try BigStack.run { () throws -> Int in throw Boom() }) { XCTAssertTrue($0 is Boom) }
    }

    /// A thread the system refuses (many renders at once, a limit) must not hang the caller: the body runs on its own stack.
    func testARefusedThreadRunsTheBodyOnTheCallersStack() {
        BigStack.simulatedRefusals = 1_000
        defer { BigStack.simulatedRefusals = 0 }
        let caller = Thread.current
        let ran = BigStack.run { Thread.current }
        XCTAssertTrue(ran === caller)
    }

    /// A refusal at the full size is retried with less.
    func testARefusedFullStackIsRetried() {
        BigStack.simulatedRefusals = 2
        defer { BigStack.simulatedRefusals = 0 }
        let caller = Thread.current
        XCTAssertFalse(BigStack.run { Thread.current } === caller)
    }

    /// Many callers at once, each hopping many times: every body runs and returns its own value.
    func testManyConcurrentHopsAllReturn() {
        let group = DispatchGroup()
        let lock = NSLock()
        var bad = 0
        for t in 0..<16 {
            group.enter()
            DispatchQueue.global().async {
                for i in 0..<300 where BigStack.run({ t * 1000 + i }) != t * 1000 + i { lock.lock(); bad += 1; lock.unlock() }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(bad, 0)
    }
}
