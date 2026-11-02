import Foundation

/// Liang/TeX pattern hyphenation (the hyph-utf8 pattern files, see
/// `HyphenationData`): where a word may be parted at a line's end.
final class Hyphenator {
    private let patterns: [String: [UInt8]]
    private let exceptions: [String: Set<Int>]
    private let longest: Int
    let leftMin: Int
    let rightMin: Int

    private init(patterns text: String, exceptions list: String, leftMin: Int, rightMin: Int) {
        var table: [String: [UInt8]] = [:]
        var longest = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("%") { continue }
            var letters = ""
            var numbers: [UInt8] = [0]
            for ch in trimmed {
                if let d = ch.wholeNumberValue, ch.isASCII { numbers[numbers.count - 1] = UInt8(d) }
                else { letters.append(ch); numbers.append(0) }
            }
            table[letters] = numbers
            longest = max(longest, letters.count)
        }
        var held: [String: Set<Int>] = [:]
        for line in list.split(separator: "\n") {
            var word = ""
            var at = Set<Int>()
            for ch in line.trimmingCharacters(in: .whitespaces) {
                if ch == "-" { at.insert(word.count) } else { word.append(ch) }
            }
            if !word.isEmpty { held[word] = at }
        }
        self.patterns = table
        self.exceptions = held
        self.longest = longest
        self.leftMin = leftMin
        self.rightMin = rightMin
    }

    private static var cache: [String: Hyphenator?] = [:]
    private static let lock = NSLock()
    static let enabled: Set<String> = ["en-us"]

    /// The hyphenator for a language tag (`en-US`, `nl-NL`, `de-DE`…), or nil
    /// where none is bundled.
    static func forLanguage(_ tag: String) -> Hyphenator? {
        let t = tag.lowercased()
        let key: String
        switch true {
        case t == "en-gb" || t == "en-au" || t == "en-nz" || t == "en-ie" || t == "en-za" || t == "en-in": key = "en-gb"
        case t.hasPrefix("en"): key = "en-us"
        case t.hasPrefix("nl"): key = "nl"
        case t.hasPrefix("de"): key = "de"
        case t.hasPrefix("es"): key = "es"
        case t.hasPrefix("fr"): key = "fr"
        default: return nil
        }
        // (Only what Word for Windows' reference prints show it hyphenating:
        // English (US) — lo-a594fa6b, lo-d1e88d77. Dutch, en-GB set no
        // hyphen where the patterns find one; German and Spanish await a lab.)
        guard enabled.contains(key) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let found = cache[key] { return found }
        let made: Hyphenator
        switch key {
        case "en-gb": made = Hyphenator(patterns: HyphenationData.en_gbPatterns, exceptions: HyphenationData.en_gbExceptions, leftMin: 2, rightMin: 3)
        case "en-us": made = Hyphenator(patterns: HyphenationData.en_usPatterns, exceptions: HyphenationData.en_usExceptions, leftMin: 2, rightMin: 3)
        case "nl": made = Hyphenator(patterns: HyphenationData.nlPatterns, exceptions: HyphenationData.nlExceptions, leftMin: 2, rightMin: 2)
        case "de": made = Hyphenator(patterns: HyphenationData.de_1996Patterns, exceptions: HyphenationData.de_1996Exceptions, leftMin: 2, rightMin: 2)
        case "es": made = Hyphenator(patterns: HyphenationData.esPatterns, exceptions: HyphenationData.esExceptions, leftMin: 2, rightMin: 2)
        default: made = Hyphenator(patterns: HyphenationData.frPatterns, exceptions: HyphenationData.frExceptions, leftMin: 2, rightMin: 2)
        }
        cache[key] = made
        return made
    }

    /// The places a word (letters only) may be parted at: counts of
    /// characters before the break, each at least `leftMin` from the start
    /// and `rightMin` from the end.
    func breaks(_ word: [Character]) -> [Int] {
        let n = word.count
        guard n >= leftMin + rightMin else { return [] }
        let lowered = word.map { Character($0.lowercased()) }
        if let held = exceptions[String(lowered)] {
            return held.filter { $0 >= leftMin && n - $0 >= rightMin }.sorted()
        }
        let padded = ["."] + lowered + ["."]
        var values = [UInt8](repeating: 0, count: padded.count + 1)
        for i in 0 ..< padded.count {
            var key = ""
            for j in i ..< min(padded.count, i + longest) {
                key.append(padded[j])
                if let nums = patterns[key] {
                    for (k, x) in nums.enumerated() where values[i + k] < x { values[i + k] = x }
                }
            }
        }
        var out: [Int] = []
        for c in leftMin ... (n - rightMin) where values[c + 1] % 2 == 1 { out.append(c) }
        return out
    }
}
