// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The iPad's spelling checker: UITextChecker, which the editors reach through
// OfficeApp's UIKitSpellChecker (OfficeApp cannot import UIKit, this target can).
// One checker for the app. Its language is the user's first preferred language
// that the system can check; a paragraph of enough words that the system
// recognises as another checkable language is checked in that one, and one it
// recognises as a language it cannot check is not checked at all (an English
// checker would underline every word of it).

#if os(iOS)
import UIKit
import NaturalLanguage

public final class OfficeTextChecker {
    private let checker = UITextChecker()
    private let available: [String]
    private let fallback: String
    private var lastLanguage: String
    /// Moves when a word is ignored or learned, so what was found is looked for again.
    public private(set) var version = 0

    public init() {
        available = UITextChecker.availableLanguages
        let mine = Locale.preferredLanguages.compactMap { Self.match($0, in: UITextChecker.availableLanguages) }.first
        fallback = mine ?? UITextChecker.availableLanguages.first(where: { $0.hasPrefix("en") }) ?? "en_US"
        lastLanguage = fallback
    }

    /// The checkable language that is `tag` (a BCP 47 tag or a bare language code), if there is one.
    private static func match(_ tag: String, in languages: [String]) -> String? {
        let t = tag.replacingOccurrences(of: "-", with: "_")
        if let exact = languages.first(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { return exact }
        let code = String(t.prefix(while: { $0 != "_" })).lowercased()
        return languages.first(where: { $0.lowercased() == code || $0.lowercased().hasPrefix(code + "_") })
    }

    /// The language to check `text` in; nil when it is plainly one the system cannot check.
    private func language(for text: String) -> String? {
        guard text.count >= 20 else { return lastLanguage }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value >= 0.85 else { return lastLanguage }
        if let found = Self.match(best.key.rawValue, in: available) { return found }
        // Recognised, and not checkable (Chinese, Japanese, ...): leave it alone.
        return nil
    }

    public func misspelledRanges(in text: String) -> [Range<Int>] {
        guard let language = language(for: text) else { return [] }
        lastLanguage = language
        let ns = text as NSString
        var out: [Range<Int>] = []
        var at = 0
        while at < ns.length {
            let r = checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: ns.length), startingAt: at,
                                                  wrap: false, language: language)
            if r.location == NSNotFound || r.length == 0 { break }
            out.append(r.location ..< r.location + r.length)
            at = r.location + r.length
        }
        return out
    }

    public func suggestions(for word: String) -> [String] {
        let ns = word as NSString
        return checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: lastLanguage) ?? []
    }

    public func ignore(_ word: String) {
        checker.ignoreWord(word)
        version += 1
    }

    public func learn(_ word: String) {
        UITextChecker.learnWord(word)
        version += 1
    }
}
#endif
