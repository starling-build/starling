import XCTest
@testable import OfficeApp

/// Insert → Video / Audio: the clip rides in the file as PowerPoint writes it, drawn as its poster frame.
final class MediaInsertTests: XCTestCase {
    private func deckWithClip(_ name: String, bytes: [UInt8]) -> DeckController {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        var clip = MediaClip(data: Data(bytes), name: name, isVideo: false)
        clip.isVideo = MediaClip.isVideo(extension: clip.fileExtension)
        let (poster, size) = MediaPoster.attachment(video: clip.isVideo, name: "poster.png")
        deck.addMedia(clip, poster: poster, size: size)
        return deck
    }

    func testVideoIsWrittenAsPowerPointWritesIt() throws {
        let bytes: [UInt8] = [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 1, 2, 3, 4, 5]
        let deck = deckWithClip("clip.MP4", bytes: bytes)
        let package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/media/media") && $0.hasSuffix(".mp4") })
        XCTAssertEqual(package.parts[part], Data(bytes))
        let slide = try XCTUnwrap(String(data: package.parts["ppt/slides/slide1.xml"] ?? Data(), encoding: .utf8))
        XCTAssertTrue(slide.contains("<a:videoFile r:link="))
        XCTAssertTrue(slide.contains("<p14:media "))
        let rels = package.rels("ppt/slides/slide1.xml").filter { $0.target.hasSuffix(part.split(separator: "/").last.map(String.init) ?? "") }
        XCTAssertEqual(Set(rels.map { $0.type.split(separator: "/").last.map(String.init) ?? "" }), ["video", "media"])
        let types = String(data: package.parts["[Content_Types].xml"] ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(types.contains("video/mp4"))
    }

    func testAudioUsesTheAudioElementAndSurvivesAReSave() throws {
        let bytes: [UInt8] = [0x49, 0x44, 0x33, 3, 0, 0, 9, 9]
        let deck = deckWithClip("tune.mp3", bytes: bytes)
        let first = try Pptx.write(deck)
        let (state, theme, package) = try Pptx.read(first)
        let slide = try XCTUnwrap(String(data: package.parts["ppt/slides/slide1.xml"] ?? Data(), encoding: .utf8))
        XCTAssertTrue(slide.contains("<a:audioFile r:link="))
        let loaded = DeckController(); loaded.load(state, theme: theme, package: package)
        let shape = try XCTUnwrap(loaded.currentSlide.shapes.first)
        guard case .opaque(let o) = shape.kind, case .picture = o.rendering.first?.kind else {
            return XCTFail("a file's clip is kept whole and drawn as its poster")
        }
        let again = PptxPackage(try Zip.read(try Pptx.write(loaded)))
        XCTAssertEqual(again.parts.first { $0.key.hasPrefix("ppt/media/media") && $0.key.hasSuffix(".mp3") }?.value, Data(bytes))
    }

    func testPosterIsADecodablePng() {
        for video in [true, false] {
            let png = [UInt8](MediaPoster.png(video: video))
            XCTAssertTrue(Png.isPng(png))
            XCTAssertNotNil(Png.repaired(png), "chunks and zlib stream are whole")
        }
    }

    func testClipsPlayOnClickThroughPowerPointsMediaTiming() throws {
        let deck = deckWithClip("a.mp4", bytes: [1, 2, 3])
        var clip = MediaClip(data: Data([4, 5]), name: "b.wav", isVideo: false)
        clip.isVideo = false
        let (poster, size) = MediaPoster.attachment(video: false, name: "poster.png")
        deck.addMedia(clip, poster: poster, size: size)
        let package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let slide = try XCTUnwrap(String(data: package.parts["ppt/slides/slide1.xml"] ?? Data(), encoding: .utf8))
        XCTAssertEqual(slide.components(separatedBy: "cmd=\"playFrom(0.0)\"").count - 1, 2)
        XCTAssertTrue(slide.contains("<p:video><p:cMediaNode") && slide.contains("<p:audio><p:cMediaNode"))
        // Each clip is named by the id its picture was written under.
        let ids = slide.components(separatedBy: "<p:cNvPr id=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
        for spid in slide.components(separatedBy: "spid=\"").dropFirst().compactMap({ Int($0.prefix { $0.isNumber }) }) {
            XCTAssertTrue(ids.contains(spid))
        }
        // Timing node ids are unique.
        let tn = slide.components(separatedBy: "<p:cTn id=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
        XCTAssertEqual(Set(tn).count, tn.count)
    }
}
