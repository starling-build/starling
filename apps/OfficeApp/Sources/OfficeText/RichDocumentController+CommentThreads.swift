import Foundation

/// Word's comment threads: a reply, Resolve / Reopen, and a comment's text edited in place. Replies and the done state
/// are kept as Word keeps them, in `word/commentsExtended.xml` (`w15:commentEx`, keyed by the `w14:paraId` of each
/// comment's last paragraph); a reply covers the same text as the comment it answers.
extension RichDocumentController {
    static let commentsExtendedPart = "word/commentsExtended.xml"
    static let commentsIdsPart = "word/commentsIds.xml"
    static let commentsExtensiblePart = "word/commentsExtensible.xml"

    /// A comment with its replies, and the text it covers.
    public struct CommentThread: Equatable, Sendable {
        public var comment: DocComment
        public var replies: [DocComment]
        public var range: CommentRange
    }

    /// The comments that cover text, each with its replies, in reading order.
    public func commentThreads() -> [CommentThread] {
        let all = comments()
        var byId: [String: DocComment] = [:]
        for c in all { byId[c.id] = c }
        /// (A reply's thread is its top comment's.)
        func root(_ c: DocComment) -> DocComment {
            var at = c
            var seen: Set<String> = [c.id]
            while let p = at.parent, let up = byId[p], seen.insert(p).inserted { at = up }
            return at
        }
        var replies: [String: [DocComment]] = [:]
        for c in all where c.parent != nil { let r = root(c); if r.id != c.id { replies[r.id, default: []].append(c) } }
        return commentRanges().compactMap { r in
            guard let c = byId[r.id], c.parent == nil || root(c).id == c.id else { return nil }
            return CommentThread(comment: c, replies: replies[c.id] ?? [], range: r)
        }
    }

    /// The top comment of comment `id`'s thread (itself when it is no reply).
    public func commentRoot(_ id: String) -> String {
        let all = comments()
        var at = id
        var seen: Set<String> = [id]
        while let p = all.first(where: { $0.id == at })?.parent, seen.insert(p).inserted { at = p }
        return at
    }

    /// Comment `id`'s thread (from a reply too), or nil when it covers no text.
    public func commentThread(_ id: String) -> CommentThread? {
        let root = commentRoot(id)
        return commentThreads().first { $0.comment.id == root }
    }

    /// Reply: a comment holding `text` that answers comment `id` (on the same text). One undo step. The new id, or nil.
    @discardableResult
    public func replyToComment(_ id: String, text: String) -> String? {
        guard !readOnly else { return nil }
        let all = comments()
        guard var parent = all.first(where: { $0.id == id }) else { return nil }
        // (Word threads a reply to a reply under the top comment.)
        while let p = parent.parent, let up = all.first(where: { $0.id == p }) { parent = up }
        var used = Set(all.compactMap { Int($0.id) })
        for p in document.paragraphs { for run in p.runs { for c in run.style.comments { if let n = Int(c) { used.insert(n) } } } }
        let newId = String((used.max() ?? -1) + 1)
        let parts = _commentParts(adding: newId, text: text, parent: parent)
        let root = parent.id
        let thread = Set(all.filter { $0.parent == root }.map(\.id))
        var changed: [(Int, RichParagraph)] = []
        for (i, p) in document.paragraphs.enumerated() where p.runs.contains(where: { $0.style.comments.contains(parent.id) }) {
            var q = p
            q.runs = q.runs.map { r in
                var r = r
                if let k = r.style.comments.firstIndex(of: parent.id), !r.style.comments.contains(newId) {
                    // (After the thread's last comment, so replies keep their order, as Word nests the reply's markers.)
                    var at = k + 1
                    while at < r.style.comments.count, thread.contains(r.style.comments[at]) { at += 1 }
                    r.style.comments.insert(newId, at: at)
                }
                return r
            }
            changed.append((i, q))
        }
        guard !changed.isEmpty else { return nil }
        edit {
            for (name, data) in parts { perform(.setKeptPart(name, old: document.keptParts[name], new: data)) }
            for (i, q) in changed { perform(.restoreParagraphs(i, count: 1, [q])) }
        }
        return newId
    }

    /// Resolve (or Reopen, `done` false) the thread comment `id` belongs to. One undo step. False when nothing changed.
    @discardableResult
    public func setCommentResolved(_ id: String, _ done: Bool) -> Bool {
        guard !readOnly else { return false }
        let all = comments()
        guard var c = all.first(where: { $0.id == id }) else { return false }
        while let p = c.parent, let up = all.first(where: { $0.id == p }) { c = up }
        guard c.done != done else { return false }
        var parts: [(String, Data?)] = []
        var paraId = c.paraId
        if paraId.isEmpty {
            // (A comment from a file that gave it no paragraph id gets one, so commentsExtended can name it.)
            guard let xml = document.keptParts[Self.commentsPart].map({ String(decoding: $0, as: UTF8.self) }) else { return false }
            paraId = _freshParaIds(1)[0]
            parts.append((Self.commentsPart, Data(Self._givingParaId(paraId, toComment: c.id, in: Self._withNamespace("w14", Self.w14NS, root: "<w:comments", xml)).utf8)))
        }
        var ext = document.keptParts[Self.commentsExtendedPart].map { String(decoding: $0, as: UTF8.self) } ?? Self.freshCommentsEx
        if let r = Self._elementRange("w15:commentEx", attribute: "w15:paraId", value: paraId, in: ext) {
            var tag = String(ext[r])
            if let a = tag.rangeOfSubstring(" w15:done=\""), let q = tag.rangeOfSubstring("\"", in: a.upperBound ..< tag.endIndex) {
                tag.replaceSubrange(a.lowerBound ..< q.upperBound, with: " w15:done=\"\(done ? 1 : 0)\"")
            } else if let end = Self._lastRange("/>", in: tag) ?? Self._lastRange(">", in: tag) {
                tag.insert(contentsOf: " w15:done=\"\(done ? 1 : 0)\"", at: end.lowerBound)
            }
            ext.replaceSubrange(r, with: tag)
        } else {
            ext = Self._appending("<w15:commentEx w15:paraId=\"\(paraId)\" w15:done=\"\(done ? 1 : 0)\"/>", before: "</w15:commentsEx>", in: ext)
        }
        parts.append((Self.commentsExtendedPart, Data(ext.utf8)))
        edit { for (name, data) in parts { perform(.setKeptPart(name, old: document.keptParts[name], new: data)) } }
        return true
    }

    /// The comment's text, as typed in its card (a line per paragraph). One undo step. False when nothing changed.
    @discardableResult
    public func setCommentText(_ id: String, _ text: String) -> Bool {
        guard !readOnly, let old = document.keptParts[Self.commentsPart] else { return false }
        let xml = String(decoding: old, as: UTF8.self)
        guard let c = Self._parseComments(xml).first(where: { $0.id == id }), c.text != text,
              let r = Self._elementRange("w:comment", attribute: "w:id", value: id, in: xml) else { return false }
        let element = String(xml[r])
        guard let tagEnd = element.rangeOfSubstring(">") else { return false }
        let tag = String(element[..<tagEnd.upperBound])
        // (The last paragraph keeps its id: commentsExtended names the comment by it.)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        var ids = c.paraId.isEmpty ? [] : _freshParaIds(lines - 1) + [c.paraId]
        if ids.count != lines { ids = [] }
        var body = Self._commentXML(id: id, author: "", date: "", text: text, paraIds: ids)
        if let open = body.rangeOfSubstring(">") { body = String(body[open.upperBound...]) }
        let open = tag.hasSuffix("/>") ? String(tag.dropLast(2)) + ">" : tag
        var out = xml
        out.replaceSubrange(r, with: open + body)
        if !ids.isEmpty { out = Self._withNamespace("w14", Self.w14NS, root: "<w:comments", out) }
        edit { perform(.setKeptPart(Self.commentsPart, old: old, new: Data(out.utf8))) }
        return true
    }

    // MARK: Parts

    static let w14NS = "http://schemas.microsoft.com/office/word/2010/wordml"
    static let w15NS = "http://schemas.microsoft.com/office/word/2012/wordml"
    static let freshCommentsEx = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<w15:commentsEx "
        + "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" xmlns:w15=\"\(w15NS)\" mc:Ignorable=\"w15\"></w15:commentsEx>"

    /// The comments parts with comment `id` added (holding `text`, answering `parent` when given): `comments.xml`, and
    /// `commentsExtended.xml`, which records it (and its parent), as Word writes every comment.
    func _commentParts(adding id: String, text: String, parent: DocComment?) -> [(String, Data?)] {
        var xml = document.keptParts[Self.commentsPart].map { String(decoding: $0, as: UTF8.self) }
            ?? "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<w:comments xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" "
            + "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"\(Self.w14NS)\" mc:Ignorable=\"w14\"></w:comments>"
        xml = Self._withNamespace("w14", Self.w14NS, root: "<w:comments", xml)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        var fresh = _freshParaIds(lines + 1)
        var parentPara = parent?.paraId ?? ""
        if let parent, parentPara.isEmpty {
            parentPara = fresh.removeLast()
            xml = Self._givingParaId(parentPara, toComment: parent.id, in: xml)
        }
        let paraIds = Array(fresh.prefix(lines))
        let who = Self.reviewer()
        let element = Self._commentXML(id: id, author: who.author.isEmpty ? "Author" : who.author, date: who.date, text: text, paraIds: paraIds)
        xml = Self._appending(element, before: "</w:comments>", in: xml)
        var ext = document.keptParts[Self.commentsExtendedPart].map { String(decoding: $0, as: UTF8.self) } ?? Self.freshCommentsEx
        ext = Self._withNamespace("w15", Self.w15NS, root: "<w15:commentsEx", ext)
        // The top comment gets its own entry too when it had none (Word writes one for every comment of a thread).
        if parent != nil, Self._elementRange("w15:commentEx", attribute: "w15:paraId", value: parentPara, in: ext) == nil {
            ext = Self._appending("<w15:commentEx w15:paraId=\"\(parentPara)\" w15:done=\"0\"/>", before: "</w15:commentsEx>", in: ext)
        }
        let link = parent == nil ? "" : " w15:paraIdParent=\"\(parentPara)\""
        ext = Self._appending("<w15:commentEx w15:paraId=\"\(paraIds.last ?? "")\"\(link) w15:done=\"0\"/>", before: "</w15:commentsEx>", in: ext)
        return [(Self.commentsPart, Data(xml.utf8)), (Self.commentsExtendedPart, Data(ext.utf8))]
    }

    /// Word's other comment parts without the entries of the comments whose last paragraphs are `paraIds`.
    func _sidePartsWithout(paraIds: Set<String>) -> [(String, Data?)] {
        guard !paraIds.isEmpty else { return [] }
        var out: [(String, Data?)] = []
        if let d = document.keptParts[Self.commentsExtendedPart] {
            var xml = String(decoding: d, as: UTF8.self)
            for p in paraIds { while let r = Self._elementRange("w15:commentEx", attribute: "w15:paraId", value: p, in: xml) { xml.removeSubrange(r) } }
            out.append((Self.commentsExtendedPart, Data(xml.utf8)))
        }
        var durable: [String] = []
        if let d = document.keptParts[Self.commentsIdsPart] {
            var xml = String(decoding: d, as: UTF8.self)
            for p in paraIds {
                while let r = Self._elementRange("w16cid:commentId", attribute: "w16cid:paraId", value: p, in: xml) {
                    if let v = Self._attribute("w16cid:durableId", in: String(xml[r])) { durable.append(v) }
                    xml.removeSubrange(r)
                }
            }
            out.append((Self.commentsIdsPart, Data(xml.utf8)))
        }
        if !durable.isEmpty, let d = document.keptParts[Self.commentsExtensiblePart] {
            var xml = String(decoding: d, as: UTF8.self)
            for v in durable { while let r = Self._elementRange("w16cex:commentExtensible", attribute: "w16cex:durableId", value: v, in: xml) { xml.removeSubrange(r) } }
            out.append((Self.commentsExtensiblePart, Data(xml.utf8)))
        }
        return out
    }

    /// `n` paragraph ids no comment part uses yet (Word's are 8 hex digits below 0x80000000).
    func _freshParaIds(_ n: Int) -> [String] {
        guard n > 0 else { return [] }
        var taken = ""
        for name in [Self.commentsPart, Self.commentsExtendedPart, Self.commentsIdsPart, "word/document.xml"] {
            if let d = document.keptParts[name] { taken += String(decoding: d, as: UTF8.self) }
        }
        var out: [String] = []
        var k: UInt32 = 0x3C00_0001
        while out.count < n {
            var hex = String(k, radix: 16, uppercase: true)
            while hex.count < 8 { hex = "0" + hex }
            if taken.rangeOfSubstring("\"\(hex)\"") == nil { out.append(hex) }
            k += 1
        }
        return out
    }

    /// The last `w14:paraId` in a comment's body ("" when none).
    static func _lastParaId(_ body: String) -> String {
        var last = ""
        var from = body.startIndex
        while let r = body.rangeOfSubstring(" w14:paraId=\"", in: from ..< body.endIndex),
              let q = body.rangeOfSubstring("\"", in: r.upperBound ..< body.endIndex) {
            last = String(body[r.upperBound ..< q.lowerBound])
            from = q.upperBound
        }
        return last
    }

    /// The paraId → (parent paraId, done) of a `w15:commentsEx` part.
    static func _parseCommentsEx(_ xml: String) -> [String: (parent: String?, done: Bool)] {
        var out: [String: (parent: String?, done: Bool)] = [:]
        var from = xml.startIndex
        while let open = xml.rangeOfSubstring("<w15:commentEx ", in: from ..< xml.endIndex),
              let end = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) {
            let tag = String(xml[open.lowerBound ..< end.upperBound])
            if let p = _attribute("w15:paraId", in: tag) {
                out[p] = (_attribute("w15:paraIdParent", in: tag), _attribute("w15:done", in: tag) == "1")
            }
            from = end.upperBound
        }
        return out
    }

    /// Where element `name` with `attribute` = `value` sits in `xml` (its whole element, self-closing or not).
    static func _elementRange(_ name: String, attribute: String, value: String, in xml: String) -> Range<String.Index>? {
        var from = xml.startIndex
        while let open = xml.rangeOfSubstring("<\(name) ", in: from ..< xml.endIndex) {
            guard let tagEnd = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { return nil }
            let tag = String(xml[open.lowerBound ..< tagEnd.upperBound])
            var end = tagEnd.upperBound
            if !tag.hasSuffix("/>"), let close = xml.rangeOfSubstring("</\(name)>", in: tagEnd.upperBound ..< xml.endIndex) { end = close.upperBound }
            if _attribute(attribute, in: tag) == value { return open.lowerBound ..< end }
            from = end
        }
        return nil
    }

    /// `xml` with `element` put before its closing tag `close` (or at the end).
    static func _appending(_ element: String, before close: String, in xml: String) -> String {
        guard let r = _lastRange(close, in: xml) else { return xml + element }
        return String(xml[..<r.lowerBound]) + element + String(xml[r.lowerBound...])
    }

    /// The last place `target` occurs in `s`.
    static func _lastRange(_ target: String, in s: String) -> Range<String.Index>? {
        var last: Range<String.Index>?
        var from = s.startIndex
        while let r = s.rangeOfSubstring(target, in: from ..< s.endIndex) { last = r; from = r.upperBound }
        return last
    }

    /// `xml` with namespace `prefix` declared on its root element (which opens with `root`) when it is not yet.
    static func _withNamespace(_ prefix: String, _ uri: String, root: String, _ xml: String) -> String {
        guard let open = xml.rangeOfSubstring(root), let end = xml.rangeOfSubstring(">", in: open.upperBound ..< xml.endIndex) else { return xml }
        if xml[open.lowerBound ..< end.lowerBound].rangeOfSubstring("xmlns:\(prefix)=") != nil { return xml }
        var out = xml
        out.insert(contentsOf: " xmlns:\(prefix)=\"\(uri)\"", at: open.upperBound)
        return out
    }

    /// `xml` with comment `id`'s last paragraph given the `w14:paraId` `paraId`.
    static func _givingParaId(_ paraId: String, toComment id: String, in xml: String) -> String {
        guard let r = _elementRange("w:comment", attribute: "w:id", value: id, in: xml) else { return xml }
        let element = String(xml[r])
        var last: Range<String.Index>?
        var from = element.startIndex
        while let p = element.rangeOfSubstring("<w:p", in: from ..< element.endIndex) {
            let next = p.upperBound < element.endIndex ? element[p.upperBound] : " "
            if next == ">" || next == " " || next == "/" { last = p }
            from = p.upperBound
        }
        guard let last else { return xml }
        var e = element
        e.insert(contentsOf: " w14:paraId=\"\(paraId)\" w14:textId=\"77777777\"", at: last.upperBound)
        var out = xml
        out.replaceSubrange(r, with: e)
        return out
    }
}
