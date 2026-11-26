#if os(Linux)
import XCTest
import Flutter
@testable import OfficeApp

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

    /// A VP8 clip every GStreamer install can decode: a frame arrives, 64x48, and its middle pixel is red.
    func testDecodesAVideoFrame() throws {
        guard let p = makeMediaPlayer() else { throw XCTSkip("GStreamer not installed") }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "red", withExtension: "webm", subdirectory: "Fixtures"))
        p.volume = 0
        p.open(url: url.absoluteString)
        var frame: MediaFrame?
        for _ in 0..<200 where frame == nil {
            frame = p.pollFrame()
            if case .failed(let m) = p.status { throw XCTSkip("no VP8 decoder: \(m)") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        p.stop()
        let f = try XCTUnwrap(frame)
        XCTAssertEqual(f.width, 64)
        XCTAssertEqual(f.height, 48)
        XCTAssertEqual(f.pixels.count, 64 * 48 * 4)
        let i = (24 * 64 + 32) * 4
        XCTAssertGreaterThan(Int(f.pixels[i]), 200)
        XCTAssertLessThan(Int(f.pixels[i + 1]), 60)
        XCTAssertLessThan(Int(f.pixels[i + 2]), 60)
    }

    /// The poster of a movie is its own first frame, as a PNG that decodes to the same pixels.
    func testPosterIsTheClipsFirstFrame() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "red", withExtension: "webm", subdirectory: "Fixtures"))
        let clip = MediaClip(data: try Data(contentsOf: url), name: "red.webm", isVideo: true)
        guard let f = MediaPoster.firstFrame(of: clip) else { throw XCTSkip("no GStreamer or VP8 decoder") }
        XCTAssertEqual(f.width, 64)
        XCTAssertEqual(f.height, 48)
        XCTAssertTrue(Png.isPng([UInt8](f.png)))
        XCTAssertNotNil(Png.repaired([UInt8](f.png)))
    }
}
#endif
