import Flutter
import FlutterSwiftBridge

extension RichLayout {
    // Yu Gothic Regular and Bold, Basic Latin advances (units of 2048 per em) read from the hmtx of the subsets embedded in Word's prints
    // (dx2): the face Word draws Latin letters, digits and most punctuation in, inside Devanagari paragraphs whose runs name Arial Unicode MS
    // (a face Windows lacks). Characters the prints never used keep the stand-in's width.
    static let yuGothicRegular: [UInt32: Int] = [
        0x21: 680, 0x22: 834, 0x24: 1184, 0x25: 1642, 0x27: 457, 0x29: 791, 0x2B: 1483, 0x2C: 528, 0x2D: 891, 0x2E: 528,
        0x2F: 991, 0x30: 1139, 0x31: 1139, 0x32: 1139, 0x33: 1139, 0x34: 1139, 0x35: 1139, 0x36: 1139, 0x37: 1139, 0x38: 1139,
        0x39: 1139, 0x3A: 582, 0x3C: 1483, 0x3D: 1483, 0x3E: 1483, 0x3F: 1065, 0x41: 1329, 0x42: 1391, 0x43: 1397, 0x44: 1526,
        0x45: 1268, 0x46: 1245, 0x47: 1487, 0x48: 1526, 0x49: 598, 0x4A: 819, 0x4B: 1417, 0x4C: 1223, 0x4D: 1882, 0x4E: 1532,
        0x4F: 1499, 0x50: 1354, 0x51: 1499, 0x52: 1370, 0x53: 1286, 0x54: 1288, 0x55: 1511, 0x56: 1329, 0x57: 1905, 0x59: 1329,
        0x5A: 1264, 0x5C: 1169, 0x5F: 1024, 0x61: 1143, 0x62: 1188, 0x63: 1057, 0x64: 1184, 0x65: 1143, 0x66: 707, 0x67: 1122,
        0x68: 1188, 0x69: 537, 0x6A: 602, 0x6B: 1085, 0x6C: 537, 0x6D: 1763, 0x6E: 1188, 0x6F: 1149, 0x70: 1188, 0x71: 1184,
        0x72: 745, 0x73: 1042, 0x74: 721, 0x75: 1190, 0x76: 1001, 0x77: 1589, 0x78: 1001, 0x79: 1008, 0x7A: 942, 0x7B: 791,
        0x7D: 791, 0x7E: 1450,
    ]
    static let yuGothicBold: [UInt32: Int] = [
        0x21: 737, 0x22: 903, 0x29: 823, 0x2A: 1038, 0x2C: 571, 0x31: 1174, 0x42: 1452, 0x44: 1581, 0x4D: 1950, 0x52: 1432,
        0x53: 1350, 0x61: 1192, 0x64: 1257, 0x65: 1204, 0x67: 1190, 0x69: 586, 0x6C: 590, 0x6D: 1866, 0x6E: 1266, 0x6F: 1214,
        0x70: 1255, 0x72: 803, 0x73: 1092, 0x74: 778, 0x75: 1266, 0x76: 1092, 0x79: 1092,
    ]
    /// The style `base` with letter spacing that gives the piece Yu Gothic's advances, "(" and spaces Leelawadee UI's.
    @inline(never)
    static func _yuLatinStyle(_ w: Substring, base: TextStyle) -> TextStyle? {
        guard let px = base.fontSize, px > 0.5 else { return nil }
        let bold = base.fontWeight == .bold
        let table = bold ? yuGothicBold : yuGothicRegular
        var sum = 0.0, known = "", rest = false, yu = false
        for u in w.unicodeScalars {
            if u.value == 0x20 { sum += bold ? 0.274 * 1.07 : 0.274; known.unicodeScalars.append(u) }
            else if u.value == 0x28, let a = TamilAdvances.leela[u.value] { sum += bold ? a * 1.07 : a; known.unicodeScalars.append(u) }
            else if let a = table[u.value] { sum += Double(a) / 2048; known.unicodeScalars.append(u); yu = true }
            else { rest = true }
        }
        if !yu { return nil }
        func measure(_ text: Substring, _ ls: Double) -> Double {
            let t = TextPainter(text: TextSpan(text: String(text), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w0 = measure(w, 0)
        guard w0 > 0.01 else { return nil }
        let n = max(1, Int((measure(w, 10) - w0) / 10 + 0.5))
        let other = rest ? w0 - measure(Substring(known), 0) : 0
        return base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (sum * px + other - w0) / Double(n))
    }
}

extension RichLayout {
    /// Latin text in a Devanagari run that names Arial Unicode MS: Yu Gothic's advances where Word draws it in Yu Gothic, else Leelawadee UI's.
    @inline(never)
    static func _arialUnicodeLatin(_ w: Substring, base: TextStyle) -> TextStyle {
        _yuLatinStyle(w, base: base) ?? _leelaLatinStyle(w, base: base)
    }
}
