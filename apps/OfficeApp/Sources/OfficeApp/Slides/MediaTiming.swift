// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The `p:timing` PowerPoint writes for a sound or movie on a slide: one
/// interactive sequence per clip that plays it from the start when the clip
/// is clicked, then one `p:video` / `p:audio` node per clip.
enum MediaTiming {
    static func write(_ clips: [(spid: Int, isVideo: Bool)]) -> String {
        guard !clips.isEmpty else { return "" }
        let (seqs, nodes) = fragments(clips, after: 1)
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
            + seqs + nodes + "</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
    }

    /// The clips' timing added to a slide's existing tree (its animations),
    /// as PowerPoint does: the interactive sequences and media nodes join
    /// the root's children, numbered after the tree's own nodes.
    static func merge(_ clips: [(spid: Int, isVideo: Bool)], into timing: String) -> String {
        guard !clips.isEmpty else { return timing }
        let tail = "</p:childTnLst></p:cTn></p:par></p:tnLst>"
        // The last occurrence (the root's own close), found with the wasm-safe helper.
        var found: Range<String.Index>?
        var from = timing.startIndex
        while let r = timing.rangeOfSubstring(tail, in: from..<timing.endIndex) { found = r; from = r.upperBound }
        guard let end = found else { return timing }
        // Every node's id, wherever it sits in the tag: a tree read from a file need not list it first.
        let top = timing.components(separatedBy: "<p:cTn ").dropFirst().compactMap { tag -> Int? in
            let head = " " + String(tag.prefix { $0 != ">" })
            guard let r = head.rangeOfSubstring(" id=\"") else { return nil }
            return Int(head[r.upperBound...].prefix { $0.isNumber })
        }.max() ?? 1
        let (seqs, nodes) = fragments(clips, after: top)
        var out = timing
        out.insert(contentsOf: seqs + nodes, at: end.lowerBound)
        return out
    }

    private static func fragments(_ clips: [(spid: Int, isVideo: Bool)], after top: Int) -> (String, String) {
        var id = top
        func next() -> Int { id += 1; return id }
        var seqs = "", nodes = ""
        for c in clips {
            let target = "<p:tgtEl><p:spTgt spid=\"\(c.spid)\"/></p:tgtEl>"
            let seq = next(), outer = next(), inner = next(), cmd = next()
            seqs += "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"\(seq)\" restart=\"whenNotActive\" fill=\"hold\" evtFilter=\"cancelBubble\" nodeType=\"interactiveSeq\">"
                + "<p:stCondLst><p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond></p:stCondLst>"
                + "<p:endSyncLst><p:cond evt=\"onStopAudio\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:endSyncLst>"
                + "<p:childTnLst><p:par><p:cTn id=\"\(outer)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
                + "<p:par><p:cTn id=\"\(inner)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>"
                + "<p:cmd type=\"call\" cmd=\"playFrom(0.0)\"><p:cBhvr><p:cTn id=\"\(cmd)\" dur=\"1\" fill=\"hold\"/>\(target)</p:cBhvr></p:cmd>"
                + "</p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn></p:par></p:childTnLst></p:cTn>"
                + "<p:nextCondLst><p:cond evt=\"onClick\" delay=\"0\">\(target)</p:cond></p:nextCondLst></p:seq>"
            let node = next()
            let tag = c.isVideo ? "p:video" : "p:audio"
            let media = c.isVideo ? "<p:cMediaNode vol=\"80000\">" : "<p:cMediaNode vol=\"80000\" showWhenStopped=\"0\">"
            nodes += "<\(tag)>\(media)<p:cTn id=\"\(node)\" fill=\"hold\"\(c.isVideo ? " display=\"0\"" : "")>"
                + "<p:stCondLst><p:cond delay=\"indefinite\"/><p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"\(seq)\"/></p:cond></p:stCondLst>"
                + "<p:endCondLst><p:cond evt=\"onStopAudio\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:endCondLst></p:cTn>"
                + "\(target)</p:cMediaNode></\(tag)>"
        }
        return (seqs, nodes)
    }
}
