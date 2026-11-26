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
        // The show plays a file's clip: its bytes ride on the shape, and re-saving adds no second timing.
        let clip = try XCTUnwrap(shape.media)
        XCTAssertEqual(clip.data, Data(bytes))
        XCTAssertTrue(clip.existing)
        XCTAssertFalse(clip.isVideo)
        let again = PptxPackage(try Zip.read(try Pptx.write(loaded)))
        let slide2 = String(data: again.parts["ppt/slides/slide1.xml"] ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(slide2.components(separatedBy: "<p:audio>").count, slide.components(separatedBy: "<p:audio>").count)
        XCTAssertEqual(again.parts.first { $0.key.hasPrefix("ppt/media/media") && $0.key.hasSuffix(".mp3") }?.value, Data(bytes))
    }

    /// A second clip does not land on the first one's centre.
    func testSecondClipIsOffsetFromTheFirst() {
        let deck = deckWithClip("a.mp4", bytes: [1])
        var audio = MediaClip(data: Data([2]), name: "b.mp3", isVideo: false)
        audio.isVideo = false
        let (poster, size) = MediaPoster.attachment(video: false, name: "poster.png")
        let first = deck.currentSlide.shapes[0]
        let second = deck.addMedia(audio, poster: poster, size: size)
        func centre(_ s: SlideShape) -> (Double, Double) { (s.frame.left + s.frame.width / 2, s.frame.top + s.frame.height / 2) }
        XCTAssertEqual(centre(second).0 - centre(first).0, 18, accuracy: 0.5)
        XCTAssertEqual(centre(second).1 - centre(first).1, 18, accuracy: 0.5)
    }

    /// The real first frame is a new picture (new id), or the painter's cache would keep drawing the generic poster.
    func testReplacingThePosterMakesANewPicture() throws {
        let deck = deckWithClip("a.mp4", bytes: [1])
        let shape = deck.currentSlide.shapes[0]
        guard case .picture(let before) = shape.kind else { return XCTFail("a picture") }
        let png = MediaPoster.png(video: false)
        deck.replacePoster(shape, png: png, width: 96, height: 96, frame: shape.frame)
        guard case .picture(let after) = shape.kind else { return XCTFail("a picture") }
        XCTAssertNotEqual(after.id, before.id)
        XCTAssertEqual(after.data, png)
        XCTAssertEqual(after.name, before.name)
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

    /// A slide with animations gets its clip's timing added to the same tree: ids stay unique and the animations stay.
    func testClipTimingJoinsExistingAnimations() throws {
        let animations = [ShapeAnimation(shapeId: 10, effect: .fade), ShapeAnimation(shapeId: 11, effect: .appear)]
        let own = AnimationXML.write(animations, spid: { $0 }, textShapes: [])
        let merged = MediaTiming.merge([(spid: 30, isVideo: true)], into: own)
        XCTAssertEqual(merged.components(separatedBy: "cmd=\"playFrom(0.0)\"").count - 1, 1)
        XCTAssertTrue(merged.contains("<p:video><p:cMediaNode"))
        XCTAssertTrue(merged.hasSuffix("</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"))
        let tn = merged.components(separatedBy: "<p:cTn id=\"").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
        XCTAssertEqual(Set(tn).count, tn.count)
        // The animations stay in the tree; a file read back keeps such a tree whole rather than remodelling it.
        XCTAssertTrue(merged.contains("spid=\"10\"") && merged.contains("spid=\"11\"") && merged.contains("spid=\"30\""))
        XCTAssertNil(AnimationXML.read(try XCTUnwrap(XNode.parse(Data(merged.utf8)))))
    }

    /// A tree read from a file can carry its attributes in any order (`<p:cTn dur=… id=…>`); the clip's nodes
    /// are still numbered after every node already there.
    func testClipTimingIdsFollowATreeWithAnyAttributeOrder() throws {
        let animations = [ShapeAnimation(shapeId: 10, effect: .fade), ShapeAnimation(shapeId: 11, effect: .appear)]
        let own = AnimationXML.write(animations, spid: { $0 }, textShapes: [])
        let reordered = own.replacingOccurrences(of: "<p:cTn id=\"", with: "<p:cTn accel=\"0\" id=\"")
        XCTAssertFalse(reordered.contains("<p:cTn id="))
        let merged = MediaTiming.merge([(spid: 30, isVideo: true)], into: reordered)
        let tn = merged.components(separatedBy: "<p:cTn ").dropFirst().compactMap { tag -> Int? in
            let head = tag.prefix { $0 != ">" }
            guard let r = head.range(of: " id=\"") ?? (head.hasPrefix("id=\"") ? head.range(of: "id=\"") : nil) else { return nil }
            return Int(head[r.upperBound...].prefix { $0.isNumber })
        }
        XCTAssertGreaterThan(tn.count, 5)
        XCTAssertEqual(Set(tn).count, tn.count, "cTn ids stay unique")
    }
}
