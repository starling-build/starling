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
}
