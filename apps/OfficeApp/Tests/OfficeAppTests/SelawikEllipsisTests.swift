import XCTest
import FluentSystemIcons

/// The UI face's ellipsis (U+2026) is three periods set as one composite glyph. Its stored box once
/// covered only the first period, and a renderer that clips a glyph to that box (iOS's) drew "Print…"
/// as "Print.". The font file stays as shipped; the copy loaded into the engine is corrected, and its box must span all three.
final class SelawikEllipsisTests: XCTestCase {
    private func u16(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) << 8 | Int(d[o + 1]) }
    private func i16(_ d: [UInt8], _ o: Int) -> Int { let v = u16(d, o); return v >= 0x8000 ? v - 0x10000 : v }
    private func u32(_ d: [UInt8], _ o: Int) -> Int { u16(d, o) << 16 | u16(d, o + 2) }

    /// (xMin, xMax) of the stored box of the glyph a character maps to (cmap format 4, BMP).
    private func box(_ face: String, _ ch: Int) throws -> (Int, Int) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../sdk/Sources/FluentSystemIcons/Resources/\(face).ttf").standardizedFileURL
        let d = [UInt8](SelawikFont.correctingEllipsisBox(try Data(contentsOf: url)))
        var tab: [String: Int] = [:]
        for i in 0..<u16(d, 4) {
            let o = 12 + 16 * i
            tab[String(decoding: d[o..<o + 4], as: UTF8.self)] = u32(d, o + 8)
        }
        let cm = tab["cmap"]!
        var gid = 0
        for i in 0..<u16(d, cm + 2) {
            let s = cm + u32(d, cm + 4 + 8 * i + 4)
            guard u16(d, s) == 4 else { continue }
            let sc = u16(d, s + 6) / 2
            for k in 0..<sc where u16(d, s + 16 + 2 * sc + 2 * k) <= ch && ch <= u16(d, s + 14 + 2 * k) {
                let delta = u16(d, s + 16 + 4 * sc + 2 * k), ro = u16(d, s + 16 + 6 * sc + 2 * k)
                if ro == 0 { gid = (ch + delta) & 0xFFFF } else {
                    let g = u16(d, s + 16 + 6 * sc + 2 * k + ro + 2 * (ch - u16(d, s + 16 + 2 * sc + 2 * k)))
                    gid = g == 0 ? 0 : (g + delta) & 0xFFFF
                }
            }
            break
        }
        XCTAssertGreaterThan(gid, 0)
        let wide = i16(d, tab["head"]! + 50) == 1
        let loca = tab["loca"]!
        let off = wide ? u32(d, loca + 4 * gid) : u16(d, loca + 2 * gid) * 2
        let p = tab["glyf"]! + off
        return (i16(d, p + 2), i16(d, p + 6))
    }

    func testTheShippedFileIsUntouched() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../sdk/Sources/FluentSystemIcons/Resources/Selawik-Regular.ttf").standardizedFileURL
        let raw = try Data(contentsOf: url)
        XCTAssertEqual(SelawikFont.correctingEllipsisBox(Data([1, 2, 3])), Data([1, 2, 3]), "not a font: unchanged")
        XCTAssertNotEqual(SelawikFont.correctingEllipsisBox(raw), raw, "the loaded copy differs from the file")
    }

    func testTheEllipsisBoxSpansThreePeriods() throws {
        for face in ["Selawik-Regular", "Selawik-Semibold"] {
            let dot = try box(face, 0x2E), dots = try box(face, 0x2026)
            XCTAssertGreaterThan(dots.1 - dots.0, 3 * (dot.1 - dot.0), "\(face): the ellipsis box is narrower than three periods")
        }
    }
}
