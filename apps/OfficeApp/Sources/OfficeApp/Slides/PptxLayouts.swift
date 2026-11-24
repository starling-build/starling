import Foundation

/// A layout the file itself carries (`ppt/slideLayouts/*`), as the layout
/// gallery lists it.
struct FileLayout: Equatable {
    let part: String
    let name: String
    /// `type` of the layout (`obj`, `title`, `secHead` ...), nil when it has none.
    let type: String?
    let master: String
    /// Position among all masters' layouts, for stable ids.
    let index: Int
}

extension PptxPackage {
    /// Every master's layouts in the order the master lists them
    /// (`p:sldLayoutIdLst`), masters in the order the presentation lists them.
    func fileLayouts() -> [FileLayout] {
        guard let pres = rel("", kind: "officeDocument")?.target, let root = xml(pres) else { return [] }
        let presRels = rels(pres)
        var out: [FileLayout] = []
        for m in root.first("p:sldMasterIdLst")?.all("p:sldMasterId") ?? [] {
            guard let rid = m["r:id"], let master = presRels.first(where: { $0.id == rid })?.target,
                  let mx = xml(master) else { continue }
            let mrels = rels(master)
            for l in mx.first("p:sldLayoutIdLst")?.all("p:sldLayoutId") ?? [] {
                guard let lid = l["r:id"], let part = mrels.first(where: { $0.id == lid })?.target,
                      let lx = xml(part) else { continue }
                let name = lx.first("p:cSld")?["name"] ?? ""
                out.append(FileLayout(part: part, name: name.isEmpty ? "Layout \(out.count + 1)" : name,
                                      type: lx["type"], master: master, index: out.count))
            }
        }
        return out
    }

    /// A one-slide copy of this package whose only slide has an empty
    /// placeholder for each of `layoutPart`'s placeholders (the layout's own
    /// `p:ph` verbatim), so the reader resolves frames, looks and background
    /// exactly as it does for a deck from disk. Nil when the layout is unreadable.
    func layoutPreviewPackage(_ layoutPart: String) -> PptxPackage? {
        guard let pres = rel("", kind: "officeDocument")?.target, let presXml = xml(pres),
              let layout = xml(layoutPart) else { return nil }
        var copy = self
        let slidePart = "ppt/slides/slidePreview.xml"
        var tree = ""
        var n = 1
        for sp in layout.first("p:cSld")?.first("p:spTree")?.all("p:sp") ?? [] {
            guard let ph = sp.first("p:nvSpPr")?.first("p:nvPr")?.first("p:ph") else { continue }
            let type = ph["type"] ?? "obj"
            if type == "dt" || type == "ftr" || type == "sldNum" { continue }
            n += 1
            var attrs = ""
            for key in ["type", "idx", "sz", "orient"] { if let v = ph[key] { attrs += " \(key)=\"\(v)\"" } }
            tree += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(n)\" name=\"Placeholder \(n)\"/><p:cNvSpPr><a:spLocks noGrp=\"1\"/></p:cNvSpPr><p:nvPr><p:ph\(attrs)/></p:nvPr></p:nvSpPr><p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang=\"en-US\"/></a:p></p:txBody></p:sp>"
        }
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
        copy.parts[slidePart] = Data("<p:sld \(ns)><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>\(tree)</p:spTree></p:cSld></p:sld>".utf8)
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout"
        copy.parts[Pptx.relsPath(slidePart)] = Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(rel)\" Target=\"/\(layoutPart)\"/></Relationships>".utf8)
        // The presentation lists just this slide.
        let slideRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
        var presRels = (xml(Pptx.relsPath(pres))?.all("Relationship") ?? []).filter { $0["Type"] != slideRel }
        let relNode = XNode(name: "Relationship", attrs: ["Id": "rIdPreview", "Type": slideRel, "Target": "/" + slidePart])
        presRels.append(relNode)
        let relsRoot = XNode(name: "Relationships", attrs: ["xmlns": "http://schemas.openxmlformats.org/package/2006/relationships"])
        relsRoot.children = presRels
        copy.parts[Pptx.relsPath(pres)] = Data(PptxXML.serialize(relsRoot).utf8)
        let lst = presXml.first("p:sldIdLst") ?? XNode(name: "p:sldIdLst", attrs: [:])
        lst.children = [XNode(name: "p:sldId", attrs: ["id": "256", "r:id": "rIdPreview"])]
        if presXml.first("p:sldIdLst") == nil { presXml.children.append(lst) }
        copy.parts[pres] = Data(PptxXML.serialize(presXml).utf8)
        return copy
    }
}

extension PptxReader {
    /// The slide the layout would give an empty slide: its placeholders (frames
    /// resolved), the layout's own drawn shapes and its background. Nil when unreadable.
    static func layoutPreview(_ package: PptxPackage, layout: String) -> SlideState? {
        guard let copy = package.layoutPreviewPackage(layout),
              let (state, _, _) = try? PptxReader(copy).read() as (DeckState, DeckTheme, PptxPackage),
              let slide = state.slides.first else { return nil }
        return slide
    }
}
