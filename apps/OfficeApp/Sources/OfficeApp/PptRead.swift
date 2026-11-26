// The legacy PowerPoint binary format (.ppt, PowerPoint 97-2003: MS-PPT), read
// into .pptx parts the same way DocRead turns a .doc into .docx parts: the
// container (CompoundFile), the "Current User" stream that says where the last
// edit starts, the "PowerPoint Document" stream of records, the persist
// directory that maps object ids to offsets, and then the slides written as
// PresentationML for the pptx reader to open.
//
// Shared code (also built for the web): bytes and our own helpers only. Every
// read is bounds-checked; a hostile file gives nil, never a trap.

import Foundation

/// The "Current User" stream (CurrentUserAtom, MS-PPT 2.3.2): where the last
/// UserEditAtom sits in the "PowerPoint Document" stream, and whether the file
/// is encrypted.
struct PptCurrentUser: Equatable {
    static let recordType = 0x0FF6
    /// headerToken of a file that is not encrypted / of one that is.
    static let plainToken: UInt32 = 0xE391_C05F, encryptedToken: UInt32 = 0xF3D1_C4DF

    var offsetToCurrentEdit = 0
    var encrypted = false
    var userName = ""

    init?(_ b: [UInt8]) {
        // Header (8) + size, token, offset (12) + name length, version words (8) at least.
        guard b.count >= 28, OfficeArt.u16(b, 2) == Self.recordType else { return nil }
        let size = OfficeArt.u32(b, 4)
        guard size >= 20, 8 + size <= b.count else { return nil }
        let token = UInt32(truncatingIfNeeded: OfficeArt.u32(b, 12))
        guard token == Self.plainToken || token == Self.encryptedToken else { return nil }
        encrypted = token == Self.encryptedToken
        offsetToCurrentEdit = OfficeArt.u32(b, 16)
        let nameLen = OfficeArt.u16(b, 20)
        // The ANSI name follows the 8 bytes of version fields.
        let from = 28, to = min(b.count, from + nameLen)
        userName = from <= to ? String(decoding: b[from ..< to], as: UTF8.self) : ""
    }
}
