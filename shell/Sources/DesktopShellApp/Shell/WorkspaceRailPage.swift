// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// A bounded viewport: closing apps clamps the offset, never shrinks cards.
struct WorkspaceRailPage {
    static let capacity = 5
    let count: Int
    let start: Int
    init(count: Int, start: Int) {
        self.count = max(0, count)
        self.start = min(max(0, start), max(0, count - Self.capacity))
    }
    var end: Int { min(count, start + Self.capacity) }
    var range: Range<Int> { start..<end }
    func moved(_ delta: Int) -> Int {
        Self(count: count, start: start + delta).start
    }
    func revealing(_ index: Int) -> Int {
        guard index >= 0 && index < count else { return start }
        return Self(count: count, start: index < start ? index :
            (index >= end ? index - Self.capacity + 1 : start)).start
    }
}
