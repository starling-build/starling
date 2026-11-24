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

    /// What a slide or master container says about itself, apart from its shapes.
    struct Page {
        var persistId = 0
        /// The id a slide's `masterRef` names (the SlidePersistAtom's slideId).
        var slideId = 0
        var masterRef = 0
        /// SlideAtom flags: bit 0 follow master objects, 1 follow master scheme, 2 follow master background.
        var flags = 7
        /// The page's own colour scheme (ColorSchemeAtom, instance 1) as 0xRRGGBB, in scheme order.
        var scheme: [Int]? = nil
        /// The background shape's solid fill as 0xRRGGBB (a scheme index already resolved), when it has one.
        var background: Int? = nil
        /// The text of a slide's placeholders, in SlideListWithText order (what OutlineTextRefAtom indexes).
        var texts: [PptTextBlock] = []
        /// A master's TextMasterStyleAtoms by text type (0 title, 1 body, 4 other...).
        var textStyles: [Int: [PptStyle.Level]] = [:]
        var followsMasterObjects: Bool { flags & 1 != 0 }
        var followsMasterScheme: Bool { flags & 2 != 0 }
        var followsMasterBackground: Bool { flags & 4 != 0 }
    }

    let data: [UInt8]
    private(set) var slides: [Page] = []
    private(set) var masters: [Page] = []
    /// persist id -> offset of its record, the newest edit winning.
    private(set) var persist: [Int: Int] = [:]
    private(set) var documentId = 0

    /// Slide persist ids in show order, and the master persist ids.
    private(set) var slideIds: [Int] = []
    private(set) var masterIds: [Int] = []
    /// The slide size in master units (576 to the inch) and the number the first slide shows.
    private(set) var slideWidth = 5760, slideHeight = 4320
    private(set) var firstSlideNumber = 1
    /// The deck's font names, by the index a text run's font reference holds (FontCollection).
    private(set) var fonts: [String] = []

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
        for env in OfficeArt.records(document, in: doc.body) where env.type == 0x03FF {
            for coll in OfficeArt.records(document, in: env.body) where coll.type == 0x07D5 {
                for e in OfficeArt.records(document, in: coll.body) where e.type == 0x0FB7 {
                    var units: [UInt16] = []
                    var k = e.body.lowerBound
                    while k + 1 < min(e.body.lowerBound + 64, e.body.upperBound) {
                        let u = UInt16(document[k]) | UInt16(document[k + 1]) << 8
                        if u == 0 { break }
                        units.append(u); k += 2
                    }
                    fonts.append(String(decoding: units, as: UTF16.self))
                }
            }
        }
        for list in OfficeArt.records(document, in: doc.body) where list.type == Self.slideListType {
            let atoms = OfficeArt.records(document, in: list.body)
                .filter { $0.type == Self.slidePersistType && $0.body.count >= 16 }
            let ids = atoms.map { OfficeArt.u32(document, $0.body.lowerBound) }
            var pages = atoms.map { page(persistId: OfficeArt.u32(document, $0.body.lowerBound), slideId: OfficeArt.u32(document, $0.body.lowerBound + 12)) }
            if list.inst == 0 {
                // The text records after each SlidePersistAtom belong to that slide.
                var k = -1
                var group: [[ArtRecord]] = Array(repeating: [], count: pages.count)
                for r in OfficeArt.records(document, in: list.body) {
                    if r.type == Self.slidePersistType { if r.body.count >= 16 { k += 1 } } else if k >= 0, k < group.count { group[k].append(r) }
                }
                for j in pages.indices { pages[j].texts = PptText.blocks(group[j], in: document) }
            }
            if list.inst == 0 { slideIds += ids; slides += pages } else if list.inst == 1 { masterIds += ids; masters += pages }
        }
        for k in slides.indices {
            slides[k].background = resolvedBackground(of: slides[k], scheme: scheme(of: slides[k]))
        }
        for k in masters.indices { masters[k].background = resolvedBackground(of: masters[k], scheme: masters[k].scheme) }
    }

    /// The master a slide names (by slide id), or the first one when the id is stale.
    func master(for slide: Page) -> Page? {
        masters.first { $0.slideId == slide.masterRef } ?? masters.first
    }

    /// The scheme a page is drawn with: its own unless it follows its master's.
    func scheme(of slide: Page) -> [Int]? {
        if !slide.followsMasterScheme, let own = slide.scheme { return own }
        return master(for: slide)?.scheme ?? slide.scheme
    }

    private func page(persistId: Int, slideId: Int) -> Page {
        var p = Page(persistId: persistId, slideId: slideId)
        guard let c = record(persistId: persistId), c.isContainer else { return p }
        for r in OfficeArt.records(data, in: c.body) {
            switch r.type {
            case 0x03EF where r.body.count >= 22:
                p.masterRef = OfficeArt.u32(data, r.body.lowerBound + 12)
                p.flags = OfficeArt.u16(data, r.body.lowerBound + 20)
            case 0x0FA3:
                p.textStyles[r.inst] = PptStyle.parseMaster(data, in: r.body, type: r.inst)
            case 0x07F0 where r.body.count >= 32:
                if r.inst == 1 || p.scheme == nil {
                    let b = r.body.lowerBound
                    p.scheme = (0 ..< 8).map { Int(data[b + 4 * $0]) << 16 | Int(data[b + 4 * $0 + 1]) << 8 | Int(data[b + 4 * $0 + 2]) }
                }
            default: break
            }
        }
        return p
    }

    /// The solid colour of the page's background shape (the shape of the drawing that sits outside its group).
    private func resolvedBackground(of p: Page, scheme: [Int]?) -> Int? {
        guard let c = record(persistId: p.persistId), c.isContainer else { return nil }
        for drawing in OfficeArt.records(data, in: c.body) where drawing.type == 0x040C {
            for dg in OfficeArt.records(data, in: drawing.body) where dg.type == 0xF002 {
                for sp in OfficeArt.records(data, in: dg.body) where sp.type == 0xF004 {
                    guard let shape = OfficeArt.shapes(drawing: data, in: sp.body.lowerBound - 8 ..< sp.body.upperBound).first else { continue }
                    let fillType = shape.props[0x180] ?? 0
                    let bools = shape.props[0x1BF]
                    let filled = bools == nil || bools! & 0x10_0000 == 0 || bools! & 0x10 != 0
                    guard fillType == 0, filled else { return nil }
                    return Self.color(shape.props[0x181] ?? 0xFFFFFF, scheme: scheme)
                }
            }
        }
        return nil
    }

    /// An OfficeArt colour: 0xRRGGBB written low byte first, or (flag 0x08 set) a scheme index in the low byte.
    static func color(_ v: Int, scheme: [Int]?) -> Int {
        if v >> 24 & 0x08 != 0 {
            let i = v & 0xFF
            if let scheme, i < scheme.count { return scheme[i] }
            return i == 0 ? 0xFFFFFF : 0
        }
        return (v & 0xFF) << 16 | (v >> 8 & 0xFF) << 8 | (v >> 16 & 0xFF)
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
