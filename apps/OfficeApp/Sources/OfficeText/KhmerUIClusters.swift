// Khmer UI cluster advances (em): HarfBuzz (Khmr) over the real Khmer UI 6.x files, metrics only (/data/corpus-cache/metrics/khmer-ui-hb-20261123.tsv, 327 clusters:
// every one of them is base + dependent signs + a subscript delta, to within 2 font units, except a vowel after U+17A1, 75 units narrower (regular)). Cmap advances for digits and punctuation.
enum KhmerUIClusters {
    static let regular: [UInt32: Double] = [
        0x1780: 0.8423, 0x1781: 0.8413, 0x1782: 0.8423, 0x1783: 0.9155, 0x1784: 0.8423, 0x1785: 0.8423,
        0x1786: 0.8423, 0x1787: 0.7690, 0x1788: 1.2817, 0x1789: 0.9155, 0x178A: 0.7690, 0x178B: 0.7324,
        0x178C: 0.7690, 0x178D: 0.9155, 0x178E: 1.0986, 0x178F: 0.8423, 0x1790: 0.7681, 0x1791: 0.7324,
        0x1792: 0.8423, 0x1793: 0.8423, 0x1794: 0.8413, 0x1795: 0.7690, 0x1796: 0.8057, 0x1797: 0.8423,
        0x1798: 0.8423, 0x1799: 0.9888, 0x179A: 0.3296, 0x179B: 0.9155, 0x179C: 0.3296, 0x179D: 0.8789,
        0x179E: 0.8423, 0x179F: 0.9155, 0x17A0: 0.9155, 0x17A1: 0.9155, 0x17A2: 0.8423, 0x17A3: 0.8423,
        0x17A4: 1.1719, 0x17A5: 0.8423, 0x17A6: 0.7544, 0x17A7: 0.7690, 0x17A8: 0.7690, 0x17A9: 0.7690,
        0x17AA: 0.7690, 0x17AB: 0.8057, 0x17AC: 0.8057, 0x17AD: 0.8057, 0x17AE: 0.8057, 0x17AF: 0.8423,
        0x17B0: 0.8057, 0x17B1: 0.7695, 0x17B2: 0.6226, 0x17B3: 0.7695, 0x17B6: 0.3296, 0x17B7: 0.0000,
        0x17B8: 0.0000, 0x17B9: 0.0000, 0x17BA: 0.0000, 0x17BB: 0.0000, 0x17BC: 0.0000, 0x17BD: 0.0000,
        0x17BE: 0.3662, 0x17BF: 0.6597, 0x17C0: 0.6592, 0x17C1: 0.3662, 0x17C2: 0.3662, 0x17C3: 0.3667,
        0x17C4: 0.6958, 0x17C5: 0.6958, 0x17C6: 0.0000, 0x17C7: 0.3740, 0x17C8: 0.3296, 0x17C9: 0.0000,
        0x17CA: 0.0000, 0x17CB: 0.0000, 0x17CC: 0.0000, 0x17CD: 0.0000, 0x17CE: 0.0000, 0x17CF: 0.0000,
        0x17D0: 0.0000, 0x17D1: 0.0000, 0x17D2: 0.0000, 0x17D3: 0.5132, 0x17D4: 0.4751, 0x17D5: 0.5850,
        0x17D6: 0.3369, 0x17D7: 0.6226, 0x17D8: 1.6113, 0x17D9: 0.5864, 0x17DA: 0.8428, 0x17DB: 0.4399,
        0x17DC: 0.5132, 0x17DD: 0.0000, 0x17E0: 0.6592, 0x17E1: 0.6582, 0x17E2: 0.7690, 0x17E3: 0.9155,
        0x17E4: 0.6958, 0x17E5: 0.6958, 0x17E6: 0.6958, 0x17E7: 0.7690, 0x17E8: 0.7690, 0x17E9: 0.6958,
        0x17F0: 0.5493, 0x17F1: 0.5483, 0x17F2: 0.2563, 0x17F3: 0.8423, 0x17F4: 0.5483, 0x17F5: 0.4751,
        0x17F6: 0.4028, 0x17F7: 0.6582, 0x17F8: 0.3652, 0x17F9: 0.6226,
    ]
    /// consonants whose subscript form (after U+17D2) adds `regularSubscriptEm`; every other subscript adds nothing
    static let regularWideSubscripts: Set<UInt32> = [0x1783, 0x1788, 0x178D, 0x1794, 0x1799, 0x179A, 0x179F]
    static let regularSubscriptEm = 0.2563
    static let bold: [UInt32: Double] = [
        0x1780: 0.8247, 0x1781: 0.8164, 0x1782: 0.8247, 0x1783: 0.9199, 0x1784: 0.8120, 0x1785: 0.8237,
        0x1786: 0.8457, 0x1787: 0.7178, 0x1788: 1.2280, 0x1789: 0.9580, 0x178A: 0.7544, 0x178B: 0.7285,
        0x178C: 0.8164, 0x178D: 0.9756, 0x178E: 1.2031, 0x178F: 0.8247, 0x1790: 0.7397, 0x1791: 0.7725,
        0x1792: 0.8237, 0x1793: 0.8164, 0x1794: 0.8364, 0x1795: 0.7397, 0x1796: 0.8530, 0x1797: 0.8711,
        0x1798: 0.8364, 0x1799: 1.0054, 0x179A: 0.3442, 0x179B: 0.9531, 0x179C: 0.3442, 0x179D: 0.8247,
        0x179E: 0.8364, 0x179F: 0.9531, 0x17A0: 0.9644, 0x17A1: 1.0850, 0x17A2: 0.8047, 0x17A3: 0.8047,
        0x17A4: 1.1313, 0x17A5: 0.8247, 0x17A6: 0.9082, 0x17A7: 0.8164, 0x17A8: 0.8164, 0x17A9: 0.8164,
        0x17AA: 0.8164, 0x17AB: 0.8364, 0x17AC: 0.8364, 0x17AD: 0.8530, 0x17AE: 0.8530, 0x17AF: 0.8120,
        0x17B0: 0.8530, 0x17B1: 0.8164, 0x17B2: 0.7432, 0x17B3: 0.8164, 0x17B6: 0.3242, 0x17B7: 0.0000,
        0x17B8: 0.0000, 0x17B9: 0.0000, 0x17BA: 0.0000, 0x17BB: 0.0000, 0x17BC: 0.0000, 0x17BD: 0.0000,
        0x17BE: 0.3511, 0x17BF: 0.6489, 0x17C0: 0.6489, 0x17C1: 0.3511, 0x17C2: 0.3511, 0x17C3: 0.3511,
        0x17C4: 0.6753, 0x17C5: 0.6753, 0x17C6: 0.0000, 0x17C7: 0.3960, 0x17C8: 0.3506, 0x17C9: 0.0000,
        0x17CA: 0.0000, 0x17CB: 0.0000, 0x17CC: 0.0000, 0x17CD: 0.0000, 0x17CE: 0.0000, 0x17CF: 0.0000,
        0x17D0: 0.0000, 0x17D1: 0.0000, 0x17D2: 0.0000, 0x17D3: 0.6533, 0x17D4: 0.5928, 0x17D5: 0.7739,
        0x17D6: 0.3960, 0x17D7: 0.7163, 0x17D8: 1.9043, 0x17D9: 0.6938, 0x17DA: 0.9565, 0x17DB: 0.3296,
        0x17DC: 0.6089, 0x17DD: 0.0000, 0x17E0: 0.6274, 0x17E1: 0.7163, 0x17E2: 0.8564, 0x17E3: 0.8984,
        0x17E4: 0.7812, 0x17E5: 0.7812, 0x17E6: 0.7163, 0x17E7: 0.8672, 0x17E8: 0.8545, 0x17E9: 0.7812,
        0x17F0: 0.6475, 0x17F1: 0.6450, 0x17F2: 0.2979, 0x17F3: 0.9487, 0x17F4: 0.6450, 0x17F5: 0.6782,
        0x17F6: 0.4434, 0x17F7: 0.6504, 0x17F8: 0.4434, 0x17F9: 0.7603,
    ]
    /// consonants whose subscript form (after U+17D2) adds `boldSubscriptEm`; every other subscript adds nothing
    static let boldWideSubscripts: Set<UInt32> = [0x1783, 0x1788, 0x178D, 0x1794, 0x1799, 0x179A, 0x179F]
    static let boldSubscriptEm = 0.3076
}

extension KhmerUIClusters {
    /// The width in em of the Khmer letters of `word` (a cluster is its base, its signs, and a subscript delta after U+17D2), and the
    /// characters that are not Khmer, which keep the stand-in's own width.
    static func split(_ word: Substring, bold: Bool) -> (ems: Double, other: String)? {
        let table = bold ? Self.bold : Self.regular
        let wide = bold ? boldWideSubscripts : regularWideSubscripts
        let sub = bold ? boldSubscriptEm : regularSubscriptEm
        var ems = 0.0, other = "", prev: UInt32 = 0, base: UInt32 = 0, any = false
        for s in word.unicodeScalars {
            let u = s.value
            guard u >= 0x1780, u <= 0x17FF, let adv = table[u] else { other.unicodeScalars.append(s); prev = u; continue }
            any = true
            if prev == 0x17D2, u >= 0x1780, u <= 0x17A2 {
                if wide.contains(u) { ems += sub }
            } else {
                ems += adv
                // (A Khmer UI regular LO followed by AA, OO or AU is 75 units narrower than the other bases' pair.)
                if !bold, base == 0x17A1, u == 0x17B6 || u == 0x17C4 || u == 0x17C5 { ems -= 75.0 / 2048 }
                if u <= 0x17B3 { base = u }
            }
            prev = u
        }
        return any ? (ems, other) : nil
    }
}
