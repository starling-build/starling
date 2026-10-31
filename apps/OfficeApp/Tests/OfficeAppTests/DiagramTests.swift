import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// SmartArt laid out by this app from its data and layout definition (a
/// deck saved by LibreOffice has no drawing part).
final class DiagramTests: XCTestCase {
    private let dgm = "xmlns:dgm=\"http://schemas.openxmlformats.org/drawingml/2006/diagram\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""

    /// A data model of `texts` as top-level nodes under the document, each
    /// child list given as nested arrays: `["A", ["B", "C"]]` is A with B
    /// and C below it.
    private func data(_ nodes: [Any]) -> XNode {
        var pts = "<dgm:pt modelId=\"doc\" type=\"doc\"><dgm:prSet/><dgm:spPr/></dgm:pt>"
        var cxns = ""
        var n = 0
        func add(_ items: [Any], under parent: String) {
            var i = 0
            while i < items.count {
                let text = items[i] as! String
                n += 1
                let id = "n\(n)"
                pts += "<dgm:pt modelId=\"\(id)\"><dgm:prSet/><dgm:spPr/><dgm:t><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang=\"en-US\"/><a:t>\(text)</a:t></a:r></a:p></dgm:t></dgm:pt>"
                pts += "<dgm:pt modelId=\"\(id)p\" type=\"parTrans\" cxnId=\"c\(n)\"><dgm:prSet/><dgm:spPr/></dgm:pt>"
                pts += "<dgm:pt modelId=\"\(id)s\" type=\"sibTrans\" cxnId=\"c\(n)\"><dgm:prSet/><dgm:spPr/></dgm:pt>"
                cxns += "<dgm:cxn modelId=\"c\(n)\" srcId=\"\(parent)\" destId=\"\(id)\" srcOrd=\"\(i)\" destOrd=\"0\" parTransId=\"\(id)p\" sibTransId=\"\(id)s\"/>"
                if i + 1 < items.count, let kids = items[i + 1] as? [Any] {
                    add(kids, under: id)
                    i += 1
                }
                i += 1
            }
        }
        add(nodes, under: "doc")
        return XNode.parse(Data("<dgm:dataModel \(dgm)><dgm:ptLst>\(pts)</dgm:ptLst><dgm:cxnLst>\(cxns)</dgm:cxnLst></dgm:dataModel>".utf8))!
    }

    private func layout(_ body: String) -> XNode {
        XNode.parse(Data("<dgm:layoutDef \(dgm) uniqueId=\"test\">\(body)</dgm:layoutDef>".utf8))!
    }

    private struct Box { var text: String; var x: Double; var y: Double; var w: Double; var h: Double; var prst: String }

    private func boxes(_ tree: XNode?) -> [Box] {
        (tree?.all("p:sp") ?? []).compactMap { sp in
            guard let x = sp.descendant("a:off"), let e = sp.descendant("a:ext") else { return nil }
            func v(_ s: String?) -> Double { (Double(s ?? "0") ?? 0) / 12700 }
            let text = (sp.first("p:txBody")?.all("a:p") ?? []).map { p in
                p.all("a:r").compactMap { $0.first("a:t")?.text }.joined()
            }.joined(separator: "|")
            return Box(text: text, x: v(x["x"]), y: v(x["y"]), w: v(e["cx"]), h: v(e["cy"]),
                       prst: sp.descendant("a:prstGeom")?["prst"] ?? (sp.descendant("a:custGeom") != nil ? "custom" : "-"))
        }
    }

    /// PowerPoint's Basic Block List: a snake of boxes 0.6 as tall as wide,
    /// in the grid closest to the frame's proportions — four in two rows of
    /// two, the first on the top left.
    func testASnakeOfBoxesInTwoRows() throws {
        let def = layout("""
        <dgm:layoutNode name="diagram"><dgm:varLst><dgm:dir/></dgm:varLst>
          <dgm:alg type="snake"><dgm:param type="grDir" val="tL"/><dgm:param type="flowDir" val="row"/><dgm:param type="contDir" val="sameDir"/><dgm:param type="off" val="ctr"/></dgm:alg>
          <dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="ch" forName="node" refType="w"/><dgm:constr type="h" for="ch" forName="node" refType="w" refFor="ch" refForName="node" fact="0.6"/><dgm:constr type="w" for="ch" forName="sibTrans" refType="w" refFor="ch" refForName="node" fact="0.1"/><dgm:constr type="sp" refType="w" refFor="ch" refForName="sibTrans"/><dgm:constr type="primFontSz" for="ch" forName="node" op="equ" val="65"/></dgm:constrLst>
          <dgm:forEach name="Name3" axis="ch" ptType="node">
            <dgm:layoutNode name="node"><dgm:varLst><dgm:bulletEnabled val="1"/></dgm:varLst><dgm:alg type="tx"/><dgm:shape type="rect"/><dgm:presOf axis="desOrSelf" ptType="node"/><dgm:constrLst/></dgm:layoutNode>
            <dgm:forEach name="Name4" axis="followSib" ptType="sibTrans" cnt="1"><dgm:layoutNode name="sibTrans"><dgm:alg type="sp"/><dgm:shape/><dgm:presOf/><dgm:constrLst/></dgm:layoutNode></dgm:forEach>
          </dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["A", "B", "C", "D"]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 400, 300))
        let b = boxes(tree)
        XCTAssertEqual(b.map(\.text), ["A", "B", "C", "D"])
        XCTAssertEqual(Set(b.map { Int($0.x.rounded()) }).count, 2, "two columns")
        XCTAssertEqual(Set(b.map { Int($0.y.rounded()) }).count, 2, "two rows")
        XCTAssertEqual(b[0].h / b[0].w, 0.6, accuracy: 0.01)
        XCTAssertLessThan(b[0].x, b[1].x)
        XCTAssertEqual(b[0].y, b[1].y, accuracy: 0.01)
        XCTAssertLessThan(b[1].y, b[2].y)
        XCTAssertEqual(b[0].x, b[2].x, accuracy: 0.01)
        // 2w + 0.1w fills the width.
        XCTAssertEqual(b[1].x + b[1].w, 400, accuracy: 1)
        XCTAssertEqual(b[1].x - (b[0].x + b[0].w), b[0].w * 0.1, accuracy: 0.5)
    }

    /// A vertical list: each row's composite as wide as the frame, the rows
    /// fitted into its height, a shape of a given shape and its text in a
    /// chevron (homePlate) beside it; the second-level text bulleted.
    func testAVerticalListFitsItsRows() throws {
        let def = layout("""
        <dgm:layoutNode name="linearFlow"><dgm:varLst><dgm:dir/></dgm:varLst>
          <dgm:alg type="lin"><dgm:param type="linDir" val="fromT"/><dgm:param type="vertAlign" val="mid"/><dgm:param type="horzAlign" val="ctr"/></dgm:alg>
          <dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="ch" forName="composite" refType="w"/><dgm:constr type="h" for="ch" forName="composite" refType="h"/><dgm:constr type="h" for="ch" forName="spacing" refType="h" refFor="ch" refForName="composite" fact="0.25"/><dgm:constr type="primFontSz" for="des" ptType="node" op="equ" val="65"/></dgm:constrLst>
          <dgm:forEach name="Name0" axis="ch" ptType="node">
            <dgm:layoutNode name="composite"><dgm:alg type="composite"/><dgm:shape/><dgm:presOf/>
              <dgm:constrLst><dgm:constr type="w" for="ch" forName="imgShp" refType="w" fact="0.335"/><dgm:constr type="h" for="ch" forName="imgShp" refType="w" refFor="ch" refForName="imgShp" op="equ"/><dgm:constr type="h" for="ch" forName="imgShp" refType="h" op="lte"/><dgm:constr type="ctrY" for="ch" forName="imgShp" refType="h" fact="0.5"/><dgm:constr type="l" for="ch" forName="imgShp"/><dgm:constr type="w" for="ch" forName="txShp" refType="w" op="equ" fact="0.665"/><dgm:constr type="h" for="ch" forName="txShp" refType="h" refFor="ch" refForName="imgShp" op="equ"/><dgm:constr type="ctrY" for="ch" forName="txShp" refType="h" fact="0.5"/><dgm:constr type="l" for="ch" forName="txShp" refType="w" refFor="ch" refForName="imgShp" fact="0.5"/></dgm:constrLst>
              <dgm:layoutNode name="imgShp"><dgm:alg type="sp"/><dgm:shape type="ellipse"/><dgm:presOf/><dgm:constrLst/></dgm:layoutNode>
              <dgm:layoutNode name="txShp"><dgm:varLst><dgm:bulletEnabled val="1"/></dgm:varLst><dgm:alg type="tx"/><dgm:shape type="homePlate" zOrderOff="-1"/><dgm:presOf axis="desOrSelf" ptType="node"/><dgm:constrLst/></dgm:layoutNode>
            </dgm:layoutNode>
            <dgm:forEach name="Name7" axis="followSib" ptType="sibTrans" cnt="1"><dgm:layoutNode name="spacing"><dgm:alg type="sp"/><dgm:shape/><dgm:presOf axis="self"/><dgm:constrLst/></dgm:layoutNode></dgm:forEach>
          </dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["One", ["detail"], "Two", "Three"]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 600, 300))
        let b = boxes(tree)
        XCTAssertEqual(b.count, 6, "an ellipse and a text shape per row")
        let plates = b.filter { $0.prst == "homePlate" }
        XCTAssertEqual(plates.map(\.text), ["One|detail", "Two", "Three"])
        guard plates.count == 3, b.count == 6 else { return }
        // `zOrderOff="-1"` on the plate: behind the circle that precedes it.
        XCTAssertEqual(b.prefix(2).map(\.prst), ["homePlate", "ellipse"], "the plate is behind its circle")
        let circle = b.first { $0.prst == "ellipse" }!
        XCTAssertEqual(plates[0].x, circle.x + circle.w * 0.5, accuracy: 0.5, "the plate starts halfway into the circle")
        XCTAssertLessThan(plates[0].y, plates[1].y)
        XCTAssertLessThan(plates[1].y, plates[2].y)
        XCTAssertLessThanOrEqual(plates[2].y + plates[2].h, 300.5, "fitted into the frame")
        XCTAssertEqual(circle.w, circle.h, accuracy: 0.01, "the circle is round")
        // The second-level text is a bulleted paragraph at level 1.
        let sp = try XCTUnwrap(tree?.all("p:sp").first { $0.descendant("a:t")?.text == "One" })
        let paras = sp.first("p:txBody")!.all("a:p")
        XCTAssertEqual(paras[1].first("a:pPr")?["lvl"], "1")
        XCTAssertNotNil(paras[1].first("a:pPr")?.first("a:buChar"))
        XCTAssertNil(paras[0].first("a:pPr")?.first("a:buChar"))
    }

    /// Nodes round a cycle, from the top clockwise, each turned to point
    /// inward when the path says so.
    func testACycleGoesRoundFromTheTop() throws {
        let def = layout("""
        <dgm:layoutNode name="cycle"><dgm:varLst><dgm:dir/></dgm:varLst>
          <dgm:alg type="cycle"><dgm:param type="stAng" val="0"/><dgm:param type="spanAng" val="360"/><dgm:param type="rotPath" val="alongPath"/></dgm:alg>
          <dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="ch" ptType="node" refType="w"/><dgm:constr type="h" for="ch" ptType="node" refType="w" refFor="ch" refPtType="node" op="equ"/><dgm:constr type="sibSp" refType="w" refFor="ch" refPtType="node" fact="0.1"/></dgm:constrLst>
          <dgm:forEach name="n" axis="ch" ptType="node">
            <dgm:layoutNode name="arrow"><dgm:alg type="tx"/><dgm:shape type="downArrow"/><dgm:presOf axis="desOrSelf" ptType="node"/><dgm:constrLst/></dgm:layoutNode>
          </dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["a", "b", "c", "d"]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 400, 400))
        // A shape turned a quarter round keeps its text upright, in a
        // shape of its own over it.
        let sps = tree!.all("p:sp")
        let arrows = sps.filter { !($0.descendant("p:cNvPr")?["name"] ?? "").hasSuffix(" text") }
        let b = boxes(tree)
        XCTAssertEqual(b.map(\.text).filter { !$0.isEmpty }, ["a", "b", "c", "d"])
        let ab = b.enumerated().filter { !(sps[$0.offset].descendant("p:cNvPr")?["name"] ?? "").hasSuffix(" text") }.map(\.element)
        let cx = ab.map { $0.x + $0.w / 2 }, cy = ab.map { $0.y + $0.h / 2 }
        XCTAssertEqual(cx[0], 200, accuracy: 1, "a at the top")
        XCTAssertLessThan(cy[0], cy[1])
        XCTAssertGreaterThan(cx[1], cx[0] + 50, "b to the right")
        XCTAssertEqual(cy[2], 400 - cy[0], accuracy: 1, "c at the bottom, mirrored")
        XCTAssertLessThan(cx[3], cx[0] - 50, "d to the left")
        let rots = arrows.map { $0.descendant("a:xfrm")?["rot"] ?? "0" }
        XCTAssertEqual(rots, ["0", "5400000", "10800000", "16200000"], "turned along the path")
        XCTAssertEqual(sps.count, 7, "b, c and d have their text upright beside them")
        let cText = try XCTUnwrap(sps.first { $0.descendant("p:cNvPr")?["name"]?.hasSuffix(" text") == true && $0.descendant("a:t")?.text == "c" })
        XCTAssertNil(cText.descendant("a:xfrm")?["rot"], "turned half round, its text is not on its head")
    }

    /// A hierarchy: the root centred above its children, side by side, and
    /// a bent connector from its bottom to each child's top.
    func testAHierarchyHangsItsChildrenBelow() throws {
        let def = layout("""
        <dgm:layoutNode name="hierChild1"><dgm:varLst><dgm:orgChart val="1"/><dgm:dir/></dgm:varLst>
          <dgm:alg type="hierChild"/><dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="des" forName="rootComposite" refType="w" fact="10"/><dgm:constr type="h" for="des" forName="rootComposite" refType="w" refFor="des" refForName="rootComposite" fact="0.5"/><dgm:constr type="sp" for="des" forName="hierRoot" refType="w" refFor="des" refForName="rootComposite" fact="0.2"/><dgm:constr type="sibSp" for="des" forName="hierChild2" refType="w" refFor="des" refForName="rootComposite" fact="0.2"/></dgm:constrLst>
          <dgm:forEach name="top" axis="ch" ptType="node"><dgm:forEach name="r" axis="self" ptType="node">
            <dgm:layoutNode name="hierRoot"><dgm:varLst><dgm:hierBranch val="std"/></dgm:varLst><dgm:alg type="hierRoot"/><dgm:shape/><dgm:presOf/>
              <dgm:layoutNode name="rootComposite"><dgm:alg type="composite"/><dgm:shape/><dgm:presOf axis="self" ptType="node" cnt="1"/>
                <dgm:constrLst><dgm:constr type="l" for="ch" forName="rootText"/><dgm:constr type="t" for="ch" forName="rootText"/><dgm:constr type="w" for="ch" forName="rootText" refType="w"/><dgm:constr type="h" for="ch" forName="rootText" refType="h"/></dgm:constrLst>
                <dgm:layoutNode name="rootText" styleLbl="node0"><dgm:alg type="tx"/><dgm:shape type="rect"/><dgm:presOf axis="self" ptType="node" cnt="1"/><dgm:constrLst/></dgm:layoutNode>
              </dgm:layoutNode>
              <dgm:layoutNode name="hierChild2"><dgm:alg type="hierChild"/><dgm:shape/><dgm:presOf/>
                <dgm:forEach name="rep" axis="ch" ptType="nonAsst">
                  <dgm:forEach name="c" axis="precedSib" ptType="parTrans" st="-1" cnt="1">
                    <dgm:layoutNode name="conn"><dgm:alg type="conn"><dgm:param type="connRout" val="bend"/><dgm:param type="dim" val="1D"/><dgm:param type="begPts" val="bCtr"/><dgm:param type="endPts" val="tCtr"/></dgm:alg><dgm:shape type="conn" zOrderOff="-99999"/><dgm:presOf axis="self"/><dgm:constrLst/></dgm:layoutNode>
                  </dgm:forEach>
                  <dgm:forEach name="again" ref="r"/>
                </dgm:forEach>
              </dgm:layoutNode>
            </dgm:layoutNode>
          </dgm:forEach></dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["A", ["B1", "B2"]]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 400, 300))
        let b = boxes(tree)
        let texts = b.filter { $0.prst == "rect" }
        XCTAssertEqual(texts.map(\.text), ["A", "B1", "B2"])
        guard texts.count == 3 else { return }
        let a = texts[0], b1 = texts[1], b2 = texts[2]
        XCTAssertLessThan(a.y + a.h, b1.y, "children below the root")
        XCTAssertEqual(b1.y, b2.y, accuracy: 0.01)
        XCTAssertEqual(a.x + a.w / 2, (b1.x + b2.x + b2.w) / 2, accuracy: 1, "root centred over its children")
        XCTAssertEqual(b1.h / b1.w, 0.5, accuracy: 0.01, "boxes twice as wide as tall")
        XCTAssertEqual(b.filter { $0.prst == "custom" }.count, 2, "a connector to each child")
        XCTAssertGreaterThanOrEqual(b.map(\.x).min() ?? -1, -0.5, "fitted into the frame")
        XCTAssertLessThanOrEqual(b.map { $0.x + $0.w }.max() ?? 1000, 400.5)
    }

    /// A second root with nothing under it stands one gap beside the first
    /// root's box, over the first root's children — not past them
    /// (lo-smartart-org-chart, as PowerPoint draws it).
    func testASiblingPacksAgainstTheOutlineNotTheBoundingBox() throws {
        let def = layout("""
        <dgm:layoutNode name="hierChild1"><dgm:varLst><dgm:orgChart val="1"/><dgm:dir/></dgm:varLst>
          <dgm:alg type="hierChild"/><dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="des" forName="rootComposite" refType="w" fact="10"/><dgm:constr type="h" for="des" forName="rootComposite" refType="w" refFor="des" refForName="rootComposite" fact="0.5"/><dgm:constr type="sp" for="des" forName="hierRoot" refType="w" refFor="des" refForName="rootComposite" fact="0.2"/><dgm:constr type="sibSp" for="des" forName="hierChild2" refType="w" refFor="des" refForName="rootComposite" fact="0.2"/><dgm:constr type="sibSp" refType="w" refFor="des" refForName="rootComposite" fact="0.2"/></dgm:constrLst>
          <dgm:forEach name="top" axis="ch" ptType="node"><dgm:forEach name="r" axis="self" ptType="node">
            <dgm:layoutNode name="hierRoot"><dgm:alg type="hierRoot"/><dgm:shape/><dgm:presOf/>
              <dgm:layoutNode name="rootComposite"><dgm:alg type="composite"/><dgm:shape/><dgm:presOf axis="self" ptType="node" cnt="1"/>
                <dgm:constrLst><dgm:constr type="l" for="ch" forName="rootText"/><dgm:constr type="t" for="ch" forName="rootText"/><dgm:constr type="w" for="ch" forName="rootText" refType="w"/><dgm:constr type="h" for="ch" forName="rootText" refType="h"/></dgm:constrLst>
                <dgm:layoutNode name="rootText"><dgm:alg type="tx"/><dgm:shape type="rect"/><dgm:presOf axis="self" ptType="node" cnt="1"/><dgm:constrLst/></dgm:layoutNode>
              </dgm:layoutNode>
              <dgm:layoutNode name="hierChild2"><dgm:alg type="hierChild"/><dgm:shape/><dgm:presOf/>
                <dgm:forEach name="rep" axis="ch" ptType="nonAsst"><dgm:forEach name="again" ref="r"/></dgm:forEach>
              </dgm:layoutNode>
            </dgm:layoutNode>
          </dgm:forEach></dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["A", ["B1", "B2"], "C"]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 600, 300))
        let t = boxes(tree).filter { $0.prst == "rect" }
        XCTAssertEqual(t.map(\.text), ["A", "B1", "B2", "C"])
        guard t.count == 4 else { return }
        let a = t[0], b2 = t[2], c = t[3]
        XCTAssertEqual(c.y, a.y, accuracy: 0.01, "C on A's row")
        XCTAssertEqual(c.x - (a.x + a.w), 0.2 * a.w, accuracy: 0.5, "one gap beside A's box")
        XCTAssertLessThan(c.x, b2.x + b2.w, "over A's children, not past them")
    }

    /// A height given in font sizes is millimetres, and a layout that may
    /// shrink its text does, to the largest whole size whose boxes fit:
    /// 2 × 65 mm is 368.5 pt, too tall for 200; 2 × 35 mm, 198.4, fits.
    func testFontSizedBoxesAreMillimetresAndShrinkToFit() throws {
        let def = layout("""
        <dgm:layoutNode name="row"><dgm:alg type="lin"/><dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="ch" forName="node" refType="w" fact="0.3"/><dgm:constr type="primFontSz" for="ch" forName="node" val="65"/><dgm:constr type="h" for="ch" forName="node" refType="primFontSz" refFor="ch" refForName="node" fact="2"/></dgm:constrLst>
          <dgm:ruleLst><dgm:rule type="primFontSz" for="ch" forName="node" val="5" fact="NaN" max="NaN"/></dgm:ruleLst>
          <dgm:forEach name="n" axis="ch" ptType="node">
            <dgm:layoutNode name="node"><dgm:alg type="tx"/><dgm:shape type="rect"/><dgm:presOf axis="desOrSelf" ptType="node"/><dgm:constrLst/></dgm:layoutNode>
          </dgm:forEach>
        </dgm:layoutNode>
        """)
        let tree = DiagramLayout.render(data: data(["a"]), layout: def, colors: nil, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 600, 200))
        let b = try XCTUnwrap(boxes(tree).first)
        XCTAssertEqual(b.h, 2 * 35 * 72 / 25.4, accuracy: 0.1)
        XCTAssertEqual(b.w, 180, accuracy: 0.1, "the width its constraint gives, not scaled down")
        XCTAssertEqual(tree?.all("p:sp").first?.descendant("a:rPr")?["sz"], "3500")
    }

    /// A diagram's margins shrink with its text; the share of the insets
    /// that is the shape's own text rectangle (an oval's inscribed box)
    /// does not.
    func testTheGeometrysInsetStaysWhenTheMarginsShrink() {
        let shape = SlideShape(id: 1, name: "Oval", kind: .geometry(.ellipse), frame: Rect.fromLTWH(0, 0, 200, 200),
                               text: nil, textTheme: nil)
        shape.insets = EdgeInsets(left: 35, top: 35, right: 35, bottom: 35)
        shape.shapeInsets = EdgeInsets(left: 29, top: 29, right: 29, bottom: 29)
        shape.insetsFollowFont = true
        shape.fontScale = 0.5
        XCTAssertEqual(shape.drawInsets.left, 29 + 6 * 0.5, accuracy: 1e-9)
        shape.insetsFollowFont = false
        XCTAssertEqual(shape.drawInsets.left, 35)
    }

    /// The style label's colours: a scheme colour per shape, repeating.
    func testTheColourSchemeFillsTheShapes() throws {
        let def = layout("""
        <dgm:layoutNode name="diagram"><dgm:alg type="lin"/><dgm:shape/><dgm:presOf/>
          <dgm:constrLst><dgm:constr type="w" for="ch" forName="node" refType="w"/></dgm:constrLst>
          <dgm:forEach name="n" axis="ch" ptType="node"><dgm:layoutNode name="node"><dgm:alg type="tx"/><dgm:shape type="roundRect"/><dgm:presOf axis="self"/><dgm:constrLst/></dgm:layoutNode></dgm:forEach>
        </dgm:layoutNode>
        """)
        let colors = XNode.parse(Data("<dgm:colorsDef \(dgm)><dgm:styleLbl name=\"node1\"><dgm:fillClrLst meth=\"cycle\"><a:schemeClr val=\"accent2\"/><a:schemeClr val=\"accent4\"/></dgm:fillClrLst><dgm:linClrLst meth=\"repeat\"><a:schemeClr val=\"lt1\"/></dgm:linClrLst></dgm:styleLbl></dgm:colorsDef>".utf8))!
        let tree = DiagramLayout.render(data: data(["a", "b", "c"]), layout: def, colors: colors, style: nil,
                                        frame: Rect.fromLTWH(0, 0, 300, 100))
        let fills = tree!.all("p:sp").map { $0.first("p:spPr")?.first("a:solidFill")?.first("a:schemeClr")?["val"] ?? "-" }
        XCTAssertEqual(fills, ["accent2", "accent4", "accent2"])
        XCTAssertEqual(tree!.all("p:sp").first?.first("p:spPr")?.first("a:ln")?.first("a:solidFill")?.first("a:schemeClr")?["val"], "lt1")
    }
}
