// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
@main
struct RailTests {
    static func main() {
        for count in 0...100 {
            for start in -2...102 {
                let page = WorkspaceRailPage(count: count, start: start)
                precondition(page.range.count == min(count, 5))
                precondition(page.start >= 0 && page.end <= count)
                precondition(page.moved(-1000) == 0)
                precondition(page.moved(1000) == max(0, count - 5))
                for index in 0..<count {
                    let revealed = WorkspaceRailPage(count: count, start: page.revealing(index))
                    precondition(revealed.range.contains(index))
                }
            }
        }
        precondition(WorkspaceRailPage(count: 6, start: 1).range == 1..<6)
        precondition(WorkspaceRailPage(count: 4, start: 9).range == 0..<4)
        print("all rail checks passed")
    }
}
