import XCTest
import Flutter

/// The clipboard carries several flavours at once (text, html, rtf, png and an
/// app's private types). Without a system clipboard the in-process fallback
/// keeps them all, so this round-trips through it; the Wayland bridge's own
/// handling of the same flavours is covered by test/clipboard_bridge_test.c.
final class ClipboardFormatsTests: XCTestCase {
    private var saved: ClipboardProvider?

    override func setUp() { saved = Clipboard.provider; Clipboard.provider = nil }
    override func tearDown() { Clipboard.provider = saved }

    private func read(_ format: String) -> ClipboardData? {
        var got: ClipboardData?
        var calls = 0
        Clipboard.getData(format) { got = $0; calls += 1 }
        XCTAssertEqual(calls, 1, "completion runs exactly once")
        return got
    }

    func testEveryFlavourRoundTrips() throws {
        let shapes = Data([0x50, 0x4b, 0x00, 0x03, 0xff])   // binary, with a NUL
        let png = Data([0x89, 0x50, 0x4e, 0x47])
        Clipboard.setData(ClipboardData(text: "two shapes", html: "<p>two shapes</p>", png: png,
                                        custom: ["application/x-starling-test-shapes": shapes]))

        let all = try XCTUnwrap(read(Clipboard.kAll))
        XCTAssertEqual(all.text, "two shapes")
        XCTAssertEqual(all.html, "<p>two shapes</p>")
        XCTAssertEqual(all.png, png)
        XCTAssertEqual(all.custom["application/x-starling-test-shapes"], shapes)

        let one = try XCTUnwrap(read("application/x-starling-test-shapes"))
        XCTAssertEqual(one.custom, ["application/x-starling-test-shapes": shapes])
        XCTAssertNil(one.text, "a single-format read brings only that format")
        XCTAssertEqual(read(ClipboardData.mimePng)?.png, png)
        XCTAssertEqual(read(Clipboard.kTextPlain)?.text, "two shapes")
        XCTAssertNil(read("application/x-starling-other"), "a type not on offer is nil")

        var formats: [String] = []
        Clipboard.availableFormats { formats = $0 }
        XCTAssertEqual(formats, ["application/x-starling-test-shapes", "text/html", "image/png", "text/plain"])
    }

    func testTextOnlyProviderOffersOnlyText() {
        final class TextOnly: ClipboardProvider {
            var text: String?
            func setText(_ t: String) { text = t }
            func getText(_ c: @escaping (String?) -> Void) { c(text) }
        }
        let p = TextOnly()
        Clipboard.provider = p
        Clipboard.setData(ClipboardData(text: "hi", custom: ["application/x-starling-test": Data([1])]))
        XCTAssertEqual(p.text, "hi")
        XCTAssertNil(read("application/x-starling-test"))
        XCTAssertEqual(read(Clipboard.kTextPlain)?.text, "hi")
        var formats: [String] = []
        Clipboard.availableFormats { formats = $0 }
        XCTAssertEqual(formats, ["text/plain"])
    }

    /// A provider that carries text and pictures but not private types (Cocoa, Win32, GTK, web): reading back what
    /// this process put there brings its private types back; anything copied since comes back as it is.
    func testPrivateTypesSurviveAProviderThatDropsThem() {
        final class NoPrivate: ClipboardProvider {
            var data: ClipboardData?
            func setText(_ t: String) { data = ClipboardData(text: t) }
            func getText(_ c: @escaping (String?) -> Void) { c(data?.text) }
            func setData(_ d: ClipboardData) { data = ClipboardData(text: d.text, png: d.png) }
            func getData(_ c: @escaping (ClipboardData?) -> Void) { c(data) }
        }
        let p = NoPrivate()
        Clipboard.provider = p
        let mime = "application/x-starling-test", png = Data([0x89, 0x50, 0x4E, 0x47, 9])
        Clipboard.setData(ClipboardData(text: "two shapes", png: png, custom: [mime: Data([7])]))
        XCTAssertEqual(read(Clipboard.kAll)?.custom[mime], Data([7]))
        p.data = ClipboardData(text: "copied in another app")        // a copy elsewhere since
        XCTAssertEqual(read(Clipboard.kAll)?.custom, [:])
        p.data = ClipboardData(text: "two shapes", png: Data([1]))   // same words, another picture
        XCTAssertEqual(read(Clipboard.kAll)?.custom, [:])
        p.data = nil                                                 // emptied
        XCTAssertNil(read(Clipboard.kAll)?.custom[mime])
        Clipboard.setData(ClipboardData(text: "plain"))              // a copy with no private types forgets the last
        p.data = ClipboardData(text: "two shapes", png: png)
        XCTAssertEqual(read(Clipboard.kAll)?.custom, [:])
    }

    func testBytesAndMimeTypesAgree() {
        let d = ClipboardData(text: nil, rtf: "{\\rtf1}", custom: ["b/x": Data([2]), "a/x": Data([1])])
        XCTAssertEqual(d.mimeTypes, ["a/x", "b/x", "text/rtf"], "private types sorted, then standard")
        for m in d.mimeTypes { XCTAssertNotNil(d.bytes(for: m), m) }
        XCTAssertNil(d.bytes(for: Clipboard.kTextPlain))
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(ClipboardData(text: nil).isEmpty)
    }

    /// The browser page answers a clipboard read with three little-endian lengths (text, HTML, PNG) and then the
    /// bytes. A paste from another app keeps its HTML and picture; an empty or cut-short answer is no data at all.
    func testTheBrowsersPackedAnswerUnpacks() throws {
        func packed(_ text: String, _ html: String, _ png: [UInt8], cut: Int = 0) -> [UInt8] {
            let parts = [Array(text.utf8), Array(html.utf8), png]
            var out: [UInt8] = []
            for p in parts { out += (0 ..< 4).map { UInt8((p.count >> (8 * $0)) & 0xFF) } }
            return Array((out + parts.joined()).dropLast(cut))
        }
        func unpack(_ bytes: [UInt8]) -> ClipboardData? { bytes.withUnsafeBufferPointer { ClipboardData(webPacked: $0) } }

        let all = try XCTUnwrap(unpack(packed("plain Qzb1", "<p>plain <b>Qzb1</b></p>", [0x89, 0x50, 0x4e, 0x47])))
        XCTAssertEqual(all.text, "plain Qzb1")
        XCTAssertEqual(all.html, "<p>plain <b>Qzb1</b></p>")
        XCTAssertEqual(all.png, Data([0x89, 0x50, 0x4e, 0x47]))

        let textOnly = try XCTUnwrap(unpack(packed("héllo", "", [])))
        XCTAssertEqual(textOnly.text, "héllo")
        XCTAssertNil(textOnly.html)
        XCTAssertNil(textOnly.png)

        let picture = try XCTUnwrap(unpack(packed("", "", [1, 2, 3])))
        XCTAssertNil(picture.text)
        XCTAssertEqual(picture.png, Data([1, 2, 3]))

        XCTAssertNil(unpack(packed("", "", [])), "nothing on the clipboard, or no permission")
        XCTAssertNil(unpack(packed("abc", "<b>x</b>", [], cut: 1)), "cut short")
        XCTAssertNil(unpack([1, 0, 0]), "no header")
    }
}
