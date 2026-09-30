// The Mac's spelling checker behind the SDK's RichSpellChecker: one
// NSSpellChecker document tag for the app, the checker's own language
// (asking with no language identifies it per string and misses short
// ones), and a version that moves when the user ignores or learns a word.

import Flutter
import Foundation
#if canImport(AppKit)
import AppKit

final class CocoaSpellChecker: RichSpellChecker {
    private let _checker: NSSpellChecker
    private let _tag: Int
    private let _language: String
    private(set) var version = 0

    init() {
        // NSSpellChecker.shared blocks without an application to talk to
        // the spelling service for; the app has one, a test may not.
        _ = NSApplication.shared
        _checker = NSSpellChecker.shared
        _tag = NSSpellChecker.uniqueSpellDocumentTag()
        _language = _checker.language()
    }

    func misspelledRanges(in text: String) -> [Range<Int>] {
        let ns = text as NSString
        var out: [Range<Int>] = []
        var at = 0
        while at < ns.length {
            var count = 0
            let r = _checker.checkSpelling(of: text, startingAt: at, language: _language, wrap: false,
                                           inSpellDocumentWithTag: _tag, wordCount: &count)
            if r.location == NSNotFound || r.length == 0 { break }
            out.append(r.location ..< r.location + r.length)
            at = r.location + r.length
        }
        return out
    }

    func suggestions(for word: String) -> [String] {
        _checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word,
                         language: _language, inSpellDocumentWithTag: _tag) ?? []
    }

    func ignore(_ word: String) {
        _checker.ignoreWord(word, inSpellDocumentWithTag: _tag)
        version += 1
    }

    func learn(_ word: String) {
        _checker.learnWord(word)
        version += 1
    }
}
#endif
