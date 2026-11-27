// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → What-If Analysis → Goal Seek. Change one input cell (a constant number) until a formula
// cell reaches a target value: secant steps with a bracketing fallback, stopping within 0.001 as Excel's
// default does. A hit is one undo step; a miss leaves the sheet as it was.

import Foundation

enum GoalSeekProblem: Equatable {
    case badSetCell, setNotFormula, badChangingCell, changingNotConstant, sameCell, badTarget, noSolution(closest: Double)
    var message: String {
        switch self {
        case .badSetCell: return "Reference is not valid: the Set cell."
        case .setNotFormula: return "The Set cell must contain a formula."
        case .badChangingCell: return "Reference is not valid: the By changing cell."
        case .changingNotConstant: return "The By changing cell must contain a value, not a formula."
        case .sameCell: return "The Set cell and the By changing cell must be different."
        case .badTarget: return "To value must be a number."
        case .noSolution: return "Goal Seeking may not have found a solution."
        }
    }
}

struct GoalSeekResult: Equatable {
    var value: Double       // what the changing cell now holds
    var reached: Double     // what the set cell then shows
}

extension WorkbookController {
    func goalSeek(set setAddr: CellAddress, to target: Double, changing chAddr: CellAddress) -> (result: GoalSeekResult?, problem: GoalSeekProblem?) {
        guard target.isFinite else { return (nil, .badTarget) }
        guard setAddr != chAddr else { return (nil, .sameCell) }
        guard sheet.cells[setAddr]?.formula != nil else { return (nil, .setNotFormula) }
        let orig = sheet.cells[chAddr]
        if orig?.formula != nil { return (nil, .changingNotConstant) }
        if refusesEdit([chAddr]) { return (nil, nil) }
        var x0 = 0.0
        if case .number(let n)? = orig?.value { x0 = n } else if let v = orig?.value, !v.isEmpty { return (nil, .changingNotConstant) }
        func f(_ x: Double) -> Double? {
            var c = orig ?? Cell(input: "")
            c.input = String(x); c.formula = nil; c.value = .number(x)
            sheet.cells[chAddr] = c
            engine.recalculate()
            if case .number(let y) = sheet.value(setAddr) { return y - target }
            return nil
        }
        var committed = false
        defer { if !committed { sheet.cells[chAddr] = orig; engine.recalculate() } }
        var xa = x0, fa = f(xa)
        guard var fA = fa else { return (nil, .noSolution(closest: 0)) }
        var best = (x: xa, err: abs(fA))
        func note(_ x: Double, _ y: Double) { if abs(y) < best.err { best = (x, abs(y)) } }
        var found: Double? = abs(fA) < 0.001 ? xa : nil
        // Look for a second point on the other side (or at least a different one) by growing steps.
        var xb = xa, fB = fA
        if found == nil {
            var step = max(abs(x0) * 0.1, 1)
            outer: for _ in 0..<60 {
                for s in [step, -step] {
                    let xt = x0 + s
                    guard let ft = f(xt) else { continue }
                    note(xt, ft)
                    if abs(ft) < 0.001 { found = xt; break outer }
                    xb = xt; fB = ft
                    if (ft < 0) != (fA < 0) { break outer }
                }
                step *= 2
            }
        }
        if found == nil, (fA < 0) != (fB < 0) {
            // Bracketed: regula falsi with bisection safeguard.
            var lo = xa, flo = fA, hi = xb, fhi = fB
            for i in 0..<200 {
                var xm = i % 3 == 2 ? (lo + hi) / 2 : lo - flo * (hi - lo) / (fhi - flo)
                if !xm.isFinite { xm = (lo + hi) / 2 }
                guard let fm = f(xm) else { break }
                note(xm, fm)
                if abs(fm) < 0.001 { found = xm; break }
                if (fm < 0) == (flo < 0) { lo = xm; flo = fm } else { hi = xm; fhi = fm }
            }
        }
        guard let x = found else { return (nil, .noSolution(closest: best.x)) }
        _ = fa; fa = nil
        sheet.cells[chAddr] = orig; engine.recalculate()
        committed = true
        structural {
            var c = orig ?? Cell(input: "")
            c.input = String(x); c.formula = nil; c.value = .number(x)
            sheet.cells[chAddr] = c
        }
        var reached = 0.0
        if case .number(let y) = sheet.value(setAddr) { reached = y }
        return (GoalSeekResult(value: x, reached: reached), nil)
    }
}
