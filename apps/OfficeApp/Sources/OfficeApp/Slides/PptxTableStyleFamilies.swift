// PowerPoint's built-in table styles, every family in every colour, keyed by style id.
// A deck that names one without defining it (other writers leave the id alone) is drawn
// as PowerPoint draws it. Each family's rules (borders, fills, bands, bold edges) were read
// off PowerPoint's own print of a table in every style (lab/tstyles) and match the
// definitions PowerPoint writes into decks that use the styles. Merged last in
// PptxTemplates.builtinTableStyles, so a definition already there wins.
extension PptxTemplates {
    static let builtinTableStyleFamilies: [String: String] = {
        // (family name, id of the colourless variant, ids for Accent 1...6)
        let families: [(String, String?, [String])] = [
        ("Themed Style 1", nil, ["{3C2FFA5D-87B4-456A-9821-1D502468CF0F}", "{284E427A-3D55-4303-BF80-6455036E1DE7}", "{69C7853C-536D-4A76-A0AE-DD22124D55A5}", "{775DCB02-9BB8-47FD-8907-85C794F793BA}", "{35758FB7-9AC5-4552-8A53-C91805E547FA}", "{08FB837D-C827-4EFA-A057-4D05807E0F7C}"]),
        ("Themed Style 2", nil, ["{D113A9D2-9D6B-4929-AA2D-F23B5EE8CBE7}", "{18603FDC-E32A-4AB5-989C-0864C3EAD2B8}", "{306799F8-075E-4A3A-A7F6-7FBC6576F1A4}", "{E269D01E-BC32-4049-B463-5C60D7B0CCD2}", "{327F97BB-C833-4FB7-BDE5-3F7075034690}", "{638B1855-1B75-4FBE-930C-398BA8C253C6}"]),
        ("Light Style 1", "{9D7B26C5-4107-4FEC-AEDC-1716B250A1EF}", ["{3B4B98B0-60AC-42C2-AFA5-B58CD77FA1E5}", "{0E3FDE45-AF77-4B5C-9715-49D594BDF05E}", "{C083E6E3-FA7D-4D7B-A595-EF9225AFEA82}", "{D27102A9-8310-4765-A935-A1911B00CA55}", "{5FD0F851-EC5A-4D38-B0AD-8093EC10F338}", "{68D230F3-CF80-4859-8CE7-A43EE81993B5}"]),
        ("Light Style 2", "{7E9639D4-E3E2-4D34-9284-5A2195B3D0D7}", ["{69012ECD-51FC-41F1-AA8D-1B2483CD663E}", "{72833802-FEF1-4C79-8D5D-14CF1EAF98D9}", "{F2DE63D5-997A-4646-A377-4702673A728D}", "{17292A2E-F333-43FB-9621-5CBBE7FDCDCB}", "{5A111915-BE36-4E01-A7E5-04B1672EAD32}", "{912C8C85-51F0-491E-9774-3900AFEF0FD7}"]),
        ("Light Style 3", "{616DA210-FB5B-4158-B5E0-FEB733F419BA}", ["{BC89EF96-8CEA-46FF-86C4-4CE0E7609802}", "{5DA37D80-6434-44D0-A028-1B22A696006F}", "{8799B23B-EC83-4686-B30A-512413B5E67A}", "{ED083AE6-46FA-4A59-8FB0-9F97EB10719F}", "{BDBED569-4797-4DF1-A0F4-6AAB3CD982D8}", "{E8B1032C-EA38-4F05-BA0D-38AFFFC7BED3}"]),
        ("Medium Style 1", "{793D81CF-94F2-401A-BA57-92F5A7B2D0C5}", ["{B301B821-A1FF-4177-AEE7-76D212191A09}", "{9DCAF9ED-07DC-4A11-8D7F-57B35C25682E}", "{1FECB4D8-DB02-4DC6-A0A2-4F2EBAE1DC90}", "{1E171933-4619-4E11-9A3F-F7608DF75F80}", "{FABFCF23-3B69-468F-B69F-88F6DE6A72F2}", "{10A1B5D5-9B99-4C35-A422-299274C87663}"]),
        ("Medium Style 2", "{073A0DAA-6AF3-43AB-8588-CEC1D06C72B9}", ["{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}", "{21E4AEA4-8DFA-4A89-87EB-49C32662AFE0}", "{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}", "{00A15C55-8517-42AA-B614-E9B94910E393}", "{7DF18680-E054-41AD-8BC1-D1AEF772440D}", "{93296810-A885-4BE3-A3E7-6D5BEEA58F35}"]),
        ("Medium Style 3", "{8EC20E35-A176-4012-BC5E-935CFFF8708E}", ["{6E25E649-3F16-4E02-A733-19D2CDBF48F0}", "{85BE263C-DBD7-4A20-BB59-AAB30ACAA65A}", "{EB344D84-9AFB-497E-A393-DC336BA19D2E}", "{EB9631B5-78F2-41C9-869B-9F39066F8104}", "{74C1A8A3-306A-4EB7-A6B1-4F7E0EB9C5D6}", "{2A488322-F2BA-4B5B-9748-0D474271808F}"]),
        ("Medium Style 4", "{D7AC3CCA-C797-4891-BE02-D94E43425B78}", ["{69CF1AB2-1976-4502-BF36-3FF5EA218861}", "{8A107856-5554-42FB-B03E-39F5DBC370BA}", "{0505E3EF-67EA-436B-97B2-0124C06EBD24}", "{C4B1156A-380E-4F78-BDF5-A606A8083BF9}", "{22838BEF-8BB2-4498-84A7-C5851F593DF1}", "{16D9F66E-5EB9-4882-86FB-DCBF35E3C3E4}"]),
        ("Dark Style 1", "{E8034E78-7F5D-4C2E-B375-FC64B27BC917}", ["{125E5076-3810-47DD-B79F-674D7AD40C01}", "{37CE84F3-28C3-443E-9E96-99CF82512B78}", "{D03447BB-5D67-496B-8E87-E561075AD55C}", "{E929F9F4-4A8F-4326-A1B4-22849713DDAB}", "{8FD4443E-F989-4FC4-A0C8-D5A2AF1F390B}", "{AF606853-7671-496A-8E4F-DF71F8EC918B}"]),
        ("Dark Style 2", "{5202B0CA-FC54-4496-8BCA-5EF66A818D29}", ["{0660B408-B3CF-4A94-85FC-2B1E0A45F4A2}", "{91EBBBCC-DAD2-459C-BE2E-F6DE35CF9A28}", "{46F890A9-2807-4EBB-B81D-B2AA78EC7F39}"]),
        ]
        let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func clr(_ c: String, _ mod: String = "") -> String {
            mod.isEmpty ? "<a:schemeClr val=\"\(c)\"/>" : "<a:schemeClr val=\"\(c)\">\(mod)</a:schemeClr>"
        }
        func solid(_ c: String, _ mod: String = "") -> String { "<a:fill><a:solidFill>\(clr(c, mod))</a:solidFill></a:fill>" }
        let none = "<a:fill><a:noFill/></a:fill>"
        func ln(_ w: Int, _ c: String, _ cmpd: String = "sng") -> String {
            "<a:ln w=\"\(w)\" cmpd=\"\(cmpd)\"><a:solidFill>\(clr(c))</a:solidFill></a:ln>"
        }
        let noLn = "<a:ln><a:noFill/></a:ln>"
        func bdr(_ l: String, _ r: String, _ t: String, _ b: String, _ h: String, _ v: String) -> String {
            "<a:tcBdr><a:left>\(l)</a:left><a:right>\(r)</a:right><a:top>\(t)</a:top><a:bottom>\(b)</a:bottom><a:insideH>\(h)</a:insideH><a:insideV>\(v)</a:insideV></a:tcBdr>"
        }
        func part(_ tag: String, _ tx: String, _ border: String, _ fill: String) -> String {
            "<a:\(tag)>\(tx)<a:tcStyle>\(border.isEmpty ? "<a:tcBdr/>" : "<a:tcBdr>\(border)</a:tcBdr>")\(fill)</a:tcStyle></a:\(tag)>"
        }
        let bold = "<a:tcTxStyle b=\"on\"/>"
        func txt(_ c: String, bold b: Bool = false) -> String {
            "<a:tcTxStyle\(b ? " b=\"on\"" : "")><a:fontRef idx=\"minor\"><a:prstClr val=\"black\"/></a:fontRef>\(clr(c))</a:tcTxStyle>"
        }
        func wrap(_ id: String, _ name: String, _ body: String) -> String {
            "<a:tblStyle \(ns) styleId=\"\(id)\" styleName=\"\(name)\">\(body)</a:tblStyle>"
        }
        let a20 = "<a:alpha val=\"20000\"/>"
        var out: [String: String] = [:]
        for (fam, noAccent, ids) in families {
            // colour variants: (id, name, colour for rules/fills, second colour for Dark 2's header)
            var variants: [(String, String, String, String)] = []
            if let na = noAccent { variants.append((na, fam, fam.hasPrefix("Light") ? "tx1" : "dk1", "dk1")) }
            for (i, id) in ids.enumerated() {
                if fam == "Dark Style 2" {
                    variants.append((id, "\(fam) - Accent \(2 * i + 1)/Accent \(2 * i + 2)", "accent\(2 * i + 1)", "accent\(2 * i + 2)"))
                } else {
                    variants.append((id, "\(fam) - Accent \(i + 1)", "accent\(i + 1)", "accent\(i + 1)"))
                }
            }
            for (id, name, c, c2) in variants {
                let isNone = noAccent != nil && id == noAccent
                let dark = isNone ? "dk1" : c
                var body = ""
                switch fam {
                case "Light Style 1":
                    body = "<a:wholeTbl>\(txt("tx1"))<a:tcStyle>" + bdr(noLn, noLn, ln(12700, c), ln(12700, c), noLn, noLn) + none + "</a:tcStyle></a:wholeTbl>"
                        + "<a:band1H><a:tcStyle><a:tcBdr/>\(solid(c, a20))</a:tcStyle></a:band1H><a:band2H><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2H>"
                        + "<a:band1V><a:tcStyle><a:tcBdr/>\(solid(c, a20))</a:tcStyle></a:band1V><a:band2V><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2V>"
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(12700, c))</a:top>", none)
                        + part("firstRow", bold, "<a:bottom>\(ln(12700, c))</a:bottom>", none)
                case "Light Style 2":
                    let all = ln(12700, c)
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(all, all, all, all, noLn, noLn) + none + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "<a:top>\(all)</a:top><a:bottom>\(all)</a:bottom>", "")
                        + "<a:band2H><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2H>"
                        + part("band1V", "", "<a:left>\(all)</a:left><a:right>\(all)</a:right>", "")
                        + "<a:band2V><a:tcStyle><a:tcBdr/></a:tcStyle></a:band2V>"
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(50800, c, "dbl"))</a:top>", "")
                        + part("firstRow", txt("bg1", bold: true), "", solid(c))
                case "Light Style 3":
                    let all = ln(12700, c)
                    body = "<a:wholeTbl>\(txt("tx1"))<a:tcStyle>" + bdr(all, all, all, all, all, all) + none + "</a:tcStyle></a:wholeTbl>"
                        + "<a:band1H><a:tcStyle><a:tcBdr/>\(solid(c, a20))</a:tcStyle></a:band1H>"
                        + "<a:band1V><a:tcStyle><a:tcBdr/>\(solid(c, a20))</a:tcStyle></a:band1V>"
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(50800, c, "dbl"))</a:top>", none)
                        + part("firstRow", bold, "<a:bottom>\(ln(25400, c))</a:bottom>", none)
                case "Medium Style 1":
                    let all = ln(12700, c)
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(all, all, all, all, all, noLn) + solid("lt1") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid(dark, "<a:tint val=\"20000\"/>"))
                        + part("band1V", "", "", solid(dark, "<a:tint val=\"20000\"/>"))
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(50800, c, "dbl"))</a:top>", solid("lt1"))
                        + part("firstRow", txt("lt1", bold: true), "", solid(c))
                case "Medium Style 3":
                    let top = ln(25400, "dk1")
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(noLn, noLn, top, top, noLn, noLn) + solid("lt1") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid("dk1", "<a:tint val=\"20000\"/>"))
                        + part("band1V", "", "", solid("dk1", "<a:tint val=\"20000\"/>"))
                        + part("lastCol", txt("lt1", bold: true), "", solid(c)) + part("firstCol", txt("lt1", bold: true), "", solid(c))
                        + part("lastRow", bold, "<a:top>\(ln(50800, "dk1", "dbl"))</a:top>", solid("lt1"))
                        + part("firstRow", txt("lt1", bold: true), "<a:bottom>\(top)</a:bottom>", solid(c))
                case "Medium Style 4":
                    let all = ln(12700, dark)
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(all, all, all, all, all, all) + solid(dark, "<a:tint val=\"20000\"/>") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid(dark, "<a:tint val=\"40000\"/>"))
                        + part("band1V", "", "", solid(dark, "<a:tint val=\"40000\"/>"))
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(25400, dark))</a:top>", solid(dark, "<a:tint val=\"20000\"/>"))
                        + part("firstRow", bold, "", solid(dark, "<a:tint val=\"20000\"/>"))
                case "Dark Style 1":
                    let w = ln(25400, "lt1")
                    let base = isNone ? solid("dk1", "<a:tint val=\"20000\"/>") : solid(c)
                    let band = isNone ? solid("dk1", "<a:tint val=\"40000\"/>") : solid(c, "<a:shade val=\"60000\"/>")
                    let edge = isNone ? solid("dk1", "<a:tint val=\"60000\"/>") : solid(c, "<a:shade val=\"60000\"/>")
                    let last = isNone ? solid("dk1", "<a:tint val=\"60000\"/>") : solid(c, "<a:shade val=\"40000\"/>")
                    body = "<a:wholeTbl>\(txt("lt1"))<a:tcStyle>" + bdr(noLn, noLn, noLn, noLn, noLn, noLn) + base + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", band) + part("band1V", "", "", band)
                        + part("lastCol", txt("lt1", bold: true), "<a:left>\(w)</a:left>", edge)
                        + part("firstCol", txt("lt1", bold: true), "<a:right>\(w)</a:right>", edge)
                        + part("lastRow", txt("lt1", bold: true), "<a:top>\(w)</a:top>", last)
                        + part("firstRow", txt("lt1", bold: true), "<a:bottom>\(w)</a:bottom>", solid("dk1"))
                case "Dark Style 2":
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(noLn, noLn, noLn, noLn, noLn, noLn) + solid(c, "<a:tint val=\"20000\"/>") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid(c, "<a:tint val=\"40000\"/>"))
                        + part("band1V", "", "", solid(c, "<a:tint val=\"40000\"/>"))
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "", "")
                        + part("lastRow", bold, "<a:top>\(ln(50800, "dk1", "dbl"))</a:top>", "")
                        + part("firstRow", txt("lt1", bold: true), "", solid(c2))
                case "Themed Style 1":
                    // Accent rules, white rows; PowerPoint also gives the table a soft
                    // gradient and shadow from the theme's effect styles, drawn here as flat tints.
                    let acc = ln(12700, c)
                    body = "<a:wholeTbl>\(txt("dk1"))<a:tcStyle>" + bdr(acc, acc, acc, acc, ln(12700, "lt1"), acc) + solid(c, "<a:tint val=\"40000\"/>") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid(c, "<a:tint val=\"60000\"/>"))
                        + part("band1V", "", "", solid(c, "<a:tint val=\"60000\"/>"))
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "<a:right>\(ln(25400, c))</a:right>", "")
                        + part("lastRow", bold, "<a:top>\(ln(25400, c))</a:top>", solid(c, "<a:tint val=\"40000\"/>"))
                        + part("firstRow", txt("lt1", bold: true), "", solid(c))
                default: // Themed Style 2: white rules over dark tints of the colour
                    let w = ln(12700, "lt1")
                    body = "<a:wholeTbl>\(txt("lt1"))<a:tcStyle>" + bdr(noLn, noLn, noLn, noLn, w, noLn) + solid(c, "<a:shade val=\"75000\"/>") + "</a:tcStyle></a:wholeTbl>"
                        + part("band1H", "", "", solid(c, "<a:tint val=\"90000\"/>"))
                        + part("band1V", "", "", solid(c, "<a:tint val=\"90000\"/>"))
                        + part("lastCol", bold, "", "") + part("firstCol", bold, "<a:right>\(ln(25400, "lt1"))</a:right>", "")
                        + part("lastRow", bold, "<a:top>\(ln(25400, "lt1"))</a:top>", solid(c, "<a:shade val=\"65000\"/>"))
                        + part("firstRow", txt("lt1", bold: true), "<a:bottom>\(ln(25400, "lt1"))</a:bottom>", solid(c, "<a:shade val=\"90000\"/>"))
                }
                out[id] = wrap(id, name, body)
            }
        }
        return out
    }()
}
