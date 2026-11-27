import XCTest
@testable import OfficeApp

/// Lab mincho-emf2 (Word print, 2026-11-26): EMF text in MS Mincho and Batang hangs from TA_TOP / TA_BOTTOM exactly like
/// MS Gothic (about 0.855 / 0.145 em at 6.74, 12 and 18 pt), and Yu Mincho at a positive lfHeight of 24 draws a 14.25 pt em.
final class MetafileGDIFileMetricsTests: XCTestCase {
    func testMinchoMatchesMeasuredGothicAndBatangAtPrintedSizes() {
        for h in Array(-72 ... -6) + Array(6 ... 72) {
            let gothic = MetafileGDIMetrics.metrics(face: "ｍｓ ゴシック", bold: false, height: h)
            XCTAssertNotNil(gothic)
            // MS Mincho's file box (220 + 36 of 256) is MS Gothic's, so they agree at every height; Batang's (879 + 145 of 1024) only
            // at the printed sizes.
            let faces = [-9, -16, -24].contains(h) ? ["ＭＳ 明朝", "ms mincho", "바탕", "batang"] : ["ＭＳ 明朝", "ms mincho"]
            for face in faces {
                let m = MetafileGDIMetrics.metrics(face: face, bold: false, height: h)
                XCTAssertEqual(m?.ascent, gothic?.ascent, "\(face) \(h)")
                XCTAssertEqual(m?.descent, gothic?.descent, "\(face) \(h)")
            }
        }
    }
    func testWordPrintSizes() {
        // 18 pt at 0.75 pt per pixel: MS Mincho 15.37 / 2.65 pt in Word, i.e. 21 / 3 whole pixels like MS Gothic's GDI row.
        let m = MetafileGDIMetrics.metrics(face: "ＭＳ 明朝", bold: false, height: -24)
        XCTAssertEqual(m?.ascent, 21); XCTAssertEqual(m?.descent, 3)
        // Yu Mincho +24 is the cell: its em is 19 px (14.25 pt), so ascent and descent scale from 19, not 18.65.
        let y = MetafileGDIMetrics.metrics(face: "游明朝", bold: false, height: 24)
        XCTAssertEqual(y?.ascent, 19); XCTAssertEqual(y?.descent, 6)
    }
}
