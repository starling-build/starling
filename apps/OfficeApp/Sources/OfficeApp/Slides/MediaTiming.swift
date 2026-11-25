// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The `p:timing` PowerPoint writes for a sound or movie on a slide: one
/// interactive sequence per clip that plays it from the start when the clip
/// is clicked, then one `p:video` / `p:audio` node per clip.
enum MediaTiming {
    static func write(_ clips: [(spid: Int, isVideo: Bool)]) -> String {
        guard !clips.isEmpty else { return "" }
        var id = 1
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
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
            + seqs + nodes + "</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
    }
}
