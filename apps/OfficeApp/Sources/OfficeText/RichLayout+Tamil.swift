// Tamil in Word for Windows: widths of Nirmala UI, per code point (em).
// Not read from glyph advances (our PDF embeds no Tamil face to compare, and the
// shaped clusters have no code point): a regression of the widths of 2864 Tamil
// words in the Word prints of four Tamil documents (all set in Nirmala UI), each
// word the sum of its code points' advances; the fit is within 1.7% per word.
// Vowel signs and the virama come out near zero, where the stand-in gives them
// full advances. Bold: 37 points fitted; one missing there takes the regular
// width +6% (the measured mean Bold/regular ratio).
enum TamilAdvances {
    static let regular: [UInt32: Double] = [
        0xB83: 0.795, 0xB85: 1.122, 0xB86: 1.296, 0xB87: 1.054, 0xB88: 0.720, 0xB89: 1.078, 0xB8A: 1.423,
        0xB8E: 0.788, 0xB8F: 0.819, 0xB90: 0.949, 0xB92: 0.972, 0xB93: 0.858, 0xB95: 0.875, 0xB99: 1.082,
        0xB9A: 0.795, 0xB9C: 0.888, 0xB9E: 1.104, 0xB9F: 0.843, 0xBA3: 1.663, 0xBA4: 0.866, 0xBA8: 0.798,
        0xBA9: 1.241, 0xBAA: 0.820, 0xBAE: 0.954, 0xBAF: 0.984, 0xBB0: 0.739, 0xBB1: 0.902, 0xBB2: 1.010,
        0xBB3: 1.060, 0xBB4: 0.974, 0xBB5: 0.985, 0xBB7: 1.303, 0xBB8: 1.243, 0xBB9: 1.574, 0xBBE: 0.680,
        0xBBF: 0.227, 0xBC0: 0.005, 0xBC1: 0.203, 0xBC2: 0.273, 0xBC6: 0.909, 0xBC7: 0.739, 0xBC8: 1.211,
        0xBCA: 0.647, 0xBCB: 0.664, 0xBCD: 0.007,
    ]
    static let bold: [UInt32: Double] = [
        0xB85: 1.158, 0xB86: 1.289, 0xB87: 1.169, 0xB8A: 1.317, 0xB8E: 0.822, 0xB92: 1.086, 0xB95: 0.932,
        0xB99: 1.110, 0xB9A: 0.847, 0xB9C: 0.993, 0xB9E: 1.253, 0xB9F: 0.812, 0xBA3: 1.722, 0xBA4: 0.925,
        0xBA8: 0.868, 0xBA9: 1.307, 0xBAA: 0.873, 0xBAE: 1.016, 0xBAF: 1.065, 0xBB0: 0.786, 0xBB1: 0.948,
        0xBB2: 1.053, 0xBB3: 1.122, 0xBB4: 0.945, 0xBB5: 1.064, 0xBB8: 1.443, 0xBBE: 0.780, 0xBBF: 0.289,
        0xBC0: 0, 0xBC1: 0.189, 0xBC2: 0.308, 0xBC6: 0.873, 0xBC7: 0.744, 0xBC8: 1.244, 0xBCA: 0.681,
        0xBCB: 0.710, 0xBCD: 0.031,
    ]
    // Leelawadee UI, the face Word for Windows draws Tamil documents' Latin letters, digits and punctuation in: advances (em) read from
    // the hmtx of the subsets embedded in the Tamil prints (dx2). Letters the prints never used keep the stand-in's width.
    static let leela: [UInt32: Double] = [
        0x21: 0.284, 0x22: 0.392, 0x28: 0.302, 0x29: 0.302, 0x2C: 0.217, 0x2D: 0.4, 0x2E: 0.217, 0x2F: 0.39, 0x30: 0.539, 0x31: 0.539,
        0x32: 0.539, 0x33: 0.539, 0x34: 0.539, 0x35: 0.539, 0x36: 0.539, 0x3A: 0.217, 0x3C: 0.684, 0x3E: 0.684, 0x41: 0.645, 0x42: 0.573,
        0x43: 0.619, 0x44: 0.701, 0x45: 0.506, 0x46: 0.488, 0x48: 0.71, 0x4C: 0.471, 0x4D: 0.898, 0x4E: 0.748, 0x4F: 0.754, 0x50: 0.56,
        0x51: 0.754, 0x52: 0.598, 0x53: 0.531, 0x54: 0.524, 0x57: 0.934, 0x58: 0.59, 0x5B: 0.302, 0x5D: 0.302, 0x61: 0.509, 0x63: 0.462,
        0x64: 0.589, 0x65: 0.523, 0x66: 0.313, 0x67: 0.589, 0x68: 0.566, 0x69: 0.242, 0x6A: 0.242, 0x6B: 0.497, 0x6C: 0.242, 0x6D: 0.861,
        0x6E: 0.566, 0x6F: 0.586, 0x70: 0.588, 0x72: 0.348, 0x73: 0.424, 0x74: 0.339, 0x75: 0.566, 0x76: 0.479, 0x77: 0.723, 0x79: 0.484,
        0x7C: 0.239,
    ]
    // Vijaya, per code point (em), from the hmtx of the Vijaya subsets embedded in the print of dx2 c30a7a61.
    // Only the code points that print used; others take the Nirmala UI width x 0.793 (PROVISIONAL scale).
    static let vijayaRegular: [UInt32: Double] = [
        0xB85: 0.887, 0xB87: 0.913, 0xB89: 0.75, 0xB8E: 0.663, 0xB8F: 0.663, 0xB95: 0.572, 0xB99: 0.744, 0xB9A: 0.49, 0xB9F: 0.772,
        0xBA3: 1.122, 0xBA4: 0.577, 0xBA8: 0.554, 0xBA9: 0.864, 0xBAA: 0.672, 0xBAE: 0.735, 0xBAF: 0.708, 0xBB0: 0.454, 0xBB1: 0.62,
        0xBB2: 0.771, 0xBB3: 0.784, 0xBB5: 0.824, 0xBBE: 0.452, 0xBC6: 0.716, 0xBC7: 0.638, 0xBC8: 0.865, 0xBCD: 0,
    ]
    static let vijayaBold: [UInt32: Double] = [
        0xB95: 0.599, 0xB99: 0.713, 0xB9A: 0.514, 0xB9F: 0.724, 0xBA4: 0.589, 0xBAA: 0.645, 0xBAE: 0.67, 0xBAF: 0.668, 0xBB1: 0.622,
        0xBB2: 0.715, 0xBB3: 0.8, 0xBB5: 0.806, 0xBBE: 0.452, 0xBC6: 0.753, 0xBC7: 0.603, 0xBC8: 0.809, 0xBCD: 0,
    ]
    /// The width in em of a word's characters that the table has, and the others
    /// (punctuation, digits, joiners) as the characters not in it.
    static func split(_ word: Substring, bold isBold: Bool, vijaya: Bool = false, leelawadee: Bool = false) -> (ems: Double, known: String, rest: Bool)? {
        var sum = 0.0, known = String.UnicodeScalarView(), rest = false, any = false
        for u in word.unicodeScalars {
            if vijaya, let w = (isBold ? vijayaBold : vijayaRegular)[u.value] { sum += w; known.append(u); any = true; continue }
            let k = vijaya ? 0.793 : 1.0
            if isBold, let w = bold[u.value] { sum += w * k; known.append(u); any = true }
            else if let w = regular[u.value] { sum += (isBold ? w * 1.06 : w) * k; known.append(u); any = true }
            else if leelawadee, let w = leela[u.value] { sum += isBold ? w * 1.07 : w; known.append(u); any = true }
            else { rest = true }
        }
        return any ? (sum, String(known), rest) : nil
    }
}
