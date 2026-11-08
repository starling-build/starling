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
    /// The width in em of a word's characters that the table has, and the others
    /// (punctuation, digits, joiners) as the characters not in it.
    static func split(_ word: Substring, bold isBold: Bool) -> (ems: Double, known: String, rest: Bool)? {
        var sum = 0.0, known = String.UnicodeScalarView(), rest = false, any = false
        for u in word.unicodeScalars {
            if isBold, let w = bold[u.value] { sum += w; known.append(u); any = true }
            else if let w = regular[u.value] { sum += isBold ? w * 1.06 : w; known.append(u); any = true }
            else { rest = true }
        }
        return any ? (sum, String(known), rest) : nil
    }
}
