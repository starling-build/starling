// Tamil in Word for Windows: widths of Nirmala UI, per code point (em), and per consonant + sign pair where the
// pair is a ligature (51 pairs, fitted on 2443 distinct words of 12 Word prints, mean error 0.57%).
// Not read from glyph advances (our PDF embeds no Tamil face to compare, and the
// shaped clusters have no code point): a regression of the widths of 2864 Tamil
// words in the Word prints of four Tamil documents (all set in Nirmala UI), each
// word the sum of its code points' advances; the fit is within 1.7% per word.
// Vowel signs and the virama come out near zero, where the stand-in gives them
// full advances. Bold: 37 points fitted; one missing there takes the regular
// width +6% (the measured mean Bold/regular ratio).
enum TamilAdvances {
    static let regular: [UInt32: Double] = [
        0xB83: 0.795, 0xB85: 1.152, 0xB86: 1.309, 0xB87: 1.054, 0xB88: 0.868, 0xB89: 1.110, 0xB8A: 1.468,
        0xB8E: 0.802, 0xB8F: 0.850, 0xB90: 0.944, 0xB92: 0.929, 0xB93: 0.936, 0xB95: 0.882, 0xB99: 1.082,
        0xB9A: 0.809, 0xB9C: 0.948, 0xB9E: 1.110, 0xB9F: 0.799, 0xBA3: 1.688, 0xBA4: 0.867, 0xBA8: 0.817,
        0xBA9: 1.236, 0xBAA: 0.852, 0xBAE: 0.953, 0xBAF: 1.016, 0xBB0: 0.707, 0xBB1: 0.898, 0xBB2: 1.004,
        0xBB3: 1.066, 0xBB4: 0.956, 0xBB5: 1.021, 0xBB7: 1.296, 0xBB8: 1.306, 0xBB9: 1.648, 0xBBE: 0.672,
        0xBBF: 0.227, 0xBC0: 0.005, 0xBC1: 0.203, 0xBC2: 0.273, 0xBC6: 0.891, 0xBC7: 0.731, 0xBC8: 1.221,
        0xBCA: 1.589, 0xBCB: 1.419, 0xBCD: 0.007,
    ]
    /// A consonant with a following vowel sign or virama (ீ ு ூ ்) as one cluster, keyed consonant<<8 | low byte of the sign: Word's
    /// ligature forms (கு, தே...) are not the sum of their parts, and a code-point table was up to 8% off on them. Fit on 2443 distinct words
    /// of 12 Word prints (mean error 0.57% per word, against 1.25% for code points alone).
    static let pairs: [UInt32: Double] = [
        0xB95C0: 0.900, 0xB95C1: 1.058, 0xB95C2: 1.268, 0xB95CD: 0.875, 0xB99CD: 1.072, 0xB9AC0: 0.852,
        0xB9AC1: 0.938, 0xB9AC2: 1.124, 0xB9ACD: 0.792, 0xB9ECD: 1.152, 0xB9FC1: 1.096, 0xB9FCD: 0.857,
        0xBA3C1: 1.753, 0xBA3CD: 1.659, 0xBA4C0: 0.875, 0xBA4C1: 1.064, 0xBA4C2: 1.385, 0xBA4CD: 0.859,
        0xBA8C0: 0.799, 0xBA8C1: 1.067, 0xBA8CD: 0.810, 0xBA9C1: 1.352, 0xBA9C2: 1.562, 0xBA9CD: 1.234,
        0xBAAC0: 0.860, 0xBAAC1: 0.863, 0xBAAC2: 1.010, 0xBAACD: 0.842, 0xBAEC0: 0.968, 0xBAEC1: 1.229,
        0xBAEC2: 1.333, 0xBAECD: 0.964, 0xBAFC1: 1.006, 0xBAFCD: 1.040, 0xBB0C1: 1.044, 0xBB0C2: 1.184,
        0xBB0CD: 0.696, 0xBB1C0: 0.863, 0xBB1C1: 1.129, 0xBB1CD: 0.910, 0xBB2C1: 1.186, 0xBB2CD: 0.997,
        0xBB3C0: 0.992, 0xBB3C1: 1.373, 0xBB3CD: 1.061, 0xBB4C1: 1.224, 0xBB4CD: 0.974, 0xBB5C0: 1.024,
        0xBB5C1: 1.014, 0xBB5CD: 1.027, 0xBB8CD: 1.302,
    ]
    static let bold: [UInt32: Double] = [
        0xB85: 1.158, 0xB86: 1.289, 0xB87: 1.169, 0xB8A: 1.317, 0xB8E: 0.822, 0xB92: 1.086, 0xB95: 0.932,
        0xB99: 1.110, 0xB9A: 0.847, 0xB9C: 0.993, 0xB9E: 1.253, 0xB9F: 0.812, 0xBA3: 1.722, 0xBA4: 0.925,
        0xBA8: 0.868, 0xBA9: 1.307, 0xBAA: 0.873, 0xBAE: 1.016, 0xBAF: 1.065, 0xBB0: 0.786, 0xBB1: 0.948,
        0xBB2: 1.053, 0xBB3: 1.122, 0xBB4: 0.945, 0xBB5: 1.064, 0xBB8: 1.443, 0xBBE: 0.780, 0xBBF: 0.289,
        0xBC0: 0, 0xBC1: 0.189, 0xBC2: 0.308, 0xBC6: 0.873, 0xBC7: 0.744, 0xBC8: 1.244, 0xBCA: 1.653,
        0xBCB: 1.524, 0xBCD: 0.031,
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
        0xBB2: 0.771, 0xBB3: 0.784, 0xBB5: 0.824, 0xBBE: 0.452, 0xBC6: 0.716, 0xBC7: 0.638, 0xBC8: 0.865, 0xBCA: 1.168, 0xBCB: 1.090, 0xBCD: 0,
    ]
    static let vijayaBold: [UInt32: Double] = [
        0xB95: 0.599, 0xB99: 0.713, 0xB9A: 0.514, 0xB9F: 0.724, 0xBA4: 0.589, 0xBAA: 0.645, 0xBAE: 0.67, 0xBAF: 0.668, 0xBB1: 0.622,
        0xBB2: 0.715, 0xBB3: 0.8, 0xBB5: 0.806, 0xBBE: 0.452, 0xBC6: 0.753, 0xBC7: 0.603, 0xBC8: 0.809, 0xBCA: 1.205, 0xBCB: 1.055, 0xBCD: 0,
    ]
    /// The width in em of a word's characters that the table has, and the others
    /// (punctuation, digits, joiners) as the characters not in it.
    static func split(_ word: Substring, bold isBold: Bool, vijaya: Bool = false, leelawadee: Bool = false) -> (ems: Double, known: String, rest: Bool)? {
        var sum = 0.0, known = String.UnicodeScalarView(), rest = false, any = false
        let us = Array(word.unicodeScalars)
        var i = 0
        while i < us.count {
            let u = us[i]
            i += 1
            if !vijaya, i < us.count, [0xBC0, 0xBC1, 0xBC2, 0xBCD].contains(us[i].value), !(0xBC0...0xBCD).contains(u.value),
               let w = pairs[u.value << 8 | (us[i].value & 0xFF)] {
                sum += isBold ? w * 1.06 : w; known.append(u); known.append(us[i]); any = true; i += 1; continue
            }
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
