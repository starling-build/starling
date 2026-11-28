#if os(macOS)  // ScriptedInput is the Mac driver; it does not exist on Linux
import XCTest
@testable import OfficeApp

/// The driver's script reader: the text of a `type` line keeps its trailing spaces.
final class ScriptedInputTests: XCTestCase {
    func testATypeLineKeepsItsTrailingSpace() {
        let lines = ScriptedInput.scriptLines("wait 100\ntype Today: \n  type  two \r\n# note\n\nclick 1 2  \n")
        XCTAssertEqual(lines, ["wait 100", "type Today: ", "type  two ", "click 1 2"],
                       "it used to trim every line, so \"type Today: \" typed \"Today:\"")
    }
}
#endif
