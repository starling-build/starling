import XCTest
@testable import OfficeApp

final class FieldClockTests: XCTestCase {
    let now = FieldClock.parse("2026-10-30T15:05:09-07:00")!

    func testParsesWallTime() {
        XCTAssertEqual(now, FieldClock(year: 2026, month: 10, day: 30, hour: 15, minute: 5, second: 9))
        XCTAssertEqual(FieldClock.parse("2026-10-30"), FieldClock(year: 2026, month: 10, day: 30, hour: 0, minute: 0, second: 0))
        XCTAssertEqual(FieldClock.parse("nonsense"), nil)
    }
    func testPictures() {
        XCTAssertEqual(now.format(picture: "dd.MM.yyyy"), "30.10.2026")
        XCTAssertEqual(now.format(picture: "dd/MM/yy"), "30/10/26")
        XCTAssertEqual(now.format(picture: "yyyy年M月d日"), "2026年10月30日")
        XCTAssertEqual(now.format(picture: "h:mm AM/PM"), "3:05 PM")
        XCTAssertEqual(now.format(picture: "hh:mm am/pm"), "03:05 pm")
        XCTAssertEqual(now.format(picture: "HH:mm:ss"), "15:05:09")
        XCTAssertEqual(now.format(picture: "dd MMMM yyyy' р.'"), nil)
        XCTAssertEqual(now.format(picture: "ddd"), nil)
    }
    func testFields() {
        XCTAssertEqual(now.text(instr: "TIME \\@ \"dd.MM.yyyy\"", cached: "13.08.2014"), "30.10.2026")
        XCTAssertEqual(now.text(instr: "DATE \\@\"dd/MM/yy\"", cached: "3/13/14"), "30/10/26")
        XCTAssertEqual(now.text(instr: "DATE  \\* MERGEFORMAT", cached: "27.02.2024"), "30.10.2026")
        XCTAssertEqual(now.text(instr: "TIME  \\* MERGEFORMAT", cached: "11:07 "), "15:05 ")
        XCTAssertEqual(now.text(instr: "CREATEDATE \\@ \"dd.MM.yyyy\"", cached: "13.08.2014"), nil)
        XCTAssertEqual(now.text(instr: "SAVEDATE", cached: "13.08.2014"), nil)
        XCTAssertEqual(now.text(instr: "DATE", cached: "no idea"), nil)
    }
}
