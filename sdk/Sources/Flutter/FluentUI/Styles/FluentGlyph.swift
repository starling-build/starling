// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The handful of marks the Fluent controls draw for themselves — chevrons,
// check, dismiss, dot, ellipsis, the InfoBar badges — PAINTED, not typed.
//
// They used to be text: "\u{25BC}" for a chevron, "\u{2713}" for a check,
// "\u{E70D}" (a Segoe MDL2 code point) for the navigation pane's expander.
// A glyph the UI font does not carry draws as nothing, and Selawik — the
// font every Fluent theme sets — carries none of them, so expanders had no
// arrow, tree views no twisties, checked boxes no check, and drop-downs no
// chevron. Windows draws these from Segoe Fluent Icons; the framework
// cannot depend on an icon font (`FluentSystemIcons` sits above it), so it
// paints them, which also keeps them crisp at every size.

import FlutterSwiftBridge

// MARK: - FluentGlyphKind

public enum FluentGlyphKind: Sendable {
    case chevronDown, chevronUp, chevronLeft, chevronRight
    case check, dismiss, dot, more, calendar
    /// The InfoBar badges: a filled circle in the severity colour with the
    /// mark cut in `ink`.
    case info, warning, error, success
}

// MARK: - FluentGlyph

/// One painted mark in a square box of `size`.
public final class FluentGlyph: StatelessWidget {
    public let kind: FluentGlyphKind
    public let size: Double
    /// The mark's colour, or the badge's fill for the InfoBar kinds. nil is
    /// the enclosing `IconTheme`'s colour.
    public let color: Color?
    /// The mark inside a badge. nil is white.
    public let ink: Color?

    public init(
        _ kind: FluentGlyphKind,
        key: (any Key)? = nil,
        size: Double = 12,
        color: Color? = nil,
        ink: Color? = nil
    ) {
        self.kind = kind
        self.size = size
        self.color = color
        self.ink = ink
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let resolved = color ?? IconTheme.of(context).color ?? Color(0xDD000000)
        return CustomPaint(
            painter: FluentGlyphPainter(kind: kind, color: resolved, ink: ink ?? Color(0xFFFFFFFF)),
            size: Size(size, size))
    }
}

// MARK: - FluentGlyphPainter

public final class FluentGlyphPainter: CustomPainter {
    public let kind: FluentGlyphKind
    public let color: Color
    public let ink: Color

    public init(kind: FluentGlyphKind, color: Color, ink: Color) {
        self.kind = kind
        self.color = color
        self.ink = ink
        super.init()
    }

    public override func paint(_ canvas: any Canvas, _ size: Size) {
        let w = size.width, h = size.height
        let stroke = Paint()
        stroke.color = color
        stroke.style = .stroke
        stroke.strokeWidth = max(1.0, w * 0.11)
        stroke.strokeCap = .round
        stroke.strokeJoin = .round
        let fill = Paint()
        fill.color = color
        fill.style = .fill

        func polyline(_ points: [(Double, Double)], _ paint: Paint) {
            let path = Path()
            path.moveTo(points[0].0 * w, points[0].1 * h)
            for p in points.dropFirst() { path.lineTo(p.0 * w, p.1 * h) }
            canvas.drawPath(path, paint)
        }

        switch kind {
        case .chevronDown:  polyline([(0.22, 0.36), (0.5, 0.64), (0.78, 0.36)], stroke)
        case .chevronUp:    polyline([(0.22, 0.64), (0.5, 0.36), (0.78, 0.64)], stroke)
        case .chevronRight: polyline([(0.36, 0.22), (0.64, 0.5), (0.36, 0.78)], stroke)
        case .chevronLeft:  polyline([(0.64, 0.22), (0.36, 0.5), (0.64, 0.78)], stroke)
        case .check:        polyline([(0.18, 0.52), (0.42, 0.76), (0.84, 0.28)], stroke)
        case .dismiss:
            polyline([(0.22, 0.22), (0.78, 0.78)], stroke)
            polyline([(0.78, 0.22), (0.22, 0.78)], stroke)
        case .dot:
            canvas.drawCircle(Offset(w / 2, h / 2), w * 0.22, fill)
        case .more:
            for x in [0.2, 0.5, 0.8] { canvas.drawCircle(Offset(x * w, h / 2), w * 0.09, fill) }
        case .calendar:
            stroke.strokeWidth = max(1.0, w * 0.09)
            canvas.drawRect(Rect.fromLTWH(0.15 * w, 0.2 * h, 0.7 * w, 0.68 * h), stroke)
            polyline([(0.15, 0.42), (0.85, 0.42)], stroke)
            polyline([(0.34, 0.1), (0.34, 0.3)], stroke)
            polyline([(0.66, 0.1), (0.66, 0.3)], stroke)
        case .info, .warning, .error, .success:
            canvas.drawCircle(Offset(w / 2, h / 2), w * 0.48, fill)
            let mark = Paint()
            mark.color = ink
            mark.style = .stroke
            mark.strokeWidth = max(1.0, w * 0.1)
            mark.strokeCap = .round
            mark.strokeJoin = .round
            let dotPaint = Paint()
            dotPaint.color = ink
            dotPaint.style = .fill
            switch kind {
            case .info:
                canvas.drawCircle(Offset(0.5 * w, 0.3 * h), w * 0.065, dotPaint)
                polyline([(0.5, 0.45), (0.5, 0.72)], mark)
            case .warning:
                polyline([(0.5, 0.26), (0.5, 0.56)], mark)
                canvas.drawCircle(Offset(0.5 * w, 0.72 * h), w * 0.065, dotPaint)
            case .error:
                polyline([(0.33, 0.33), (0.67, 0.67)], mark)
                polyline([(0.67, 0.33), (0.33, 0.67)], mark)
            default:
                polyline([(0.28, 0.52), (0.44, 0.68), (0.72, 0.36)], mark)
            }
        }
    }

    public override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? FluentGlyphPainter else { return true }
        return old.kind != kind || old.color != color || old.ink != ink
    }
}
