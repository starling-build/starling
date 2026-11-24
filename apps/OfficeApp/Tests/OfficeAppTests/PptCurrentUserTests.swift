import XCTest
@testable import OfficeApp

final class PptCurrentUserTests: XCTestCase {
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24 & 255)] }
    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255)] }

    /// A CurrentUserAtom: header, size, token, offset to the current edit, name length, versions, ANSI name.
    private func atom(token: UInt32 = 0xE391_C05F, offset: UInt32, name: String = "Ann") -> [UInt8] {
        let n = Array(name.utf8)
        var body: [UInt8] = le32(20 + UInt32(n.count))
        body += le32(token)
        body += le32(offset)
        body += le16(n.count)
        body += le16(0x3F4)
        body += [3, 0, 0, 0]
        body += n
        return le16(0) + le16(0x0FF6) + le32(UInt32(body.count)) + body
    }

    func testTheOffsetOfTheCurrentEditAndTheNameAreRead() throws {
        let cu = try XCTUnwrap(PptCurrentUser(atom(offset: 0x1234, name: "Ann")))
        XCTAssertEqual(cu.offsetToCurrentEdit, 0x1234)
        XCTAssertFalse(cu.encrypted)
        XCTAssertEqual(cu.userName, "Ann")
    }

    func testTheEncryptedTokenIsReported() throws {
        let cu = try XCTUnwrap(PptCurrentUser(atom(token: 0xF3D1_C4DF, offset: 8)))
        XCTAssertTrue(cu.encrypted)
    }

    func testAStreamThatIsNotACurrentUserAtomIsRefused() {
        XCTAssertNil(PptCurrentUser([]))
        XCTAssertNil(PptCurrentUser([UInt8](repeating: 0, count: 40)))
        var bad = atom(offset: 8); bad[12] ^= 0xFF   // a token that is neither value
        XCTAssertNil(PptCurrentUser(bad))
        XCTAssertNil(PptCurrentUser(Array(atom(offset: 8).prefix(20))))   // cut short
    }
}
