import Flutter
import FlutterSwiftBridge
import OfficeText

/// S-SH-5: Shape Effects — PowerPoint's presets for shadow, glow, reflection, soft edges and bevel, the controller
/// methods that apply them, and the file XML a save writes for them.
enum ShapeEffectPresets {
    /// Outer shadows: 4 pt blur, 3 pt out, black at 60% transparency, in the nine directions (angle clockwise from the
    /// right; nil for the centred one).
    static let shadows: [(name: String, angle: Double?)] = [
        ("Offset: Bottom Right", 45), ("Offset: Bottom", 90), ("Offset: Bottom Left", 135),
        ("Offset: Right", 0), ("Offset: Center", nil), ("Offset: Left", 180),
        ("Offset: Top Right", 315), ("Offset: Top", 270), ("Offset: Top Left", 225),
    ]

    static func shadow(angle: Double?) -> CharShadow {
        guard let a = angle else { return CharShadow(color: Color(0x66000000), dx: 0, dy: 0, blur: 5) }
        let r = a * .pi / 180
        return CharShadow(color: Color(0x66000000), dx: 3 * cos(r), dy: 3 * sin(r), blur: 4)
    }

    static let glowSizes: [Double] = [5, 8, 11, 18]
    static let softEdgeSizes: [Double] = [1, 2.5, 5, 10, 25, 50]

    /// The glow's colour: the accent at 40% opacity, as PowerPoint's gallery does.
    static func glowColor(_ accent: Color) -> Color { Color((102 << 24) | (accent.value & 0xFFFFFF)) }

    /// Office's nine reflection presets, exactly as PowerPoint writes them (blur 0.5 pt; touching, 4 pt and 8 pt below):
    /// tight, half and full. Only the first uses a start opacity of 52%; the end opacity and end position vary too.
    static let reflections: [(name: String, dist: Double, startAlpha: Double, endAlpha: Double, endPos: Double)] = [
        ("Tight Reflection, touching", 0, 0.52, 0.003, 0.35), ("Half Reflection, touching", 0, 0.50, 0.003, 0.55),
        ("Full Reflection, touching", 0, 0.50, 0.003, 0.90),
        ("Tight Reflection, 4 pt offset", 4, 0.50, 0.003, 0.385), ("Half Reflection, 4 pt offset", 4, 0.50, 0.003, 0.555),
        ("Full Reflection, 4 pt offset", 4, 0.50, 0.003, 0.90),
        ("Tight Reflection, 8 pt offset", 8, 0.50, 0.00275, 0.40), ("Half Reflection, 8 pt offset", 8, 0.50, 0.003, 0.555),
        ("Full Reflection, 8 pt offset", 8, 0.50, 0.00295, 0.92),
    ]

    static func reflection(_ r: (name: String, dist: Double, startAlpha: Double, endAlpha: Double, endPos: Double)) -> Reflection {
        Reflection(blur: 0.5, dist: r.dist, startAlpha: r.startAlpha, endAlpha: r.endAlpha, startPos: 0, endPos: r.endPos,
                   scaleY: -1, onText: false)
    }

    /// The twelve bevels of the gallery, each 6 pt wide and high.
    static let bevels: [(name: String, preset: String)] = [
        ("Circle", "circle"), ("Relaxed Inset", "relaxedInset"), ("Cross", "cross"), ("Cool Slant", "coolSlant"),
        ("Angle", "angle"), ("Soft Round", "softRound"), ("Convex", "convex"), ("Slope", "slope"),
        ("Divot", "divot"), ("Riblet", "riblet"), ("Hard Edge", "hardEdge"), ("Art Deco", "artDeco"),
    ]
}

extension DeckController {
    private func _editEffects(_ edit: (SlideShape) -> Void) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { edit(s); s.keptLook?.effectsEdited = true }
        _changed()
    }

    /// A glow of `radius` points in `color` round the selected shapes; nil radius for none.
    func setGlow(radius: Double?, color: Color?) {
        _editEffects { s in s.glowRadius = radius; s.glowColor = radius == nil ? nil : color }
    }

    /// Soft edges: the shapes fade out over `radius` points; nil for none.
    func setSoftEdge(_ radius: Double?) { _editEffects { s in s.softEdge = radius } }

    /// A reflection under the selected shapes; nil for none.
    func setReflection(_ r: Reflection?) { _editEffects { s in s.reflection = r } }

    /// A bevel on the selected shapes; nil for none.
    func setBevel(_ b: ShapeBevel?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.bevel = b; s.keptLook?.bevelEdited = true }
        _changed()
    }

    /// Shadow, glow, reflection, soft edges and bevel all off.
    func clearEffects() {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection {
            s.shadow = nil; s.glowRadius = nil; s.glowColor = nil; s.softEdge = nil; s.reflection = nil; s.bevel = nil
            s.keptLook?.effectsEdited = true; s.keptLook?.bevelEdited = true
        }
        _changed()
    }
}
