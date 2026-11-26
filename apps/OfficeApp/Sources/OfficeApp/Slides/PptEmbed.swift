// A legacy .ppt shape written by PowerPoint 2007 or later keeps its modern form beside the old one: the
// OfficeArt property 0x3A9 (metroBlob) holds a small package. When its drs/e2oDoc.xml is a graphic frame
// (a chart or a SmartArt diagram) PowerPoint opens the .ppt with that frame and its parts, not with the
// picture the older versions show; this copies the frame and its parts into the converted deck.
//
// Shared code (also built for the web): no legacy Foundation calls, never traps.

import Foundation

struct PptEmbeds {
    /// The parts copied so far, and the content types they need.
    var parts: [ZipEntry] = []
    var overrides: [(String, String)] = []      // part name -> content type
    var defaults: [String: String] = [:]        // extension -> content type
    private var counters: [String: Int] = [:]

    /// The graphic frame a metroBlob holds, as a `p:graphicFrame` with cNvPr id `id` and the place `xfrm`
    /// (a `p:xfrm`), its parts added; `relate(type, target)` adds a relationship to the part that shows it
    /// and returns the id. Nil when the blob holds no frame or names a part it does not carry.
    mutating func frame(_ blob: [UInt8], id: Int, xfrm: String?, relate: (String, String) -> String) -> String? {
        guard let entries = try? Zip.read(Data(blob)) else { return nil }
        var raw: [String: Data] = [:]
        for e in entries { raw[e.name] = e.data }
        func text(_ name: String) -> String? { raw[name].map { String(decoding: $0, as: UTF8.self) } }
        guard let doc = text("drs/e2oDoc.xml"), let start = doc.rangeOfSubstring("<p:E2oFrame"),
              let end = doc.rangeOfSubstring("</p:E2oFrame>"), start.lowerBound < end.lowerBound else { return nil }
        var frame = String(doc[start.lowerBound ..< end.upperBound])

        // Every part but the package's own gets a name of its own in the deck: drs/x/name1.ext -> ppt/x/namem<k>.ext.
        var rename: [String: String] = [:]
        for name in raw.keys.sorted() where name.hasPrefix("drs/") && !name.containsSubstring("_rels/")
            && name != "drs/e2oDoc.xml" && name != "drs/downrev.xml" {
            rename[name] = fresh(name)
        }
        // The frame's relationships move to the slide; each must point at a part the blob carries.
        var ids: [String: String] = [:]
        if let r = text("drs/_rels/e2oDoc.xml.rels") {
            for tag in Self.tags(r, "Relationship") {
                guard let old = Self.attr(tag, "Id"), let type = Self.attr(tag, "Type"), let target = Self.attr(tag, "Target"),
                      Self.attr(tag, "TargetMode") == nil, let to = rename[Self.resolve("drs/", target)] else { return nil }
                ids[old] = relate(type, Self.relative(from: "ppt/slides/", to: to))
            }
        }
        for (from, to) in rename.sorted(by: { $0.key < $1.key }) {
            guard var data = raw[from] else { continue }
            // A diagram's data names its drawing by the slide's relationship id.
            if from.hasPrefix("drs/diagrams/data"), !ids.isEmpty {
                data = Data(Self.renameIds(String(decoding: data, as: UTF8.self), ids, attribute: "relId").utf8)
            }
            parts.append(ZipEntry(name: to, data: data))
            // The part's own relationships, retargeted at the new names.
            let dir = Self.directory(from), file = String(from.dropFirst(dir.count))
            if let r = text(dir + "_rels/" + file + ".rels") {
                let newDir = Self.directory(to)
                let x = Self.retarget(r) { t in rename[Self.resolve(dir, t)].map { Self.relative(from: newDir, to: $0) } }
                parts.append(ZipEntry(name: newDir + "_rels/" + String(to.dropFirst(newDir.count)) + ".rels", data: Data(x.utf8)))
            }
        }
        if let ct = text("[Content_Types].xml") {
            for tag in Self.tags(ct, "Override") {
                if let p = Self.attr(tag, "PartName"), let t = Self.attr(tag, "ContentType"), let to = rename[String(p.drop(while: { $0 == "/" }))] {
                    overrides.append(("/" + to, t))
                }
            }
            for tag in Self.tags(ct, "Default") {
                if let e = Self.attr(tag, "Extension")?.lowercased(), let t = Self.attr(tag, "ContentType"), e != "rels", e != "xml", defaults[e] == nil {
                    defaults[e] = t
                }
            }
        }

        frame = "<p:graphicFrame" + frame.dropFirst("<p:E2oFrame".count)
        frame = String(frame.dropLast("</p:E2oFrame>".count)) + "</p:graphicFrame>"
        frame = Self.renameIds(frame, ids, attribute: nil)
        if let r = frame.rangeOfSubstring("<p:cNvPr id=\""), let q = frame[r.upperBound...].firstIndex(of: "\"") {
            frame.replaceSubrange(r.upperBound ..< q, with: String(id))
        }
        if let xfrm, let a = frame.rangeOfSubstring("<p:xfrm"), let b = frame.rangeOfSubstring("</p:xfrm>"), a.lowerBound < b.lowerBound {
            frame.replaceSubrange(a.lowerBound ..< b.upperBound, with: xfrm)
        }
        return frame
    }

    private mutating func fresh(_ name: String) -> String {
        let dir = "ppt/" + Self.directory(name).dropFirst("drs/".count)
        let file = String(name.dropFirst(Self.directory(name).count))
        let dot = file.lastIndex(of: ".") ?? file.endIndex
        var stem = String(file[..<dot])
        while let c = stem.last, c.isNumber { stem.removeLast() }
        let key = dir + stem
        let k = (counters[key] ?? 0) + 1
        counters[key] = k
        return dir + stem + "m\(k)" + file[dot...]
    }

    // MARK: package paths and XML attributes

    static func directory(_ path: String) -> String {
        guard let s = path.lastIndex(of: "/") else { return "" }
        return String(path[...s])
    }

    /// `target` read from a part in `dir` as a package path (no leading slash).
    static func resolve(_ dir: String, _ target: String) -> String {
        var segs: [Substring] = target.hasPrefix("/") ? [] : dir.split(separator: "/")
        for s in target.split(separator: "/") {
            if s == ".." { if !segs.isEmpty { segs.removeLast() } } else if s != "." { segs.append(s) }
        }
        return segs.joined(separator: "/")
    }

    /// The target that names package path `to` from a part in `from`.
    static func relative(from: String, to: String) -> String {
        let a = from.split(separator: "/"), b = to.split(separator: "/")
        var k = 0
        while k < a.count, k + 1 < b.count, a[k] == b[k] { k += 1 }
        return (Array(repeating: "..", count: a.count - k) + b[k...].map(String.init)).joined(separator: "/")
    }

    /// The `<name .../>` tags of `xml`.
    static func tags(_ xml: String, _ name: String) -> [Substring] {
        var out: [Substring] = []
        var at = xml.startIndex
        while let r = xml.rangeOfSubstring("<" + name + " ", in: at ..< xml.endIndex) {
            let close = xml[r.upperBound...].firstIndex(of: ">") ?? xml.endIndex
            out.append(xml[r.lowerBound ..< close])
            at = close
        }
        return out
    }

    static func attr(_ tag: Substring, _ name: String) -> String? {
        let s = String(tag)
        guard let r = s.rangeOfSubstring(" " + name + "=\"") else { return nil }
        let end = s[r.upperBound...].firstIndex(of: "\"") ?? s.endIndex
        return String(s[r.upperBound ..< end])
    }

    /// A relationships part with every internal Target passed through `map` (kept when it gives nil).
    static func retarget(_ xml: String, _ map: (String) -> String?) -> String {
        var out = ""
        var at = xml.startIndex
        while let r = xml.rangeOfSubstring("<Relationship ", in: at ..< xml.endIndex) {
            let close = xml[r.upperBound...].firstIndex(of: ">") ?? xml.endIndex
            var tag = String(xml[r.lowerBound ..< close])
            if attr(Substring(tag), "TargetMode") == nil, let t = attr(Substring(tag), "Target"), let n = map(t),
               let a = tag.rangeOfSubstring(" Target=\"") {
                let e = tag[a.upperBound...].firstIndex(of: "\"") ?? tag.endIndex
                tag.replaceSubrange(a.upperBound ..< e, with: n)
            }
            out += xml[at ..< r.lowerBound] + tag
            at = close
        }
        return out + xml[at...]
    }

    /// `xml` with every quoted relationship id in `ids` renamed (only in `attribute` when given).
    static func renameIds(_ xml: String, _ ids: [String: String], attribute: String?) -> String {
        var pieces = xml.split(separator: "\"", omittingEmptySubsequences: false).map(String.init)
        var k = 1
        while k < pieces.count {
            if let n = ids[pieces[k]], attribute.map({ pieces[k - 1].hasSuffix(" " + $0 + "=") || pieces[k - 1].hasSuffix(":" + $0 + "=") }) ?? pieces[k - 1].hasSuffix("=") {
                pieces[k] = n
            }
            k += 2
        }
        return pieces.joined(separator: "\"")
    }
}
