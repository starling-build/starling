import AppKit
import CoreText

// ---- A minimal retained node tree: layout nodes (no layer), content nodes (CALayer).

class Node {
    var children: [Node] = []
    var size: CGSize = .zero
    var origin: CGPoint = .zero          // relative to parent
    var absOrigin: CGPoint = .zero       // resolved at commit
    var needsLayout = true
    var needsPaint = true
    var layer: CALayer? { nil }
    init(_ children: [Node] = []) { self.children = children }
    func layout(maxWidth: CGFloat) { }
    /// Apply node state to its layer. Only content nodes override.
    func apply(scale: CGFloat) { }
}

final class Column: Node {
    let spacing: CGFloat
    init(spacing: CGFloat = 8, _ children: [Node]) { self.spacing = spacing; super.init(children) }
    override func layout(maxWidth: CGFloat) {
        var y: CGFloat = 0; var w: CGFloat = 0
        for c in children {
            c.layout(maxWidth: maxWidth)
            c.origin = CGPoint(x: 0, y: y)
            y += c.size.height + spacing; w = max(w, c.size.width)
        }
        size = CGSize(width: w, height: max(0, y - spacing)); needsLayout = false
    }
}

final class Row: Node {
    let spacing: CGFloat
    init(spacing: CGFloat = 8, _ children: [Node]) { self.spacing = spacing; super.init(children) }
    override func layout(maxWidth: CGFloat) {
        var x: CGFloat = 0; var h: CGFloat = 0
        for c in children {
            c.layout(maxWidth: maxWidth)
            c.origin = CGPoint(x: x, y: 0)
            x += c.size.width + spacing; h = max(h, c.size.height)
        }
        size = CGSize(width: max(0, x - spacing), height: h); needsLayout = false
    }
}

/// Content node resolved to layer properties: background, corner radius, border, shadow.
final class Box: Node {
    let _layer = CALayer()
    var color: NSColor; var radius: CGFloat; var padding: CGFloat; var fixed: CGSize?
    init(color: NSColor, radius: CGFloat = 8, padding: CGFloat = 12, fixed: CGSize? = nil, _ child: Node? = nil) {
        self.color = color; self.radius = radius; self.padding = padding; self.fixed = fixed
        super.init(child.map { [$0] } ?? [])
        _layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "backgroundColor": NSNull(), "cornerRadius": NSNull(), "transform": NSNull()]
    }
    override var layer: CALayer? { _layer }
    override func layout(maxWidth: CGFloat) {
        if let f = fixed { size = f; children.first?.layout(maxWidth: f.width - 2*padding) }
        else if let c = children.first {
            c.layout(maxWidth: maxWidth - 2*padding)
            c.origin = CGPoint(x: padding, y: padding)
            size = CGSize(width: c.size.width + 2*padding, height: c.size.height + 2*padding)
        } else { size = CGSize(width: 2*padding, height: 2*padding) }
        needsLayout = false
    }
    override func apply(scale: CGFloat) {
        _layer.backgroundColor = color.cgColor
        _layer.cornerRadius = radius
        needsPaint = false
    }
}

/// Content node resolved to a CoreText bitmap.
final class Label: Node {
    let _layer = CALayer()
    var text: String; var font: NSFont; var color: NSColor
    private var line: CTLine?
    private var ascent: CGFloat = 0, descent: CGFloat = 0
    init(_ text: String, size: CGFloat = 15, weight: NSFont.Weight = .regular, color: NSColor = NSColor(white: 0.1, alpha: 1)) {
        self.text = text; self.font = NSFont.systemFont(ofSize: size, weight: weight); self.color = color
        super.init()
        _layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "contents": NSNull()]
    }
    override var layer: CALayer? { _layer }
    override func layout(maxWidth: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var a: CGFloat = 0, d: CGFloat = 0, lead: CGFloat = 0
        let w = CTLineGetTypographicBounds(l, &a, &d, &lead)
        line = l; ascent = a; descent = d
        size = CGSize(width: ceil(CGFloat(w)), height: ceil(a + d)); needsLayout = false
    }
    /// Rasterize on the calling queue; the caller decides whether that is the raster queue.
    func rasterize(scale: CGFloat) -> CGImage? {
        guard let line, size.width > 0, size.height > 0 else { return nil }
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsFontSmoothing(true); ctx.setShouldSmoothFonts(true)
        ctx.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, ctx)
        return ctx.makeImage()
    }
    override func apply(scale: CGFloat) {
        _layer.contents = rasterize(scale: scale)
        _layer.contentsScale = scale
        _layer.contentsGravity = .bottomLeft
        needsPaint = false
    }
}
