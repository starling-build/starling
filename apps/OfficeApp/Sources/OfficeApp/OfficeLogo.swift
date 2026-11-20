// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The suite's icon, drawn by the app: the badge at the left of the title
// row. It was a white tile with a letter — "W" for Writer and "S" for both
// Sheets and Slides — which matched nothing once the apps had icons, and
// told two of them apart not at all. The picture is the icon's own
// (OfficeLogoArt.swift, taken from the SVGs in build/office-gtk by
// build/tools/office-logo-swift.py), painted rather than loaded: the
// framework reads no SVG and the web build has no bundle to hold a picture.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

final class OfficeLogoPainter: CustomPainter {
    let kind: DocumentKind

    init(kind: DocumentKind) {
        self.kind = kind
        super.init()
    }

    private var art: OfficeLogoArt {
        switch kind {
        case .document: return .document
        case .presentation: return .presentation
        case .workbook: return .workbook
        }
    }

    private static func path(_ pieces: [OfficeLogoArt.Piece]) -> Path {
        let p = Path()
        for (command, n) in pieces {
            switch command {
            case "M": p.moveTo(n[0], n[1])
            case "L": p.lineTo(n[0], n[1])
            case "C": p.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5])
            default: p.close()
            }
        }
        return p
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let art = self.art
        let tile = OfficeLogoArt.tile
        // The tile, not the icon's whole box, fills the space given: the
        // SVG keeps a margin round it for a launcher's grid, and a badge
        // 32 points wide has none to spare.
        let k = min(size.width, size.height) / tile[2]
        canvas.save()
        canvas.translate((size.width - tile[2] * k) / 2, (size.height - tile[3] * k) / 2)
        canvas.scale(k, k)
        canvas.translate(-tile[0], -tile[1])

        let sky = Paint()
        sky.style = .fill
        sky.color = Color(0xFFFFFFFF)
        let g = OfficeLogoArt.gradient
        sky.shader = Gradient(linear: Offset(g[0], g[1]), to: Offset(g[2], g[3]),
                              colors: [Color(art.top), Color(art.bottom)], colorStops: [0, 1])
        canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(tile[0], tile[1], tile[2], tile[3]),
                               Radius(circular: tile[4])), sky)

        let rim = OfficeLogoArt.rim
        let edge = Paint()
        edge.style = .stroke
        edge.strokeWidth = OfficeLogoArt.rimWidth
        edge.color = Color(OfficeLogoArt.rimColor)
        canvas.drawRRect(RRect(fromRectAndRadius: Rect.fromLTWH(rim[0], rim[1], rim[2], rim[3]),
                               Radius(circular: rim[4])), edge)

        let bird = Self.path(OfficeLogoArt.bird)
        let feather = Paint()
        feather.style = .fill
        for b in art.birds {
            canvas.save()
            canvas.translate(b.x, b.y)
            canvas.rotate(b.turn * .pi / 180)
            canvas.scale(b.scale, b.scale)
            feather.color = Color(b.color)
            canvas.drawPath(bird, feather)
            canvas.restore()
        }

        let ink = Paint()
        ink.style = .stroke
        ink.strokeWidth = art.glyphWidth
        ink.strokeCap = art.roundCap ? .round : .butt
        ink.strokeJoin = art.roundJoin ? .round : .miter
        ink.color = Color(art.glyphColor)
        canvas.drawPath(Self.path(art.glyph), ink)
        canvas.restore()
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        (oldDelegate as? OfficeLogoPainter)?.kind != kind
    }
}
