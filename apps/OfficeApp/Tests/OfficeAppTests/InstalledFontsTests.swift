import XCTest
@testable import OfficeApp

/// `OfficeFonts.installedFamilies`: the machine's faces, keyed by the
/// lowercased name and giving the name as the platform spells it — on
/// macOS and iOS from Core Text, which on every Apple system lists Helvetica and
/// Courier New (iOS has no plain Courier).
final class InstalledFontsTests: XCTestCase {
    func testTheMachinesFamiliesAreListedByLowercasedName() {
        let families = OfficeFonts.installedFamilies
        #if !os(Windows)
        for (key, name) in families {
            XCTAssertEqual(key, name.lowercased(), "\(name) is keyed by its lowercased name")
        }
        #endif
        #if os(macOS) || os(iOS)
        XCTAssertFalse(families.isEmpty, "Core Text lists the system's faces")
        XCTAssertEqual(families["helvetica"], "Helvetica")
        XCTAssertEqual(families["courier new"], "Courier New")
        #endif
    }
}
