// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The rest of the functions everyday workbooks use: ranking and order
// statistics, more maths and trigonometry, conditional MAX/MIN, the
// lookup and information functions, SUBTOTAL/AGGREGATE, text and date
// helpers, and the loan and investment functions. Functions.swift holds
// the first set and the helpers these use.

import Foundation

extension SheetFunctions {
    static func addMore(_ t: inout [String: Fn]) {
        _addStatistics(&t)
        _addMaths(&t)
        _addLookupAndInfo(&t)
        _addTextAndDates(&t)
        _addFinance(&t)
    }

    // MARK: Helpers

    /// Numbers of a range or list argument (text and blanks skipped).
    static func _numbers(_ e: FormulaExpr, _ c: EvalContext) -> [Double] {
        c.engine.gridFull(c.engine.evaluate(e, c), c).flatMap { $0 }.compactMap(\.number)
    }

    static func _opt(_ a: [FormulaExpr], _ i: Int, _ c: EvalContext, _ d: Double) -> Double? {
        guard a.count > i, a[i] != .missing else { return d }
        if case .success(let v) = _n(a[i], c) { return v }
        return nil
    }

    static func _percentile(_ xs: [Double], _ p: Double, exclusive: Bool) -> Double? {
        let s = xs.sorted()
        guard !s.isEmpty, p >= 0, p <= 1 else { return nil }
        let rank: Double
        if exclusive {
            rank = p * Double(s.count + 1) - 1
            guard rank >= 0, rank <= Double(s.count - 1) else { return nil }
        } else {
            rank = p * Double(s.count - 1)
        }
        let k = Int(rank.rounded(.down)), f = rank - Double(k)
        return k + 1 < s.count ? s[k] + (s[k + 1] - s[k]) * f : s[k]
    }

    /// Pairs of numbers from two equal-shaped ranges (both cells numeric).
    static func _pairs(_ a: FormulaExpr, _ b: FormulaExpr, _ c: EvalContext) -> [(Double, Double)]? {
        let x = c.engine.gridFull(c.engine.evaluate(a, c), c).flatMap { $0 }
        let y = c.engine.gridFull(c.engine.evaluate(b, c), c).flatMap { $0 }
        guard x.count == y.count else { return nil }
        return zip(x, y).compactMap { p in p.0.number.flatMap { u in p.1.number.map { (u, $0) } } }
    }

    // MARK: Statistics

    private static func _addStatistics(_ t: inout [String: Fn]) {
        func nth(_ largest: Bool) -> Fn {
            { a, c in
                guard a.count == 2, case .success(let k) = _n(a[1], c) else { return .error(.value) }
                let s = _numbers(a[0], c).sorted(by: largest ? (>) : (<))
                let i = Int(k.rounded(.up)) - 1
                guard i >= 0, i < s.count else { return .error(.num) }
                return .number(s[i])
            }
        }
        t["LARGE"] = nth(true)
        t["SMALL"] = nth(false)
        func rank(_ average: Bool) -> Fn {
            { a, c in
                guard a.count >= 2, case .success(let x) = _n(a[0], c) else { return .error(.value) }
                let xs = _numbers(a[1], c)
                let ascending = (_opt(a, 2, c, 0) ?? 0) != 0
                guard xs.contains(where: { abs($0 - x) < 1e-12 }) else { return .error(.na) }
                let before = xs.filter { ascending ? $0 < x : $0 > x }.count
                let ties = xs.filter { abs($0 - x) < 1e-12 }.count
                return .number(Double(before + 1) + (average ? Double(ties - 1) / 2 : 0))
            }
        }
        t["RANK"] = rank(false)
        t["RANK.EQ"] = rank(false)
        t["RANK.AVG"] = rank(true)
        func pct(_ exclusive: Bool, quart: Bool) -> Fn {
            { a, c in
                guard a.count == 2, case .success(var p) = _n(a[1], c) else { return .error(.value) }
                if quart {
                    guard p >= (exclusive ? 1 : 0), p <= (exclusive ? 3 : 4) else { return .error(.num) }
                    p = p.rounded(.down) / 4
                }
                guard let v = _percentile(_numbers(a[0], c), p, exclusive: exclusive) else { return .error(.num) }
                return .number(v)
            }
        }
        t["PERCENTILE"] = pct(false, quart: false)
        t["PERCENTILE.INC"] = pct(false, quart: false)
        t["PERCENTILE.EXC"] = pct(true, quart: false)
        t["QUARTILE"] = pct(false, quart: true)
        t["QUARTILE.INC"] = pct(false, quart: true)
        t["QUARTILE.EXC"] = pct(true, quart: true)
        t["MODE"] = { a, c in _aggregate(a, c) { xs in
            var counts: [Double: Int] = [:]
            var order: [Double] = []
            for x in xs { if counts[x] == nil { order.append(x) }; counts[x, default: 0] += 1 }
            guard let best = counts.values.max(), best > 1 else { return nil }
            return order.first { counts[$0] == best }
        } }
        t["MODE.SNGL"] = t["MODE"]
        t["VAR.P"] = { a, c in _aggregate(a, c) { _stdev($0, sample: false).map { $0 * $0 } } }
        t["VARP"] = t["VAR.P"]
        t["STDEVP"] = t["STDEV.P"] ?? { a, c in _aggregate(a, c) { _stdev($0, sample: false) } }
        t["GEOMEAN"] = { a, c in _aggregate(a, c) { xs in
            guard !xs.isEmpty, xs.allSatisfy({ $0 > 0 }) else { return nil }
            return exp(xs.map(log).reduce(0, +) / Double(xs.count))
        } }
        t["HARMEAN"] = { a, c in _aggregate(a, c) { xs in
            guard !xs.isEmpty, xs.allSatisfy({ $0 > 0 }) else { return nil }
            return Double(xs.count) / xs.map { 1 / $0 }.reduce(0, +)
        } }
        t["AVEDEV"] = { a, c in _aggregate(a, c) { xs in
            guard !xs.isEmpty else { return nil }
            let m = xs.reduce(0, +) / Double(xs.count)
            return xs.map { abs($0 - m) }.reduce(0, +) / Double(xs.count)
        } }
        t["DEVSQ"] = { a, c in _aggregate(a, c) { xs in
            let m = xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
            return xs.map { ($0 - m) * ($0 - m) }.reduce(0, +)
        } }
        // AVERAGEA and kin count text as 0 and TRUE as 1 in ranges.
        func withA(_ f: @escaping ([Double]) -> Double?) -> Fn {
            { a, c in
                var xs: [Double] = []
                for e in a {
                    for v in c.engine.gridFull(c.engine.evaluate(e, c), c).flatMap({ $0 }) where !v.isEmpty {
                        switch v {
                        case .number(let n): xs.append(n)
                        case .bool(let b): xs.append(b ? 1 : 0)
                        case .error(let err): return .error(err)
                        default: xs.append(0)
                        }
                    }
                }
                return f(xs).map { .number($0) } ?? .error(.div0)
            }
        }
        t["AVERAGEA"] = withA { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
        t["MAXA"] = withA { $0.max() ?? 0 }
        t["MINA"] = withA { $0.min() ?? 0 }
        func line(_ f: @escaping (_ slope: Double, _ intercept: Double, _ r: Double) -> Double) -> Fn {
            { a, c in
                guard a.count >= 2, let ps = _pairs(a[0], a[1], c), ps.count >= 2 else { return .error(.div0) }
                // y first, x second (Excel's argument order for SLOPE etc.).
                let n = Double(ps.count)
                let my = ps.map(\.0).reduce(0, +) / n, mx = ps.map(\.1).reduce(0, +) / n
                let sxy = ps.reduce(0) { $0 + ($1.1 - mx) * ($1.0 - my) }
                let sxx = ps.reduce(0) { $0 + ($1.1 - mx) * ($1.1 - mx) }
                let syy = ps.reduce(0) { $0 + ($1.0 - my) * ($1.0 - my) }
                guard sxx != 0 else { return .error(.div0) }
                let slope = sxy / sxx
                let r = syy == 0 ? 0 : sxy / (sxx * syy).squareRoot()
                return .number(f(slope, my - slope * mx, r))
            }
        }
        t["SLOPE"] = line { s, _, _ in s }
        t["INTERCEPT"] = line { _, i, _ in i }
        t["RSQ"] = line { _, _, r in r * r }
        t["CORREL"] = { a, c in
            // x, y order; the same coefficient either way round.
            guard a.count == 2 else { return .error(.value) }
            return line { _, _, r in r }([a[1], a[0]], c)
        }
        t["PEARSON"] = t["CORREL"]
        t["FORECAST"] = { a, c in
            guard a.count == 3, case .success(let x) = _n(a[0], c) else { return .error(.value) }
            return line { s, i, _ in i + s * x }([a[1], a[2]], c)
        }
        t["FORECAST.LINEAR"] = t["FORECAST"]
        t["FREQUENCY"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            let data = _numbers(a[0], c), bins = _numbers(a[1], c).sorted()
            var counts = Array(repeating: 0.0, count: bins.count + 1)
            for x in data { counts[bins.firstIndex { x <= $0 } ?? bins.count] += 1 }
            return .array(counts.map { [.number($0)] })
        }
        // The normal distribution.
        func erf(_ x: Double) -> Double { Foundation.erf(x) }
        t["NORM.DIST"] = { a, c in
            guard a.count == 4, case .success(let x) = _n(a[0], c), case .success(let m) = _n(a[1], c),
                  case .success(let sd) = _n(a[2], c), sd > 0 else { return .error(.num) }
            let cumulative = c.engine.scalar(c.engine.evaluate(a[3], c), c)
            let z = (x - m) / sd
            if cumulative == .bool(true) || (cumulative.number ?? 0) != 0 { return .number(0.5 * (1 + erf(z / 2.0.squareRoot()))) }
            return .number(exp(-z * z / 2) / (sd * (2 * Double.pi).squareRoot()))
        }
        t["NORMDIST"] = t["NORM.DIST"]
        t["NORM.S.DIST"] = { a, c in
            guard !a.isEmpty, case .success(let z) = _n(a[0], c) else { return .error(.value) }
            let cumulative = a.count < 2 || c.engine.scalar(c.engine.evaluate(a[1], c), c) != .bool(false)
            return .number(cumulative ? 0.5 * (1 + erf(z / 2.0.squareRoot())) : exp(-z * z / 2) / (2 * Double.pi).squareRoot())
        }
        t["NORMSDIST"] = { a, c in
            guard a.count == 1, case .success(let z) = _n(a[0], c) else { return .error(.value) }
            return .number(0.5 * (1 + erf(z / 2.0.squareRoot())))
        }
        func inverseNormal(_ p: Double) -> Double? {
            guard p > 0, p < 1 else { return nil }
            // Acklam's rational approximation, then one Newton step.
            let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
            let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
            let cc = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
            let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
            let lo = 0.02425
            var x: Double
            if p < lo {
                let q = (-2 * log(p)).squareRoot()
                x = (((((cc[0] * q + cc[1]) * q + cc[2]) * q + cc[3]) * q + cc[4]) * q + cc[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
            } else if p <= 1 - lo {
                let q = p - 0.5, r = q * q
                x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
            } else {
                let q = (-2 * log(1 - p)).squareRoot()
                x = -(((((cc[0] * q + cc[1]) * q + cc[2]) * q + cc[3]) * q + cc[4]) * q + cc[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
            }
            let e = 0.5 * (1 + erf(x / 2.0.squareRoot())) - p
            let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
            return x - u / (1 + x * u / 2)
        }
        t["NORM.S.INV"] = { a, c in
            guard a.count == 1, case .success(let p) = _n(a[0], c), let z = inverseNormal(p) else { return .error(.num) }
            return .number(z)
        }
        t["NORMSINV"] = t["NORM.S.INV"]
        t["NORM.INV"] = { a, c in
            guard a.count == 3, case .success(let p) = _n(a[0], c), case .success(let m) = _n(a[1], c),
                  case .success(let sd) = _n(a[2], c), sd > 0, let z = inverseNormal(p) else { return .error(.num) }
            return .number(m + sd * z)
        }
        t["NORMINV"] = t["NORM.INV"]
        t["STANDARDIZE"] = { a, c in
            guard a.count == 3, case .success(let x) = _n(a[0], c), case .success(let m) = _n(a[1], c),
                  case .success(let sd) = _n(a[2], c), sd > 0 else { return .error(.num) }
            return .number((x - m) / sd)
        }
    }

    // MARK: Maths

    private static func _addMaths(_ t: inout [String: Fn]) {
        t["SUMSQ"] = { a, c in _aggregate(a, c) { $0.map { $0 * $0 }.reduce(0, +) } }
        t["EVEN"] = { a, c in _num1(a, c) { x in let r = (abs(x) / 2).rounded(.up) * 2; return x < 0 ? -r : r } }
        t["ODD"] = { a, c in _num1(a, c) { x in
            var r = abs(x).rounded(.up)
            if r.truncatingRemainder(dividingBy: 2) == 0 { r += 1 }
            return x < 0 ? -r : r
        } }
        t["FACT"] = { a, c in
            guard a.count == 1, case .success(let x) = _n(a[0], c), x >= 0, x < 171 else { return .error(.num) }
            return .number((0 ..< Int(x)).reduce(1.0) { $0 * Double($1 + 1) })
        }
        func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
        t["GCD"] = { a, c in
            let xs = a.flatMap { _numbers($0, c) }.map { Int($0) }
            guard xs.allSatisfy({ $0 >= 0 }) else { return .error(.num) }
            return .number(Double(xs.reduce(0, gcd)))
        }
        t["LCM"] = { a, c in
            let xs = a.flatMap { _numbers($0, c) }.map { Int($0) }
            guard xs.allSatisfy({ $0 >= 0 }) else { return .error(.num) }
            if xs.contains(0) { return .number(0) }
            return .number(Double(xs.reduce(1) { $0 / gcd($0, $1) * $1 }))
        }
        t["COMBIN"] = { a, c in
            guard a.count == 2, case .success(let n) = _n(a[0], c), case .success(let k) = _n(a[1], c) else { return .error(.value) }
            let ni = Int(n), ki = Int(k)
            guard ni >= 0, ki >= 0, ki <= ni else { return .error(.num) }
            var r = 1.0
            for i in 0 ..< min(ki, ni - ki) { r = r * Double(ni - i) / Double(i + 1) }
            return .number(r.rounded())
        }
        t["PERMUT"] = { a, c in
            guard a.count == 2, case .success(let n) = _n(a[0], c), case .success(let k) = _n(a[1], c) else { return .error(.value) }
            let ni = Int(n), ki = Int(k)
            guard ni >= 0, ki >= 0, ki <= ni else { return .error(.num) }
            return .number((0 ..< ki).reduce(1.0) { $0 * Double(ni - $1) })
        }
        t["QUOTIENT"] = { a, c in
            guard a.count == 2, case .success(let x) = _n(a[0], c), case .success(let y) = _n(a[1], c) else { return .error(.value) }
            guard y != 0 else { return .error(.div0) }
            return .number((x / y).rounded(.towardZero))
        }
        t["MROUND"] = { a, c in
            guard a.count == 2, case .success(let x) = _n(a[0], c), case .success(let m) = _n(a[1], c) else { return .error(.value) }
            if m == 0 { return .number(0) }
            guard (x < 0) == (m < 0) || x == 0 else { return .error(.num) }
            return .number((x / m).rounded(.toNearestOrAwayFromZero) * m)
        }
        func toMultiple(up: Bool) -> Fn {
            { a, c in
                guard !a.isEmpty, case .success(let x) = _n(a[0], c), let sig = _opt(a, 1, c, 1), let mode = _opt(a, 2, c, 0) else { return .error(.value) }
                let s = abs(sig)
                if s == 0 { return .number(0) }
                // Negative numbers go toward zero unless mode says away.
                let away = mode != 0 && x < 0
                let q = x / s
                let r = up ? (away ? q.rounded(.down) : q.rounded(.up)) : (away ? q.rounded(.up) : q.rounded(.down))
                return .number(r * s)
            }
        }
        t["CEILING.MATH"] = toMultiple(up: true)
        t["FLOOR.MATH"] = toMultiple(up: false)
        t["DEGREES"] = { a, c in _num1(a, c) { $0 * 180 / Double.pi } }
        t["RADIANS"] = { a, c in _num1(a, c) { $0 * Double.pi / 180 } }
        t["SIN"] = { a, c in _num1(a, c, Foundation.sin) }
        t["COS"] = { a, c in _num1(a, c, Foundation.cos) }
        t["TAN"] = { a, c in _num1(a, c, Foundation.tan) }
        t["ASIN"] = { a, c in _num1(a, c, Foundation.asin) }
        t["ACOS"] = { a, c in _num1(a, c, Foundation.acos) }
        t["ATAN"] = { a, c in _num1(a, c, Foundation.atan) }
        t["SINH"] = { a, c in _num1(a, c, Foundation.sinh) }
        t["COSH"] = { a, c in _num1(a, c, Foundation.cosh) }
        t["TANH"] = { a, c in _num1(a, c, Foundation.tanh) }
        t["ATAN2"] = { a, c in
            guard a.count == 2, case .success(let x) = _n(a[0], c), case .success(let y) = _n(a[1], c) else { return .error(.value) }
            guard x != 0 || y != 0 else { return .error(.div0) }
            return .number(Foundation.atan2(y, x))
        }
        t["SUMX2MY2"] = { a, c in
            guard a.count == 2, let ps = _pairs(a[0], a[1], c) else { return .error(.na) }
            return .number(ps.reduce(0) { $0 + $1.0 * $1.0 - $1.1 * $1.1 })
        }
        t["SUMX2PY2"] = { a, c in
            guard a.count == 2, let ps = _pairs(a[0], a[1], c) else { return .error(.na) }
            return .number(ps.reduce(0) { $0 + $1.0 * $1.0 + $1.1 * $1.1 })
        }
        t["SUMXMY2"] = { a, c in
            guard a.count == 2, let ps = _pairs(a[0], a[1], c) else { return .error(.na) }
            return .number(ps.reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) })
        }
    }
}

// MARK: - Lookup, information, SUBTOTAL

extension SheetFunctions {
    fileprivate static func _addLookupAndInfo(_ t: inout [String: Fn]) {
        func ifs(_ pick: @escaping ([Double]) -> Double) -> Fn {
            { a, c in
                guard a.count >= 3, a.count % 2 == 1 else { return .error(.value) }
                let pairs = stride(from: 1, to: a.count, by: 2)
                return _conditional(ranges: pairs.map { a[$0] }, criteria: pairs.map { a[$0 + 1] }, target: a[0], c) { $0.isEmpty ? 0 : pick($0) }
            }
        }
        t["MAXIFS"] = ifs { $0.max()! }
        t["MINIFS"] = ifs { $0.min()! }
        t["SWITCH"] = { a, c in
            guard a.count >= 3 else { return .error(.value) }
            let v = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            var i = 1
            while i + 1 < a.count {
                if CalcEngine.compare(v, c.engine.scalar(c.engine.evaluate(a[i], c), c)) == 0 { return c.engine.evaluate(a[i + 1], c) }
                i += 2
            }
            return i < a.count ? c.engine.evaluate(a[i], c) : .error(.na)
        }
        t["XMATCH"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let key = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            let g = c.engine.gridFull(c.engine.evaluate(a[1], c), c)
            let list = g.count == 1 ? g[0] : g.map { $0.first ?? .empty }
            let mode = Int(_opt(a, 2, c, 0) ?? 0), search = Int(_opt(a, 3, c, 1) ?? 1)
            let order = search < 0 ? Array(list.indices.reversed()) : Array(list.indices)
            var best: Int? = nil
            for i in order {
                let v = list[i]
                if mode == 2, case .text(let k) = key, case .text(let s) = v {
                    if _globMatch(Array(s.lowercased()), Array(k.lowercased())) { return .number(Double(i + 1)) }
                    continue
                }
                let cmp = CalcEngine.compare(v, key)
                if cmp == 0 && (v.isText == key.isText) { return .number(Double(i + 1)) }
                if mode == -1, cmp < 0, v.number != nil || v.isText == key.isText {
                    if best == nil || CalcEngine.compare(list[best!], v) < 0 { best = i }
                }
                if mode == 1, cmp > 0, v.number != nil || v.isText == key.isText {
                    if best == nil || CalcEngine.compare(list[best!], v) > 0 { best = i }
                }
            }
            return best.map { .number(Double($0 + 1)) } ?? .error(.na)
        }
        t["LOOKUP"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let key = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            let g = c.engine.gridFull(c.engine.evaluate(a[1], c), c)
            // The vector form, or an array searched along its longer side.
            let wide = (g.first?.count ?? 0) > g.count
            let keys = wide ? (g.first ?? []) : g.map { $0.first ?? .empty }
            var hit: Int? = nil
            for (i, v) in keys.enumerated() where !v.isEmpty && (v.number != nil) == (key.number != nil) {
                if CalcEngine.compare(v, key) <= 0 { hit = i } else { break }
            }
            guard let i = hit else { return .error(.na) }
            if a.count >= 3 {
                let r = c.engine.gridFull(c.engine.evaluate(a[2], c), c).flatMap { $0 }
                return i < r.count ? .scalar(r[i]) : .error(.na)
            }
            return .scalar(wide ? (g.last?[i] ?? .empty) : (g[i].last ?? .empty))
        }
        t["ADDRESS"] = { a, c in
            guard a.count >= 2, case .success(let r) = _n(a[0], c), case .success(let col) = _n(a[1], c),
                  r >= 1, col >= 1, Int(r) <= CellAddress.maxRows, Int(col) <= CellAddress.maxCols else { return .error(.value) }
            let absNum = Int(_opt(a, 2, c, 1) ?? 1)
            let a1 = a.count < 4 || a[3] == .missing || c.engine.scalar(c.engine.evaluate(a[3], c), c) != .bool(false)
            var s: String
            if a1 {
                let colAbs = absNum == 1 || absNum == 3, rowAbs = absNum == 1 || absNum == 2
                s = (colAbs ? "$" : "") + CellAddress.columnName(Int(col) - 1) + (rowAbs ? "$" : "") + "\(Int(r))"
            } else {
                s = (absNum == 1 || absNum == 2 ? "R\(Int(r))" : "R[\(Int(r))]") + (absNum == 1 || absNum == 3 ? "C\(Int(col))" : "C[\(Int(col))]")
            }
            if a.count >= 5, case .success(let sheet) = _t(a[4], c), !sheet.isEmpty { s = Formula.quoteSheet(sheet) + "!" + s }
            return .scalar(.text(s))
        }
        t["OFFSET"] = { a, c in
            guard a.count >= 3, case .success(let dr) = _n(a[1], c), case .success(let dc) = _n(a[2], c) else { return .error(.value) }
            let base: (Int, CellRange)
            switch c.engine.evaluate(a[0], c) {
            case .range(let s, let r): base = (s, r)
            default:
                guard case .ref(let r) = a[0] else { return .error(.value) }
                base = (r.sheet.flatMap { c.engine.book.sheet(named: $0) } ?? c.sheet, r.range)
            }
            let h = Int(_opt(a, 3, c, Double(base.1.rows)) ?? 0), w = Int(_opt(a, 4, c, Double(base.1.cols)) ?? 0)
            let top = base.1.top + Int(dr), left = base.1.left + Int(dc)
            guard h >= 1, w >= 1, top >= 0, left >= 0, top + h <= CellAddress.maxRows, left + w <= CellAddress.maxCols else { return .error(.ref) }
            return .range(sheet: base.0, CellRange(top: top, left: left, bottom: top + h - 1, right: left + w - 1))
        }
        t["INDIRECT"] = { a, c in
            guard !a.isEmpty, case .success(let text) = _t(a[0], c) else { return .error(.ref) }
            if let e = try? Formula.parse("=" + text), case .ref(let r) = e {
                let si = r.sheet.flatMap { c.engine.book.sheet(named: $0) } ?? c.sheet
                guard si >= 0 else { return .error(.ref) }
                return .range(sheet: si, r.range)
            }
            if let target = c.engine.book.names[text.uppercased()], let e = try? Formula.parse("=" + target) {
                return c.engine.evaluate(e, c)
            }
            return .error(.ref)
        }
        t["ISFORMULA"] = { a, c in
            guard a.count == 1, case .ref(let r) = a[0], let at = r.start.row.flatMap({ row in r.start.col.map { CellAddress(row: row, col: $0) } }) else { return .error(.value) }
            let si = r.sheet.flatMap { c.engine.book.sheet(named: $0) } ?? c.sheet
            return .scalar(.bool(c.engine.book.sheets[si].cells[at]?.formula != nil))
        }
        t["ISREF"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            if case .range = c.engine.evaluate(a[0], c) { return .scalar(.bool(true)) }
            if case .ref = a[0] { return .scalar(.bool(true)) }
            return .scalar(.bool(false))
        }
        t["N"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            switch c.engine.scalar(c.engine.evaluate(a[0], c), c) {
            case .number(let n): return .number(n)
            case .bool(let b): return .number(b ? 1 : 0)
            case .error(let e): return .error(e)
            default: return .number(0)
            }
        }
        t["T"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            let v = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            if case .error(let e) = v { return .error(e) }
            if case .text = v { return .scalar(v) }
            return .scalar(.text(""))
        }
        t["TYPE"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            let e = c.engine.evaluate(a[0], c)
            if c.engine._isMulti(e) { return .number(64) }
            switch c.engine.scalar(e, c) {
            case .text: return .number(2)
            case .bool: return .number(4)
            case .error: return .number(16)
            default: return .number(1)
            }
        }
        t["ERROR.TYPE"] = { a, c in
            guard a.count == 1, case .error(let e) = c.engine.scalar(c.engine.evaluate(a[0], c), c) else { return .error(.na) }
            let codes: [ExcelError: Double] = [.null: 1, .div0: 2, .value: 3, .ref: 4, .name: 5, .num: 6, .na: 7, .spill: 9, .calc: 14]
            return codes[e].map { .number($0) } ?? .error(.na)
        }
        // SUBTOTAL(fn, refs…): leaves out rows a filter hid (and, for
        // 101–111, rows hidden by hand) and other SUBTOTALs' cells.
        func subtotalValues(_ refs: ArraySlice<FormulaExpr>, _ c: EvalContext, skipHidden: Bool, skipErrors: Bool) -> Result<[CellValue], ExcelError> {
            var out: [CellValue] = []
            for e in refs {
                switch c.engine.evaluate(e, c) {
                case .range(let si, let r):
                    let ws = c.engine.book.sheets[si]
                    let used = c.engine.usedExtent(si)
                    guard r.top <= used.row, r.left <= used.col else { continue }
                    for row in r.top ... min(r.bottom, used.row) {
                        if ws.filteredRows.contains(row) || (skipHidden && (ws.hiddenRows.contains(row) || ws.rowHeights[row] == 0)) { continue }
                        for col in r.left ... min(r.right, used.col) {
                            let at = CellAddress(row: row, col: col)
                            if let f = ws.cells[at]?.formula, case .call(let n, _) = f, ["SUBTOTAL", "AGGREGATE"].contains(n.uppercased()) { continue }
                            let v = c.engine.value(si, at)
                            if case .error(let err) = v { if skipErrors { continue }; return .failure(err) }
                            out.append(v)
                        }
                    }
                case .scalar(let v): out.append(v)
                case .array(let rows): out += rows.flatMap { $0 }
                }
            }
            return .success(out)
        }
        func reduce(_ fn: Int, _ vals: [CellValue]) -> EvalValue {
            let xs = vals.compactMap(\.number)
            switch fn {
            case 1: return xs.isEmpty ? .error(.div0) : .number(xs.reduce(0, +) / Double(xs.count))
            case 2: return .number(Double(xs.count))
            case 3: return .number(Double(vals.filter { !$0.isEmpty }.count))
            case 4: return .number(xs.max() ?? 0)
            case 5: return .number(xs.min() ?? 0)
            case 6: return .number(xs.reduce(1, *))
            case 7: return _stdev(xs, sample: true).map { .number($0) } ?? .error(.div0)
            case 8: return _stdev(xs, sample: false).map { .number($0) } ?? .error(.div0)
            case 9: return .number(xs.reduce(0, +))
            case 10: return _stdev(xs, sample: true).map { .number($0 * $0) } ?? .error(.div0)
            case 11: return _stdev(xs, sample: false).map { .number($0 * $0) } ?? .error(.div0)
            case 12:
                guard !xs.isEmpty else { return .error(.num) }
                let s = xs.sorted(), m = s.count / 2
                return .number(s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2)
            default: return .error(.value)
            }
        }
        t["SUBTOTAL"] = { a, c in
            guard a.count >= 2, case .success(let f) = _n(a[0], c) else { return .error(.value) }
            let fn = Int(f)
            guard (1 ... 11).contains(fn % 100), fn < 112 else { return .error(.value) }
            switch subtotalValues(a.dropFirst(), c, skipHidden: fn > 100, skipErrors: false) {
            case .success(let vals): return reduce(fn % 100, vals)
            case .failure(let e): return .error(e)
            }
        }
        t["AGGREGATE"] = { a, c in
            guard a.count >= 3, case .success(let f) = _n(a[0], c), case .success(let o) = _n(a[1], c) else { return .error(.value) }
            let fn = Int(f), opt = Int(o)
            let skipHidden = [1, 3, 5, 7].contains(opt), skipErrors = [2, 3, 6, 7].contains(opt)
            if fn >= 14 {
                // LARGE, SMALL, PERCENTILE, QUARTILE: an array and k.
                guard a.count >= 4, case .success(let k) = _n(a[3], c) else { return .error(.value) }
                guard case .success(let vals) = subtotalValues(a[2 ... 2], c, skipHidden: skipHidden, skipErrors: skipErrors) else { return .error(.value) }
                let xs = vals.compactMap(\.number)
                switch fn {
                case 14, 15:
                    let s = xs.sorted(by: fn == 14 ? (>) : (<)), i = Int(k) - 1
                    return i >= 0 && i < s.count ? .number(s[i]) : .error(.num)
                case 16: return _percentile(xs, k, exclusive: false).map { .number($0) } ?? .error(.num)
                case 17: return _percentile(xs, k.rounded(.down) / 4, exclusive: false).map { .number($0) } ?? .error(.num)
                case 18: return _percentile(xs, k, exclusive: true).map { .number($0) } ?? .error(.num)
                case 19: return _percentile(xs, k.rounded(.down) / 4, exclusive: true).map { .number($0) } ?? .error(.num)
                default: return .error(.value)
                }
            }
            switch subtotalValues(a.dropFirst(2), c, skipHidden: skipHidden, skipErrors: skipErrors) {
            case .success(let vals): return reduce(fn == 13 ? 12 : fn, vals)
            case .failure(let e): return .error(e)
            }
        }
    }
}

// MARK: - Text and dates

extension SheetFunctions {
    fileprivate static func _addTextAndDates(_ t: inout [String: Fn]) {
        t["REPLACE"] = { a, c in
            guard a.count == 4, case .success(let s) = _t(a[0], c), case .success(let start) = _n(a[1], c),
                  case .success(let n) = _n(a[2], c), case .success(let new) = _t(a[3], c), start >= 1, n >= 0 else { return .error(.value) }
            var chars = Array(s)
            let i = min(chars.count, Int(start) - 1), j = min(chars.count, i + Int(n))
            chars.replaceSubrange(i ..< j, with: Array(new))
            return .scalar(.text(String(chars)))
        }
        t["CLEAN"] = { a, c in _text1(a, c) { .scalar(.text(String($0.unicodeScalars.filter { $0.value >= 32 }.map(Character.init)))) } }
        t["UNICHAR"] = { a, c in
            guard a.count == 1, case .success(let n) = _n(a[0], c), let u = Unicode.Scalar(UInt32(max(0, n))), n >= 1 else { return .error(.value) }
            return .scalar(.text(String(Character(u))))
        }
        t["UNICODE"] = { a, c in
            guard a.count == 1, case .success(let s) = _t(a[0], c), let u = s.unicodeScalars.first else { return .error(.value) }
            return .number(Double(u.value))
        }
        func fixed(_ x: Double, _ d: Int, commas: Bool) -> String {
            var code = commas ? "#,##0" : "0"
            if d > 0 { code += "." + String(repeating: "0", count: d) }
            let rounded = d >= 0 ? x : (x / pow(10, Double(-d))).rounded() * pow(10, Double(-d))
            return NumberFormat.display(.number(rounded), code, width: 255).text
        }
        t["FIXED"] = { a, c in
            guard !a.isEmpty, case .success(let x) = _n(a[0], c), let d = _opt(a, 1, c, 2) else { return .error(.value) }
            let noCommas = a.count > 2 && c.engine.scalar(c.engine.evaluate(a[2], c), c) == .bool(true)
            return .scalar(.text(fixed(x, Int(d), commas: !noCommas)))
        }
        t["DOLLAR"] = { a, c in
            guard !a.isEmpty, case .success(let x) = _n(a[0], c), let d = _opt(a, 1, c, 2) else { return .error(.value) }
            let s = fixed(abs(x), Int(d), commas: true)
            return .scalar(.text(x < 0 ? "($" + s + ")" : "$" + s))
        }
        func around(_ before: Bool) -> Fn {
            { a, c in
                guard a.count >= 2, case .success(let s) = _t(a[0], c), case .success(let d) = _t(a[1], c), !d.isEmpty else { return .error(.value) }
                let n = Int(_opt(a, 2, c, 1) ?? 1)
                let ci = (_opt(a, 3, c, 0) ?? 0) == 1
                let hay = ci ? s.lowercased() : s, needle = ci ? d.lowercased() : d
                var ranges: [Range<String.Index>] = []
                var from = hay.startIndex
                while let r = hay.findRange(of: needle, in: from ..< hay.endIndex) { ranges.append(r); from = r.upperBound }
                guard n != 0, abs(n) <= ranges.count else {
                    return a.count > 5 ? c.engine.evaluate(a[5], c) : .error(.na)
                }
                let r = n > 0 ? ranges[n - 1] : ranges[ranges.count + n]
                // The same offsets in the original text.
                let lo = hay.distance(from: hay.startIndex, to: r.lowerBound), hi = hay.distance(from: hay.startIndex, to: r.upperBound)
                let chars = Array(s)
                return .scalar(.text(before ? String(chars[..<lo]) : String(chars[hi...])))
            }
        }
        t["TEXTBEFORE"] = around(true)
        t["TEXTAFTER"] = around(false)
        t["NUMBERVALUE"] = { a, c in
            guard !a.isEmpty, case .success(var s) = _t(a[0], c) else { return .error(.value) }
            let dec = a.count > 1 ? ((try? _t(a[1], c).get()) ?? ".") : "."
            let group = a.count > 2 ? ((try? _t(a[2], c).get()) ?? ",") : ","
            s = s.replacingAll(" ", with: "")
            if let g = group.first { s = s.replacingAll(String(g), with: "") }
            if let d = dec.first, d != "." { s = s.replacingAll(String(d), with: ".") }
            var pct = 0
            while s.hasSuffix("%") { s.removeLast(); pct += 1 }
            guard let x = Double(s) else { return .error(.value) }
            return .number(x / pow(100, Double(pct)))
        }
        // Dates.
        func isoWeek(_ serial: Double) -> Int {
            let (y, m, d) = ExcelDate.ymd(serial)
            let wd = (ExcelDate.weekday(serial) + 5) % 7 + 1          // Monday 1 … Sunday 7
            let ordinal = Int(serial) - Int(ExcelDate.serial(y, 1, 1)) + 1
            var week = (ordinal - wd + 10) / 7
            if week < 1 { return isoWeek(ExcelDate.serial(y - 1, 12, 31)) }
            let thursdayOfLast = ExcelDate.serial(y, 12, 28)
            if week > isoWeekCount(thursdayOfLast) { week = 1 }
            _ = (m, d)
            return week
        }
        func isoWeekCount(_ serialInYear: Double) -> Int {
            let (y, _, _) = ExcelDate.ymd(serialInYear)
            let jan1 = ExcelDate.weekday(ExcelDate.serial(y, 1, 1))          // 1 Sunday … 7 Saturday
            let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
            return jan1 == 5 || (leap && jan1 == 4) ? 53 : 52
        }
        t["ISOWEEKNUM"] = { a, c in
            guard a.count == 1, case .success(let s) = _n(a[0], c) else { return .error(.value) }
            return .number(Double(isoWeek(s)))
        }
        t["WEEKNUM"] = { a, c in
            guard !a.isEmpty, case .success(let s) = _n(a[0], c), let type = _opt(a, 1, c, 1) else { return .error(.value) }
            if Int(type) == 21 { return .number(Double(isoWeek(s))) }
            // Week 1 holds 1 January; weeks start on Sunday (1, 17) or Monday (2, 11), …
            let start: Int
            switch Int(type) {
            case 1, 17: start = 1
            case 2, 11: start = 2
            case 12: start = 3
            case 13: start = 4
            case 14: start = 5
            case 15: start = 6
            case 16: start = 7
            default: return .error(.num)
            }
            let (y, _, _) = ExcelDate.ymd(s)
            let jan1 = ExcelDate.serial(y, 1, 1)
            let offset = (ExcelDate.weekday(jan1) - start + 7) % 7
            return .number(Double((Int(s) - Int(jan1) + offset) / 7 + 1))
        }
        t["WORKDAY"] = { a, c in
            guard a.count >= 2, case .success(let s) = _n(a[0], c), case .success(let n) = _n(a[1], c) else { return .error(.value) }
            var holidays: Set<Int> = []
            if a.count >= 3 { for v in _numbers(a[2], c) { holidays.insert(Int(v)) } }
            var d = Int(s), left = Int(n)
            let step = left >= 0 ? 1 : -1
            while left != 0 {
                d += step
                let w = ExcelDate.weekday(Double(d))
                if w != 1 && w != 7 && !holidays.contains(d) { left -= step }
            }
            return .number(Double(d))
        }
        t["DAYS"] = { a, c in
            guard a.count == 2, case .success(let e) = _n(a[0], c), case .success(let s) = _n(a[1], c) else { return .error(.value) }
            return .number(e.rounded(.down) - s.rounded(.down))
        }
        func days360(_ s: Double, _ e: Double, european: Bool) -> Double {
            var (y1, m1, d1) = ExcelDate.ymd(s)
            var (y2, m2, d2) = ExcelDate.ymd(e)
            if european {
                d1 = min(d1, 30); d2 = min(d2, 30)
            } else {
                let lastFeb = { (y: Int, m: Int, d: Int) -> Bool in m == 2 && ExcelDate.ymd(ExcelDate.serial(y, 3, 1) - 1).2 == d }
                if lastFeb(y1, m1, d1) { if lastFeb(y2, m2, d2) { d2 = 30 }; d1 = 30 }
                if d2 == 31 && d1 >= 30 { d2 = 30 }
                if d1 == 31 { d1 = 30 }
            }
            _ = (y1, y2, m1, m2)
            return Double((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1))
        }
        t["DAYS360"] = { a, c in
            guard a.count >= 2, case .success(let s) = _n(a[0], c), case .success(let e) = _n(a[1], c) else { return .error(.value) }
            let eu = a.count > 2 && c.engine.scalar(c.engine.evaluate(a[2], c), c) == .bool(true)
            return .number(days360(s, e, european: eu))
        }
        t["YEARFRAC"] = { a, c in
            guard a.count >= 2, case .success(var s) = _n(a[0], c), case .success(var e) = _n(a[1], c), let basis = _opt(a, 2, c, 0) else { return .error(.value) }
            if s > e { swap(&s, &e) }
            switch Int(basis) {
            case 0: return .number(days360(s, e, european: false) / 360)
            case 1:
                let (y1, _, _) = ExcelDate.ymd(s), (y2, _, _) = ExcelDate.ymd(e)
                let years = (y1 ... y2).map { ExcelDate.serial($0 + 1, 1, 1) - ExcelDate.serial($0, 1, 1) }
                let avg = years.reduce(0, +) / Double(years.count)
                if y1 == y2 || (y2 == y1 + 1 && e <= ExcelDate.serial(y2, ExcelDate.ymd(s).1, ExcelDate.ymd(s).2)) {
                    let len = y1 == y2 ? years[0] : ((e - s) <= 365 ? 365 : 366)
                    return .number((e - s) / (y1 == y2 ? len : max(len, avg.rounded())))
                }
                return .number((e - s) / avg)
            case 2: return .number((e - s) / 360)
            case 3: return .number((e - s) / 365)
            case 4: return .number(days360(s, e, european: true) / 360)
            default: return .error(.num)
            }
        }
        t["DATEVALUE"] = { a, c in
            guard a.count == 1, case .success(let s) = _t(a[0], c), let p = InputParser.parse(s), case .number(let n) = p.value else { return .error(.value) }
            return .number(n.rounded(.down))
        }
        t["TIMEVALUE"] = { a, c in
            guard a.count == 1, case .success(let s) = _t(a[0], c), let p = InputParser.parse(s), case .number(let n) = p.value else { return .error(.value) }
            return .number(n - n.rounded(.down))
        }
    }
}

// MARK: - Finance

extension SheetFunctions {
    static func _pmt(_ rate: Double, _ n: Double, _ pv: Double, _ fv: Double, _ type: Double) -> Double {
        if rate == 0 { return -(pv + fv) / n }
        let f = pow(1 + rate, n)
        return -(rate * (pv * f + fv)) / ((1 + rate * type) * (f - 1))
    }

    /// The interest part of payment `per`: the balance before it, as FV
    /// gives it, times the rate.
    static func _ipmt(_ rate: Double, _ per: Double, _ n: Double, _ pv: Double, _ fv: Double, _ type: Double) -> Double {
        let pmt = _pmt(rate, n, pv, fv, type)
        func balance(_ k: Double) -> Double {
            rate == 0 ? -(pv + pmt * k) : -(pv * pow(1 + rate, k) + pmt * (1 + rate * type) * (pow(1 + rate, k) - 1) / rate)
        }
        let before: Double
        if per == 1 { before = type > 0 ? 0 : -pv }
        else if type > 0 { before = balance(per - 2) - pmt }
        else { before = balance(per - 1) }
        return before * rate
    }

    fileprivate static func _addFinance(_ t: inout [String: Fn]) {
        func args(_ a: [FormulaExpr], _ c: EvalContext, _ need: Int) -> [Double]? {
            var out: [Double] = []
            for i in 0 ..< a.count {
                if a[i] == .missing { out.append(0); continue }
                guard case .success(let v) = _n(a[i], c) else { return nil }
                out.append(v)
            }
            return out.count >= need ? out : nil
        }
        t["NPER"] = { a, c in
            guard let v = args(a, c, 3) else { return .error(.value) }
            let rate = v[0], pmt = v[1], pv = v[2], fv = v.count > 3 ? v[3] : 0, type = v.count > 4 ? v[4] : 0
            if rate == 0 { return pmt == 0 ? .error(.num) : .number(-(pv + fv) / pmt) }
            let x = pmt * (1 + rate * type) / rate
            let num = (x - fv) / (x + pv)
            guard num > 0 else { return .error(.num) }
            return .number(log(num) / log(1 + rate))
        }
        t["IPMT"] = { a, c in
            guard let v = args(a, c, 4) else { return .error(.value) }
            let rate = v[0], per = v[1], n = v[2], pv = v[3], fv = v.count > 4 ? v[4] : 0, type = v.count > 5 ? v[5] : 0
            guard per >= 1, per <= n else { return .error(.num) }
            return .number(_ipmt(rate, per, n, pv, fv, type))
        }
        t["PPMT"] = { a, c in
            guard let v = args(a, c, 4) else { return .error(.value) }
            let rate = v[0], per = v[1], n = v[2], pv = v[3], fv = v.count > 4 ? v[4] : 0, type = v.count > 5 ? v[5] : 0
            guard per >= 1, per <= n else { return .error(.num) }
            return .number(_pmt(rate, n, pv, fv, type) - _ipmt(rate, per, n, pv, fv, type))
        }
        func cumulative(_ principal: Bool) -> Fn {
            { a, c in
                guard let v = args(a, c, 6) else { return .error(.value) }
                let rate = v[0], n = v[1], pv = v[2], s = Int(v[3]), e = Int(v[4]), type = v[5]
                guard rate > 0, n > 0, pv > 0, s >= 1, e >= s, Double(e) <= n else { return .error(.num) }
                var total = 0.0
                for p in s ... e {
                    let i = _ipmt(rate, Double(p), n, pv, 0, type)
                    total += principal ? _pmt(rate, n, pv, 0, type) - i : i
                }
                return .number(total)
            }
        }
        t["CUMIPMT"] = cumulative(false)
        t["CUMPRINC"] = cumulative(true)
        t["SLN"] = { a, c in
            guard let v = args(a, c, 3), v[2] != 0 else { return .error(.div0) }
            return .number((v[0] - v[1]) / v[2])
        }
        t["SYD"] = { a, c in
            guard let v = args(a, c, 4), v[2] > 0, v[3] >= 1, v[3] <= v[2] else { return .error(.num) }
            return .number((v[0] - v[1]) * (v[2] - v[3] + 1) * 2 / (v[2] * (v[2] + 1)))
        }
        t["DDB"] = { a, c in
            guard let v = args(a, c, 4) else { return .error(.value) }
            let cost = v[0], salvage = v[1], life = v[2], period = v[3], factor = v.count > 4 && v[4] != 0 ? v[4] : 2
            guard life > 0, period >= 1, period <= life else { return .error(.num) }
            var value = cost, dep = 0.0
            for _ in 0 ..< Int(period) {
                dep = min(value * factor / life, max(0, value - salvage))
                value -= dep
            }
            return .number(dep)
        }
        t["DB"] = { a, c in
            guard let v = args(a, c, 4) else { return .error(.value) }
            let cost = v[0], salvage = v[1], life = v[2], period = Int(v[3]), month = v.count > 4 && v[4] != 0 ? v[4] : 12
            guard cost > 0, life > 0, period >= 1 else { return .error(.num) }
            let rate = ((1 - pow(salvage / cost, 1 / life)) * 1000).rounded() / 1000
            var total = 0.0, dep = cost * rate * month / 12
            if period == 1 { return .number(dep) }
            total = dep
            for p in 2 ... period {
                dep = p == Int(life) + 1 ? (cost - total) * rate * (12 - month) / 12 : (cost - total) * rate
                total += dep
            }
            return .number(dep)
        }
        func npv(_ rate: Double, _ flows: [Double], _ times: [Double]) -> Double {
            zip(flows, times).reduce(0) { $0 + $1.0 / pow(1 + rate, $1.1) }
        }
        func solve(_ guess: Double, _ f: (Double) -> Double) -> Double? {
            var r = guess
            for _ in 0 ..< 100 {
                let y = f(r), h = 1e-6
                let d = (f(r + h) - y) / h
                guard d != 0, d.isFinite else { return nil }
                let next = r - y / d
                if abs(next - r) < 1e-10 { return next }
                r = next
                if r <= -1 { r = -0.999999 }
            }
            return abs(f(r)) < 1e-6 ? r : nil
        }
        t["IRR"] = { a, c in
            guard !a.isEmpty else { return .error(.value) }
            let flows = _numbers(a[0], c)
            guard flows.contains(where: { $0 > 0 }), flows.contains(where: { $0 < 0 }) else { return .error(.num) }
            let times = flows.indices.map(Double.init)
            return solve(_opt(a, 1, c, 0.1) ?? 0.1) { npv($0, flows, times) }.map { .number($0) } ?? .error(.num)
        }
        t["XNPV"] = { a, c in
            guard a.count == 3, case .success(let rate) = _n(a[0], c) else { return .error(.value) }
            let flows = _numbers(a[1], c), dates = _numbers(a[2], c)
            guard flows.count == dates.count, let d0 = dates.first else { return .error(.num) }
            return .number(npv(rate, flows, dates.map { ($0 - d0) / 365 }))
        }
        t["XIRR"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let flows = _numbers(a[0], c), dates = _numbers(a[1], c)
            guard flows.count == dates.count, let d0 = dates.first, flows.contains(where: { $0 > 0 }), flows.contains(where: { $0 < 0 }) else { return .error(.num) }
            let times = dates.map { ($0 - d0) / 365 }
            return solve(_opt(a, 2, c, 0.1) ?? 0.1) { npv($0, flows, times) }.map { .number($0) } ?? .error(.num)
        }
    }
}
