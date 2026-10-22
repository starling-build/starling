// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

#if os(macOS) || os(Linux)
final class SiteGitUploadTests: XCTestCase {
    private func run(_ script: String, timeout: TimeInterval = 3, control: SitePublishControl = SitePublishControl(), extra: [String] = []) -> SiteGitUpload.Result {
        SiteGitUpload.run(arguments: ["/bin/sh", "-c", script, "upload-test"] + extra,
                          environment: ProcessInfo.processInfo.environment, timeout: timeout, control: control)
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    func testExitCodeAndBothOutputStreamsArePreserved() {
        let result = run("printf stdout; printf stderr >&2; exit 7")
        XCTAssertEqual(result.status, 7)
        XCTAssertNil(result.stopped)
        XCTAssertTrue(result.output.contains("stdout"))
        XCTAssertTrue(result.output.contains("stderr"))
        XCTAssertEqual(run("exit 0").status, 0)
    }

    func testCancellationBeforeStartDoesNotLaunchCommand() throws {
        try withFolder { folder in
            let marker = folder.appendingPathComponent("started")
            let control = SitePublishControl(); control.cancel()
            let result = run("touch \"$1\"", control: control, extra: [marker.path])
            XCTAssertEqual(result.stopped, .cancelled)
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
    }

    func testCancellationReachesDescendantsThatIgnoreTermination() throws {
        try withFolder { folder in
            let marker = folder.appendingPathComponent("heartbeat")
            let control = SitePublishControl()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { control.cancel() }
            let started = ProcessInfo.processInfo.systemUptime
            let result = run("trap '' TERM; (trap '' TERM; while :; do echo alive >> \"$1\"; sleep 0.02; done) & wait",
                             control: control, extra: [marker.path])
            XCTAssertEqual(result.stopped, .cancelled)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
            let stopped = try Data(contentsOf: marker)
            XCTAssertFalse(stopped.isEmpty)
            Thread.sleep(forTimeInterval: 0.15)
            XCTAssertEqual(try Data(contentsOf: marker), stopped, "A transport descendant kept running after Stop")
        }
    }

    func testDeadlineStopsProcessWithClosedOutput() {
        let started = ProcessInfo.processInfo.systemUptime
        let result = run("exec 1>&- 2>&-; trap '' TERM; while :; do sleep 1; done", timeout: 0.2)
        XCTAssertEqual(result.stopped, .timedOut)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
    }

    func testNoisyProcessCannotStarveDeadlineOrGrowCaptureWithoutBound() {
        let started = ProcessInfo.processInfo.systemUptime
        let result = run("trap '' TERM; while :; do printf 'continuous-output-1234567890\\n'; done", timeout: 0.2)
        XCTAssertEqual(result.stopped, .timedOut)
        XCTAssertFalse(result.output.isEmpty)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 65_536)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
    }

    func testExitedParentDoesNotWaitForInheritedOutputPipe() {
        let started = ProcessInfo.processInfo.systemUptime
        let result = run("sleep 2 & printf finished; exit 0", timeout: 0.3)
        XCTAssertEqual(result.status, 0)
        XCTAssertNil(result.stopped)
        XCTAssertTrue(result.output.contains("finished"))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1)
    }

    func testSpawnFailureAndInvalidTimeoutReturnWithoutHanging() {
        let result = SiteGitUpload.run(arguments: ["/no-such-starling-upload-executable"], environment: [:], timeout: 1, control: SitePublishControl())
        XCTAssertEqual(result.status, 127)
        XCTAssertNil(result.stopped)
        XCTAssertEqual(run("sleep 10", timeout: 0).status, 127)
        XCTAssertEqual(run("sleep 10", timeout: .infinity).status, 127)
    }

    func testStoppedMessagesDoNotClaimRemoteRollback() {
        for issue in [SitePublishIssue.cancelled, .timedOut] {
            XCTAssertTrue(issue.guidance.contains("unconfirmed"))
            XCTAssertTrue(issue.guidance.contains("may already have received"))
            XCTAssertTrue(issue.guidance.contains("saved writing"))
            XCTAssertFalse(issue.message.contains("Nothing was uploaded"))
        }
    }
}
#endif
