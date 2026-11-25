import XCTest
@testable import OfficeApp

/// NOW()/TODAY() follow OFFICE_NOW, so a render gate draws the same time in base and PR.
final class SheetsNowClockTests: XCTestCase {
    func testNowHonoursOfficeNow() {
        setenv("OFFICE_NOW", "2026-10-30T12:30:15", 1)
        defer { unsetenv("OFFICE_NOW") }
        let n = ExcelDate.now()
        let day: Double = ExcelDate.serial(2026, 10, 30)
        let secs: Double = 45015
        XCTAssertEqual(n, day + secs / 86400.0, accuracy: 1e-9)
    }
}
