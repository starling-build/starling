// Which character scripts a page's text uses, so the page can fetch the font
// files that are their glyph fallback (docs/plans/web-lazy-fonts.md). Named
// families already load by request_font; this is for characters in a run whose
// family names no face for them (Chinese text in Calibri).

public enum ScriptFonts {
    private nonisolated(unsafe) static var requested: Set<String> = []

    /// The script (Resources/fonts/fonts.tsv's names) a scalar needs a face for,
    /// or nil when the page's eager faces cover it (Latin, Greek, Cyrillic).
    /// Han is taken as Simplified Chinese (cjk-sc), kana as Japanese, Hangul as
    /// Korean: the first face whose file serves the whole CJK block.
    static func script(of value: UInt32) -> String? {
        switch value {
        case 0x0590 ... 0x05FF, 0xFB1D ... 0xFB4F: return "hebrew"
        case 0x0600 ... 0x06FF, 0x0750 ... 0x077F, 0x08A0 ... 0x08FF, 0xFB50 ... 0xFDFF, 0xFE70 ... 0xFEFF: return "arabic"
        case 0x0900 ... 0x097F: return "devanagari"
        case 0x0E00 ... 0x0E7F: return "thai"
        case 0x1100 ... 0x11FF, 0x3130 ... 0x318F, 0xAC00 ... 0xD7AF: return "cjk-kr"
        case 0x3040 ... 0x30FF, 0x31F0 ... 0x31FF: return "cjk-jp"
        case 0x2E80 ... 0x2FDF, 0x3100 ... 0x312F, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF,
             0xFF00 ... 0xFFEF, 0x20000 ... 0x2FA1F: return "cjk-sc"
        case 0x1F000 ... 0x1FAFF: return "emoji"
        default: return nil
        }
    }

    /// Asks the page, once per script, for the file(s) behind any script in `text`.
    public static func request(for text: String) {
        // (ASCII is nearly all of it; skip the scan.)
        if text.utf8.allSatisfy({ $0 < 0x80 }) { return }
        for scalar in text.unicodeScalars {
            guard scalar.value >= 0x0590, let name = script(of: scalar.value), requested.insert(name).inserted else { continue }
            let bytes = Array(name.utf8)
            bytes.withUnsafeBytes { starling_host_request_script($0.baseAddress, UInt32($0.count)) }
        }
    }
}
