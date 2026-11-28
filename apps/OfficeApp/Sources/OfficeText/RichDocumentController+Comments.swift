import Foundation

/// Word's Review > Comments: New Comment, Delete, Previous / Next. A comment's text lives in the kept
/// `word/comments.xml`; the stretch it covers rides on the runs (`CharStyle.comments`), and the writer puts the range
/// markers and the reference back around it.
extension RichDocumentController {
    static let commentsPart = "word/comments.xml"
    /// Word's other comment parts: they describe the comments in `word/comments.xml` and go with it.
    static let commentSideParts = ["word/commentsExtended.xml", "word/commentsIds.xml", "word/commentsExtensible.xml"]

    /// One comment as the file holds it.
    public struct DocComment: Equatable, Sendable {
        public var id: String
        public var author: String
        public var initials: String
        public var date: String
        /// Its paragraphs' text, one line each.
        public var text: String
        /// Its last paragraph's `w14:paraId`, by which `commentsExtended.xml` names it ("" when it has none).
        public var paraId: String = ""
        /// The comment this one replies to (from `commentsExtended.xml`), nil for a comment of its own.
        public var parent: String? = nil
        /// Resolved (Word's "done").
        public var done: Bool = false
        public init(id: String, author: String, initials: String, date: String, text: String,
                    paraId: String = "", parent: String? = nil, done: Bool = false) {
            self.id = id; self.author = author; self.initials = initials; self.date = date; self.text = text
            self.paraId = paraId; self.parent = parent; self.done = done
        }
    }

    /// The stretch of text a comment covers.
    public struct CommentRange: Equatable, Sendable {
        public var id: String
        public var start: RichPosition
        public var end: RichPosition
        public init(id: String, start: RichPosition, end: RichPosition) { self.id = id; self.start = start; self.end = end }
    }

    /// Every comment in the file, in the file's order.
    public func comments() -> [DocComment] {
        guard let data = document.keptParts[Self.commentsPart] else { return [] }
        var all = Self._parseComments(String(decoding: data, as: UTF8.self))
        // (Replies and the done state live in commentsExtended, keyed by each comment's last paragraph id.)
        let ext = Self._parseCommentsEx(document.keptParts[Self.commentsExtendedPart].map { String(decoding: $0, as: UTF8.self) } ?? "")
        guard !ext.isEmpty else { return all }
        var byPara: [String: String] = [:]
        for c in all where !c.paraId.isEmpty { byPara[c.paraId] = c.id }
        for k in all.indices where !all[k].paraId.isEmpty {
            guard let e = ext[all[k].paraId] else { continue }
            all[k].done = e.done
            if let p = e.parent, let id = byPara[p], id != all[k].id { all[k].parent = id }
        }
        return all
    }

    /// Every comment that covers some text, in reading order (by where it starts).
    public func commentRanges() -> [CommentRange] {
        var first: [String: RichPosition] = [:]
        var last: [String: RichPosition] = [:]
        var order: [String] = []
        for (i, p) in document.paragraphs.enumerated() {
            var at = 0
            for run in p.runs {
                for id in run.style.comments where run.length > 0 {
                    if first[id] == nil { first[id] = RichPosition(paragraph: i, offset: at); order.append(id) }
                    last[id] = RichPosition(paragraph: i, offset: at + run.length)
                }
                at += run.length
            }
        }
        return order.compactMap { id in
            guard let s = first[id], let e = last[id] else { return nil }
            return CommentRange(id: id, start: s, end: e)
        }
    }

    /// The comments the selection touches (with no selection, the ones around the caret), in reading order.
    public func commentsAtSelection() -> [CommentRange] {
        let lo = selection.start, hi = selection.end
        return commentRanges().filter { c in
            lo == hi ? (c.start <= lo && lo <= c.end) : (c.start < hi && lo < c.end)
        }
    }

    /// The comment the selection is on, with its text (for the status line).
    public func currentComment() -> DocComment? {
        guard let r = commentsAtSelection().first else { return nil }
        return comments().first { $0.id == r.id }
    }

    /// Next / Previous Comment: select the next (previous) comment's text, wrapping round. False when there is none.
    @discardableResult
    public func selectAdjacentComment(forward: Bool) -> Bool {
        // (A reply covers its comment's text: one stop per thread.)
        let replies = Set(comments().filter { $0.parent != nil }.map(\.id))
        let all = commentRanges().filter { !replies.contains($0.id) }
        guard !all.isEmpty else { return false }
        let lo = selection.start, hi = selection.end
        let pick: CommentRange
        if let k = all.firstIndex(where: { $0.start == lo && $0.end == hi }) {
            pick = all[(k + (forward ? 1 : all.count - 1)) % all.count]
        } else if forward {
            pick = all.first { $0.start >= hi } ?? all.first!
        } else {
            pick = all.last { $0.end <= lo && $0.start < lo } ?? all.last!
        }
        moveTo(pick.start, extend: false)
        moveTo(pick.end, extend: true)
        return true
    }

    /// New Comment: a comment holding `text` on the selection, or with no selection on the word at the caret. One undo
    /// step. Returns the new comment's id, or nil when there is no text to hang it on.
    @discardableResult
    public func addComment(_ text: String) -> String? {
        guard !readOnly else { return nil }
        var lo = selection.start, hi = selection.end
        if lo == hi {
            let p = document.clamped(lo)
            let r = document.paragraphs[p.paragraph].wordRange(at: p.offset)
            guard !r.isEmpty else { return nil }
            lo = RichPosition(paragraph: p.paragraph, offset: r.lowerBound)
            hi = RichPosition(paragraph: p.paragraph, offset: r.upperBound)
        }
        let xml = document.keptParts[Self.commentsPart].map { String(decoding: $0, as: UTF8.self) }
        // A new id above every one in use (the file's comments and the ranges on the text).
        var used = Set(Self._parseComments(xml ?? "").compactMap { Int($0.id) })
        for p in document.paragraphs { for run in p.runs { for id in run.style.comments { if let n = Int(id) { used.insert(n) } } } }
        let id = String((used.max() ?? -1) + 1)
        let parts = _commentParts(adding: id, text: text, parent: nil)
        let first = lo.paragraph, last = hi.paragraph
        var slice = Array(document.paragraphs[first ... last])
        for k in slice.indices {
            let i = first + k
            let a = i == lo.paragraph ? lo.offset : 0
            let b = i == hi.paragraph ? hi.offset : slice[k].length
            slice[k].runs = Self._mapRuns(slice[k].runs, from: a, to: b) { s in
                if !s.comments.contains(id) { s.comments.append(id) }
            }
            slice[k].normalize()
        }
        edit {
            for (name, data) in parts { perform(.setKeptPart(name, old: document.keptParts[name], new: data)) }
            perform(.restoreParagraphs(first, count: slice.count, slice))
        }
        moveTo(lo, extend: false)
        moveTo(hi, extend: true)
        return id
    }

    /// Delete: the comments the selection touches (or the one at the caret). One undo step. Returns how many went.
    @discardableResult
    public func deleteComments() -> Int {
        _deleteComments(Set(commentsAtSelection().map(\.id)), all: false)
    }

    /// Delete comment `id` (from its balloon) with its replies. One undo step. False when there is none.
    @discardableResult
    public func deleteComment(_ id: String) -> Bool {
        _deleteComments([id], all: false) > 0
    }

    /// Delete All Comments in Document. One undo step.
    @discardableResult
    public func deleteAllComments() -> Int {
        let ids = Set(comments().map(\.id)).union(commentRanges().map(\.id))
        return _deleteComments(ids, all: true)
    }

    private func _deleteComments(_ picked: Set<String>, all: Bool) -> Int {
        guard !readOnly, !picked.isEmpty else { return 0 }
        // (A comment goes with its replies, as in Word.)
        let known = comments()
        var ids = picked
        var grew = true
        while grew {
            grew = false
            for c in known where !ids.contains(c.id) { if let p = c.parent, ids.contains(p) { ids.insert(c.id); grew = true } }
        }
        let paraIds = Set(known.filter { ids.contains($0.id) && !$0.paraId.isEmpty }.map(\.paraId))
        var changed: [(Int, RichParagraph)] = []
        for (i, p) in document.paragraphs.enumerated() where p.runs.contains(where: { !Set($0.style.comments).isDisjoint(with: ids) }) {
            var q = p
            q.runs = q.runs.map { r in var r = r; r.style.comments.removeAll { ids.contains($0) }; return r }
            q.normalize()
            changed.append((i, q))
        }
        let old = document.keptParts[Self.commentsPart]
        edit {
            if all {
                // No comment left: the parts go, and the writer adds no markers.
                for name in [Self.commentsPart] + Self.commentSideParts where document.keptParts[name] != nil {
                    perform(.setKeptPart(name, old: document.keptParts[name], new: nil))
                }
            } else if let old {
                var xml = String(decoding: old, as: UTF8.self)
                for id in ids { xml = Self._removingComment(id, from: xml) }
                perform(.setKeptPart(Self.commentsPart, old: old, new: Data(xml.utf8)))
                for (name, data) in _sidePartsWithout(paraIds: paraIds) {
                    perform(.setKeptPart(name, old: document.keptParts[name], new: data))
                }
            }
            for (i, q) in changed { perform(.restoreParagraphs(i, count: 1, [q])) }
        }
        if let lo = changed.first { moveTo(document.clamped(RichPosition(paragraph: lo.0, offset: 0)), extend: false) }
        return picked.count
    }

    /// `runs` with `change` applied to the stretch [a, b), the runs split at its ends.
    static func _mapRuns(_ runs: [Run], from a: Int, to b: Int, _ change: (inout CharStyle) -> Void) -> [Run] {
        var out: [Run] = []
        var at = 0
        for run in runs {
            let s = at, e = at + run.length
            at = e
            let cuts = [s, max(s, min(e, a)), max(s, min(e, b)), e]
            for j in 0 ..< 3 where cuts[j + 1] > cuts[j] || (run.length == 0 && j == 0) {
                var style = run.style
                if j == 1 { change(&style) }
                out.append(Run(length: cuts[j + 1] - cuts[j], style: style))
            }
        }
        return out
    }

    // MARK: The part's XML

    static func _commentXML(id: String, author: String, date: String, text: String, paraIds: [String] = []) -> String {
        let initials = String(author.split(separator: " ").compactMap(\.first))
        var out = "<w:comment w:id=\"\(id)\" w:author=\"\(_xmlEscaped(author))\""
        if !date.isEmpty { out += " w:date=\"\(_xmlEscaped(date))\"" }
        if !initials.isEmpty { out += " w:initials=\"\(_xmlEscaped(initials))\"" }
        out += ">"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (k, line) in lines.enumerated() {
            out += k < paraIds.count ? "<w:p w14:paraId=\"\(paraIds[k])\" w14:textId=\"77777777\">" : "<w:p>"
            if k == 0 { out += "<w:r><w:annotationRef/></w:r>" }
            if !line.isEmpty { out += "<w:r><w:t xml:space=\"preserve\">\(_xmlEscaped(String(line)))</w:t></w:r>" }
            out += "</w:p>"
        }
        return out + "</w:comment>"
    }

    /// The comments in a `w:comments` part.
    public static func _parseComments(_ xml: String) -> [DocComment] {
        var out: [DocComment] = []
        var from = xml.startIndex
        while let open = xml.rangeOfSubstring("<w:comment ", in: from ..< xml.endIndex) {
            guard let tagEnd = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound ..< tagEnd.upperBound])
            let selfClosing = tag.hasSuffix("/>")
            var body = ""
            from = tagEnd.upperBound
            if !selfClosing, let close = xml.rangeOfSubstring("</w:comment>", in: tagEnd.upperBound ..< xml.endIndex) {
                body = String(xml[tagEnd.upperBound ..< close.lowerBound])
                from = close.upperBound
            }
            out.append(DocComment(id: _attribute("w:id", in: tag) ?? "", author: _attribute("w:author", in: tag) ?? "",
                                  initials: _attribute("w:initials", in: tag) ?? "", date: _attribute("w:date", in: tag) ?? "",
                                  text: _plainText(body), paraId: _lastParaId(body)))
        }
        return out
    }

    /// `xml` without the comment `id` (its whole element).
    public static func _removingComment(_ id: String, from xml: String) -> String {
        var from = xml.startIndex
        while let open = xml.rangeOfSubstring("<w:comment ", in: from ..< xml.endIndex) {
            guard let tagEnd = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { break }
            let tag = String(xml[open.lowerBound ..< tagEnd.upperBound])
            var end = tagEnd.upperBound
            if !tag.hasSuffix("/>"), let close = xml.rangeOfSubstring("</w:comment>", in: tagEnd.upperBound ..< xml.endIndex) { end = close.upperBound }
            if _attribute("w:id", in: tag) == id {
                var out = xml
                out.removeSubrange(open.lowerBound ..< end)
                return out
            }
            from = end
        }
        return xml
    }

    static func _attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.rangeOfSubstring(" \(name)=\"") else { return nil }
        guard let close = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) else { return nil }
        return _xmlUnescaped(String(tag[r.upperBound ..< close.lowerBound]))
    }

    /// The text of the `w:t` elements, a line per paragraph.
    static func _plainText(_ body: String) -> String {
        var lines: [String] = []
        var line = ""
        var i = body.startIndex
        while let lt = body.rangeOfSubstring("<", in: i ..< body.endIndex) {
            guard let gt = body.rangeOfSubstring(">", in: lt.upperBound ..< body.endIndex) else { break }
            let tag = body[lt.upperBound ..< gt.lowerBound]
            if tag == "/w:p" { lines.append(line); line = "" }
            else if tag == "w:tab/" { line += "\t" }
            else if (tag == "w:t" || tag.hasPrefix("w:t ")) && !tag.hasSuffix("/"),
                    let close = body.rangeOfSubstring("</w:t>", in: gt.upperBound ..< body.endIndex) {
                line += _xmlUnescaped(String(body[gt.upperBound ..< close.lowerBound]))
                i = close.upperBound
                continue
            }
            i = gt.upperBound
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }

    static func _xmlEscaped(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    static func _xmlUnescaped(_ s: String) -> String {
        guard s.rangeOfSubstring("&") != nil else { return s }
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s.rangeOfSubstring(";", in: i ..< s.endIndex) {
                let name = s[s.index(after: i) ..< semi.lowerBound]
                var put: String? = nil
                switch name {
                case "amp": put = "&"
                case "lt": put = "<"
                case "gt": put = ">"
                case "quot": put = "\""
                case "apos": put = "'"
                default:
                    if name.hasPrefix("#x"), let n = UInt32(name.dropFirst(2), radix: 16), let u = Unicode.Scalar(n) { put = String(Character(u)) }
                    else if name.hasPrefix("#"), let n = UInt32(name.dropFirst()), let u = Unicode.Scalar(n) { put = String(Character(u)) }
                }
                if let put { out += put; i = semi.upperBound; continue }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }
}
