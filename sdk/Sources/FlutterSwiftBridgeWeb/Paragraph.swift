// Laid-out text: paragraph_bridge.h, over skwasm's text/paragraph.cpp.
import CSkwasm

extension flutter.swift_bridge {
    public final class ParagraphBridge {
        /// The Skwasm::Paragraph*. 0 once disposed, and every method then
        /// answers as the native bridge does for a released paragraph.
        public private(set) var skHandle: sk_ptr

        /// Takes ownership of a paragraph from `paragraphBuilder_build`.
        public init(skHandle: sk_ptr) { self.skHandle = skHandle }

        deinit { if skHandle != 0 { paragraph_dispose(skHandle) } }

        // MARK: - Metrics

        // skwasm reports every metric as a float (SkScalar); the native
        // bridge widens the same floats, so nothing is lost by it.
        public func GetWidth() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getWidth(skHandle))
        }

        public func GetHeight() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getHeight(skHandle))
        }

        public func GetLongestLine() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getLongestLine(skHandle))
        }

        public func GetMinIntrinsicWidth() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getMinIntrinsicWidth(skHandle))
        }

        public func GetMaxIntrinsicWidth() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getMaxIntrinsicWidth(skHandle))
        }

        public func GetAlphabeticBaseline() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getAlphabeticBaseline(skHandle))
        }

        public func GetIdeographicBaseline() -> Double {
            skHandle == 0 ? 0 : Double(paragraph_getIdeographicBaseline(skHandle))
        }

        public func DidExceedMaxLines() -> Bool {
            skHandle == 0 ? false : paragraph_getDidExceedMaxLines(skHandle)
        }

        public func GetNumberOfLines() -> Int {
            skHandle == 0 ? 0 : Int(paragraph_getLineCount(skHandle))
        }

        // MARK: - Layout

        public func Layout(_ width: Double) {
            guard skHandle != 0 else { return }
            paragraph_layout(skHandle, Float(width))
            // WEB-TODO: Flutter's web engine asks here for the code points no
            // registered font covers (paragraph_getUnresolvedCodePoints) and
            // downloads a Noto fallback for them. That needs the page to
            // fetch fonts on demand; until it can, such characters draw as
            // missing glyphs.
        }

        // MARK: - Boxes

        /// Copies a TextBoxList out as five floats a box — left, top, right,
        /// bottom, direction — and disposes it.
        private func encode(
            boxes list: sk_ptr, _ out_data: UnsafeMutablePointer<Float>?, _ max_boxes: Int
        ) -> Int {
            guard list != 0 else { return 0 }
            defer { textBoxList_dispose(list) }
            guard let out_data else { return 0 }
            let count = min(Int(textBoxList_getLength(list)), max_boxes)
            guard count > 0 else { return 0 }
            withSkStack { stack in
                let rect = stack.alloc(16)
                for i in 0..<count {
                    let direction = textBoxList_getBoxAtIndex(list, UInt32(i), rect)
                    starling_host_read(out_data + i * 5, rect, 16)
                    out_data[i * 5 + 4] = Float(direction)
                }
            }
            return count
        }

        private func count(boxes list: sk_ptr) -> Int {
            guard list != 0 else { return 0 }
            defer { textBoxList_dispose(list) }
            return Int(textBoxList_getLength(list))
        }

        // Skia's RectHeightStyle and RectWidthStyle are numbered as dart:ui's
        // BoxHeightStyle and BoxWidthStyle are, so the values pass through.
        private func boxes(
            _ start: UInt32, _ end: UInt32, _ heightStyle: UInt32, _ widthStyle: UInt32
        ) -> sk_ptr {
            guard skHandle != 0 else { return 0 }
            return paragraph_getBoxesForRange(
                skHandle, Int32(truncatingIfNeeded: start), Int32(truncatingIfNeeded: end),
                Int32(truncatingIfNeeded: heightStyle), Int32(truncatingIfNeeded: widthStyle))
        }

        public func GetBoxesForRange(
            _ start: UInt32, _ end: UInt32, _ box_height_style: UInt32,
            _ box_width_style: UInt32, _ out_data: UnsafeMutablePointer<Float>?,
            _ out_count: UnsafeMutablePointer<Int>?, _ max_boxes: Int
        ) {
            out_count?.pointee = encode(
                boxes: boxes(start, end, box_height_style, box_width_style), out_data, max_boxes)
        }

        public func GetBoxesForRangeCount(
            _ start: UInt32, _ end: UInt32, _ box_height_style: UInt32,
            _ box_width_style: UInt32
        ) -> Int {
            count(boxes: boxes(start, end, box_height_style, box_width_style))
        }

        public func GetBoxesForPlaceholders(
            _ out_data: UnsafeMutablePointer<Float>?, _ out_count: UnsafeMutablePointer<Int>?,
            _ max_boxes: Int
        ) {
            let list = skHandle == 0 ? 0 : paragraph_getBoxesForPlaceholders(skHandle)
            out_count?.pointee = encode(boxes: list, out_data, max_boxes)
        }

        public func GetBoxesForPlaceholdersCount() -> Int {
            skHandle == 0 ? 0 : count(boxes: paragraph_getBoxesForPlaceholders(skHandle))
        }

        // MARK: - Hit testing

        public func GetPositionForOffset(
            _ dx: Double, _ dy: Double, _ out_offset: UnsafeMutablePointer<Int>?,
            _ out_affinity: UnsafeMutablePointer<Int32>?
        ) {
            guard skHandle != 0 else {
                out_offset?.pointee = 0
                out_affinity?.pointee = 1  // downstream
                return
            }
            withSkStack { stack in
                let affinity = stack.alloc(4)
                let position = paragraph_getPositionForOffset(
                    skHandle, Float(dx), Float(dy), affinity)
                out_offset?.pointee = Int(position)
                let values: [Int32] = skRead(affinity, count: 1)
                out_affinity?.pointee = values[0]
            }
        }

        public func GetWordBoundary(
            _ offset: UInt32, _ out_start: UnsafeMutablePointer<Int>?,
            _ out_end: UnsafeMutablePointer<Int>?
        ) {
            guard skHandle != 0 else {
                out_start?.pointee = 0
                out_end?.pointee = 0
                return
            }
            withSkStack { stack in
                let range = stack.alloc(8)
                paragraph_getWordBoundary(skHandle, offset, range)
                let values: [Int32] = skRead(range, count: 2)
                out_start?.pointee = Int(values[0])
                out_end?.pointee = Int(values[1])
            }
        }

        public func GetLineBoundary(
            _ offset: UInt32, _ out_start: UnsafeMutablePointer<Int32>?,
            _ out_end: UnsafeMutablePointer<Int32>?
        ) {
            out_start?.pointee = -1
            out_end?.pointee = -1
            guard skHandle != 0 else { return }
            // The first line whose range holds the offset, ends included —
            // what paragraph.cc does, and the web engine after it.
            for line in 0..<paragraph_getLineCount(skHandle) {
                let metrics = paragraph_getLineMetricsAtIndex(skHandle, line)
                guard metrics != 0 else { continue }
                defer { lineMetrics_dispose(metrics) }
                let start = lineMetrics_getStartIndex(metrics)
                let end = lineMetrics_getEndIndex(metrics)
                if offset >= start && offset <= end {
                    out_start?.pointee = Int32(truncatingIfNeeded: start)
                    out_end?.pointee = Int32(truncatingIfNeeded: end)
                    return
                }
            }
        }

        // MARK: - Glyph info

        /// Runs one of skwasm's two glyph queries, which share their out
        /// parameters: a rect, a code unit range and a direction flag.
        private func glyphInfo(
            _ out_bounds_left: UnsafeMutablePointer<Double>?,
            _ out_bounds_top: UnsafeMutablePointer<Double>?,
            _ out_bounds_right: UnsafeMutablePointer<Double>?,
            _ out_bounds_bottom: UnsafeMutablePointer<Double>?,
            _ out_range_start: UnsafeMutablePointer<Int>?,
            _ out_range_end: UnsafeMutablePointer<Int>?,
            _ out_is_ltr: UnsafeMutablePointer<Bool>?,
            query: (_ rect: sk_ptr, _ range: sk_ptr, _ flags: sk_ptr) -> Bool
        ) -> Bool {
            guard skHandle != 0 else { return false }
            return withSkStack { stack in
                let rect = stack.alloc(16)
                let range = stack.alloc(8)
                let flags = stack.alloc(1)
                guard query(rect, range, flags) else { return false }
                let bounds: [Float] = skRead(rect, count: 4)
                let units: [UInt32] = skRead(range, count: 2)
                let ltr: [UInt8] = skRead(flags, count: 1)
                out_bounds_left?.pointee = Double(bounds[0])
                out_bounds_top?.pointee = Double(bounds[1])
                out_bounds_right?.pointee = Double(bounds[2])
                out_bounds_bottom?.pointee = Double(bounds[3])
                out_range_start?.pointee = Int(units[0])
                out_range_end?.pointee = Int(units[1])
                out_is_ltr?.pointee = ltr[0] != 0
                return true
            }
        }

        public func GetGlyphInfoAt(
            _ code_unit_offset: UInt32,
            _ out_bounds_left: UnsafeMutablePointer<Double>?,
            _ out_bounds_top: UnsafeMutablePointer<Double>?,
            _ out_bounds_right: UnsafeMutablePointer<Double>?,
            _ out_bounds_bottom: UnsafeMutablePointer<Double>?,
            _ out_range_start: UnsafeMutablePointer<Int>?,
            _ out_range_end: UnsafeMutablePointer<Int>?,
            _ out_is_ltr: UnsafeMutablePointer<Bool>?
        ) -> Bool {
            glyphInfo(
                out_bounds_left, out_bounds_top, out_bounds_right, out_bounds_bottom,
                out_range_start, out_range_end, out_is_ltr
            ) { rect, range, flags in
                paragraph_getGlyphInfoAt(skHandle, code_unit_offset, rect, range, flags)
            }
        }

        public func GetClosestGlyphInfoForOffset(
            _ dx: Double, _ dy: Double,
            _ out_bounds_left: UnsafeMutablePointer<Double>?,
            _ out_bounds_top: UnsafeMutablePointer<Double>?,
            _ out_bounds_right: UnsafeMutablePointer<Double>?,
            _ out_bounds_bottom: UnsafeMutablePointer<Double>?,
            _ out_range_start: UnsafeMutablePointer<Int>?,
            _ out_range_end: UnsafeMutablePointer<Int>?,
            _ out_is_ltr: UnsafeMutablePointer<Bool>?
        ) -> Bool {
            glyphInfo(
                out_bounds_left, out_bounds_top, out_bounds_right, out_bounds_bottom,
                out_range_start, out_range_end, out_is_ltr
            ) { rect, range, flags in
                paragraph_getClosestGlyphInfoAtCoordinate(
                    skHandle, Float(dx), Float(dy), rect, range, flags)
            }
        }

        // MARK: - Line metrics

        private struct Line {
            var hardBreak: Bool
            var ascent, descent, unscaledAscent, height, width, left, baseline: Double
            var lineNumber: Int32
        }

        private func line(_ index: UInt32) -> Line? {
            guard skHandle != 0 else { return nil }
            let metrics = paragraph_getLineMetricsAtIndex(skHandle, index)
            guard metrics != 0 else { return nil }
            defer { lineMetrics_dispose(metrics) }
            let ascent = Double(lineMetrics_getAscent(metrics))
            let descent = Double(lineMetrics_getDescent(metrics))
            return Line(
                hardBreak: lineMetrics_getHardBreak(metrics),
                ascent: ascent,
                descent: descent,
                unscaledAscent: Double(lineMetrics_getUnscaledAscent(metrics)),
                // Not skwasm's own height: the native bridge, following
                // paragraph.cc, reports round(ascent + descent).
                height: (ascent + descent).rounded(),
                width: Double(lineMetrics_getWidth(metrics)),
                left: Double(lineMetrics_getLeft(metrics)),
                baseline: Double(lineMetrics_getBaseline(metrics)),
                lineNumber: lineMetrics_getLineNumber(metrics))
        }

        /// Nine doubles a line: hard break, ascent, descent, unscaled ascent,
        /// height, width, left, baseline, line number.
        public func ComputeLineMetrics(
            _ out_data: UnsafeMutablePointer<Double>?, _ out_count: UnsafeMutablePointer<Int>?,
            _ max_lines: Int
        ) {
            out_count?.pointee = 0
            guard skHandle != 0, let out_data else { return }
            let count = min(Int(paragraph_getLineCount(skHandle)), max_lines)
            var written = 0
            for index in 0..<max(count, 0) {
                guard let line = line(UInt32(index)) else { break }
                let at = out_data + written * 9
                at[0] = line.hardBreak ? 1 : 0
                at[1] = line.ascent
                at[2] = line.descent
                at[3] = line.unscaledAscent
                at[4] = line.height
                at[5] = line.width
                at[6] = line.left
                at[7] = line.baseline
                at[8] = Double(line.lineNumber)
                written += 1
            }
            out_count?.pointee = written
        }

        public func ComputeLineMetricsCount() -> Int {
            skHandle == 0 ? 0 : Int(paragraph_getLineCount(skHandle))
        }

        public func GetLineMetricsAt(
            _ line_number: Int32,
            _ out_hard_break: UnsafeMutablePointer<Bool>?,
            _ out_ascent: UnsafeMutablePointer<Double>?,
            _ out_descent: UnsafeMutablePointer<Double>?,
            _ out_unscaled_ascent: UnsafeMutablePointer<Double>?,
            _ out_height: UnsafeMutablePointer<Double>?,
            _ out_width: UnsafeMutablePointer<Double>?,
            _ out_left: UnsafeMutablePointer<Double>?,
            _ out_baseline: UnsafeMutablePointer<Double>?,
            _ out_line_number: UnsafeMutablePointer<Int32>?
        ) -> Bool {
            guard line_number >= 0, let line = line(UInt32(line_number)) else { return false }
            out_hard_break?.pointee = line.hardBreak
            out_ascent?.pointee = line.ascent
            out_descent?.pointee = line.descent
            out_unscaled_ascent?.pointee = line.unscaledAscent
            out_height?.pointee = line.height
            out_width?.pointee = line.width
            out_left?.pointee = line.left
            out_baseline?.pointee = line.baseline
            out_line_number?.pointee = line.lineNumber
            return true
        }

        public func GetLineNumberAt(_ code_unit_offset: Int) -> Int32 {
            guard skHandle != 0, code_unit_offset >= 0 else { return -1 }
            return paragraph_getLineNumberAt(skHandle, UInt32(code_unit_offset))
        }

        // MARK: - Painting

        public func Paint(_ canvas_bridge: CanvasBridge?, _ x: Double, _ y: Double) {
            guard skHandle != 0, let canvas = canvas_bridge, canvas.skHandle != 0 else { return }
            canvas_drawParagraph(canvas.skHandle, skHandle, Float(x), Float(y))
        }

        // MARK: - Lifecycle

        public func Dispose() {
            guard skHandle != 0 else { return }
            paragraph_dispose(skHandle)
            skHandle = 0
        }

        public func IsDisposed() -> Bool { skHandle == 0 }
    }
}
