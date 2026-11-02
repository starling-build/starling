import XCTest
@testable import OfficeText

/// Swift compares Characters (and Strings) by canonical equivalence, so a
/// literal that another code point decomposes to compares EQUAL to it.
/// These pin the pairs the layout meets: code that must tell them apart
/// compares `unicodeScalars`, never the Characters (lo-11ad5a95's rows of
/// U+2000 and U+2001 took U+2002's and U+2003's treatment through `==`).
final class CanonicalEquivalenceTests: XCTestCase {
    func testSwiftEqualityIsCanonicalEquivalence() {
        let pairs: [(UInt32, UInt32)] = [
            (0x2000, 0x2002), (0x2001, 0x2003),   // en quad, em quad
            (0x2126, 0x03A9),                     // ohm sign, Omega
            (0x212A, 0x004B), (0x212B, 0x00C5),   // Kelvin, Angstrom
            (0x0340, 0x0300), (0x0341, 0x0301),
            (0x037E, 0x003B), (0x0387, 0x00B7),   // Greek question mark, ano teleia
            (0x2329, 0x3008), (0x232A, 0x3009),   // angle brackets
            (0xF909, 0x8AAA),                     // a compatibility ideograph
        ]
        for (a, b) in pairs {
            let x = Character(Unicode.Scalar(a)!), y = Character(Unicode.Scalar(b)!)
            XCTAssertEqual(x, y, "U+\(String(a, radix: 16)) == U+\(String(b, radix: 16)) in Swift")
            XCTAssertNotEqual(x.unicodeScalars.first, y.unicodeScalars.first)
        }
    }

    func testSpacesThatSetNoLineAreTheEnEmAndFourPerEmOnly() {
        // The quads are not them, though "\u{2000}" == "\u{2002}".
        XCTAssertTrue(RichLayout._setsNoLineBesideText("\t"))
        XCTAssertTrue(RichLayout._setsNoLineBesideText(" "))
        XCTAssertFalse(RichLayout._setsNoLineBesideText("\u{2000}"))
        XCTAssertFalse(RichLayout._setsNoLineBesideText("\u{2001}"))
        XCTAssertFalse(RichLayout._setsNoLineBesideText("\u{00A0}"))
    }
}
