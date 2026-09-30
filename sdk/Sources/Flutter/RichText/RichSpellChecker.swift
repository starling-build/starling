/// A spelling checker the layout can ask about paragraph text. The host
/// supplies one (NSSpellChecker on macOS); the layout caches its answers
/// by paragraph text and paints Word's red underline under each range,
/// leaving out the word the caret is in.
public protocol RichSpellChecker: AnyObject {
    /// The misspelled ranges of `text`, in UTF-16 offsets, ascending.
    func misspelledRanges(in text: String) -> [Range<Int>]
    /// Corrections for one word, best first.
    func suggestions(for word: String) -> [String]
    /// Stop flagging `word` for this document.
    func ignore(_ word: String)
    /// Add `word` to the user's dictionary.
    func learn(_ word: String)
    /// Changes whenever `ignore` or `learn` did, so cached results are dropped.
    var version: Int { get }
}
