#if os(Linux)
import XCTest
import Flutter

final class MediaPlayerTests: XCTestCase {
    func testPlaysAudioFileToTheEnd() throws {
        let path = "/data/s/lenovo-2/ui-check/t.mp3"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path))
        guard let p = makeMediaPlayer() else { throw XCTSkip("GStreamer not installed") }
        p.volume = 0
        p.open(url: "file://" + path)
        var sawDuration = false
        for _ in 0..<200 {
            _ = p.pollFrame()
            if p.duration > 1 { sawDuration = true }
            if p.status == .ended { break }
            if case .failed(let m) = p.status { XCTFail(m); return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(sawDuration)
        XCTAssertEqual(p.status, .ended)
        p.stop()
    }
}
#endif
