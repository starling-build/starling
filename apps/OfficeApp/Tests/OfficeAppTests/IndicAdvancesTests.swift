import XCTest
@testable import OfficeText

/// Excel draws these scripts in Nirmala UI. Each script's widths are checked against the Excel print of the indic1 lab (Calibri 16
/// cluster rows, pitch read from the glyph origins): a consonant, a three-consonant conjunct and a conjunct with a sign, the last two
/// being clusters the table does not hold and the rule must build.
final class IndicAdvancesTests: XCTestCase {
    private func check(_ s: String, _ print: Double, _ tol: Double, _ name: String) {
        guard let e = IndicAdvances.ems(s) else { return XCTFail("\(name): no width") }
        XCTAssertEqual(e, print, accuracy: tol, name)
    }
    func testDevanagari() {
        check("क", 0.8579, 0.01, "hi cons"); check("क्क्ड", 1.7456, 0.02, "hi conj3"); check("त्कऀ", 1.1371, 0.02, "hi conj+sign")
    }
    func testBengali() {
        check("ক", 0.8678, 0.01, "bn cons"); check("ক্ঘ্ড", 2.3042, 0.02, "bn conj3"); check("ত্কঁ", 1.6259, 0.02, "bn conj+sign")
    }
    func testGurmukhi() {
        check("ਕ", 0.6883, 0.01, "pa cons"); check("ਕ੍ਕ੍ਡ", 2.0349, 0.02, "pa conj3"); check("ਤ੍ਕਁ", 1.3167, 0.02, "pa conj+sign")
    }
    func testGujarati() {
        check("ક", 0.5786, 0.01, "gu cons"); check("ક્ક્ડ", 1.5661, 0.02, "gu conj3"); check("ત્કઁ", 0.8878, 0.02, "gu conj+sign")
    }
    func testNonIndicIsNil() { XCTAssertNil(IndicAdvances.ems("abc")) }
    func testBoldIsWider() {
        XCTAssertGreaterThan(IndicAdvances.ems("क", bold: true) ?? 0, IndicAdvances.ems("क") ?? 1)
    }
}

extension IndicAdvancesTests {
    func testKannada() {
        check("ಕ", 0.718, 0.01, "kn cons")
        check("ಕ್ಕ", 0.928, 0.01, "kn conjunct (the print's, not the shaper's)")
        check("ಅ", 0.960, 0.01, "kn vowel")
        check("ತ್ಕಾ", 1.4863, 0.07, "kn conjunct + sign, built")
        XCTAssertEqual(IndicAdvances.ems("ಕ್ಕ್ಕ")!, 1.35, accuracy: 0.001, "a three-consonant conjunct is the print's own")
        XCTAssertEqual(IndicAdvances.ems("ಕ್ಕ್ಡ")!, 0.928 + 0.488, accuracy: 0.01, "outside the table: first pair plus the mean third-letter add")
    }
}
