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
