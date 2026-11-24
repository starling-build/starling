// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The Fluent style's TEXT, as opposed to its icons.
//
// Windows 11 sets everything in Segoe UI Variable, and typeface is most of
// what a desktop's "feel" is — the same layout in the wrong face still reads
// as the wrong desktop. Segoe is a Windows system font and cannot ship with
// us, so this is **Selawik**: Microsoft's own metric-compatible substitute
// for Segoe UI, released under the SIL Open Font License precisely so that
// software which cannot license Segoe can still lay out as though it had.
// Metric-compatible means every glyph has Segoe's advance width, so text
// occupies the same space to the pixel — the layout the Windows shell was
// tuned against transfers unchanged.
//
// Two weights, which is all Windows 11's chrome uses: Regular for body and
// Semibold for the few things that are emphasised. Roughly 44 KB each.
//
// The bundle search below is `CupertinoIcons.fontData()`'s, for the same
// reasons — see the long note there before changing it.

import Flutter
import FlutterSwiftBridge
import Foundation

/// Selawik, registered under its own family names so a caller asks for it
/// explicitly and nothing else on the desktop changes shape.
public enum SelawikFont {

    /// Ask for this in a `TextStyle(fontFamily:)`.
    public static let family = "Selawik"
    /// The semibold cut is a SEPARATE family rather than a weight of the
    /// first: the engine picks a face by family name here, and registering
    /// two faces under one name is what once left only the last one loaded.
    public static let semibold = "Selawik Semibold"

    private nonisolated(unsafe) static var _registered = false

    /// Registers both cuts with the engine. Safe to call more than once.
    @discardableResult
    public static func registerFont() -> Bool {
        #if os(WASI)
        return true  // the page registered both faces (fonts/manifest.json)
        #endif
        guard !_registered else { return true }
        // The semibold cut goes in under both names: its own, for a style
        // that asks for it by name, and the regular's, so that weight 600
        // inside "Selawik" is this cut rather than a synthesized bold.
        let ok = load("Selawik-Regular", as: family)
            && load("Selawik-Semibold", as: semibold)
            && load("Selawik-Semibold", as: family)
        if ok { _registered = true }
        return ok
    }

    private static func load(_ resource: String, as familyName: String) -> Bool {
        let data = correctingEllipsisBox(fontData(resource))
        guard !data.isEmpty else { return false }
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            guard let base = buffer.baseAddress else { return false }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            return flutter.swift_bridge.LoadFontFromList(ptr, data.count, familyName)
        }
    }

    /// See `CupertinoIcons.fontData()`: deliberately not `Bundle.module`,
    /// and both the `.bundle` and `.resources` suffixes have to be searched
    /// or the font silently loads as nothing.
    public static func fontData(_ resource: String) -> Data {
        #if os(WASI)
        return Data()  // no files; and Bundle is the legacy Foundation layer
        #else
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() {
            roots.append(exe)
        }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                let candidate = root
                    .appendingPathComponent("FlutterSwift_FluentSystemIcons.\(suffix)")
                if let bundle = Bundle(url: candidate),
                   let url = bundle.url(forResource: resource, withExtension: "ttf"),
                   let data = try? Data(contentsOf: url) {
                    return data
                }
            }
        }
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = (execPath as NSString).deletingLastPathComponent
        for dir in [execDir, "\(execDir)/.."] {
            for suffix in ["bundle", "resources"] {
                let path = "\(dir)/FlutterSwift_FluentSystemIcons.\(suffix)/\(resource).ttf"
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    return data
                }
            }
        }
        return Data()
        #endif
    }

    /// The font as shipped, with the stored box of the ellipsis glyph (U+2026) corrected in memory.
    ///
    /// Selawik sets its ellipsis as one composite of three periods, but the box stored in its header covers
    /// only the first period. A renderer that clips a glyph to its stored box (iOS's) then draws "Print…"
    /// as "Print.". The file is not touched: the box is recomputed from the glyph's own components
    /// (translated simple glyphs) and written into the copy handed to the engine. Anything this does not
    /// understand (another face, a cmap or glyph shape it does not read) comes back unchanged.
    public static func correctingEllipsisBox(_ font: Data) -> Data {
        var d = [UInt8](font)
        func u16(_ o: Int) -> Int { Int(d[o]) << 8 | Int(d[o + 1]) }
        func i16(_ o: Int) -> Int { let v = u16(o); return v >= 0x8000 ? v - 0x10000 : v }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        guard d.count > 12, u16(4) < 64 else { return font }
        var tab: [String: Int] = [:]
        for i in 0..<u16(4) {
            let o = 12 + 16 * i
            guard o + 16 <= d.count else { return font }
            tab[String(decoding: d[o..<o + 4], as: UTF8.self)] = u32(o + 8)
        }
        guard let cmap = tab["cmap"], let head = tab["head"], let loca = tab["loca"], let glyf = tab["glyf"],
              head + 52 <= d.count, cmap + 4 <= d.count else { return font }
        // U+2026 -> glyph, through a format 4 subtable.
        var gid = 0
        for i in 0..<u16(cmap + 2) {
            let s = cmap + u32(cmap + 4 + 8 * i + 4)
            guard s + 16 <= d.count, u16(s) == 4 else { continue }
            let sc = u16(s + 6) / 2
            guard s + 16 + 8 * sc <= d.count else { return font }
            for k in 0..<sc where u16(s + 16 + 2 * sc + 2 * k) <= 0x2026 && 0x2026 <= u16(s + 14 + 2 * k) {
                let delta = u16(s + 16 + 4 * sc + 2 * k), ro = u16(s + 16 + 6 * sc + 2 * k)
                if ro == 0 { gid = (0x2026 + delta) & 0xFFFF } else {
                    let at = s + 16 + 6 * sc + 2 * k + ro + 2 * (0x2026 - u16(s + 16 + 2 * sc + 2 * k))
                    guard at + 2 <= d.count else { return font }
                    let g = u16(at)
                    gid = g == 0 ? 0 : (g + delta) & 0xFFFF
                }
            }
            break
        }
        guard gid > 0 else { return font }
        let wide = i16(head + 50) == 1
        func glyphStart(_ g: Int) -> Int? {
            let o = wide ? 4 * g : 2 * g
            guard loca + o + (wide ? 4 : 2) <= d.count else { return nil }
            return glyf + (wide ? u32(loca + o) : u16(loca + o) * 2)
        }
        guard let p = glyphStart(gid), p + 10 <= d.count, i16(p) == -1 else { return font }
        var q = p + 10
        var box: (Int, Int, Int, Int)? = nil
        while true {
            guard q + 8 <= d.count else { return font }
            let flags = u16(q), part = u16(q + 2)
            q += 4
            guard flags & 2 != 0 else { return font }   // point matching: not read here
            var dx = 0, dy = 0
            if flags & 1 != 0 { dx = i16(q); dy = i16(q + 2); q += 4 } else {
                dx = Int(Int8(bitPattern: d[q])); dy = Int(Int8(bitPattern: d[q + 1])); q += 2
            }
            if flags & 8 != 0 { q += 2 } else if flags & 0x40 != 0 { q += 4 } else if flags & 0x80 != 0 { q += 8 }
            guard flags & 0xC8 == 0, let sp = glyphStart(part), sp + 10 <= d.count, i16(sp) >= 0 else { return font }
            let b = (i16(sp + 2) + dx, i16(sp + 4) + dy, i16(sp + 6) + dx, i16(sp + 8) + dy)
            box = box.map { (min($0.0, b.0), min($0.1, b.1), max($0.2, b.2), max($0.3, b.3)) } ?? b
            if flags & 0x20 == 0 { break }
        }
        guard let box else { return font }
        for (i, v) in [box.0, box.1, box.2, box.3].enumerated() {
            let u = UInt16(truncatingIfNeeded: v)
            d[p + 2 + 2 * i] = UInt8(u >> 8); d[p + 3 + 2 * i] = UInt8(u & 0xFF)
        }
        return Data(d)
    }
}
