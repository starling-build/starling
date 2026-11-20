import XCTest
import Flutter
@testable import OfficeText
@testable import OfficeApp

/// The squeeze pass walks a paragraph by a probe painter laid out at no width, summing each
/// piece's boxes. A script whose clusters the probe parts mid-cluster reads zero there (the
/// audit of 2026-11-08: every Indic script, Khmer, Lao, Myanmar, Tibetan and Thai did), and the
/// walk then never squeezes the line. `_probeReadsZero` is the decision to measure such a step
/// on one unbroken line; it must fire for every script's letters and for none of the blanks.
final class FitWalkScriptTests: XCTestCase {
    static let samples: [(String, String)] = [
        ("Devanagari", "विद्यार्थियों के लिए जानकारी"), ("Bengali", "বাংলাদেশের জাতীয় সংগীত"),
        ("Gurmukhi", "ਪੰਜਾਬੀ ਭਾਸ਼ਾ ਦੀ ਜਾਣਕਾਰੀ"), ("Gujarati", "ગુજરાતી ભાષાની માહિતી"),
        ("Oriya", "ଓଡ଼ିଆ ଭାଷାର ସୂଚନା"), ("Tamil", "தமிழ் மொழியின் தகவல்"),
        ("Telugu", "తెలుగు భాష సమాచారం"), ("Kannada", "ಕನ್ನಡ ಭಾಷೆಯ ಮಾಹಿತಿ"),
        ("Malayalam", "മലയാളം ഭാഷയുടെ വിവരങ്ങൾ"), ("Sinhala", "සිංහල භාෂාවේ තොරතුරු"),
        ("Khmer", "ព័ត៌មានភាសាខ្មែរ"), ("Lao", "ຂໍ້ມູນພາສາລາວ"), ("Myanmar", "မြန်မာဘာသာ အချက်အလက်"),
        ("Tibetan", "བོད་ཡིག་གི་ཆ་འཕྲིན"), ("Georgian", "ქართული ენის ინფორმაცია"),
        ("Armenian", "Հայերեն լեզվի տեղեկատվություն"), ("Ethiopic", "የአማርኛ ቋንቋ መረጃ"),
        ("Hebrew", "מידע על השפה העברית"), ("Arabic", "معلومات عن اللغة العربية"), ("Thai", "ข้อมูลภาษาไทยจัดสรร"),
        ("Latin", "Information about the language"),
    ]

    static let partingScripts: Set<String> = ["Devanagari", "Bengali", "Gurmukhi", "Gujarati", "Oriya", "Tamil", "Telugu", "Kannada", "Malayalam", "Sinhala", "Khmer", "Lao", "Myanmar", "Tibetan", "Thai"]

    func testZeroProbeOnAnyScriptTakesTheFlatWidth() {
        for (name, text) in Self.samples {
            let units = Array(text.utf16)
            XCTAssertTrue(RichLayout._probeCannotMeasure(0, units[...]), "\(name): a zero probe over drawn text must fall back to the flat width")
            // A script whose clusters the probe parts is read whole even when part of it measured;
            // other scripts keep a measured probe width.
            XCTAssertEqual(RichLayout._probeCannotMeasure(12.5, units[...]), Self.partingScripts.contains(name), "\(name)")
        }
    }

    func testBlankStepsMayReadZero() {
        for blanks in [[0x20], [0xA0], [0x200B, 0x200D], [0x20, 0x200C, 0xFEFF]] as [[UInt16]] {
            XCTAssertFalse(RichLayout._probeCannotMeasure(0, blanks[...]))
        }
    }
}
