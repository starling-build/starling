import XCTest
@testable import OfficeApp

final class PptContainerTests: XCTestCase {
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }
    func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
    func rec(_ type: Int, ver: Int = 0, inst: Int = 0, _ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = le16(ver | inst << 4)
        out += le16(type)
        out += le32(body.count)
        return out + body
    }
    func slidePersist(_ id: Int) -> [UInt8] {
        var body: [UInt8] = le32(id)
        body += [UInt8](repeating: 0, count: 20)
        return rec(0x03F3, body)
    }
    func userEdit(lastEdit: Int, directory: Int, document: Int) -> [UInt8] {
        var body: [UInt8] = le32(0)
        body += [0, 0, 3, 0]
        body += le32(lastEdit)
        body += le32(directory)
        body += le32(document)
        body += le32(100)
        return rec(0x0FF5, body)
    }
    func directory(_ entries: [(Int, [Int])]) -> [UInt8] {
        var body: [UInt8] = []
        for (first, offsets) in entries {
            body += le32(first | offsets.count << 20)
            for o in offsets { body += le32(o) }
        }
        return rec(0x1772, body)
    }
    func currentUser(offset: Int, token: Int = 0xE391_C05F) -> [UInt8] {
        var body: [UInt8] = le32(20)
        body += le32(token)
        body += le32(offset)
        body += le16(0)
        body += le16(0x3F4)
        body += [3, 0, 0, 0, 0, 0, 0, 0]
        return rec(0x0FF6, body)
    }

    /// Two edits. The first writes the document (slides 256, 257) and slide
    /// 257 at one offset; the second rewrites slide 257 elsewhere.
    func twoEdits() -> (doc: [UInt8], user: [UInt8], oldOffset: Int, newOffset: Int) {
        var d: [UInt8] = []
        let list = rec(0x0FF0, ver: 15, inst: 0, slidePersist(256) + slidePersist(257) as [UInt8])
        let masters = rec(0x0FF0, ver: 15, inst: 1, slidePersist(300))
        var kids = list
        kids += masters
        let document = rec(0x03E8, ver: 15, kids)
        let documentAt = d.count; d += document
        let slideA = rec(0x03EE, ver: 15, []), slideAt = d.count; d += slideA
        let oldAt = d.count; d += rec(0x03EE, ver: 15, rec(0x03EF, [1]))
        let dir1At = d.count
        d += directory([(1, [documentAt]), (256, [slideAt, oldAt])])
        let edit1At = d.count
        d += userEdit(lastEdit: 0, directory: dir1At, document: 1)
        let newAt = d.count; d += rec(0x03EE, ver: 15, rec(0x03EF, [2]))
        let dir2At = d.count
        d += directory([(257, [newAt])])
        let edit2At = d.count
        d += userEdit(lastEdit: edit1At, directory: dir2At, document: 1)
        return (d, currentUser(offset: edit2At), oldAt, newAt)
    }

    /// A document of three slides in a 4:3 show (5760 x 4320 master units).
    func deckWithThreeSlides() -> (doc: [UInt8], user: [UInt8]) {
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 0, slidePersist(256) + slidePersist(257) + slidePersist(258) as [UInt8])
        var d = rec(0x03E8, ver: 15, kids)
        let dir = d.count
        d += directory([(1, [0])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        return (d, currentUser(offset: edit))
    }

    func testTheNewerEditWinsAndSlidesFollowTheList() throws {
        let t = twoEdits()
        let f = try PptFile(currentUser: t.user, document: t.doc)
        XCTAssertEqual(f.slideIds, [256, 257])
        XCTAssertEqual(f.masterIds, [300])
        XCTAssertEqual(f.persist[257], t.newOffset)
        XCTAssertNotEqual(f.persist[257], t.oldOffset)
        XCTAssertEqual(f.record(persistId: 257)?.type, 0x03EE)
        XCTAssertNil(f.record(persistId: 999))
    }

    func testAnEncryptedFileIsRefused() {
        let t = twoEdits()
        XCTAssertThrowsError(try PptFile(currentUser: currentUser(offset: 0, token: 0xF3D1_C4DF), document: t.doc))
    }

    func testALoopingEditChainEnds() throws {
        var d: [UInt8] = []
        let list = rec(0x0FF0, ver: 15, inst: 0, slidePersist(256))
        let docAt = d.count; d += rec(0x03E8, ver: 15, list)
        let dirAt = d.count; d += directory([(1, [docAt])])
        let editAt = d.count
        d += userEdit(lastEdit: editAt, directory: dirAt, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: editAt), document: d)
        XCTAssertEqual(f.slideIds, [256])
    }

    func testSlideListAndSize() throws {
        let (doc, user) = deckWithThreeSlides()
        let f = try PptFile(currentUser: user, document: doc)
        let (state, _, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        XCTAssertEqual(state.slides.count, 3)
        XCTAssertEqual(state.slideSize.width, 720, accuracy: 0.01)
        XCTAssertEqual(state.slideSize.height, 540, accuracy: 0.01)
    }

    // A page container: SlideAtom (master ref, flags), a colour scheme, and a drawing whose only shape is a solid background.
    func page(type: Int, masterRef: Int, flags: Int, scheme: [Int], background: Int?, hidden: Bool = false) -> [UInt8] {
        var atom: [UInt8] = [UInt8](repeating: 0, count: 12)
        atom += le32(masterRef)
        atom += le32(0)
        atom += le16(flags)
        atom += le16(0)
        var kids = rec(0x03EF, atom)
        if hidden { kids += rec(0x03F9, [UInt8](repeating: 0, count: 10) + le16(4) + [UInt8](repeating: 0, count: 4)) }
        var sch: [UInt8] = []
        for c in scheme { sch += [UInt8(c >> 16 & 255), UInt8(c >> 8 & 255), UInt8(c & 255), 0] }
        kids += rec(0x07F0, inst: 1, sch)
        if let bg = background {
            var opt: [UInt8] = le16(0x181) + le32((bg >> 16 & 0xFF) | (bg & 0xFF00) | ((bg & 0xFF) << 16))
            opt += le16(0x1BF) + le32(0x110011)
            let sp = rec(0xF00A, ver: 2, inst: 1, le32(1) + le32(0x400))
            let shape = rec(0xF004, ver: 15, sp + rec(0xF00B, ver: 3, inst: 2, opt))
            kids += rec(0x040C, ver: 15, rec(0xF002, ver: 15, shape))
        }
        return rec(type, ver: 15, kids)
    }

    func testMastersAndBackgrounds() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] {
            var b: [UInt8] = le32(id)
            b += le32(0) + le32(0) + le32(slideId) + le32(0)
            return rec(0x03F3, b)
        }
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000) + persist(3, 0x8000_0001) as [UInt8])
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(4, 256) + persist(5, 257) as [UInt8])
        var d = rec(0x03E8, ver: 15, kids)
        let white = 0xFFFFFF, black = 0, red = 0xFF0000
        let scheme1 = [white, black, 0x808080, 0x000080, 0x333333, 0x444444, 0x0000FF, 0x800080]
        let scheme2 = [0x112233, white, 0x808080, 0x000080, 0x333333, 0x444444, 0x0000FF, 0x800080]
        var offs: [Int] = []
        for p in [page(type: 0x03F8, masterRef: 0, flags: 7, scheme: scheme1, background: white),
                  page(type: 0x03F8, masterRef: 0, flags: 7, scheme: scheme2, background: 0x112233),
                  page(type: 0x03EE, masterRef: 0x8000_0000, flags: 7, scheme: scheme1, background: nil),
                  page(type: 0x03EE, masterRef: 0x8000_0001, flags: 3, scheme: scheme2, background: red)] {
            offs.append(d.count); d += p
        }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]]), (4, [offs[2]]), (5, [offs[3]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        XCTAssertEqual(f.masters.count, 2)
        XCTAssertEqual(f.masters[1].background, 0x112233)
        XCTAssertEqual(f.slides[1].background, red)
        XCTAssertNil(f.slides[0].background)
        let (state, theme, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        XCTAssertEqual(state.slides.count, 2)
        XCTAssertNotEqual(state.slides[0].layoutPart, state.slides[1].layoutPart)
        XCTAssertNotNil(state.slides[1].background)
        XCTAssertNil(state.slides[0].background)
        _ = theme
    }

    func testPlaceholderTextFromTheListAndTextInAShape() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] {
            var b: [UInt8] = le32(id)
            b += le32(0) + le32(1) + le32(slideId) + le32(0)
            return rec(0x03F3, b)
        }
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        // The title text lives in the list, after the slide's persist atom (UTF-16).
        var title: [UInt8] = []
        for u in "Hello title".utf16 { title += le16(Int(u)) }
        var list: [UInt8] = persist(3, 256)
        list += rec(0x0F9F, le32(0))
        list += rec(0x0FA0, title)
        kids += rec(0x0FF0, ver: 15, inst: 0, list)
        var d = rec(0x03E8, ver: 15, kids)

        func shape(placeholder: Int?, textbox: [UInt8], anchor: [Int]) -> [UInt8] {
            var k = rec(0xF00A, ver: 2, inst: 1, le32(2) + le32(0x400))
            var a: [UInt8] = []
            for v in anchor { a += le16(v) }
            k += rec(0xF010, a)
            if let p = placeholder { k += rec(0xF011, ver: 15, rec(0x0BC3, le32(0) + [UInt8(p), 0, 0, 0])) }
            k += rec(0xF00D, ver: 15, textbox)
            return rec(0xF004, ver: 15, k)
        }
        let group = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 0, le32(1) + le32(5)))
        let titleShape = shape(placeholder: 13, textbox: rec(0x0F9E, le32(0)), anchor: [100, 200, 5000, 700])
        // "one", "two", "three" as Latin-1 bytes, with a line break inside the second.
        let body = shape(placeholder: nil, textbox: rec(0x0F9F, le32(4)) + rec(0x0FA8, Array("one\rtw\u{0B}o\rthree".utf8)), anchor: [800, 200, 5000, 3000])
        let top = rec(0xF003, ver: 15, group + titleShape + body)
        let pageKids = rec(0x03EF, [UInt8](repeating: 0, count: 12) + le32(0x8000_0000) + le32(0) + le16(7) + le16(0))
            + rec(0x040C, ver: 15, rec(0xF002, ver: 15, top))
        let master = rec(0x03F8, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 24)))
        var offs: [Int] = []
        for p in [master, rec(0x03EE, ver: 15, pageKids)] { offs.append(d.count); d += p }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        XCTAssertEqual(f.slides[0].texts.map(\.text), ["Hello title"])
        let (state, _, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        let shapes = state.slides[0].shapes
        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes[0].kind, .placeholder(.title))
        XCTAssertEqual(shapes[0].text?.paragraphs.map(\.text), ["Hello title"])
        XCTAssertEqual(shapes[1].text?.paragraphs.count, 3)
        XCTAssertEqual(shapes[1].text?.paragraphs.first?.text, "one")
        XCTAssertEqual(shapes[1].frame.width, 600, accuracy: 0.5)
        XCTAssertEqual(shapes[1].frame.top, 100, accuracy: 0.5)
    }

    func testShapesWithoutTextKeepTheirGeometryFillAndGroupSpace() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] {
            var b: [UInt8] = le32(id)
            b += le32(0) + le32(1) + le32(slideId) + le32(0)
            return rec(0x03F3, b)
        }
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(3, 256))
        var d = rec(0x03E8, ver: 15, kids)
        func opt(_ props: [(Int, Int)]) -> [UInt8] {
            var b: [UInt8] = []
            for (pid, v) in props { b += le16(pid) + le32(v) }
            return rec(0xF00B, ver: 3, inst: props.count, b)
        }
        func shape(type: Int, flags: Int = 0x400, props: [(Int, Int)], anchor: [Int], extra: [UInt8] = []) -> [UInt8] {
            var k = rec(0xF00A, ver: 2, inst: type, le32(2) + le32(flags))
            k += opt(props) + extra
            var a: [UInt8] = []
            for v in anchor { a += le16(v) }
            k += rec(0xF010, a)
            return rec(0xF004, ver: 15, k)
        }
        let head = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 0, le32(1) + le32(5)))
        // A red ellipse (fill colour is blue-green-red: 0x0000FF is red), then a group whose space is 0..1000 square placed at 1000,1000..3000,3000.
        let ellipse = shape(type: 3, props: [(0x181, 0x0000FF), (0x1BF, 0x10_0010), (0x1FF, 0x8_0000)], anchor: [100, 200, 1100, 1200])
        var space: [UInt8] = []
        for v in [0, 0, 1000, 1000] { space += le32(v) }
        let gHead = rec(0xF004, ver: 15, rec(0xF009, ver: 1, space) + rec(0xF00A, ver: 2, inst: 0, le32(9) + le32(0x201)) + rec(0xF010, le16(1000) + le16(1000) + le16(3000) + le16(3000)))
        // A shape inside a group carries a child anchor (left, top, right, bottom), not a client anchor.
        var innerKids = rec(0xF00A, ver: 2, inst: 1, le32(3) + le32(0x400))
        innerKids += opt([(0x181, 0x00FF00), (0x1BF, 0x10_0010), (0x1FF, 0x8_0000)])
        innerKids += rec(0xF00F, le32(100) + le32(200) + le32(500) + le32(600))
        let inner = rec(0xF004, ver: 15, innerKids)
        let group = rec(0xF003, ver: 15, gHead + inner)
        let top = rec(0xF003, ver: 15, head + ellipse + group)
        let pageKids = rec(0x03EF, [UInt8](repeating: 0, count: 12) + le32(0x8000_0000) + le32(0) + le16(7) + le16(0))
            + rec(0x040C, ver: 15, rec(0xF002, ver: 15, top))
        let master = rec(0x03F8, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 24)))
        var offs: [Int] = []
        for p in [master, rec(0x03EE, ver: 15, pageKids)] { offs.append(d.count); d += p }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        let xml = f.shapeXML(of: f.slides[0])
        XCTAssertTrue(xml.contains("prst=\"ellipse\""))
        XCTAssertTrue(xml.contains("<a:srgbClr val=\"FF0000\"/>"))
        XCTAssertTrue(xml.contains("<p:grpSp>"))
        XCTAssertTrue(xml.contains("<a:off x=\"\(PptBuild.emu(100))\" y=\"\(PptBuild.emu(200))\"/><a:ext cx=\"\(PptBuild.emu(400))\" cy=\"\(PptBuild.emu(400))\"/>"))
        XCTAssertTrue(xml.contains("<a:chExt cx=\"\(PptBuild.emu(1000))\" cy=\"\(PptBuild.emu(1000))\"/>"))
        let (state, _, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        XCTAssertEqual(state.slides[0].shapes.count, 2)
        XCTAssertEqual(state.slides[0].shapes[0].kind, .geometry(ShapePreset(rawValue: "ellipse")))
    }

    func testShadedAndPictureFillsBecomeGradientAndBlipFills() {
        var s = ArtShape()
        s.type = 1
        s.props = [0x1BF: 0x10001, 0x180: 7, 0x181: 0xFF0000, 0x183: 0x0000FF, 0x18B: 90 << 16]
        let g = PptFile.fillLineXML(s, placeholder: false)
        XCTAssertTrue(g.contains("<a:gradFill"))
        XCTAssertTrue(g.contains("<a:lin ang=\"5400000\""))
        s.props = [0x1BF: 0x10001, 0x180: 3, 0x181: 0xFF0000, 0x186: 4]
        let b = PptFile.fillLineXML(s, placeholder: false) { $0 == 4 ? "rId9" : nil }
        XCTAssertTrue(b.contains("<a:blip r:embed=\"rId9\"/>"))
        XCTAssertTrue(PptFile.fillLineXML(s, placeholder: false).contains("<a:solidFill>"))
    }

    func testPicturesComeFromThePicturesStreamThroughTheStore() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] {
            var b: [UInt8] = le32(id)
            b += le32(0) + le32(1) + le32(slideId) + le32(0)
            return rec(0x03F3, b)
        }
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        // The Pictures stream: one PNG record at offset 0 (uid, tag, bytes).
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]
        let blip = rec(0xF01E, ver: 0, inst: 0x6E0, [UInt8](repeating: 7, count: 16) + [0xFF] + png)
        // The store: one FBSE whose foDelay points at it; the entry holds no picture itself.
        var fbse: [UInt8] = [6, 6] + [UInt8](repeating: 7, count: 16) + le16(0xFF) + le32(blip.count) + le32(1) + le32(0)
        fbse += [0, 0, 0, 0]
        let store = rec(0xF001, ver: 15, inst: 1, rec(0xF007, ver: 2, inst: 6, fbse))
        let drawingGroup = rec(0x040B, ver: 15, rec(0xF000, ver: 15, store))
        var kids = rec(0x03E9, atom) + drawingGroup
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(3, 256))
        var d = rec(0x03E8, ver: 15, kids)
        var opt: [UInt8] = le16(0x104) + le32(1)
        opt = rec(0xF00B, ver: 3, inst: 1, opt)
        var k = rec(0xF00A, ver: 2, inst: 75, le32(2) + le32(0x400)) + opt
        k += rec(0xF010, le16(100) + le16(200) + le16(1100) + le16(1200))
        let head = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 0, le32(1) + le32(5)))
        let top = rec(0xF003, ver: 15, head + rec(0xF004, ver: 15, k))
        let pageKids = rec(0x03EF, [UInt8](repeating: 0, count: 12) + le32(0x8000_0000) + le32(0) + le16(7) + le16(0))
            + rec(0x040C, ver: 15, rec(0xF002, ver: 15, top))
        let master = rec(0x03F8, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 24)))
        var offs: [Int] = []
        for p in [master, rec(0x03EE, ver: 15, pageKids)] { offs.append(d.count); d += p }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        var f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        f.pictures = blip
        XCTAssertEqual(f.blip(1)?.ext, "png")
        XCTAssertEqual(f.blip(1)?.data, png)
        XCTAssertNil(f.blip(2))
        let parts = PptBuild.parts(f)
        XCTAssertTrue(parts.contains { $0.name == "ppt/media/image1.png" })
        let rels = parts.first { $0.name == "ppt/slides/_rels/slide1.xml.rels" }.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        XCTAssertTrue(rels.contains("../media/image1.png"))
        let slide = parts.first { $0.name == "ppt/slides/slide1.xml" }.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        XCTAssertTrue(slide.contains("<p:pic>"))
    }

    /// PowerPoint 2007 and later store a chart's own frame and parts in the shape's metroBlob (0x3A9, in the
    /// tertiary property table): the converted slide shows that chart, its parts renamed and relinked.
    func testAMetroBlobChartBecomesAGraphicFrameWithItsParts() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] {
            var b: [UInt8] = le32(id)
            b += le32(0) + le32(1) + le32(slideId) + le32(0)
            return rec(0x03F3, b)
        }
        func entry(_ name: String, _ xml: String) -> ZipEntry { ZipEntry(name: name, data: Data(xml.utf8)) }
        let relNS = "http://schemas.openxmlformats.org/package/2006/relationships"
        let officeRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let blob = [UInt8](try Zip.write([
            entry("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"bin\" ContentType=\"application/vnd.openxmlformats-officedocument.oleObject\"/><Override PartName=\"/drs/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/></Types>"),
            entry("drs/downrev.xml", "<a:downRevStg/>"),
            entry("drs/e2oDoc.xml", "<?xml version=\"1.0\"?><p:E2oFrame xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:nvGraphicFramePr><p:cNvPr id=\"9\" name=\"Chart 5\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"1\" y=\"1\"/><a:ext cx=\"1\" cy=\"1\"/></p:xfrm><a:graphic><a:graphicData uri=\"c\"><c:chart r:id=\"rId1\"/></a:graphicData></a:graphic></p:E2oFrame>"),
            entry("drs/_rels/e2oDoc.xml.rels", "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"rId1\" Type=\"\(officeRel)chart\" Target=\"charts/chart1.xml\"/></Relationships>"),
            entry("drs/charts/chart1.xml", "<c:chartSpace/>"),
            entry("drs/charts/_rels/chart1.xml.rels", "<Relationships xmlns=\"\(relNS)\"><Relationship Id=\"rId1\" Type=\"\(officeRel)oleObject\" Target=\"../embeddings/oleObject1.bin\"/></Relationships>"),
            entry("drs/embeddings/oleObject1.bin", "ole"),
        ]))
        var atom: [UInt8] = le32(5760)
        atom += le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(3, 256))
        var d = rec(0x03E8, ver: 15, kids)
        let tertiary = rec(0xF122, ver: 3, inst: 1, le16(0x3A9 | 0x8000) + le32(blob.count) + blob)
        var k = rec(0xF00A, ver: 2, inst: 75, le32(2) + le32(0xA00)) + tertiary
        k += rec(0xF010, le16(100) + le16(200) + le16(1100) + le16(1200))
        let head = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 0, le32(1) + le32(5)))
        let top = rec(0xF003, ver: 15, head + rec(0xF004, ver: 15, k))
        let pageKids = rec(0x03EF, [UInt8](repeating: 0, count: 12) + le32(0x8000_0000) + le32(0) + le16(7) + le16(0))
            + rec(0x040C, ver: 15, rec(0xF002, ver: 15, top))
        let master = rec(0x03F8, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 24)))
        var offs: [Int] = []
        for p in [master, rec(0x03EE, ver: 15, pageKids)] { offs.append(d.count); d += p }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let parts = PptBuild.parts(try PptFile(currentUser: currentUser(offset: edit), document: d))
        func text(_ name: String) -> String { parts.first { $0.name == name }.map { String(decoding: $0.data, as: UTF8.self) } ?? "" }

        let slide = text("ppt/slides/slide1.xml")
        XCTAssertTrue(slide.contains("<p:graphicFrame xmlns:p="), slide)
        XCTAssertTrue(slide.contains("<c:chart r:id=\"rIdE1\"/>"))
        XCTAssertTrue(slide.contains("<p:cNvPr id=\"2\" name=\"Chart 5\"/>"))
        // The shape's own anchor (master units to EMU), not the blob's.
        XCTAssertTrue(slide.contains("<p:xfrm><a:off x=\"317500\" y=\"158750\"/><a:ext cx=\"1428750\" cy=\"1746250\"/></p:xfrm>"), slide)
        XCTAssertFalse(slide.contains("E2oFrame"))
        XCTAssertTrue(text("ppt/slides/_rels/slide1.xml.rels").contains("Id=\"rIdE1\" Type=\"\(officeRel)chart\" Target=\"../charts/chartm1.xml\""))
        XCTAssertEqual(text("ppt/charts/chartm1.xml"), "<c:chartSpace/>")
        XCTAssertTrue(text("ppt/charts/_rels/chartm1.xml.rels").contains("Target=\"../embeddings/oleObjectm1.bin\""))
        XCTAssertEqual(text("ppt/embeddings/oleObjectm1.bin"), "ole")
        let types = text("[Content_Types].xml")
        XCTAssertTrue(types.contains("<Override PartName=\"/ppt/charts/chartm1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"))
        XCTAssertTrue(types.contains("<Default Extension=\"bin\""))
        XCTAssertFalse(parts.contains { $0.name.contains("downrev") || $0.name.contains("e2oDoc") })
    }

    /// An array property's size may count its 6-byte header (a table's row heights, 0x3A0) or leave it out
    /// (vertices): either way the complex data after it is read from the right place.
    func testAnArraysSizeWithOrWithoutItsHeaderKeepsTheNextComplexPropertyInPlace() {
        let array: [UInt8] = le16(2) + le16(2) + le16(4) + le32(100) + le32(200)
        for counted in [true, false] {
            let table = le16(0x3A0 | 0xC000) + le32(counted ? array.count : array.count - 6) + le16(0x3A9 | 0x8000) + le32(3)
            let opt = rec(0xF122, ver: 3, inst: 2, table + array + [0x50, 0x4B, 0x03])
            let sp = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 1, le32(7) + le32(0)) + opt)
            let art = OfficeArt.shapes(drawing: sp).first
            XCTAssertEqual(art?.complex[0x3A0], array, "counted \(counted)")
            XCTAssertEqual(art?.complex[0x3A9], [0x50, 0x4B, 0x03], "counted \(counted)")
        }
    }

    func testSlideNumberAndDateMarksBecomeFields() throws {
        // text "Page *": a slide-number mark at position 5, then a date mark at position 6.
        let text: [UInt8] = "Page **".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        var recs = rec(0x0F9F, le32(4)) + rec(0x0FA0, text)
        recs += rec(0x0FD8, le32(5)) + rec(0x0FF7, le32(6) + [0, 0, 0, 0])
        let blocks = PptText.blocks(OfficeArt.records(recs, in: 0 ..< recs.count), in: recs)
        XCTAssertEqual(blocks.first?.fields, [5: "slidenum", 6: "datetime1"])
        let f = try PptFile(currentUser: deckWithThreeSlides().user, document: deckWithThreeSlides().doc)
        let xml = f.paragraphsXML(blocks.first)
        XCTAssertTrue(xml.contains("type=\"slidenum\""), xml)
        XCTAssertTrue(xml.contains("type=\"datetime1\""), xml)
        XCTAssertTrue(xml.contains("<a:t>Page </a:t>"), xml)
    }

    func testTextBoxSettingsBecomeBodyProperties() {
        var s = ArtShape()
        XCTAssertEqual(PptFile.bodyPrXML(s), "<a:bodyPr/>")
        s.props = [0x81: 0, 0x87: 1, 0x85: 2]
        let x = PptFile.bodyPrXML(s)
        XCTAssertTrue(x.contains("lIns=\"0\"") && x.contains("anchor=\"ctr\"") && x.contains("wrap=\"none\""), x)
        XCTAssertFalse(x.contains("tIns"), x)
    }

    func testStyleRunsKeepOnlyTheFieldsTheirMaskNames() throws {
        // "Big red": one paragraph (level 1, centred, nothing else), runs "Big " (bold red 24 pt) and "red" (no fields).
        var atom: [UInt8] = le32(8) + le16(1) + le32(0x800) + le16(1)
        atom += le32(4) + le32(0x1 | 0x2_0000 | 0x4_0000) + le16(1) + le16(24) + [255, 0, 0, 0xFE]
        atom += le32(4) + le32(0)
        let parsed = PptStyle.parse(atom, in: 0 ..< atom.count, length: 7)
        XCTAssertEqual(parsed.paras.count, 1)
        XCTAssertEqual(parsed.paras[0].level, 1)
        XCTAssertEqual(parsed.paras[0].align, 1)
        XCTAssertNil(parsed.paras[0].leftMargin)
        XCTAssertNil(parsed.paras[0].spaceBefore)
        XCTAssertEqual(parsed.chars.count, 2)
        XCTAssertEqual(parsed.chars[0].bold, true)
        XCTAssertNil(parsed.chars[0].italic)
        XCTAssertEqual(parsed.chars[0].size, 24)
        XCTAssertEqual(parsed.chars[0].color, PptColorRef(rgb: 0xFF0000, scheme: nil))
        XCTAssertNil(parsed.chars[1].size)
        // A truncated atom never reads past its end.
        XCTAssertNoThrow(PptStyle.parse(Array(atom.prefix(11)), in: 0 ..< 11, length: 7))

        var block = PptTextBlock()
        block.text = "Big red"
        block.paraRuns = parsed.paras
        block.charRuns = parsed.chars
        let xml = try PptFile(currentUser: deckWithThreeSlides().user, document: deckWithThreeSlides().doc).paragraphsXML(block)
        XCTAssertTrue(xml.contains("<a:pPr lvl=\"1\" algn=\"ctr\"/>"), xml)
        XCTAssertTrue(xml.contains("<a:rPr sz=\"2400\" b=\"1\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:rPr><a:t>Big </a:t>"), xml)
        XCTAssertTrue(xml.contains("<a:r><a:t>red</a:t></a:r>"), xml)
        XCTAssertFalse(xml.contains("i=\""), xml)
        XCTAssertFalse(xml.contains("marL"), xml)
    }

    func testALineBreakKeepsTheSizeOfTheRunItSitsIn() throws {
        var block = PptTextBlock()
        block.text = "a\u{0B}\u{0B}b"
        var run = PptCharRun()
        run.size = 18
        run.count = 4
        block.charRuns = [run]
        let f = try PptFile(currentUser: deckWithThreeSlides().user, document: deckWithThreeSlides().doc)
        let xml = f.paragraphsXML(block)
        XCTAssertTrue(xml.contains("<a:br><a:rPr sz=\"1800\"/></a:br>"), xml)
    }

    func testMasterTextStylesReachPlaceholdersWithoutTheirOwnRuns() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] { rec(0x03F3, le32(id) + le32(0) + le32(1) + le32(slideId) + le32(0)) }
        var atom: [UInt8] = le32(5760) + le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(3, 256))
        var d = rec(0x03E8, ver: 15, kids)
        // Body style, two levels: level 1 has a bullet "•", left margin 300 and 28 pt; level 2 only 24 pt.
        var style: [UInt8] = le16(2)
        style += le32(0x1 | 0x80 | 0x100) + le16(1) + le16(0x2022) + le16(300)
        style += le32(0x2_0000) + le16(28)
        style += le32(0) + le32(0x2_0000) + le16(24)
        let master = rec(0x03F8, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 24)) + rec(0x0FA3, inst: 1, style))
        let bodyShape = rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 1, le32(2) + le32(0x400)) + rec(0xF010, le16(100) + le16(100) + le16(2000) + le16(900))
            + rec(0xF011, ver: 15, rec(0x0BC3, le32(0) + [14, 0, 0, 0])) + rec(0xF00D, ver: 15, rec(0x0F9F, le32(1)) + rec(0x0FA8, Array("Body".utf8))))
        let top = rec(0xF003, ver: 15, rec(0xF004, ver: 15, rec(0xF00A, ver: 2, inst: 0, le32(1) + le32(5))) + bodyShape)
        let slide = rec(0x03EE, ver: 15, rec(0x03EF, [UInt8](repeating: 0, count: 12) + le32(0x8000_0000) + le32(0) + le16(7) + le16(0)) + rec(0x040C, ver: 15, rec(0xF002, ver: 15, top)))
        var offs: [Int] = []
        for p in [master, slide] { offs.append(d.count); d += p }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        XCTAssertEqual(f.masters[0].textStyles[1]?.count, 2)
        XCTAssertEqual(f.masters[0].textStyles[1]?[0].char.size, 28)
        XCTAssertEqual(f.masters[0].textStyles[1]?[1].para.leftMargin, nil)
        let xml = f.textStylesXML(of: f.masters[0])
        XCTAssertTrue(xml.contains("<a:lvl1pPr marL=\"\(PptBuild.emu(300))\">"), xml)
        XCTAssertTrue(xml.contains("<a:buChar char=\"\u{2022}\"/>"), xml)
        XCTAssertTrue(xml.contains("<a:defRPr sz=\"2800\"/>"), xml)
        XCTAssertTrue(xml.contains("<a:lvl2pPr><a:defRPr sz=\"2400\"/></a:lvl2pPr>"), xml)
        let (state, _, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        XCTAssertEqual(state.slides[0].shapes.first?.text?.paragraphs.first?.runs.first?.style.fontSize, 28)
    }
}

extension PptContainerTests {
    func testAHiddenSlideIsMarkedHidden() throws {
        func persist(_ id: Int, _ slideId: Int) -> [UInt8] { rec(0x03F3, le32(id) + le32(0) + le32(1) + le32(slideId) + le32(0)) }
        var atom: [UInt8] = le32(5760) + le32(4320)
        atom += [UInt8](repeating: 0, count: 22) + le16(1) + [UInt8](repeating: 0, count: 6)
        var kids = rec(0x03E9, atom)
        kids += rec(0x0FF0, ver: 15, inst: 1, persist(2, 0x8000_0000))
        kids += rec(0x0FF0, ver: 15, inst: 0, persist(3, 256))
        var d = rec(0x03E8, ver: 15, kids)
        var offs: [Int] = []
        for p in [page(type: 0x03F8, masterRef: 0, flags: 7, scheme: [0, 0, 0, 0, 0, 0, 0, 0], background: nil),
                  page(type: 0x03EE, masterRef: 0x8000_0000, flags: 7, scheme: [0, 0, 0, 0, 0, 0, 0, 0], background: nil, hidden: true)] {
            offs.append(d.count); d += p
        }
        let dir = d.count
        d += directory([(1, [0]), (2, [offs[0]]), (3, [offs[1]])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        let f = try PptFile(currentUser: currentUser(offset: edit), document: d)
        XCTAssertTrue(f.slides[0].hidden)
        let (state, _, _) = try PptxReader(PptxPackage(PptBuild.parts(f))).read()
        XCTAssertTrue(state.slides[0].hidden)
    }
}

extension PptContainerTests {
    func testARulerGivesTheLeftMarginOfItsLevels() {
        // mask: left margin 1 (bit 3) and indent 1 (bit 8)
        let body = le32(0x108) + le16(569) + le16(216)
        let r = rec(0x0FA6, body)
        let recs = OfficeArt.records(r, in: 0 ..< r.count)
        let ruler = PptText.ruler(recs[0], in: r)
        XCTAssertEqual(ruler[0]?.left, 569)
        XCTAssertEqual(ruler[0]?.indent, 216)
    }
}

extension PptContainerTests {
    /// A deck whose Environment (0x03F2) names two fonts, sets font 1 as the default and gives "other" text 20 pt.
    func deckWithEnvironment() -> (doc: [UInt8], user: [UInt8]) {
        func font(_ name: String) -> [UInt8] {
            var b: [UInt8] = []
            for u in name.utf16 { b += le16(Int(u)) }
            return rec(0x0FB7, b + [UInt8](repeating: 0, count: 68 - b.count))
        }
        var atom: [UInt8] = le32(5760) + le32(4320)
        atom += [UInt8](repeating: 0, count: 22)
        atom += le16(1)
        atom += [UInt8](repeating: 0, count: 6)
        var env = rec(0x07D5, ver: 15, font("Arial") + font("Calibri"))
        env += rec(0x0FA4, le32(0x1_0000) + le16(1))
        env += rec(0x0FA3, inst: 4, le16(1) + le32(0) + le32(0x2_0000) + le16(20))
        var kids = rec(0x03E9, atom)
        kids += rec(0x03F2, ver: 15, env)
        var d = rec(0x03E8, ver: 15, kids)
        let dir = d.count
        d += directory([(1, [0])])
        let edit = d.count
        d += userEdit(lastEdit: 0, directory: dir, document: 1)
        return (d, currentUser(offset: edit))
    }

    func testTheEnvironmentGivesTheFontsAndTheDefaultTextStyle() throws {
        let deck = deckWithEnvironment()
        let f = try PptFile(currentUser: deck.user, document: deck.doc)
        XCTAssertEqual(f.fonts, ["Arial", "Calibri"])
        XCTAssertEqual(f.defaultChar.font, 1)
        let xml = f.defaultTextStyleXML()
        XCTAssertTrue(xml.hasPrefix("<p:defaultTextStyle><a:lvl1pPr"), xml)
        XCTAssertTrue(xml.contains("sz=\"2000\""), xml)
        // The style names no font: it takes the document's default one.
        XCTAssertTrue(xml.contains("<a:latin typeface=\"Calibri\"/>"), xml)
    }

    func testAStyleLevelWithoutAFontKeepsTheLevelAboveAndARulerSetsTheMargins() throws {
        let deck = deckWithEnvironment()
        let f = try PptFile(currentUser: deck.user, document: deck.doc)
        var one = PptStyle.Level(), two = PptStyle.Level()
        one.char.font = 0
        one.para.leftMargin = 216
        one.para.indent = 0
        two.para.leftMargin = 468
        two.para.indent = 288
        let xml = f.levelsXML("a:lstStyle", [one, two], ruler: [0: (left: 0, indent: nil)])
        XCTAssertTrue(xml.contains("<a:lvl1pPr marL=\"0\" indent=\"0\""), xml)
        XCTAssertTrue(xml.contains("<a:lvl2pPr marL=\"\(PptBuild.emu(468))\" indent=\"\(PptBuild.emu(-180))\""), xml)
        // Level 2 names no font: Arial from level 1, not the document's Calibri.
        XCTAssertEqual(xml.components(separatedBy: "<a:latin typeface=\"Arial\"/>").count, 3, xml)
        XCTAssertFalse(xml.contains("Calibri"), xml)
    }

    func testAnEmptyParagraphKeepsTheSizeOfItsMark() throws {
        var block = PptTextBlock()
        block.text = "\rb"
        var run = PptCharRun()
        run.size = 20
        run.count = 3
        block.charRuns = [run]
        let deck = deckWithEnvironment()
        let f = try PptFile(currentUser: deck.user, document: deck.doc)
        let xml = f.paragraphsXML(block)
        XCTAssertTrue(xml.hasPrefix("<a:p><a:endParaRPr sz=\"2000\"/></a:p>"), xml)
    }

    func testTheRoundTripThemeIsKeptWithTheDecksColours() throws {
        let theme = "<?xml version=\"1.0\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Kept\"><a:themeElements>"
            + "<a:clrScheme name=\"K\"><a:dk1><a:sysClr val=\"windowText\"/></a:dk1><a:lt1><a:sysClr val=\"window\"/></a:lt1>"
            + "<a:accent3><a:srgbClr val=\"123456\"/></a:accent3></a:clrScheme>"
            + "<a:fontScheme name=\"K\"><a:majorFont><a:latin typeface=\"Calibri Light\"/></a:majorFont></a:fontScheme></a:themeElements></a:theme>"
        let zip = try Zip.write([ZipEntry(name: "theme/theme/themeManager.xml", data: Data("<x/>".utf8)),
                                 ZipEntry(name: "theme/theme/theme1.xml", data: Data(theme.utf8))])
        let xml = PptBuild.theme([0xFFFFFF, 0x000000], kept: [UInt8](zip))
        XCTAssertTrue(xml.hasPrefix("<a:theme"), xml)
        XCTAssertTrue(xml.contains("name=\"Kept\""), xml)
        XCTAssertTrue(xml.contains("<a:dk1><a:srgbClr val=\"000000\"/></a:dk1>"), xml)
        XCTAssertTrue(xml.contains("<a:lt1><a:srgbClr val=\"FFFFFF\"/></a:lt1>"), xml)
        XCTAssertTrue(xml.contains("<a:srgbClr val=\"123456\"/>"), xml)
        XCTAssertTrue(xml.contains("Calibri Light"), xml)
    }
}
