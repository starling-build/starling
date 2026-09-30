// Fonts: font_collection_bridge.h, over skwasm's fonts.cpp.
import CSkwasm

/// The one font collection every paragraph on the page is built against.
///
/// The native bridge keeps two (the engine's and a standalone one for
/// measuring before an engine exists) and registers each face in both. Here
/// there is no engine, so there is one. skwasm cannot see system fonts: a
/// family resolves only if its bytes were registered here first.
public enum WebFonts {
    /// A FlutterFontCollection*, created on first use and never disposed.
    public static let collection: sk_ptr = fontCollection_create()

    /// Registers one font file. `family` nil or empty means the family name
    /// inside the file.
    public static func register(bytes: UnsafeRawPointer, count: Int, family: String?) -> Bool {
        guard count > 0 else { return false }
        let data = skData_create(UInt32(count))
        guard data != 0 else { return false }
        starling_host_write(skData_getPointer(data), bytes, UInt32(count))
        return register(data: data, family: family)
    }

    /// Registers a font whose bytes are already an SkData in skwasm's memory
    /// (the page fetches a font straight into one). Takes over the caller's
    /// reference to `data`.
    public static func register(data: sk_ptr, family: String?) -> Bool {
        guard data != 0 else { return false }
        // The typeface holds its own reference to the bytes, and the
        // collection its own to the typeface, so ours can go as soon as each
        // has been handed on. typeface_create returns 0 for bytes that are
        // not a font.
        let typeface = typeface_create(data)
        skData_dispose(data)
        guard typeface != 0 else { return false }

        if let family, !family.isEmpty {
            let name = makeSkString(family)
            fontCollection_registerTypeface(collection, typeface, name)
            skString_free(name)
        } else {
            fontCollection_registerTypeface(collection, typeface, 0)
        }
        typeface_dispose(typeface)

        // Resolved families are cached; without this a family that missed
        // before the font arrived keeps missing.
        fontCollection_clearCaches(collection)
        return true
    }
}

extension flutter.swift_bridge {
    public static func LoadFontFromList(
        _ data: UnsafePointer<UInt8>?, _ length: Int, _ family_name: UnsafePointer<CChar>?
    ) -> Bool {
        guard let data, length > 0 else { return false }
        let family = family_name.map { String(cString: $0) }
        return WebFonts.register(bytes: UnsafeRawPointer(data), count: length, family: family)
    }

    public static func LoadFontFromFile(
        _ path: UnsafePointer<CChar>?, _ family_name: UnsafePointer<CChar>?
    ) -> Bool {
        // WEB-TODO: there is no filesystem to map a font from. A caller that
        // has a path needs the page to fetch the file and hand the bytes to
        // WebFonts.register; until then this reports failure, which callers
        // already treat as "font unavailable".
        false
    }

    public static func ClearFontFamilyCache() {
        fontCollection_clearCaches(WebFonts.collection)
    }
}
