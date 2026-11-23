// OLE compound files (MS-CFB): the container of an encrypted OOXML package,
// of a legacy .xls (the "Workbook" stream), and of .doc and .ppt. Every read
// is bounds-checked; a hostile file gives a throw or a missing stream, never a
// trap, and every chain walk is capped so a loop in the FAT ends.
//
// Shared code (also built for the web): bytes and our own helpers only.

import Foundation

struct CompoundFile {
    /// One directory entry. `type` is 1 storage, 2 stream, 5 root.
    struct Entry {
        var name: String
        var type: UInt8
        var start: UInt32
        var size: Int
        var left: UInt32, right: UInt32, child: UInt32
    }

    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private(set) var entries: [Entry] = []
    private var miniStream: [UInt8] = []

    static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        i >= 0 && i + 2 <= b.count ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : 0
    }
    static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        i >= 0 && i + 4 <= b.count ? UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 : 0
    }

    init(_ bytes: [UInt8]) throws {
        guard OfficeCrypto.isCompoundFile(bytes) else { throw OfficeCrypto.Failure.notEncrypted }
        self.bytes = bytes
        let u16 = Self.u16, u32 = Self.u32
        let sectorShift = Int(u16(bytes, 0x1E)), miniShift = Int(u16(bytes, 0x20))
        guard (9 ... 12).contains(sectorShift), (4 ... 9).contains(miniShift) else {
            throw OfficeCrypto.Failure.corrupt("compound file header")
        }
        sectorSize = 1 << sectorShift
        miniSectorSize = 1 << miniShift
        miniCutoff = Int(u32(bytes, 0x38))
        // The FAT's sectors: 109 in the header, the rest down the DIFAT chain.
        var fatSectors: [UInt32] = (0 ..< 109).map { u32(bytes, 0x4C + $0 * 4) }
        var difat = u32(bytes, 0x44)
        var hops = 0
        while difat < 0xFFFF_FFFA, hops < 10_000 {
            let base = (Int(difat) + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { break }
            let per = sectorSize / 4 - 1
            fatSectors += (0 ..< per).map { u32(bytes, base + $0 * 4) }
            difat = u32(bytes, base + per * 4)
            hops += 1
        }
        for s in fatSectors where s < 0xFFFF_FFFA {
            let base = (Int(s) + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { continue }
            fat += (0 ..< sectorSize / 4).map { u32(bytes, base + $0 * 4) }
        }
        // The directory, then the mini stream and its FAT.
        let dir = chain(u32(bytes, 0x30))
        for k in 0 ..< dir.count / 128 {
            let e = k * 128
            let nameLen = Int(u16(dir, e + 64))
            let units = (0 ..< max(0, min(32, nameLen / 2 - 1))).map { UInt16(dir[e + $0 * 2]) | UInt16(dir[e + $0 * 2 + 1]) << 8 }
            let size = Int(truncatingIfNeeded: (UInt64(u32(dir, e + 120)) | UInt64(u32(dir, e + 124)) << 32) & (sectorSize == 512 ? 0xFFFF_FFFF : 0x7FFF_FFFF_FFFF))
            entries.append(Entry(name: String(decoding: units, as: UTF16.self), type: dir[e + 66], start: u32(dir, e + 116), size: size,
                                 left: u32(dir, e + 68), right: u32(dir, e + 72), child: u32(dir, e + 76)))
        }
        if let root = entries.first(where: { $0.type == 5 }) {
            miniStream = Array(chain(root.start).prefix(root.size))
            let mf = chain(u32(bytes, 0x3C))
            miniFat = (0 ..< mf.count / 4).map { u32(mf, $0 * 4) }
        }
    }

    /// The sectors from `start` on, joined.
    private func chain(_ start: UInt32) -> [UInt8] {
        var out: [UInt8] = []
        var s = start
        var seen = 0
        while s < 0xFFFF_FFFA, Int(s) < fat.count, seen <= fat.count {
            let base = (Int(s) + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { break }
            out += bytes[base ..< base + sectorSize]
            s = fat[Int(s)]
            seen += 1
        }
        return out
    }

    private func content(of e: Entry) -> [UInt8] {
        if e.size >= miniCutoff { return Array(chain(e.start).prefix(e.size)) }
        var out: [UInt8] = []
        var s = e.start
        var seen = 0
        while s < 0xFFFF_FFFA, Int(s) < miniFat.count, seen <= miniFat.count {
            let base = Int(s) * miniSectorSize
            guard base + miniSectorSize <= miniStream.count else { break }
            out += miniStream[base ..< base + miniSectorSize]
            s = miniFat[Int(s)]
            seen += 1
        }
        return Array(out.prefix(e.size))
    }

    private static func fold(_ s: String) -> String { s.lowercased() }

    /// A stream by name or by a path through the storages ("ObjectPool/_1/Ole10Native");
    /// names match without regard to case ("Workbook", "WorkBook"). Nil when absent.
    func stream(_ path: String) -> [UInt8]? {
        let parts = path.split(separator: "/").map { Self.fold(String($0)) }
        guard !parts.isEmpty, let rootIndex = entries.firstIndex(where: { $0.type == 5 }) else { return nil }
        var node = rootIndex
        for (k, part) in parts.enumerated() {
            guard let hit = find(part, under: node) else { return nil }
            if k == parts.count - 1 { return entries[hit].type == 2 ? content(of: entries[hit]) : nil }
            guard entries[hit].type == 1 else { return nil }
            node = hit
        }
        return nil
    }

    /// The directory entry named `name` among the children of `parent` (the
    /// siblings form a tree; a flat scan of that subtree, loop-guarded).
    private func find(_ name: String, under parent: Int) -> Int? {
        var stack: [Int] = []
        let c = entries[parent].child
        if c < 0xFFFF_FFFA, Int(c) < entries.count { stack.append(Int(c)) }
        var visited = Set<Int>()
        while let i = stack.popLast() {
            guard visited.insert(i).inserted else { continue }
            let e = entries[i]
            if Self.fold(e.name) == name { return i }
            for n in [e.left, e.right] where n < 0xFFFF_FFFA && Int(n) < entries.count { stack.append(Int(n)) }
        }
        return nil
    }

    /// Every stream, as a path from the root, in directory order.
    var streamPaths: [String] {
        guard let rootIndex = entries.firstIndex(where: { $0.type == 5 }) else { return [] }
        var out: [String] = []
        func walk(_ parent: Int, _ prefix: String, _ depth: Int) {
            guard depth < 32 else { return }
            var stack: [Int] = []
            let c = entries[parent].child
            if c < 0xFFFF_FFFA, Int(c) < entries.count { stack.append(Int(c)) }
            var visited = Set<Int>()
            var found: [Int] = []
            while let i = stack.popLast() {
                guard visited.insert(i).inserted else { continue }
                found.append(i)
                let e = entries[i]
                for n in [e.right, e.left] where n < 0xFFFF_FFFA && Int(n) < entries.count { stack.append(Int(n)) }
            }
            for i in found.sorted() {
                let e = entries[i]
                if e.type == 2 { out.append(prefix + e.name) } else if e.type == 1 { walk(i, prefix + e.name + "/", depth + 1) }
            }
        }
        walk(rootIndex, "", 0)
        return out
    }
}
