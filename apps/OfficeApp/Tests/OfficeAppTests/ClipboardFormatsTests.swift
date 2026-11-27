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

    func testBytesAndMimeTypesAgree() {
        let d = ClipboardData(text: nil, rtf: "{\\rtf1}", custom: ["b/x": Data([2]), "a/x": Data([1])])
        XCTAssertEqual(d.mimeTypes, ["a/x", "b/x", "text/rtf"], "private types sorted, then standard")
        for m in d.mimeTypes { XCTAssertNotNil(d.bytes(for: m), m) }
        XCTAssertNil(d.bytes(for: Clipboard.kTextPlain))
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(ClipboardData(text: nil).isEmpty)
    }
}
