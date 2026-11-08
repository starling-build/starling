// Kokila's own Latin, digits, punctuation and space in Word for Windows (em), read from the glyph advances of
// the Kokila subsets embedded in the dx2 prints (all nine low Hindi/Nepali Kokila documents set ascii and hAnsi to
// Kokila too): the space is 0.193 em, digits 0.387, where the stand-in Carlito has 0.226 and 0.507. Characters the
// subsets lacked (about a dozen capitals, "k", "j", "q", "z") keep the stand-in's width. Bold: the same space, digits
// and punctuation; its letters are within 0.04 em, so one table serves both.
enum KokilaLatin {
    static let advance: [UInt32: Double] = [
        0x20: 0.193, 0x21: 0.258, 0x22: 0.316, 0x23: 0.387, 0x28: 0.258, 0x29: 0.258, 0x2A: 0.387, 0x2C: 0.193,
        0x2D: 0.258, 0x2E: 0.193, 0x2F: 0.215, 0x30: 0.387, 0x31: 0.387, 0x32: 0.387, 0x33: 0.387, 0x34: 0.387,
        0x35: 0.387, 0x36: 0.387, 0x37: 0.387, 0x38: 0.387, 0x39: 0.387, 0x3A: 0.215, 0x3B: 0.215, 0x41: 0.559,
        0x42: 0.516, 0x43: 0.516, 0x44: 0.559, 0x45: 0.473, 0x46: 0.431, 0x47: 0.559, 0x48: 0.602, 0x49: 0.258,
        0x4C: 0.473, 0x4D: 0.688, 0x4E: 0.559, 0x4F: 0.559, 0x50: 0.431, 0x51: 0.559, 0x52: 0.516, 0x53: 0.431,
        0x54: 0.473, 0x55: 0.559, 0x57: 0.730, 0x5D: 0.258, 0x61: 0.344, 0x62: 0.387, 0x63: 0.344, 0x64: 0.387,
        0x65: 0.344, 0x66: 0.258, 0x67: 0.387, 0x68: 0.387, 0x69: 0.215, 0x6C: 0.215, 0x6D: 0.602, 0x6E: 0.387,
        0x6F: 0.387, 0x70: 0.387, 0x72: 0.258, 0x73: 0.301, 0x74: 0.215, 0x75: 0.387, 0x76: 0.387, 0x77: 0.559,
        0x78: 0.387, 0x79: 0.387, 0x201C: 0.344, 0x201D: 0.344, 0x2026: 0.774,
    ]
    /// Width in em of a Latin stretch's characters that the table has, the characters it lacks as `rest`.
    static func split(_ s: Substring) -> (ems: Double, known: String, rest: Bool, any: Bool) {
        var sum = 0.0, known = String.UnicodeScalarView(), rest = false, any = false
        for u in s.unicodeScalars {
            if let w = advance[u.value] { sum += w; known.append(u); any = true } else { rest = true }
        }
        return (sum, String(known), rest, any)
    }
}
