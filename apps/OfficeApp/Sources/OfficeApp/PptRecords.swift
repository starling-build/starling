// The record layer of a legacy .ppt (MS-PPT): the edit chain that starts at the
// Current User stream's offset, the persist directory that maps object ids to
// offsets in the "PowerPoint Document" stream, and the document container's
// slide and master lists. Old versions stay in the stream, so nothing is ever
// found by scanning: every object is reached through the newest directory.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation

struct PptFile {
    static let userEditType = 0x0FF5, persistDirectoryType = 0x1772
    static let documentType = 0x03E8, slideListType = 0x0FF0, slidePersistType = 0x03F3
    static let maxEdits = 4096

    let data: [UInt8]
    /// persist id -> offset of its record, the newest edit winning.
    private(set) var persist: [Int: Int] = [:]
    private(set) var documentId = 0

    /// Slide persist ids in show order, and the master persist ids.
    private(set) var slideIds: [Int] = []
    private(set) var masterIds: [Int] = []
    /// The slide size in master units (576 to the inch) and the number the first slide shows.
    private(set) var slideWidth = 5760, slideHeight = 4320
    private(set) var firstSlideNumber = 1

    init(currentUser: [UInt8], document: [UInt8]) throws {
        guard let user = PptCurrentUser(currentUser) else {
            throw OfficeFormats.FormatError.unsupported("PowerPoint file without a readable Current User stream")
        }
        if user.encrypted { throw OfficeFormats.FormatError.unsupported("encrypted PowerPoint file") }
        data = document
        var offset = user.offsetToCurrentEdit
        var seen = Set<Int>()
        var first = true
        while offset > 0, offset + 8 <= document.count, seen.insert(offset).inserted, seen.count <= Self.maxEdits {
            guard let edit = OfficeArt.records(document, in: offset ..< document.count).first,
                  edit.type == Self.userEditType, edit.body.count >= 24 else { break }
            let b = edit.body.lowerBound
            let lastEdit = OfficeArt.u32(document, b + 8)
            let directory = OfficeArt.u32(document, b + 12)
            if first { documentId = OfficeArt.u32(document, b + 16); first = false }
            readDirectory(at: directory)
            offset = lastEdit
        }
        if first { throw OfficeFormats.FormatError.unsupported("PowerPoint file with no edit record") }
        guard let doc = record(persistId: documentId), doc.type == Self.documentType else {
            throw OfficeFormats.FormatError.unsupported("PowerPoint file without a document container")
        }
        for atom in OfficeArt.records(document, in: doc.body) where atom.type == 0x03E9 && atom.body.count >= 34 {
            let b = atom.body.lowerBound
            let w = OfficeArt.u32(document, b), h = OfficeArt.u32(document, b + 4)
            if w > 0, h > 0, w < 0x10000, h < 0x10000 { slideWidth = w; slideHeight = h }
            firstSlideNumber = OfficeArt.u16(document, b + 32)
        }
        for list in OfficeArt.records(document, in: doc.body) where list.type == Self.slideListType {
            let ids = OfficeArt.records(document, in: list.body)
                .filter { $0.type == Self.slidePersistType && $0.body.count >= 4 }
                .map { OfficeArt.u32(document, $0.body.lowerBound) }
            if list.inst == 0 { slideIds += ids } else if list.inst == 1 { masterIds += ids }
        }
    }

    /// Adds a directory's entries that no newer edit has set.
    private mutating func readDirectory(at offset: Int) {
        guard offset >= 0, offset + 8 <= data.count,
              let atom = OfficeArt.records(data, in: offset ..< data.count).first,
              atom.type == Self.persistDirectoryType else { return }
        var p = atom.body.lowerBound
        let end = atom.body.upperBound
        while p + 4 <= end {
            let head = OfficeArt.u32(data, p)
            let first = head & 0xFFFFF, count = head >> 20
            p += 4
            for k in 0 ..< count where p + 4 * (k + 1) <= end {
                let id = first + k
                if persist[id] == nil { persist[id] = OfficeArt.u32(data, p + 4 * k) }
            }
            p += 4 * count
        }
    }

    /// The record a persist id names, or nil when the id or its offset is bad.
    func record(persistId id: Int) -> ArtRecord? {
        guard let at = persist[id], at >= 0, at + 8 <= data.count else { return nil }
        return OfficeArt.records(data, in: at ..< data.count).first
    }
}
