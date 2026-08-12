// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A glyph atlas for the terminal grid, and the painter that blits from it.
//
// Why. Painting a row as a Text widget makes Skia SHAPE that row every frame —
// run building, font resolution, glyph sorting, grapheme-boundary scanning. A
// sample of DOOM-Fire put 72.9% of wall inside flushLayout, essentially all of
// it the paragraph shaper, and on a monospace grid it is all waste: every cell
// is one glyph at a position already known. (The cheap explanation — that the
// fire's block characters miss the primary family and re-resolve the fallback
// per run — was measured and rejected: making them native to the primary font
// moved 801 -> 829 fps, inside noise. The cost is shaping itself.)
//
// So shape each distinct glyph ONCE into an atlas image and draw a frame as a
// single drawRawAtlas: one textured quad per cell, tinted per quad, no shaping.
//
// Scope, deliberately narrow: single-width, non-combining, non-cluster scalars
// in the regular or bold face, with no decoration. Everything else — wide
// characters, clusters, colour emoji, underline, reverse-video tails — makes
// the row fall back to the Text path, which stays the only place those rules
// live. `canDraw` is the gate, and the caller decides per row.
//
// Enabled by STARLING_TERM_ATLAS=1 while it earns its place; the Text path is
// unchanged and remains the default.

import Foundation
import FlutterSwiftBridge

/// Identity of a rasterised glyph: the scalar plus the face it was drawn in.
private struct GlyphKey: Hashable {
    let scalar: UInt32
    let bold: Bool
}

/// Rasterises terminal glyphs once and hands out their atlas rectangles.
///
/// The atlas is a grid of cell-sized slots at device pixel scale, drawn white
/// on transparent so the blit can tint each quad to its cell's foreground.
/// It grows by re-rasterising; a session's working set is small, so this
/// settles in the first frames and then never runs again.
final class TerminalGlyphAtlas {

    /// 32 slots across keeps the texture comfortably within any GPU's limit
    /// while leaving room for a couple of thousand glyphs.
    private static let slotsPerRow = 32
    private static let maxSlots = 32 * 64

    private var slots: [GlyphKey: Int] = [:]     // key -> slot index
    private var next = 0
    private var dirty = false
    private(set) var image: Image?

    let cellW: Double
    let cellH: Double
    let scale: Double
    private let family: String
    private let fallback: [String]
    private let fontSize: Double

    private var slotW: Int { max(1, Int((cellW * scale).rounded(.up))) }
    private var slotH: Int { max(1, Int((cellH * scale).rounded(.up))) }

    init(cellW: Double, cellH: Double, scale: Double,
         family: String, fallback: [String], fontSize: Double) {
        self.cellW = cellW
        self.cellH = cellH
        self.scale = scale
        self.family = family
        self.fallback = fallback
        self.fontSize = fontSize
    }

    /// True when this atlas was built for the metrics it is being asked to
    /// draw with. Cell size moves with the font and the display, and a stale
    /// atlas would blit glyphs rasterised for a different grid.
    func matches(cellW: Double, cellH: Double, scale: Double,
                 family: String, fontSize: Double) -> Bool {
        self.cellW == cellW && self.cellH == cellH && self.scale == scale
            && self.family == family && self.fontSize == fontSize
    }

    /// Whether a cell is inside this renderer's scope (see the file comment).
    static func canDraw(_ cell: TermCell) -> Bool {
        if cell.scalar > 0x10FFFF { return false }       // cluster reference
        if cell.attrs.contains(.wideLead) || cell.attrs.contains(.wideCont) { return false }
        if cell.attrs.contains(.underline) || cell.attrs.contains(.reverse) { return false }
        if cell.attrs.contains(.italic) { return false } // one face pair for now
        return true
    }

    /// The atlas rect for a glyph, reserving a slot on first sighting. nil when
    /// the atlas is full — the caller then falls back for that row.
    func rect(for scalar: UInt32, bold: Bool) -> Rect? {
        let key = GlyphKey(scalar: scalar, bold: bold)
        let index: Int
        if let existing = slots[key] {
            index = existing
        } else {
            guard next < TerminalGlyphAtlas.maxSlots else { return nil }
            index = next
            slots[key] = index
            next += 1
            dirty = true
        }
        let col = index % TerminalGlyphAtlas.slotsPerRow
        let row = index / TerminalGlyphAtlas.slotsPerRow
        let x = Double(col * slotW), y = Double(row * slotH)
        return Rect.fromLTRB(x, y, x + Double(slotW), y + Double(slotH))
    }

    /// Re-rasterise if glyphs were added. Cheap once the working set settles.
    func rebuildIfNeeded() {
        guard dirty, next > 0 else { return }
        dirty = false

        let rows = (next + TerminalGlyphAtlas.slotsPerRow - 1) / TerminalGlyphAtlas.slotsPerRow
        let w = slotW * TerminalGlyphAtlas.slotsPerRow
        let h = slotH * max(rows, 1)

        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        canvas.scale(scale, scale)

        // White on transparent: the atlas carries coverage, the blit carries
        // colour. This is the only place shaping happens, once per glyph.
        for (key, index) in slots {
            guard let u = Unicode.Scalar(key.scalar) else { continue }
            let style = TextStyle(
                color: Color(0xFFFF_FFFF),
                fontSize: fontSize,
                fontWeight: key.bold ? .w700 : .normal,
                fontFamily: family,
                fontFamilyFallback: fallback
            )
            let builder = ParagraphBuilders.create(
                style.getParagraphStyle(textDirection: .ltr))
            builder.pushStyle(style.getTextStyle(textScaler: TextScalers.noScaling))
            builder.addText(String(Character(u)))
            let paragraph = builder.build()
            paragraph.layout(ParagraphConstraints(width: Double.infinity))
            let col = index % TerminalGlyphAtlas.slotsPerRow
            let row = index / TerminalGlyphAtlas.slotsPerRow
            canvas.drawParagraph(paragraph,
                                 Offset(Double(col) * cellW, Double(row) * cellH))
        }
        let picture = recorder.endRecording()
        image = picture.toImageSync(width: w, height: h)
    }
}
