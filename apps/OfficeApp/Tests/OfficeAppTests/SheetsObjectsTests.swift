// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsObjectsTests: XCTestCase {
    /// Excel's legacy drawing, as it writes one: an ActiveX control's shape
    /// (named for the control, its number in o:spid, a picture) and a form
    /// control's (a caption broken across lines, its state in ClientData).
    private let vml = """
    <xml xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">
     <v:shapetype id="_x0000_t201" coordsize="21600,21600" o:spt="201" path="m,l,21600r21600,l21600,xe"/>
     <v:shape id="OptionButton1" o:spid="_x0000_s1025" type="#_x0000_t201"
      style='position:absolute;margin-left:2.25pt;z-index:1' stroked="f">
      <v:imagedata o:relid="rId1" o:title=""/>
      <x:ClientData ObjectType="Pict"><x:Anchor>
        0, 3, 0, 16, 2, 19, 2, 8</x:Anchor></x:ClientData>
     </v:shape>
     <v:shape id="_x0000_s1029" type="#_x0000_t201" style='position:absolute;z-index:5'>
      <v:textbox style='mso-direction-alt:auto'>
       <div style='text-align:left'><font face="Tahoma" size="160" color="auto">Form\r\n   button1 &amp; more</font></div>
      </v:textbox>
      <x:ClientData ObjectType="Radio"><x:Anchor>5, 54, 0, 15, 8, 29, 2, 4</x:Anchor>
       <x:PrintObject>False</x:PrintObject><x:Checked>1</x:Checked></x:ClientData>
     </v:shape>
    </xml>
    """

    func testLegacyShapesByNumber() {
        let shapes = SheetObjectsXML._vmlShapes(vml)
        XCTAssertEqual(Set(shapes.keys), ["1025", "1029"])
        let picture = shapes["1025"]!
        XCTAssertEqual(picture.imageRel, "rId1")
        XCTAssertFalse(picture.stroked)
        XCTAssertEqual(picture.objectType, "Pict")
        // Offsets are screen pixels: 3 px is 2.25 pt.
        XCTAssertEqual(picture.anchor, .twoCell(from: SheetMarker(col: 0, colOff: 2.25, row: 0, rowOff: 12),
                                                to: SheetMarker(col: 2, colOff: 14.25, row: 2, rowOff: 6)))
        let radio = shapes["1029"]!
        XCTAssertEqual(radio.text, "Form button1 & more")
        XCTAssertEqual(radio.fontFace, "Tahoma")
        XCTAssertEqual(radio.fontSize, 8)
        XCTAssertEqual(radio.objectType, "Radio")
        XCTAssertEqual(radio.checked, 1)
        XCTAssertFalse(radio.printed)
        XCTAssertTrue(radio.stroked)
    }

    /// The sheet's entry places a control and names its parts; a form
    /// control with no entry at all (before Excel 2010) is still found.
    func testObjectsOfASheet() {
        let sheet = """
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
        <sheetData/><legacyDrawing r:id="rId1"/>
        <controls><mc:AlternateContent><mc:Choice Requires="x14"><control shapeId="1025" r:id="rId2" name="OptionButton1">
        <controlPr r:id="rId3"><anchor><from><xdr:col>1</xdr:col><xdr:colOff>12700</xdr:colOff><xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></from>
        <to><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>4</xdr:row><xdr:rowOff>25400</xdr:rowOff></to></anchor></controlPr></control></mc:Choice>
        <mc:Fallback><control shapeId="1025" r:id="rId2" name="OptionButton1"/></mc:Fallback></mc:AlternateContent></controls>
        </worksheet>
        """
        let rels = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing" Target="../drawings/vmlDrawing1.vml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/control" Target="../activeX/activeX1.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.emf"/>
        </Relationships>
        """
        let picture = Data([1, 2, 3])
        let parts: [String: Data] = [
            "xl/worksheets/sheet1.xml": Data(sheet.utf8),
            "xl/worksheets/_rels/sheet1.xml.rels": Data(rels.utf8),
            "xl/drawings/vmlDrawing1.vml": Data(vml.utf8),
            "xl/activeX/activeX1.xml": Data("<ax:ocx xmlns:ax=\"http://schemas.microsoft.com/office/2006/activeX\"/>".utf8),
            "xl/media/image1.emf": picture,
        ]
        let objects = SheetObjectsXML.read(sheetPath: "xl/worksheets/sheet1.xml", parts: parts)
        XCTAssertEqual(objects.count, 2)
        // The entry's own anchor, in cells and points, over the legacy shape's.
        XCTAssertEqual(objects[0].anchor, .twoCell(from: SheetMarker(col: 1, colOff: 1, row: 2, rowOff: 0),
                                                   to: SheetMarker(col: 3, colOff: 0, row: 4, rowOff: 2)))
        XCTAssertEqual(objects[0].kind, .preview(path: "xl/media/image1.emf", data: picture))
        XCTAssertFalse(objects[0].framed)
        guard case .control(let radio) = objects[1].kind else { return XCTFail("the form control") }
        XCTAssertEqual(radio.kind, .radio)
        XCTAssertTrue(radio.checked)
        XCTAssertEqual(radio.text, "Form button1 & more")
        XCTAssertTrue(objects[1].screenOnly)
    }
}
