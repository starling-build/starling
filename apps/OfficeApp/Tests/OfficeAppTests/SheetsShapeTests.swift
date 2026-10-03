// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsShapeTests: XCTestCase {
    private let ns = "xmlns:xdr=\"http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""

    func testRotationGradientAndArrows() throws {
        let xml = """
        <xdr:sp \(ns)><xdr:nvSpPr><xdr:cNvPr id="2" name="Arrow 1"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr>
        <a:xfrm rot="2700000" flipH="1"><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm>
        <a:prstGeom prst="hexagon"><a:avLst/></a:prstGeom>
        <a:gradFill><a:gsLst><a:gs pos="100000"><a:srgbClr val="0000FF"/></a:gs><a:gs pos="0"><a:srgbClr val="FF0000"/></a:gs></a:gsLst><a:lin ang="0"/></a:gradFill>
        <a:ln w="25400"><a:solidFill><a:srgbClr val="00FF00"/></a:solidFill><a:headEnd type="none"/><a:tailEnd type="triangle"/></a:ln>
        </xdr:spPr></xdr:sp>
        """
        let node = try XCTUnwrap(XNode.parse(Data(xml.utf8)))
        let s = SheetShape.read(node, colors: ColorContext(theme: PptxTheme(nil)))
        XCTAssertEqual(s.geometry, "hexagon")
        XCTAssertEqual(s.rotation, 45)
        XCTAssertTrue(s.flipH)
        XCTAssertEqual(s.fill, Color(0xFFFF0000))                 // the first stop, sorted by position
        XCTAssertEqual(s.gradient?.stops.map(\.position), [0, 1])
        XCTAssertEqual(s.gradient?.angle, 0)
        XCTAssertEqual(s.lineWidth, 2)
        XCTAssertFalse(s.headArrow)
        XCTAssertTrue(s.tailArrow)
    }

    func testGroupPlacesChildrenByItsChildSpace() throws {
        // A group 2in by 1in whose child space runs 1000…3000 by 500…1500:
        // a child at (1000,500) 1000×500 fills the group's left half.
        let xml = """
        <xdr:grpSp \(ns)><xdr:nvGrpSpPr><xdr:cNvPr id="5" name="Group 4"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>
        <xdr:grpSpPr><a:xfrm rot="5400000"><a:off x="0" y="0"/><a:ext cx="1828800" cy="914400"/><a:chOff x="1000" y="500"/><a:chExt cx="2000" cy="1000"/></a:xfrm></xdr:grpSpPr>
        <xdr:sp><xdr:nvSpPr><xdr:cNvPr id="6" name="Rectangle 5"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr>
        <a:xfrm><a:off x="1000" y="500"/><a:ext cx="1000" cy="500"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
        <a:solidFill><a:srgbClr val="112233"/></a:solidFill></xdr:spPr></xdr:sp>
        <xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="7" name="Group 6"/><xdr:cNvGrpSpPr/></xdr:nvGrpSpPr>
        <xdr:grpSpPr><a:xfrm><a:off x="2000" y="1000"/><a:ext cx="1000" cy="500"/><a:chOff x="0" y="0"/><a:chExt cx="10" cy="10"/></a:xfrm></xdr:grpSpPr>
        <xdr:cxnSp><xdr:nvCxnSpPr><xdr:cNvPr id="8" name="Connector 7"/><xdr:cNvCxnSpPr/></xdr:nvCxnSpPr><xdr:spPr>
        <a:xfrm><a:off x="5" y="0"/><a:ext cx="5" cy="10"/></a:xfrm><a:prstGeom prst="straightConnector1"><a:avLst/></a:prstGeom></xdr:spPr></xdr:cxnSp>
        </xdr:grpSp>
        <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="9" name="Picture 8"/><xdr:cNvPicPr/></xdr:nvPicPr><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></a:xfrm></xdr:spPr></xdr:pic>
        </xdr:grpSp>
        """
        let node = try XCTUnwrap(XNode.parse(Data(xml.utf8)))
        let g = SheetShape.readGroup(node, colors: ColorContext(theme: PptxTheme(nil)))
        XCTAssertTrue(g.isGroup)
        XCTAssertEqual(g.rotation, 90)
        XCTAssertEqual(g.children.count, 2)   // the picture is not drawn
        XCTAssertEqual(g.children[0].frame, Rect.fromLTWH(0, 0, 0.5, 0.5))
        XCTAssertEqual(g.children[0].shape.fill, Color(0xFF112233))
        XCTAssertEqual(g.children[1].frame, Rect.fromLTWH(0.5, 0.5, 0.5, 0.5))
        XCTAssertTrue(g.children[1].shape.isGroup)
        XCTAssertEqual(g.children[1].shape.children.first?.frame, Rect.fromLTWH(0.5, 0, 0.5, 1))
        XCTAssertEqual(g.children[1].shape.children.first?.shape.geometry, "straightConnector1")
    }
}
