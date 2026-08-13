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

    /// Device pixels of empty space around every slot.
    ///
    /// The blit is close to 1:1 — a slot is `ceil(cell * scale)` device pixels
    /// and lands on `cell` logical ones — but never exactly, because the cell
    /// size is fractional and the destination lands on sub-pixel offsets. So
    /// the sampler reaches slightly outside the source rect, and with slots
    /// packed edge to edge that means picking up the NEIGHBOURING GLYPH: a
    /// faint ghost of an unrelated character down one side of every cell. One
    /// pixel would do for bilinear; two is free and covers rounding.
    private static let pad = 2

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

    /// The glyph's own area, in device pixels.
    ///
    /// The height is derived from the width rather than measured, so the slot
    /// has EXACTLY the cell's aspect ratio. It has to: the blit is an
    /// `RSTransform`, whose scale is uniform, so one factor has to satisfy
    /// both axes. Rounding each axis independently — `ceil(cellW * scale)` by
    /// `ceil(cellH * scale)` — makes them disagree by a couple of percent, and
    /// the vertical comes out short: box-drawing characters then stop
    /// connecting to the row above and below, and a full block ▀ leaves a gap.
    /// That is 0.4 px at a 17 px cell and it is plainly visible.
    private var slotW: Int { max(1, Int((cellW * scale).rounded(.up))) }
    private var slotH: Int {
        max(1, Int((Double(slotW) * cellH / cellW).rounded()))
    }
    /// Slot-to-slot spacing, padding included.
    private var pitchW: Int { slotW + 2 * TerminalGlyphAtlas.pad }
    private var pitchH: Int { slotH + 2 * TerminalGlyphAtlas.pad }

    /// What one atlas pixel is worth on screen: the uniform scale a blit needs
    /// to put a `slotW`-wide source into a `cellW`-wide cell.
    var blitScale: Double { cellW / Double(slotW) }

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

    /// Whether this cell's GLYPH can come from the atlas.
    ///
    /// Narrower than it looks, because the painter handles more than the atlas
    /// does. Reverse video is a colour swap the painter resolves before it
    /// gets here, and an underline is a rectangle the painter draws itself —
    /// neither changes which glyph is wanted, so neither disqualifies a cell.
    /// What does: anything the atlas cannot represent as one tintable,
    /// single-cell, upright image.
    static func canDraw(_ cell: TermCell) -> Bool {
        if cell.scalar > 0x10FFFF { return false }       // cluster reference
        // A wide glyph spans two columns and has to be CENTRED across them;
        // its continuation cell draws nothing at all.
        if cell.attrs.contains(.wideLead) || cell.attrs.contains(.wideCont) { return false }
        if cell.attrs.contains(.italic) { return false } // one face pair for now
        return true
    }

    /// Blank cells never reach the atlas — there is no glyph to draw and a
    /// space would waste a slot per style.
    static func isBlank(_ scalar: UInt32) -> Bool { scalar == 32 || scalar == 0 }

    var slotCount: Int { next }
    var imageSize: String { image.map { "\($0.width)x\($0.height)" } ?? "none" }

    /// The atlas rect for a glyph, reserving a slot on first sighting. nil when
    /// the atlas is full — the caller then falls back for that row.
    func rect(for scalar: UInt32, bold: Bool) -> Rect? {
        // A drawn sprite has no weight, so bold and regular share one slot
        // rather than rasterising the same rectangles twice.
        let key = GlyphKey(scalar: scalar,
                           bold: bold && !TerminalBoxGlyphs.handles(scalar))
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
        // The glyph sits inside its padding, so the rect handed out is the
        // inner area — the padding exists to be sampled INTO, never drawn.
        let x = Double(col * pitchW + TerminalGlyphAtlas.pad)
        let y = Double(row * pitchH + TerminalGlyphAtlas.pad)
        return Rect.fromLTRB(x, y, x + Double(slotW), y + Double(slotH))
    }

    /// The baseline of an ordinary glyph in the primary family — the line
    /// every other family's glyph is shifted onto.
    private func baselineOfPrimary() -> Double {
        let style = TextStyle(color: Color(0xFFFF_FFFF), fontSize: fontSize,
                              fontFamily: family)
        let builder = ParagraphBuilders.create(
            style.getParagraphStyle(textDirection: .ltr))
        builder.pushStyle(style.getTextStyle(textScaler: TextScalers.noScaling))
        builder.addText("M")
        let p = builder.build()
        p.layout(ParagraphConstraints(width: Double.infinity))
        return p.alphabeticBaseline
    }

    /// Re-rasterise if glyphs were added. Cheap once the working set settles.
    func rebuildIfNeeded() {
        guard dirty, next > 0 else { return }
        dirty = false

        let rows = (next + TerminalGlyphAtlas.slotsPerRow - 1) / TerminalGlyphAtlas.slotsPerRow
        let w = pitchW * TerminalGlyphAtlas.slotsPerRow
        let h = pitchH * max(rows, 1)

        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        // Scale each axis to fill its slot exactly, rather than by the display
        // scale — the slot is an integer number of pixels and the cell is not,
        // so these differ slightly, and it is the slot the blit samples.
        let sx = Double(slotW) / cellW
        let sy = Double(slotH) / cellH
        canvas.scale(sx, sy)

        // Every glyph is its own paragraph here, so every glyph gets ITS OWN
        // font's baseline — and a fallback family's differs from the primary's.
        // Left alone, box-drawing characters sit a couple of pixels off the
        // row they are supposed to join and a full block leaves a gap at one
        // edge. So measure the primary family's baseline once and shift each
        // glyph onto it, which is what a terminal row means by a baseline.
        let reference = baselineOfPrimary()

        // White on transparent: the atlas carries coverage, the blit carries
        // colour. This is the only place shaping happens, once per glyph.
        for (key, index) in slots {
            guard let u = Unicode.Scalar(key.scalar) else { continue }
            let col = index % TerminalGlyphAtlas.slotsPerRow
            let row = index / TerminalGlyphAtlas.slotsPerRow
            let ox = Double(col * pitchW + TerminalGlyphAtlas.pad) / sx
            let oy = Double(row * pitchH + TerminalGlyphAtlas.pad) / sy

            // Box and block characters are drawn from the SLOT's geometry
            // rather than shaped, because a font glyph is sized to its own
            // advance and the cell is not the advance — see TerminalBoxGlyphs.
            // Doing it here rather than straight onto the frame's canvas is
            // what keeps them on the fast path: the slot fills the cell
            // exactly AND the cell is still one batched quad, instead of a
            // drawRect per cell. Drawn white, so the per-quad tint colours
            // them like any other glyph; a shade is white at a fraction of
            // full alpha, which the tint then multiplies to the right result.
            if TerminalBoxGlyphs.handles(key.scalar) {
                TerminalBoxGlyphs.draw(canvas, scalar: key.scalar,
                                       x: ox, y: oy, w: cellW, h: cellH,
                                       color: 0xFFFF_FFFF, scale: sx)
                continue
            }

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
            // The baseline correction is in the same logical units as the
            // slot origin computed above.
            canvas.drawParagraph(paragraph, Offset(
                ox, oy + (reference - paragraph.alphabeticBaseline)))
        }
        let picture = recorder.endRecording()
        image = picture.toImageSync(width: w, height: h)
    }
}
