// Building text: paragraph_builder_bridge.h, over skwasm's text/*.cpp.
//
// The Swift side hands over styles the way dart:ui hands them to the engine:
// an Int32 array whose first element is a mask of which fields are set, with
// the floats and strings beside it and the lists packed into bytes. The
// native bridge decodes that into a txt::TextStyle; this decodes the same
// buffers into calls on a Skwasm::TextStyle.
import CSkwasm

extension WebFonts {
    /// Families tried after the ones a style names, in every paragraph.
    ///
    /// On the desktop a family nobody registered falls through to a system
    /// font. skwasm has no system fonts and its collection's default family
    /// ("Roboto") resolves only if a font was registered under that name, so
    /// a style naming only families the page never loaded would draw nothing
    /// at all. Whoever loads the page's text font names it here.
    public nonisolated(unsafe) static var fallbackFamilies: [String] = []

    /// skwasm's collection was created with this as its default family
    /// (fonts.cpp): what a style with no family gets. The page registers
    /// its UI face under this name too.
    public static let defaultFamily = "Roboto"

    /// The family list a style is given: its own, then the fallbacks. A
    /// style with no family of its own must still lead with the default,
    /// because skparagraph consults the collection's default only for an
    /// EMPTY list — with fallbacks alone appended, the first fallback would
    /// become the face of every unstyled run.
    static func familiesWithFallbacks(_ families: [String]) -> [String] {
        var all = families.isEmpty && !fallbackFamilies.isEmpty ? [defaultFamily] : families
        for family in fallbackFamilies where !all.contains(family) { all.append(family) }
        return all
    }
}

/// A text style with every inherited field resolved, as the builder's stack
/// holds it.
///
/// skwasm can copy a native style and set fields on the copy, which is how
/// Flutter's web engine inherits. It cannot express what the native bridge
/// does, though: there is no export that clears shadows, and setting a weight
/// always sets the slant with it. So inheritance happens here, on values, and
/// each push builds its native style from nothing.
private struct ResolvedTextStyle {
    struct Shadow {
        var color: UInt32
        var x, y, blurSigma: Float
    }

    var color: UInt32?
    var decoration: Int32?
    var decorationColor: UInt32?
    var decorationStyle: Int32?
    var decorationThickness: Float?
    // FontWeight.w400, upright.
    var weight: Int32 = 400
    var slant: Int32 = 0
    var hasFontStyle = false
    var baseline: Int32?
    var families: [String] = []
    var fontSize: Float?
    var letterSpacing: Float?
    var wordSpacing: Float?
    var height: Float?
    var halfLeading: Bool?
    var locale: String?
    var background: UInt32?
    var foreground: UInt32?
    var shadows: [Shadow] = []
    var features: [(tag: String, value: Int32)] = []
    var variations: [(tag: UInt32, value: Float)] = []

    /// A new Skwasm::TextStyle*; the caller disposes it.
    func makeNative() -> sk_ptr {
        let style = textStyle_create()
        if let color { textStyle_setColor(style, color) }
        if let decoration { textStyle_setDecoration(style, decoration) }
        if let decorationColor { textStyle_setDecorationColor(style, decorationColor) }
        if let decorationStyle { textStyle_setDecorationStyle(style, decorationStyle) }
        if let decorationThickness { textStyle_setDecorationThickness(style, decorationThickness) }
        if hasFontStyle { textStyle_setFontStyle(style, weight, slant) }
        if let baseline { textStyle_setTextBaseline(style, baseline) }

        withSkStrings(WebFonts.familiesWithFallbacks(families)) {
            textStyle_addFontFamilies(style, $0, $1)
        }

        if let fontSize { textStyle_setFontSize(style, fontSize) }
        if let letterSpacing { textStyle_setLetterSpacing(style, letterSpacing) }
        if let wordSpacing { textStyle_setWordSpacing(style, wordSpacing) }
        if let height { textStyle_setHeight(style, height) }
        if let halfLeading { textStyle_setHalfLeading(style, halfLeading) }
        if let locale {
            let s = makeSkString(locale)
            textStyle_setLocale(style, s)
            skString_free(s)
        }
        if let background {
            let paint = makePlainPaint(background)
            textStyle_setBackground(style, paint)
            paint_dispose(paint)
        }
        if let foreground {
            let paint = makePlainPaint(foreground)
            textStyle_setForeground(style, paint)
            paint_dispose(paint)
        }
        for shadow in shadows {
            textStyle_addShadow(style, shadow.color, shadow.x, shadow.y, shadow.blurSigma)
        }
        for feature in features {
            let name = makeSkString(feature.tag)
            textStyle_addFontFeature(style, name, feature.value)
            skString_free(name)
        }
        if !variations.isEmpty {
            withSkStack { stack in
                textStyle_setFontVariations(
                    style, stack.array(variations.map(\.tag)),
                    stack.array(variations.map(\.value)), Int32(variations.count))
            }
        }
        return style
    }
}

/// A fill of one colour: what a default-constructed paint with its colour
/// set is. Blend mode 3 is srcOver; miter limit 4 is the default.
private func makePlainPaint(_ color: UInt32) -> sk_ptr {
    paint_create(true, 3, color, 0, 0, 0, 0, 4, false)
}

/// Calls `body` with an array of SkString* on skwasm's stack, then frees the
/// strings. Not called at all for an empty list.
private func withSkStrings(_ strings: [String], _ body: (sk_ptr, Int32) -> Void) {
    guard !strings.isEmpty else { return }
    let handles = strings.map(makeSkString)
    withSkStack { stack in body(stack.pointers(handles), Int32(handles.count)) }
    handles.forEach(skString_free)
}

private func strings(
    _ pointers: UnsafePointer<UnsafePointer<CChar>?>?, _ count: Int
) -> [String] {
    guard let pointers, count > 0 else { return [] }
    return (0..<count).compactMap { index in pointers[index].map { String(cString: $0) } }
}

/// A C string that is present and not empty. The Swift side passes "" for
/// "not set".
private func text(_ pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer, pointer.pointee != 0 else { return nil }
    return String(cString: pointer)
}

/// dart:ui encodes a FontWeight as its index, w100 = 0 ... w900 = 8; Skia
/// takes the weight itself.
private func weight(fromIndex index: Int32) -> Int32 {
    (min(max(index, 0), 8) + 1) * 100
}

extension flutter.swift_bridge {
    public final class ParagraphBuilderBridge {
        /// The Skwasm::ParagraphBuilder*. 0 once built, after which every
        /// method does nothing, as the native bridge's do.
        public private(set) var skHandle: sk_ptr

        /// The style in force, innermost last. The first entry is the
        /// paragraph style's own text style and is never popped.
        private var styles: [ResolvedTextStyle]

        // MARK: - ParagraphStyle

        // Indices into the encoded paragraph style; a field is set when its
        // bit (1 << index) is in element 0.
        private static let psTextAlign: Int32 = 1 << 1
        private static let psTextDirection: Int32 = 1 << 2
        private static let psFontWeight: Int32 = 1 << 3
        private static let psFontStyle: Int32 = 1 << 4
        private static let psMaxLines: Int32 = 1 << 5
        private static let psTextHeightBehavior: Int32 = 1 << 6

        public init(
            _ encoded_style: UnsafePointer<Int32>?,
            _ encoded_style_length: Int,
            _ font_family: UnsafePointer<CChar>?,
            _ font_size: Double,
            _ height: Double,
            _ ellipsis: UnsafePointer<CChar>?,
            _ locale: UnsafePointer<CChar>?,
            _ strut_data: UnsafePointer<UInt8>?,
            _ strut_data_length: Int,
            _ strut_font_families: UnsafePointer<UnsafePointer<CChar>?>?,
            _ strut_font_families_count: Int
        ) {
            let paragraphStyle = paragraphStyle_create()
            var base = ResolvedTextStyle()

            if let encoded = encoded_style, encoded_style_length >= 7 {
                let mask = encoded[0]
                if mask & Self.psTextAlign != 0 {
                    paragraphStyle_setTextAlign(paragraphStyle, encoded[1])
                }
                if mask & Self.psTextDirection != 0 {
                    paragraphStyle_setTextDirection(paragraphStyle, encoded[2])
                }
                if mask & (Self.psFontWeight | Self.psFontStyle) != 0 {
                    base.hasFontStyle = true
                    if mask & Self.psFontWeight != 0 { base.weight = weight(fromIndex: encoded[3]) }
                    if mask & Self.psFontStyle != 0 { base.slant = encoded[4] }
                }
                if mask & Self.psMaxLines != 0, encoded[5] >= 0 {
                    paragraphStyle_setMaxLines(paragraphStyle, UInt32(encoded[5]))
                }
                if mask & Self.psTextHeightBehavior != 0 {
                    // Bit 0 set means "do not apply to the first ascent",
                    // bit 1 the same for the last descent.
                    paragraphStyle_setTextHeightBehavior(
                        paragraphStyle, encoded[6] & 1 == 0, encoded[6] & 2 == 0)
                }
            }

            // The engine's encoding has mask bits for the fields below too
            // (7 through 12), and the native bridge tests them. The Swift
            // side never sets those bits — it passes "", 0 and an empty strut
            // for "not set" — so natively these six fields are dropped. Here
            // a value that is present is used, which is what the caller meant.
            if let family = text(font_family) { base.families = [family] }
            if font_size > 0 { base.fontSize = Float(font_size) }
            if height != 0 {
                paragraphStyle_setHeight(paragraphStyle, Float(height))
                base.height = Float(height)
            }
            if let ellipsis = text(ellipsis) {
                let s = makeSkString(ellipsis)
                paragraphStyle_setEllipsis(paragraphStyle, s)
                skString_free(s)
            }
            if let locale = text(locale) { base.locale = locale }
            if let strut_data, strut_data_length > 0 {
                let strut = Self.makeStrut(
                    UnsafeRawBufferPointer(start: strut_data, count: strut_data_length),
                    families: strings(strut_font_families, strut_font_families_count))
                paragraphStyle_setStrutStyle(paragraphStyle, strut)
                strutStyle_dispose(strut)
            }

            let textStyle = base.makeNative()
            paragraphStyle_setTextStyle(paragraphStyle, textStyle)
            // Flutter lays out in fractional pixels everywhere; the rounding
            // hack is Skia's legacy default.
            paragraphStyle_setApplyRoundingHack(paragraphStyle, false)

            skHandle = paragraphBuilder_create(paragraphStyle, WebFonts.collection)
            styles = [base]

            // The builder copied both.
            textStyle_dispose(textStyle)
            paragraphStyle_dispose(paragraphStyle)
        }

        deinit { if skHandle != 0 { paragraphBuilder_dispose(skHandle) } }

        /// Decodes dart:ui's strut encoding: a mask byte, then one byte each
        /// for weight and slant if present, then a float each for size,
        /// height and leading if present. Two mask bits are values in
        /// themselves (3: half leading, 7: force strut height), and the
        /// families travel separately.
        private static func makeStrut(_ data: UnsafeRawBufferPointer, families: [String]) -> sk_ptr {
            let strut = strutStyle_create()
            let mask = data[0]
            var at = 1

            func byte() -> Int32? {
                guard at < data.count else { return nil }
                defer { at += 1 }
                return Int32(data[at])
            }
            func float() -> Float? {
                guard at + 4 <= data.count else { return nil }
                defer { at += 4 }
                return Float(
                    bitPattern: UInt32(
                        littleEndian: data.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
            }

            let weightIndex = mask & (1 << 0) != 0 ? byte() : nil
            let slant = mask & (1 << 1) != 0 ? byte() : nil
            if weightIndex != nil || slant != nil {
                strutStyle_setFontStyle(strut, weight(fromIndex: weightIndex ?? 3), slant ?? 0)
            }
            strutStyle_setHalfLeading(strut, mask & (1 << 3) != 0)
            if mask & (1 << 4) != 0, let size = float() { strutStyle_setFontSize(strut, size) }
            if mask & (1 << 5) != 0, let height = float() { strutStyle_setHeight(strut, height) }
            if mask & (1 << 6) != 0, let leading = float() { strutStyle_setLeading(strut, leading) }
            strutStyle_setForceStrutHeight(strut, mask & (1 << 7) != 0)

            withSkStrings(WebFonts.familiesWithFallbacks(mask & (1 << 2) != 0 ? families : [])) {
                strutStyle_setFontFamilies(strut, $0, $1)
            }
            return strut
        }

        // MARK: - TextStyle

        private static let tsLeadingDistribution: Int32 = 1 << 0
        private static let tsColor: Int32 = 1 << 1
        private static let tsDecoration: Int32 = 1 << 2
        private static let tsDecorationColor: Int32 = 1 << 3
        private static let tsDecorationStyle: Int32 = 1 << 4
        private static let tsFontWeight: Int32 = 1 << 5
        private static let tsFontStyle: Int32 = 1 << 6
        private static let tsTextBaseline: Int32 = 1 << 7
        private static let tsDecorationThickness: Int32 = 1 << 8
        private static let tsFontFamily: Int32 = 1 << 9
        private static let tsFontSize: Int32 = 1 << 10
        private static let tsLetterSpacing: Int32 = 1 << 11
        private static let tsWordSpacing: Int32 = 1 << 12
        private static let tsHeight: Int32 = 1 << 13
        private static let tsLocale: Int32 = 1 << 14
        private static let tsBackground: Int32 = 1 << 15
        private static let tsForeground: Int32 = 1 << 16
        private static let tsShadows: Int32 = 1 << 17
        private static let tsFontFeatures: Int32 = 1 << 18
        private static let tsFontVariations: Int32 = 1 << 19

        public func PushStyle(
            _ encoded_style: UnsafePointer<Int32>?,
            _ encoded_style_length: Int,
            _ font_families: UnsafePointer<UnsafePointer<CChar>?>?,
            _ font_families_count: Int,
            _ font_size: Double,
            _ letter_spacing: Double,
            _ word_spacing: Double,
            _ height: Double,
            _ decoration_thickness: Double,
            _ locale: UnsafePointer<CChar>?,
            _ shadows_data: UnsafePointer<UInt8>?,
            _ shadows_data_length: Int,
            _ font_features_data: UnsafePointer<UInt8>?,
            _ font_features_data_length: Int,
            _ font_variations_data: UnsafePointer<UInt8>?,
            _ font_variations_data_length: Int,
            _ has_background: Bool,
            _ has_foreground: Bool,
            _ background_color: UInt32,
            _ foreground_color: UInt32
        ) {
            guard skHandle != 0, let encoded = encoded_style, encoded_style_length >= 9,
                var style = styles.last
            else { return }
            let mask = encoded[0]

            // Not a "set" bit but the value: even leading or proportional.
            style.halfLeading = mask & Self.tsLeadingDistribution != 0

            if mask & Self.tsColor != 0 { style.color = UInt32(bitPattern: encoded[1]) }
            if mask & Self.tsDecoration != 0 { style.decoration = encoded[2] }
            if mask & Self.tsDecorationColor != 0 {
                style.decorationColor = UInt32(bitPattern: encoded[3])
            }
            if mask & Self.tsDecorationStyle != 0 { style.decorationStyle = encoded[4] }
            if mask & Self.tsDecorationThickness != 0 {
                style.decorationThickness = Float(decoration_thickness)
            }
            if mask & Self.tsFontWeight != 0 {
                style.weight = weight(fromIndex: encoded[5])
                style.hasFontStyle = true
            }
            if mask & Self.tsFontStyle != 0 {
                style.slant = encoded[6]
                style.hasFontStyle = true
            }
            // The native bridge leaves the baseline alone (paragraph_builder.cc
            // carries a TODO for it); skwasm has the setter, as the web engine
            // uses it.
            if mask & Self.tsTextBaseline != 0 { style.baseline = encoded[7] }
            if mask & Self.tsFontSize != 0 { style.fontSize = Float(font_size) }
            if mask & Self.tsLetterSpacing != 0 { style.letterSpacing = Float(letter_spacing) }
            if mask & Self.tsWordSpacing != 0 { style.wordSpacing = Float(word_spacing) }
            if mask & Self.tsHeight != 0 { style.height = Float(height) }
            if mask & Self.tsLocale != 0 { style.locale = locale.map { String(cString: $0) } ?? "" }

            // WEB-TODO: a foreground or background arrives as a colour only —
            // the call site (Text.swift, pushStyle) reduces the Paint to its
            // colour before calling, on every platform. When it passes the
            // whole paint, build it with the canvas family's paint decoding
            // (a `webMakePaint` hook) in place of makePlainPaint.
            if mask & Self.tsBackground != 0, has_background { style.background = background_color }
            if mask & Self.tsForeground != 0, has_foreground { style.foreground = foreground_color }

            if mask & Self.tsShadows != 0 {
                style.shadows = Self.decodeShadows(shadows_data, shadows_data_length)
            }
            if mask & Self.tsFontFamily != 0 {
                // The families named here, then the inherited ones. The
                // native bridge replaces the list outright and lets the
                // system supply a font when none of them exists; with no
                // system fonts, the enclosing style's families are the
                // nearest thing, and what Flutter's web engine falls back to.
                var families = strings(font_families, font_families_count)
                for family in style.families where !families.contains(family) {
                    families.append(family)
                }
                style.families = families
            }
            if mask & Self.tsFontFeatures != 0 {
                Self.decodeFeatures(
                    font_features_data, font_features_data_length, into: &style.features)
            }
            if mask & Self.tsFontVariations != 0 {
                Self.decodeVariations(
                    font_variations_data, font_variations_data_length, into: &style.variations)
            }

            let native = style.makeNative()
            paragraphBuilder_pushStyle(skHandle, native)
            textStyle_dispose(native)
            styles.append(style)
        }

        private static func bytes(
            _ data: UnsafePointer<UInt8>?, _ length: Int, per record: Int
        ) -> UnsafeRawBufferPointer? {
            guard let data, length > 0, length % record == 0 else { return nil }
            return UnsafeRawBufferPointer(start: data, count: length)
        }

        private static func uint32(_ data: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
            UInt32(littleEndian: data.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }

        /// Sixteen bytes a shadow: colour, x, y, blur sigma. The colour is
        /// stored XORed with opaque black, so that zeroed bytes mean the
        /// default shadow.
        private static func decodeShadows(
            _ data: UnsafePointer<UInt8>?, _ length: Int
        ) -> [ResolvedTextStyle.Shadow] {
            guard let data = bytes(data, length, per: 16) else { return [] }
            let opaqueBlack: UInt32 = 0xFF00_0000
            return stride(from: 0, to: data.count, by: 16).map { at in
                ResolvedTextStyle.Shadow(
                    color: uint32(data, at) ^ opaqueBlack,
                    x: Float(bitPattern: uint32(data, at + 4)),
                    y: Float(bitPattern: uint32(data, at + 8)),
                    blurSigma: Float(bitPattern: uint32(data, at + 12)))
            }
        }

        /// Eight bytes a feature: a four character tag, then an Int32. A tag
        /// already present takes the new value.
        private static func decodeFeatures(
            _ data: UnsafePointer<UInt8>?, _ length: Int,
            into features: inout [(tag: String, value: Int32)]
        ) {
            guard let data = bytes(data, length, per: 8) else { return }
            for at in stride(from: 0, to: data.count, by: 8) {
                let tag = String(decoding: data[at..<(at + 4)], as: UTF8.self)
                let value = Int32(bitPattern: uint32(data, at + 4))
                if let existing = features.firstIndex(where: { $0.tag == tag }) {
                    features[existing].value = value
                } else {
                    features.append((tag, value))
                }
            }
        }

        /// Eight bytes a variation: a four character axis tag, then a float.
        /// Skia takes the tag as one integer, first character in the high
        /// byte.
        private static func decodeVariations(
            _ data: UnsafePointer<UInt8>?, _ length: Int,
            into variations: inout [(tag: UInt32, value: Float)]
        ) {
            guard let data = bytes(data, length, per: 8) else { return }
            for at in stride(from: 0, to: data.count, by: 8) {
                let tag =
                    UInt32(data[at]) << 24 | UInt32(data[at + 1]) << 16
                    | UInt32(data[at + 2]) << 8 | UInt32(data[at + 3])
                let value = Float(bitPattern: uint32(data, at + 4))
                if let existing = variations.firstIndex(where: { $0.tag == tag }) {
                    variations[existing].value = value
                } else {
                    variations.append((tag, value))
                }
            }
        }

        public func Pop() {
            guard skHandle != 0, styles.count > 1 else { return }
            styles.removeLast()
            paragraphBuilder_pop(skHandle)
        }

        // MARK: - Content

        public func AddTextSafe(_ text: UnsafePointer<CChar>?) -> Bool {
            guard skHandle != 0 else { return false }
            guard let text, text.pointee != 0 else { return true }
            // skwasm takes UTF-16. Decoding repairs malformed UTF-8 (U+FFFD)
            // rather than rejecting it, so there is no failure to report.
            let text16 = makeSkString16(String(cString: text))
            paragraphBuilder_addText(skHandle, text16)
            skString16_free(text16)
            return true
        }

        public func AddPlaceholder(
            _ width: Double, _ height: Double, _ alignment: Int32, _ baseline_offset: Double,
            _ baseline: Int32
        ) {
            guard skHandle != 0 else { return }
            paragraphBuilder_addPlaceholder(
                skHandle, Float(width), Float(height), alignment, Float(baseline_offset), baseline)
        }

        // MARK: - Build

        /// The builder is spent afterwards; a second call returns nil.
        public func Build() -> ParagraphBridge? {
            guard skHandle != 0 else { return nil }
            // The light skwasm build has no ICU. The page reads the text back
            // out of the builder and supplies grapheme, word and line breaks
            // from the browser; without them nothing wraps.
            starling_host_segment(skHandle)
            let paragraph = paragraphBuilder_build(skHandle)
            paragraphBuilder_dispose(skHandle)
            skHandle = 0
            styles.removeAll()
            return paragraph == 0 ? nil : ParagraphBridge(skHandle: paragraph)
        }
    }
}
