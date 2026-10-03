// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Dates as Slides shows them — the date field's thirteen PowerPoint
// formats, the header/footer dialog, the presenter's clock, the package's
// timestamps — from the calendar's numbers. DateFormatter is the legacy
// Foundation layer over ICU, which does not link on the web, and these
// patterns need no locale data: PowerPoint's field formats are en-US
// whatever the deck's language.

import Foundation

enum SlidesDates {
    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// `date` in a Unicode date pattern made of EEEE, MMMM, MMM, MM, M,
    /// dd, d, yyyy, yy, HH, H, hh, h, mm, ss and a; anything else is
    /// copied through.
    static func format(_ date: Date, _ pattern: String) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second],
                                                                   from: date)
        let year = c.year ?? 1970, month = c.month ?? 1, day = c.day ?? 1
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = c.second ?? 0
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        var out = ""
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let ch = pattern[i]
            var j = i
            while j < pattern.endIndex, pattern[j] == ch { j = pattern.index(after: j) }
            let run = pattern.distance(from: i, to: j)
            switch ch {
            case "E": out += weekdays[((c.weekday ?? 1) - 1 + 7) % 7]
            case "M":
                switch run {
                case 1: out += "\(month)"
                case 2: out += two(month)
                case 3: out += String(months[month - 1].prefix(3))
                default: out += months[month - 1]
                }
            case "d": out += run >= 2 ? two(day) : "\(day)"
            case "y": out += run <= 2 ? two(year % 100) : "\(year)"
            case "H": out += run >= 2 ? two(hour) : "\(hour)"
            case "h":
                let h = hour % 12 == 0 ? 12 : hour % 12
                out += run >= 2 ? two(h) : "\(h)"
            case "m": out += two(minute)
            case "s": out += two(second)
            case "a": out += hour < 12 ? "AM" : "PM"
            default: out += String(repeating: ch, count: run)
            }
            i = j
        }
        return out
    }

    /// `2026-10-03T14:05:09Z` — W3C's date-time, as a package's core
    /// properties carry it.
    static func iso8601(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ n: Int?) -> String { let n = n ?? 0; return n < 10 ? "0\(n)" : "\(n)" }
        return "\(c.year ?? 1970)-\(two(c.month))-\(two(c.day))T\(two(c.hour)):\(two(c.minute)):\(two(c.second))Z"
    }
}
