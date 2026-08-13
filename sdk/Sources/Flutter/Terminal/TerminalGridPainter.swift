// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Paints the terminal grid cell by cell, instead of building a widget per row.
//
// WHY, in two halves.
//
// Performance. A row painted as a Text is a paragraph, and a paragraph is
// SHAPED every frame: run building, font resolution, glyph sorting, grapheme
// scanning — for a monospace grid whose answer is known before the frame
// starts. A sample of DOOM-Fire put 72.9% of wall inside the shaper. Here each
// distinct glyph is shaped once into `TerminalGlyphAtlas` and a frame becomes
// one `drawRawAtlas`: a textured quad per cell, tinted per quad, no shaping.
//
// Correctness, which is the half that cannot be fixed any other way. When a
// row is one shaped paragraph, the TEXT ENGINE decides where each glyph lands,
// and it places them by the advance of whatever font it resolved — which is
// only our grid's advance for the primary family. That single fact caused
// every one of these:
//
//   * a CJK glyph came back from the fallback at 1 em against our 1.2 em cell
//     pair, so every column after it was wrong (worked around with a measured
//     per-scalar `letterSpacing`);
//   * fallback resolution inside a paragraph is monotonic, so a row needing
//     two families in descending order lost everything from the first fallback
//     glyph on (worked around by giving each run its own paragraph);
//   * a wide glyph sits LEFT-ALIGNED in its two columns, so CJK reads
//     spaced-out — and that one has no workaround at all inside a paragraph.
//
// A painter that places every cell itself cannot drift by construction, and
// both workarounds above come back out when this path becomes the default.
//
// SCOPE. The atlas covers the common cell: single-width, upright, non-cluster.
// Everything else still has to draw, so this keeps a fallback that paints one
// paragraph per cell AT ITS CELL — wide glyphs centred across their two
// columns, clusters and colour emoji drawn whole. Backgrounds, underlines and
// the block cursor are rectangles the painter draws directly.
//
// Enabled by STARLING_TERM_ATLAS=1 while it earns its place; the Text path
// stays the default and is unchanged.

import Foundation
import FlutterSwiftBridge

/// One cell that the atlas could not supply a glyph for, held until the
/// fallback pass so the atlas blit stays one call.
private struct BoxCell {
    let scalar: UInt32
    let col: Int
    let row: Int
    let fg: UInt32
}

private struct FallbackCell {
    let text: String
    let col: Int
    let row: Int
    let columns: Int          // 1, or 2 for a wide glyph
    let fg: UInt32
    let bold: Bool
    let italic: Bool
}

/// Paints a whole terminal grid: backgrounds, glyphs, underlines.
///
/// Selection and the block cursor stay where they were, as translucent layers
/// above this in the Stack — they are two rectangles a frame and separating
/// them keeps this painter about the grid.
final class TerminalGridPainter: CustomPainter {

    static let debug = ProcessInfo.processInfo.environment["STARLING_TERM_ATLAS_DEBUG"] != nil

    private let lines: [[TermCell]]
    private let cols: Int
    private let cellW: Double
    private let cellH: Double
    private let theme: TerminalTheme
    private let font: TerminalFont
    private let fallbackFamilies: [String]
    private let atlas: TerminalGlyphAtlas
    private let clusterText: (UInt32) -> String
    private let generation: UInt64

    init(lines: [[TermCell]],
         cols: Int,
         cellW: Double,
         cellH: Double,
         theme: TerminalTheme,
         font: TerminalFont,
         fallbackFamilies: [String],
         atlas: TerminalGlyphAtlas,
         generation: UInt64,
         clusterText: @escaping (UInt32) -> String) {
        self.lines = lines
        self.cols = cols
        self.cellW = cellW
        self.cellH = cellH
        self.theme = theme
        self.font = font
        self.fallbackFamilies = fallbackFamilies
        self.atlas = atlas
        self.generation = generation
        self.clusterText = clusterText
        super.init()
    }

    /// The snapshot is immutable and a new painter is built for every frame the
    /// view schedules, so "did anything change" is just "is this a different
    /// painter" — the emulator's generation counter answers it exactly.
    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? TerminalGridPainter else { return true }
        return old.generation != generation
            || old.cellW != cellW || old.cellH != cellH
            || old.lines.count != lines.count || old.cols != cols
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        // ── pass 1: backgrounds ──────────────────────────────────────────
        // Batched into runs. A default background needs no rectangle at all —
        // the view paints one behind the whole grid.
        let bgPaint = Paint()
        for (r, line) in lines.enumerated() {
            var c = 0
            let y = Double(r) * cellH
            while c < cols {
                let bg = effectiveBg(at: c, in: line)
                if bg == 0 { c += 1; continue }
                var end = c + 1
                while end < cols, effectiveBg(at: end, in: line) == bg { end += 1 }
                bgPaint.color = Color(Int(bg))
                canvas.drawRect(
                    Rect.fromLTWH(Double(c) * cellW, y,
                                  Double(end - c) * cellW, cellH),
                    bgPaint)
                c = end
            }
        }

        // ── pass 2: glyphs from the atlas, one call ──────────────────────
        var transforms: [Float] = []
        var rects: [Float] = []
        var colors: [Int32] = []
        var fallbacks: [FallbackCell] = []
        var boxes: [BoxCell] = []
        transforms.reserveCapacity(cols * lines.count * 4)
        rects.reserveCapacity(cols * lines.count * 4)
        colors.reserveCapacity(cols * lines.count)

        for (r, line) in lines.enumerated() {
            let y = Double(r) * cellH
            for c in 0 ..< min(cols, line.count) {
                let cell = line[c]
                if cell.attrs.contains(.wideCont) { continue }  // lead drew it
                if TerminalGlyphAtlas.isBlank(cell.scalar) { continue }

                let fg = effectiveFg(cell)
                let bold = cell.attrs.contains(.bold)
                let x = Double(c) * cellW

                // Box and block characters are drawn from the CELL's geometry,
                // not the font's advance — see TerminalBoxGlyphs. Collected
                // rather than drawn here so the atlas blit stays one call.
                if TerminalBoxGlyphs.handles(cell.scalar) {
                    boxes.append(BoxCell(scalar: cell.scalar, col: c, row: r, fg: fg))
                } else if TerminalGlyphAtlas.canDraw(cell),
                          let src = atlas.rect(for: cell.scalar, bold: bold) {
                    let s = Float(atlas.blitScale)
                    transforms.append(contentsOf: [s, 0, Float(x), Float(y)])
                    rects.append(contentsOf: [Float(src.left), Float(src.top),
                                              Float(src.right), Float(src.bottom)])
                    colors.append(Int32(bitPattern: fg))
                } else {
                    let text = cell.scalar > 0x10FFFF
                        ? clusterText(cell.scalar)
                        : String(cell.char)
                    fallbacks.append(FallbackCell(
                        text: text, col: c, row: r,
                        columns: cell.attrs.contains(.wideLead) ? 2 : 1,
                        fg: fg, bold: bold,
                        italic: cell.attrs.contains(.italic)))
                }
            }
        }

        // Rasterise anything newly sighted BEFORE the blit that reads it.
        atlas.rebuildIfNeeded()
        if TerminalGridPainter.debug {
            let d = "[atlas] quads=\(colors.count) fallback=\(fallbacks.count)"
                + " slots=\(atlas.slotCount) image=\(atlas.imageSize)\n"
            FileHandle.standardError.write(Data(d.utf8))
        }
        if !colors.isEmpty, let image = atlas.image {
            let paint = Paint()
            paint.filterQuality = .low     // the blit is near 1:1; see `pad`
            canvas.drawRawAtlas(image, transforms, rects, colors,
                                .modulate, nil, paint)
        }

        // ── pass 2b: box and block characters, from cell geometry ────────
        for b in boxes {
            TerminalBoxGlyphs.draw(canvas, scalar: b.scalar,
                                   x: Double(b.col) * cellW,
                                   y: Double(b.row) * cellH,
                                   w: cellW, h: cellH,
                                   color: b.fg, scale: atlas.scale)
        }

        // ── pass 3: everything the atlas cannot represent ────────────────
        for f in fallbacks { paintFallback(canvas, f) }

        // ── pass 4: underlines ───────────────────────────────────────────
        let thickness = max(1.0, (cellH / 16).rounded())
        let ulPaint = Paint()
        for (r, line) in lines.enumerated() {
            let y = Double(r) * cellH + cellH - thickness
            var c = 0
            while c < min(cols, line.count) {
                guard line[c].attrs.contains(.underline) else { c += 1; continue }
                let fg = effectiveFg(line[c])
                var end = c + 1
                while end < min(cols, line.count),
                      line[end].attrs.contains(.underline),
                      effectiveFg(line[end]) == fg { end += 1 }
                ulPaint.color = Color(Int(fg))
                canvas.drawRect(
                    Rect.fromLTWH(Double(c) * cellW, y,
                                  Double(end - c) * cellW, thickness),
                    ulPaint)
                c = end
            }
        }
    }

    // MARK: - Headless dump

    /// Paint the grid into an offscreen image and write it as raw RGBA with a
    /// one-line header. Debug only (`STARLING_TERM_DUMP=<path>`).
    ///
    /// This exists because on macOS `screencapture` returns the desktop with
    /// no windows in it unless the invoking process holds Screen Recording
    /// permission, so a screenshot is not available to verify rendering. This
    /// is better than a screenshot anyway: it is exactly what the painter
    /// draws, at a known size, with nothing composited over it.
    func dumpRaw(to path: String, size: Size, scale: Double) {
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder)
        canvas.scale(scale, scale)
        let bg = Paint()
        bg.color = Color(Int(theme.background | 0xFF00_0000))
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg)
        paint(canvas, size)
        let picture = recorder.endRecording()
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        let image = picture.toImageSync(width: w, height: h)
        guard let bytes = try? image.toByteData(format: .rawStraightRgba)
        else { return }
        var out = Data("RGBA \(w) \(h)\n".utf8)
        out.append(bytes)
        try? out.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Per-cell fallback

    /// One paragraph, drawn AT ITS CELL rather than wherever a row-long
    /// paragraph would have put it. A wide glyph is centred across its two
    /// columns — the defect that has no in-paragraph fix.
    private func paintFallback(_ canvas: any Canvas, _ f: FallbackCell) {
        let style = TextStyle(
            color: Color(Int(f.fg)),
            fontSize: font.size,
            fontWeight: f.bold ? .w700 : .normal,
            fontStyle: f.italic ? .italic : .normal,
            fontFamily: font.family,
            fontFamilyFallback: fallbackFamilies
        )
        let builder = ParagraphBuilders.create(
            style.getParagraphStyle(textDirection: .ltr))
        builder.pushStyle(style.getTextStyle(textScaler: TextScalers.noScaling))
        builder.addText(f.text)
        let paragraph = builder.build()
        paragraph.layout(ParagraphConstraints(width: Double.infinity))

        let boxWidth = Double(f.columns) * cellW
        // Centre horizontally in the columns the emulator reserved. For a
        // single column this is a no-op for anything on our own grid and a
        // small correction for a fallback face with a different advance.
        let dx = paragraph.width > 0 && paragraph.width < boxWidth
            ? (boxWidth - paragraph.width) / 2
            : 0
        canvas.drawParagraph(paragraph,
                             Offset(Double(f.col) * cellW + dx,
                                    Double(f.row) * cellH))
    }

    // MARK: - Colour resolution

    /// Reverse video is a swap, and it is resolved HERE rather than in the
    /// atlas so a reversed cell still gets its glyph from the fast path.
    private func effectiveFg(_ cell: TermCell) -> UInt32 {
        var fg = cell.attrs.contains(.reverse)
            ? (cell.bg == 0 ? theme.reverseBackground : cell.bg)
            : (cell.fg == 0 ? theme.defaultForeground : cell.fg)
        if cell.attrs.contains(.dim) {
            let r = ((fg >> 16) & 0xFF) / 2
            let g = ((fg >> 8) & 0xFF) / 2
            let b = (fg & 0xFF) / 2
            fg = 0xFF00_0000 | (r << 16) | (g << 8) | b
        }
        return fg
    }

    private func effectiveBg(at col: Int, in line: [TermCell]) -> UInt32 {
        guard col < line.count else { return 0 }
        let cell = line[col]
        guard cell.attrs.contains(.reverse) else { return cell.bg }
        return cell.fg == 0 ? theme.defaultForeground : cell.fg
    }
}
