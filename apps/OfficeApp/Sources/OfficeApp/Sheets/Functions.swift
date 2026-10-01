// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The worksheet functions. Each takes its arguments unevaluated (IF must
// not evaluate the branch it does not take, and SUM wants the cells of a
// range rather than one value) and the context of the cell it is in.
//
// Coercion follows Excel's rule of thumb: a value written directly as an
// argument is converted ("3" to 3, TRUE to 1), while text and booleans
// met inside a range are skipped by the aggregate functions.

import Foundation

enum SheetFunctions {
    typealias Fn = ([FormulaExpr], EvalContext) -> EvalValue

    static let table: [String: Fn] = {
        var t: [String: Fn] = [:]
        // Aggregates.
        t["SUM"] = { a, c in _aggregate(a, c) { $0.reduce(0, +) } }
        t["PRODUCT"] = { a, c in _aggregate(a, c) { $0.isEmpty ? 0 : $0.reduce(1, *) } }
        t["AVERAGE"] = { a, c in _aggregate(a, c) { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) } }
        t["MIN"] = { a, c in _aggregate(a, c) { $0.min() ?? 0 } }
        t["MAX"] = { a, c in _aggregate(a, c) { $0.max() ?? 0 } }
        t["MEDIAN"] = { a, c in _aggregate(a, c) { xs in
            guard !xs.isEmpty else { return nil }
            let s = xs.sorted(); let m = s.count / 2
            return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
        } }
        t["STDEV"] = { a, c in _aggregate(a, c) { _stdev($0, sample: true) } }
        t["STDEV.S"] = t["STDEV"]
        t["STDEV.P"] = { a, c in _aggregate(a, c) { _stdev($0, sample: false) } }
        t["VAR"] = { a, c in _aggregate(a, c) { _stdev($0, sample: true).map { $0 * $0 } } }
        t["VAR.S"] = t["VAR"]
        t["COUNT"] = { a, c in
            var n = 0
            for arg in a { _each(arg, c, direct: { if case .success = CalcEngine.toNumber($0), !$0.isText { n += 1 } },
                                 inRange: { if $0.number != nil { n += 1 } }) }
            return .number(Double(n))
        }
        t["COUNTA"] = { a, c in
            var n = 0
            for arg in a { _each(arg, c, direct: { if !$0.isEmpty { n += 1 } }, inRange: { if !$0.isEmpty { n += 1 } }) }
            return .number(Double(n))
        }
        t["COUNTBLANK"] = { a, c in
            guard let first = a.first, case .range(let s, let r) = c.engine.evaluate(first, c) else { return .error(.value) }
            let filled = c.engine.values(s, r).filter { if case .text("") = $0 { return false }; return true }.count
            return .number(Double(r.rows * r.cols - filled))
        }
        // Rounding and arithmetic.
        t["ROUND"] = { a, c in _num2(a, c) { x, d in _round(x, Int(d), .toNearestOrAwayFromZero) } }
        t["ROUNDUP"] = { a, c in _num2(a, c) { x, d in _round(x, Int(d), .awayFromZero) } }
        t["ROUNDDOWN"] = { a, c in _num2(a, c) { x, d in _round(x, Int(d), .towardZero) } }
        t["INT"] = { a, c in _num1(a, c) { floor($0) } }
        t["TRUNC"] = { a, c in
            a.count >= 2 ? _num2(a, c) { x, d in _round(x, Int(d), .towardZero) } : _num1(a, c) { $0.rounded(.towardZero) }
        }
        t["ABS"] = { a, c in _num1(a, c) { abs($0) } }
        t["SIGN"] = { a, c in _num1(a, c) { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) } }
        t["SQRT"] = { a, c in _num1(a, c) { $0 < 0 ? .nan : $0.squareRoot() } }
        t["EXP"] = { a, c in _num1(a, c) { exp($0) } }
        t["LN"] = { a, c in _num1(a, c) { $0 <= 0 ? .nan : log($0) } }
        t["LOG10"] = { a, c in _num1(a, c) { $0 <= 0 ? .nan : log10($0) } }
        t["LOG"] = { a, c in
            a.count >= 2 ? _num2(a, c) { x, b in x <= 0 || b <= 0 || b == 1 ? .nan : log(x) / log(b) }
                         : _num1(a, c) { $0 <= 0 ? .nan : log10($0) }
        }
        t["PI"] = { _, _ in .number(Double.pi) }
        t["POWER"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            return c.engine.binary(.pow, c.engine.scalar(c.engine.evaluate(a[0], c), c), c.engine.scalar(c.engine.evaluate(a[1], c), c))
        }
        t["MOD"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            switch (_n(a[0], c), _n(a[1], c)) {
            case (.success(let x), .success(let y)):
                if y == 0 { return .error(.div0) }
                return .number(x - y * floor(x / y))
            case (.failure(let e), _), (_, .failure(let e)): return .error(e)
            }
        }
        t["CEILING"] = { a, c in _num2(a, c, defaultSecond: 1) { x, s in s == 0 ? 0 : ceil(x / s) * s } }
        t["FLOOR"] = { a, c in _num2(a, c, defaultSecond: 1) { x, s in s == 0 ? .nan : floor(x / s) * s } }
        t["RAND"] = { _, _ in .number(Double.random(in: 0 ..< 1)) }
        t["RANDBETWEEN"] = { a, c in _num2(a, c) { lo, hi in lo > hi ? .nan : Double(Int.random(in: Int(ceil(lo)) ... Int(floor(hi)))) } }
        t["SUMPRODUCT"] = { a, c in
            let grids = a.map { c.engine.grid(c.engine.evaluate($0, c), c) }
            guard let first = grids.first else { return .error(.value) }
            let rows = first.count, cols = first.first?.count ?? 0
            guard grids.allSatisfy({ $0.count == rows && ($0.first?.count ?? 0) == cols }) else { return .error(.value) }
            var total = 0.0
            for r in 0 ..< rows {
                for col in 0 ..< cols {
                    var p = 1.0
                    for g in grids {
                        if let e = g[r][col].error { return .error(e) }
                        p *= g[r][col].number ?? 0
                    }
                    total += p
                }
            }
            return .number(total)
        }
        // Logic.
        t["IF"] = { a, c in
            guard a.count >= 1, a.count <= 3 else { return .error(.value) }
            switch CalcEngine.toBool(c.engine.scalar(c.engine.evaluate(a[0], c), c)) {
            case .failure(let e): return .error(e)
            case .success(let b):
                if b { return a.count >= 2 ? _orZero(a[1], c) : .scalar(.bool(true)) }
                return a.count >= 3 ? _orZero(a[2], c) : .scalar(.bool(false))
            }
        }
        t["IFS"] = { a, c in
            guard a.count % 2 == 0 else { return .error(.value) }
            var i = 0
            while i < a.count {
                switch CalcEngine.toBool(c.engine.scalar(c.engine.evaluate(a[i], c), c)) {
                case .failure(let e): return .error(e)
                case .success(true): return c.engine.evaluate(a[i + 1], c)
                default: i += 2
                }
            }
            return .error(.na)
        }
        t["IFERROR"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            let v = c.engine.evaluate(a[0], c)
            if c.engine.scalar(v, c).error != nil { return c.engine.evaluate(a[1], c) }
            return v
        }
        t["IFNA"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            let v = c.engine.evaluate(a[0], c)
            if c.engine.scalar(v, c).error == .na { return c.engine.evaluate(a[1], c) }
            return v
        }
        t["AND"] = { a, c in _logic(a, c, and: true) }
        t["OR"] = { a, c in _logic(a, c, and: false) }
        t["XOR"] = { a, c in
            var n = 0
            for arg in a {
                var err: ExcelError? = nil
                _each(arg, c, direct: { v in
                    switch CalcEngine.toBool(v) { case .success(let b): if b { n += 1 }; case .failure(let e): err = e }
                }, inRange: { v in if case .bool(true) = v { n += 1 } else if let x = v.number, x != 0 { n += 1 } })
                if let err { return .error(err) }
            }
            return .scalar(.bool(n % 2 == 1))
        }
        t["NOT"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            switch CalcEngine.toBool(c.engine.scalar(c.engine.evaluate(a[0], c), c)) {
            case .success(let b): return .scalar(.bool(!b))
            case .failure(let e): return .error(e)
            }
        }
        t["TRUE"] = { _, _ in .scalar(.bool(true)) }
        t["FALSE"] = { _, _ in .scalar(.bool(false)) }
        t["NA"] = { _, _ in .error(.na) }
        t["CHOOSE"] = { a, c in
            guard a.count >= 2, case .success(let i) = _n(a[0], c) else { return .error(.value) }
            let k = Int(i)
            guard k >= 1, k < a.count else { return .error(.value) }
            return c.engine.evaluate(a[k], c)
        }
        // Information.
        t["ISBLANK"] = { a, c in _is(a, c) { $0.isEmpty } }
        t["ISNUMBER"] = { a, c in _is(a, c) { $0.number != nil } }
        t["ISTEXT"] = { a, c in _is(a, c) { $0.isText } }
        t["ISNONTEXT"] = { a, c in _is(a, c) { !$0.isText } }
        t["ISLOGICAL"] = { a, c in _is(a, c) { if case .bool = $0 { return true }; return false } }
        t["ISERROR"] = { a, c in _is(a, c) { $0.error != nil } }
        t["ISERR"] = { a, c in _is(a, c) { $0.error != nil && $0.error != .na } }
        t["ISNA"] = { a, c in _is(a, c) { $0.error == .na } }
        t["ISEVEN"] = { a, c in _num1(a, c) { Int(floor(abs($0))) % 2 == 0 ? 1 : 0 }.asBool }
        t["ISODD"] = { a, c in _num1(a, c) { Int(floor(abs($0))) % 2 == 1 ? 1 : 0 }.asBool }
        // Conditional aggregates.
        t["SUMIF"] = { a, c in
            guard a.count == 2 || a.count == 3 else { return .error(.value) }
            return _conditional(ranges: [a[0]], criteria: [a[1]], target: a.count == 3 ? a[2] : a[0], c) { $0.reduce(0, +) }
        }
        t["SUMIFS"] = { a, c in
            guard a.count >= 3, a.count % 2 == 1 else { return .error(.value) }
            let pairs = stride(from: 1, to: a.count, by: 2)
            return _conditional(ranges: pairs.map { a[$0] }, criteria: pairs.map { a[$0 + 1] }, target: a[0], c) { $0.reduce(0, +) }
        }
        t["AVERAGEIF"] = { a, c in
            guard a.count == 2 || a.count == 3 else { return .error(.value) }
            return _conditional(ranges: [a[0]], criteria: [a[1]], target: a.count == 3 ? a[2] : a[0], c) {
                $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count)
            }
        }
        t["AVERAGEIFS"] = { a, c in
            guard a.count >= 3, a.count % 2 == 1 else { return .error(.value) }
            let pairs = stride(from: 1, to: a.count, by: 2)
            return _conditional(ranges: pairs.map { a[$0] }, criteria: pairs.map { a[$0 + 1] }, target: a[0], c) {
                $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count)
            }
        }
        t["COUNTIF"] = { a, c in
            guard a.count == 2 else { return .error(.value) }
            return _conditional(ranges: [a[0]], criteria: [a[1]], target: nil, c) { Double($0.count) }
        }
        t["COUNTIFS"] = { a, c in
            guard a.count >= 2, a.count % 2 == 0 else { return .error(.value) }
            let pairs = stride(from: 0, to: a.count, by: 2)
            return _conditional(ranges: pairs.map { a[$0] }, criteria: pairs.map { a[$0 + 1] }, target: nil, c) { Double($0.count) }
        }
        // Lookup.
        t["VLOOKUP"] = { a, c in _hvlookup(a, c, vertical: true) }
        t["HLOOKUP"] = { a, c in _hvlookup(a, c, vertical: false) }
        // HYPERLINK(location, [name]): shows the name (or the location);
        // ⌘-click on the cell follows it (Hyperlinks.swift).
        // Dynamic arrays: results spill from a dynamic formula's cell.
        t["SEQUENCE"] = { a, c in
            guard !a.isEmpty, case .success(let r) = _n(a[0], c) else { return .error(.value) }
            func opt(_ i: Int, _ d: Double) -> Double? {
                guard a.count > i, a[i] != .missing else { return d }
                if case .success(let v) = _n(a[i], c) { return v } else { return nil }
            }
            guard let cols = opt(1, 1), let start = opt(2, 1), let step = opt(3, 1) else { return .error(.value) }
            let nr = Int(r), nc = Int(cols)
            guard nr >= 1, nc >= 1, nr * nc <= 1_000_000 else { return .error(nr < 1 || nc < 1 ? .calc : .num) }
            return .array((0 ..< nr).map { i in (0 ..< nc).map { j in .number(start + Double(i * nc + j) * step) } })
        }
        t["TRANSPOSE"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            let g = c.engine.gridFull(c.engine.evaluate(a[0], c), c)
            guard let w = g.first?.count, w > 0 else { return .error(.value) }
            return .array((0 ..< w).map { j in g.map { $0.count > j ? $0[j] : .empty } })
        }
        t["FILTER"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let g = c.engine.gridFull(c.engine.evaluate(a[0], c), c)
            var dyn = c
            dyn.dynamic = true
            let inc = c.engine.gridFull(c.engine.evaluate(a[1], dyn), dyn)
            func keep(_ v: CellValue) -> Bool {
                if case .bool(let b) = v { return b }
                return (v.number ?? 0) != 0
            }
            var out: [[CellValue]]
            if inc.count == g.count, inc.first?.count == 1 {
                out = zip(g, inc).filter { keep($0.1[0]) }.map(\.0)
            } else if inc.count == 1, inc[0].count == (g.first?.count ?? 0) {
                let cols = inc[0].indices.filter { keep(inc[0][$0]) }
                out = cols.isEmpty ? [] : g.map { row in cols.map { row[$0] } }
            } else {
                return .error(.value)
            }
            if out.isEmpty || out.first?.isEmpty == true {
                return a.count > 2 ? c.engine.evaluate(a[2], c) : .error(.calc)
            }
            return .array(out)
        }
        t["UNIQUE"] = { a, c in
            guard !a.isEmpty else { return .error(.value) }
            var g = c.engine.gridFull(c.engine.evaluate(a[0], c), c)
            let byCol = a.count > 1 && c.engine.scalar(c.engine.evaluate(a[1], c), c) == .bool(true)
            let once = a.count > 2 && c.engine.scalar(c.engine.evaluate(a[2], c), c) == .bool(true)
            if byCol, let w = g.first?.count { g = (0 ..< w).map { j in g.map { $0[j] } } }
            func key(_ row: [CellValue]) -> String {
                row.map { v in v.number.map { "n\($0)" } ?? "t" + NumberFormat.display(v, "General", width: 255).text.lowercased() }.joined(separator: "\u{1}")
            }
            var counts: [String: Int] = [:]
            for row in g { counts[key(row), default: 0] += 1 }
            var seen = Set<String>(), out: [[CellValue]] = []
            for row in g where seen.insert(key(row)).inserted && (!once || counts[key(row)] == 1) { out.append(row) }
            guard !out.isEmpty else { return .error(.calc) }
            if byCol, let h = out.first?.count { out = (0 ..< h).map { i in out.map { $0[i] } } }
            return .array(out)
        }
        func sortRows(_ g: [[CellValue]], keys: [(values: [CellValue], ascending: Bool)]) -> [[CellValue]] {
            let order = g.indices.sorted { x, y in
                for k in keys {
                    let a = x < k.values.count ? k.values[x] : .empty, b = y < k.values.count ? k.values[y] : .empty
                    // Blanks last, whichever way.
                    if a.isEmpty != b.isEmpty { return b.isEmpty }
                    let cmp = CalcEngine.compare(a, b)
                    if cmp != 0 { return k.ascending ? cmp < 0 : cmp > 0 }
                }
                return x < y
            }
            return order.map { g[$0] }
        }
        t["SORT"] = { a, c in
            guard !a.isEmpty else { return .error(.value) }
            var g = c.engine.gridFull(c.engine.evaluate(a[0], c), c)
            func num(_ i: Int, _ d: Double) -> Double {
                guard a.count > i, a[i] != .missing, case .success(let v) = _n(a[i], c) else { return d }
                return v
            }
            let index = Int(num(1, 1)), ascending = num(2, 1) >= 0
            let byCol = a.count > 3 && c.engine.scalar(c.engine.evaluate(a[3], c), c) == .bool(true)
            if byCol, let w = g.first?.count { g = (0 ..< w).map { j in g.map { $0[j] } } }
            guard index >= 1, index <= (g.first?.count ?? 0) else { return .error(.value) }
            var out = sortRows(g, keys: [(g.map { $0[index - 1] }, ascending)])
            if byCol, let h = out.first?.count { out = (0 ..< h).map { i in out.map { $0[i] } } }
            return .array(out)
        }
        t["SORTBY"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let g = c.engine.gridFull(c.engine.evaluate(a[0], c), c)
            var keys: [(values: [CellValue], ascending: Bool)] = []
            var i = 1
            while i < a.count {
                let by = c.engine.gridFull(c.engine.evaluate(a[i], c), c)
                let column = by.count == g.count ? by.map { $0.first ?? .empty } : (by.first ?? [])
                var ascending = true
                if i + 1 < a.count, a[i + 1] != .missing, case .success(let o) = _n(a[i + 1], c) { ascending = o >= 0 }
                keys.append((column, ascending))
                i += 2
            }
            return .array(sortRows(g, keys: keys))
        }
        // @x: one value of x, the one in the formula's row or column.
        t["SINGLE"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            return .scalar(c.engine.scalar(c.engine.evaluate(a[0], c), c))
        }
        // LET(name, value, …, calculation): values named for the calculation.
        t["LET"] = { a, c in
            guard a.count >= 3, a.count % 2 == 1 else { return .error(.value) }
            var scope = c
            for i in stride(from: 0, to: a.count - 1, by: 2) {
                guard case .name(let n) = a[i] else { return .error(.name) }
                scope.locals[n.uppercased()] = c.engine.evaluate(a[i + 1], scope)
            }
            return c.engine.evaluate(a[a.count - 1], scope)
        }
        // Excel 365's array shapers.
        func g(_ e: FormulaExpr, _ c: EvalContext) -> [[CellValue]] { c.engine.gridFull(c.engine.evaluate(e, c), c) }
        func int(_ e: FormulaExpr, _ c: EvalContext) -> Int? { if case .success(let v) = _n(e, c) { return Int(v) } else { return nil } }
        func pad(_ rows: [[CellValue]], _ w: Int) -> [[CellValue]] { rows.map { $0 + Array(repeating: .error(.na), count: max(0, w - $0.count)) } }
        t["VSTACK"] = { a, c in
            let parts = a.map { g($0, c) }
            let w = parts.map { $0.first?.count ?? 0 }.max() ?? 0
            return .array(parts.flatMap { pad($0, w) })
        }
        t["HSTACK"] = { a, c in
            let parts = a.map { g($0, c) }
            let h = parts.map(\.count).max() ?? 0
            return .array((0 ..< h).map { r in parts.flatMap { p in r < p.count ? p[r] : Array(repeating: .error(.na), count: p.first?.count ?? 0) } })
        }
        t["TAKE"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            var rows = g(a[0], c)
            if a[1] != .missing, let n = int(a[1], c) { rows = n >= 0 ? Array(rows.prefix(n)) : Array(rows.suffix(-n)) }
            if a.count > 2, let n = int(a[2], c) { rows = rows.map { n >= 0 ? Array($0.prefix(n)) : Array($0.suffix(-n)) } }
            return rows.isEmpty || rows[0].isEmpty ? .error(.calc) : .array(rows)
        }
        t["DROP"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            var rows = g(a[0], c)
            if a[1] != .missing, let n = int(a[1], c) { rows = n >= 0 ? Array(rows.dropFirst(n)) : Array(rows.dropLast(-n)) }
            if a.count > 2, let n = int(a[2], c) { rows = rows.map { n >= 0 ? Array($0.dropFirst(n)) : Array($0.dropLast(-n)) } }
            return rows.isEmpty || rows[0].isEmpty ? .error(.calc) : .array(rows)
        }
        t["CHOOSEROWS"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let rows = g(a[0], c)
            var out: [[CellValue]] = []
            for e in a.dropFirst() {
                for n in g(e, c).flatMap({ $0 }).compactMap({ $0.number.map(Int.init) }) {
                    let i = n > 0 ? n - 1 : rows.count + n
                    guard i >= 0, i < rows.count else { return .error(.value) }
                    out.append(rows[i])
                }
            }
            return .array(out)
        }
        t["CHOOSECOLS"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let rows = g(a[0], c)
            let w = rows.first?.count ?? 0
            var cols: [Int] = []
            for e in a.dropFirst() {
                for n in g(e, c).flatMap({ $0 }).compactMap({ $0.number.map(Int.init) }) {
                    let i = n > 0 ? n - 1 : w + n
                    guard i >= 0, i < w else { return .error(.value) }
                    cols.append(i)
                }
            }
            return .array(rows.map { r in cols.map { r[$0] } })
        }
        func flat(_ a: [FormulaExpr], _ c: EvalContext) -> [CellValue] {
            let rows = g(a[0], c)
            let byCol = a.count > 2 && c.engine.scalar(c.engine.evaluate(a[2], c), c) == .bool(true)
            let ignore = a.count > 1 ? int(a[1], c) ?? 0 : 0
            var vals = byCol ? (0 ..< (rows.first?.count ?? 0)).flatMap { j in rows.map { $0[j] } } : rows.flatMap { $0 }
            if ignore == 1 || ignore == 3 { vals.removeAll { $0.isEmpty } }
            if ignore == 2 || ignore == 3 { vals.removeAll { $0.error != nil } }
            return vals
        }
        t["TOCOL"] = { a, c in a.isEmpty ? .error(.value) : .array(flat(a, c).map { [$0] }) }
        t["TOROW"] = { a, c in a.isEmpty ? .error(.value) : .array([flat(a, c)]) }
        func wrap(_ a: [FormulaExpr], _ c: EvalContext, rowsFirst: Bool) -> EvalValue {
            guard a.count >= 2, let n = int(a[1], c), n >= 1 else { return .error(.value) }
            let vals = g(a[0], c).flatMap { $0 }
            let fill = a.count > 2 ? c.engine.scalar(c.engine.evaluate(a[2], c), c) : .error(.na)
            var chunks = stride(from: 0, to: vals.count, by: n).map { Array(vals[$0 ..< min($0 + n, vals.count)]) }
            if let last = chunks.indices.last { chunks[last] += Array(repeating: fill, count: n - chunks[last].count) }
            return .array(rowsFirst ? chunks : (0 ..< n).map { i in chunks.map { $0[i] } })
        }
        t["WRAPROWS"] = { a, c in wrap(a, c, rowsFirst: true) }
        t["WRAPCOLS"] = { a, c in wrap(a, c, rowsFirst: false) }
        t["TEXTSPLIT"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let text = NumberFormat.display(c.engine.scalar(c.engine.evaluate(a[0], c), c), "General", width: 32767).text
            func delims(_ e: FormulaExpr?) -> [String] {
                guard let e, e != .missing else { return [] }
                return g(e, c).flatMap { $0 }.map { NumberFormat.display($0, "General", width: 255).text }.filter { !$0.isEmpty }
            }
            func split(_ s: String, _ ds: [String]) -> [String] {
                guard !ds.isEmpty else { return [s] }
                var parts = [s]
                for d in ds { parts = parts.flatMap { $0.components(separatedBy: d) } }
                return parts
            }
            let ignoreEmpty = a.count > 3 && c.engine.scalar(c.engine.evaluate(a[3], c), c) == .bool(true)
            var rows = split(text, delims(a.count > 2 ? a[2] : nil)).map { split($0, delims(a[1])) }
            if ignoreEmpty { rows = rows.map { $0.filter { !$0.isEmpty } }.filter { !$0.isEmpty } }
            let w = rows.map(\.count).max() ?? 0
            return .array(rows.map { r in r.map { CellValue.text($0) } + Array(repeating: .error(.na), count: w - r.count) })
        }
        t["HYPERLINK"] = { a, c in
            guard !a.isEmpty else { return .error(.value) }
            return .scalar(c.engine.scalar(c.engine.evaluate(a.count > 1 ? a[1] : a[0], c), c))
        }
        t["INDEX"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let src = c.engine.evaluate(a[0], c)
            guard case .success(let r) = _n(a[1], c) else { return .error(.value) }
            let col: Double
            if a.count >= 3 { guard case .success(let x) = _n(a[2], c) else { return .error(.value) }; col = x } else { col = 0 }
            if case .range(let s, let rg) = src {
                // INDEX of a range is a reference — INDEX(A:A,3):B5 works.
                var row = Int(r), cc = Int(col)
                if rg.rows == 1 && a.count < 3 { cc = row; row = 1 }
                if row == 0 && cc == 0 { return src }
                if row == 0 { return .range(sheet: s, CellRange(top: rg.top, left: rg.left + cc - 1, bottom: rg.bottom, right: rg.left + cc - 1)) }
                if cc == 0 && rg.cols > 1 { return .range(sheet: s, CellRange(top: rg.top + row - 1, left: rg.left, bottom: rg.top + row - 1, right: rg.right)) }
                if cc == 0 { cc = 1 }
                guard row >= 1, row <= rg.rows, cc >= 1, cc <= rg.cols else { return .error(.ref) }
                return .scalar(c.engine.value(s, CellAddress(row: rg.top + row - 1, col: rg.left + cc - 1)))
            }
            let g = c.engine.grid(src, c)
            var row = Int(r), cc = max(1, Int(col))
            // One row and no column given: the number picks the column, as for a range.
            if g.count == 1 && a.count < 3 { cc = row; row = 1 }
            guard row >= 1, row <= g.count, cc <= (g.first?.count ?? 0) else { return .error(.ref) }
            return .scalar(g[row - 1][cc - 1])
        }
        t["MATCH"] = { a, c in
            guard a.count >= 2 else { return .error(.value) }
            let key = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            if let e = key.error { return .error(e) }
            let g = c.engine.grid(c.engine.evaluate(a[1], c), c)
            let list = g.count == 1 ? g[0] : g.map { $0.first ?? .empty }
            var mode = 1.0
            if a.count >= 3 { guard case .success(let m) = _n(a[2], c) else { return .error(.value) }; mode = m }
            guard let i = _match(key, list, mode: Int(mode)) else { return .error(.na) }
            return .number(Double(i + 1))
        }
        t["XLOOKUP"] = { a, c in
            guard a.count >= 3 else { return .error(.value) }
            let key = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            if let e = key.error { return .error(e) }
            let lg = c.engine.grid(c.engine.evaluate(a[1], c), c)
            let rg = c.engine.grid(c.engine.evaluate(a[2], c), c)
            let vertical = lg.count > 1
            let list = vertical ? lg.map { $0.first ?? .empty } : (lg.first ?? [])
            var mode = 0.0
            if a.count >= 5 { if case .success(let m) = _n(a[4], c) { mode = m } }
            let found: Int?
            switch Int(mode) {
            case -1: found = _approx(key, list, smaller: true)
            case 1: found = _approx(key, list, smaller: false)
            case 2: found = list.firstIndex { _wildcard(key, $0) }
            default: found = list.firstIndex { CalcEngine.compare(key, $0) == 0 && !$0.isEmpty }
            }
            guard let i = found else {
                if a.count >= 4, a[3] != .missing { return c.engine.evaluate(a[3], c) }
                return .error(.na)
            }
            if vertical { return i < rg.count ? .array([rg[i]]) : .error(.ref) }
            return .array(rg.map { i < $0.count ? [$0[i]] : [.error(.ref)] })
        }
        t["ROW"] = { a, c in
            if let f = a.first, case .range(_, let r) = c.engine.evaluate(f, c) { return .number(Double(r.top + 1)) }
            if let f = a.first, case .ref(let r) = f, let row = r.start.row { return .number(Double(row + 1)) }
            return .number(Double(c.cell.row + 1))
        }
        t["COLUMN"] = { a, c in
            if let f = a.first, case .range(_, let r) = c.engine.evaluate(f, c) { return .number(Double(r.left + 1)) }
            if let f = a.first, case .ref(let r) = f, let col = r.start.col { return .number(Double(col + 1)) }
            return .number(Double(c.cell.col + 1))
        }
        t["ROWS"] = { a, c in
            guard let f = a.first else { return .error(.value) }
            if case .range(_, let r) = c.engine.evaluate(f, c) { return .number(Double(r.rows)) }
            return .number(Double(c.engine.grid(c.engine.evaluate(f, c), c).count))
        }
        t["COLUMNS"] = { a, c in
            guard let f = a.first else { return .error(.value) }
            if case .range(_, let r) = c.engine.evaluate(f, c) { return .number(Double(r.cols)) }
            return .number(Double(c.engine.grid(c.engine.evaluate(f, c), c).first?.count ?? 0))
        }
        // Text.
        t["CONCATENATE"] = { a, c in _concat(a, c, separator: "", skipEmpty: false) }
        t["CONCAT"] = t["CONCATENATE"]
        t["TEXTJOIN"] = { a, c in
            guard a.count >= 3, case .success(let sep) = _t(a[0], c),
                  case .success(let skip) = CalcEngine.toBool(c.engine.scalar(c.engine.evaluate(a[1], c), c)) else { return .error(.value) }
            return _concat(Array(a.dropFirst(2)), c, separator: sep, skipEmpty: skip)
        }
        t["LEN"] = { a, c in _text1(a, c) { .number(Double($0.count)) } }
        t["UPPER"] = { a, c in _text1(a, c) { .scalar(.text($0.uppercased())) } }
        t["LOWER"] = { a, c in _text1(a, c) { .scalar(.text($0.lowercased())) } }
        t["PROPER"] = { a, c in _text1(a, c) { s in
            var out = "", prevLetter = false
            for ch in s { out += prevLetter ? ch.lowercased() : ch.uppercased(); prevLetter = ch.isLetter }
            return .scalar(.text(out))
        } }
        t["TRIM"] = { a, c in _text1(a, c) { s in
            .scalar(.text(s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")))
        } }
        t["LEFT"] = { a, c in _textN(a, c, defaultN: 1) { s, n in String(s.prefix(n)) } }
        t["RIGHT"] = { a, c in _textN(a, c, defaultN: 1) { s, n in String(s.suffix(n)) } }
        t["MID"] = { a, c in
            guard a.count == 3, case .success(let s) = _t(a[0], c), case .success(let st) = _n(a[1], c),
                  case .success(let n) = _n(a[2], c), st >= 1, n >= 0 else { return .error(.value) }
            let chars = Array(s)
            let from = min(chars.count, Int(st) - 1)
            return .scalar(.text(String(chars[from ..< min(chars.count, from + Int(n))])))
        }
        t["REPT"] = { a, c in _textN(a, c, defaultN: 1) { s, n in String(repeating: s, count: max(0, n)) } }
        t["FIND"] = { a, c in _find(a, c, caseSensitive: true) }
        t["SEARCH"] = { a, c in _find(a, c, caseSensitive: false) }
        t["SUBSTITUTE"] = { a, c in
            guard a.count >= 3, case .success(let s) = _t(a[0], c), case .success(let old) = _t(a[1], c),
                  case .success(let new) = _t(a[2], c) else { return .error(.value) }
            guard !old.isEmpty else { return .scalar(.text(s)) }
            if a.count >= 4 {
                guard case .success(let k) = _n(a[3], c), k >= 1 else { return .error(.value) }
                var count = 0
                var from = s.startIndex, out = ""
                while let r = s.findRange(of: old, in: from ..< s.endIndex) {
                    count += 1
                    out += s[from ..< r.lowerBound]
                    out += count == Int(k) ? new : old
                    from = r.upperBound
                }
                return .scalar(.text(out + s[from...]))
            }
            return .scalar(.text(s.replacingAll(old, with: new)))
        }
        t["TEXT"] = { a, c in
            guard a.count == 2, case .success(let fmt) = _t(a[1], c) else { return .error(.value) }
            let v = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            if let e = v.error { return .error(e) }
            if case .text(let s) = v, let n = InputParser.number(s) {
                return .scalar(.text(NumberFormat.format(n.value, fmt, width: 255).text))
            }
            return .scalar(.text(NumberFormat.display(v, fmt, width: 255).text))
        }
        t["VALUE"] = { a, c in
            guard a.count == 1 else { return .error(.value) }
            let v = c.engine.scalar(c.engine.evaluate(a[0], c), c)
            switch CalcEngine.toNumber(v) { case .success(let n): return .number(n); case .failure(let e): return .error(e) }
        }
        t["EXACT"] = { a, c in
            guard a.count == 2, case .success(let x) = _t(a[0], c), case .success(let y) = _t(a[1], c) else { return .error(.value) }
            return .scalar(.bool(x == y))
        }
        t["CHAR"] = { a, c in _num1(a, c) { $0 }.map { n in
            guard n >= 1, n <= 255, let u = UnicodeScalar(UInt32(n)) else { return .error(.value) }
            return .scalar(.text(String(Character(u))))
        } }
        t["CODE"] = { a, c in _text1(a, c) { s in
            guard let u = s.unicodeScalars.first else { return .error(.value) }
            return .number(Double(u.value))
        } }
        // Dates.
        t["TODAY"] = { _, c in .number(floor(c.engine.now)) }
        t["NOW"] = { _, c in .number(c.engine.now) }
        t["DATE"] = { a, c in
            guard a.count == 3, case .success(let y) = _n(a[0], c), case .success(let m) = _n(a[1], c),
                  case .success(let d) = _n(a[2], c) else { return .error(.value) }
            let yy = Int(y) < 1900 ? Int(y) + 1900 : Int(y)
            let s = ExcelDate.serial(yy, Int(m), Int(d))
            return s < 0 ? .error(.num) : .number(s)
        }
        t["YEAR"] = { a, c in _date1(a, c) { y, _, _ in Double(y) } }
        t["MONTH"] = { a, c in _date1(a, c) { _, m, _ in Double(m) } }
        t["DAY"] = { a, c in _date1(a, c) { _, _, d in Double(d) } }
        t["WEEKDAY"] = { a, c in
            guard let f = a.first, case .success(let s) = _n(f, c) else { return .error(.value) }
            var type = 1.0
            if a.count >= 2, case .success(let ty) = _n(a[1], c) { type = ty }
            let w = ExcelDate.weekday(s)   // 1 = Sunday
            switch Int(type) {
            case 2: return .number(Double((w + 5) % 7 + 1))   // 1 = Monday
            case 3: return .number(Double((w + 5) % 7))       // 0 = Monday
            default: return .number(Double(w))
            }
        }
        t["HOUR"] = { a, c in _num1(a, c) { floor(($0 - floor($0)) * 24 + 1e-9) } }
        t["MINUTE"] = { a, c in _num1(a, c) { Double(Int((($0 - floor($0)) * 1440 + 1e-7)) % 60) } }
        t["SECOND"] = { a, c in _num1(a, c) { Double(Int((($0 - floor($0)) * 86400).rounded()) % 60) } }
        t["TIME"] = { a, c in
            guard a.count == 3, case .success(let h) = _n(a[0], c), case .success(let m) = _n(a[1], c),
                  case .success(let s) = _n(a[2], c) else { return .error(.value) }
            let v = (h * 3600 + m * 60 + s) / 86400
            return .number(v - floor(v))
        }
        t["EDATE"] = { a, c in
            guard a.count == 2, case .success(let s) = _n(a[0], c), case .success(let k) = _n(a[1], c) else { return .error(.value) }
            let (y, m, d) = ExcelDate.ymd(s)
            let target = ExcelDate.ymd(ExcelDate.serial(y, m + Int(k) + 1, 1) - 1)   // last day of target month
            return .number(ExcelDate.serial(target.0, target.1, min(d, target.2)))
        }
        t["EOMONTH"] = { a, c in
            guard a.count == 2, case .success(let s) = _n(a[0], c), case .success(let k) = _n(a[1], c) else { return .error(.value) }
            let (y, m, _) = ExcelDate.ymd(s)
            return .number(ExcelDate.serial(y, m + Int(k) + 1, 1) - 1)
        }
        t["DATEDIF"] = { a, c in
            guard a.count == 3, case .success(let s1) = _n(a[0], c), case .success(let s2) = _n(a[1], c),
                  case .success(let unit) = _t(a[2], c), s2 >= s1 else { return .error(.num) }
            let (y1, m1, d1) = ExcelDate.ymd(s1), (y2, m2, d2) = ExcelDate.ymd(s2)
            var months = (y2 - y1) * 12 + (m2 - m1)
            if d2 < d1 { months -= 1 }
            switch unit.uppercased() {
            case "D": return .number(floor(s2) - floor(s1))
            case "M": return .number(Double(months))
            case "Y": return .number(Double(months / 12))
            case "YM": return .number(Double(months % 12))
            default: return .error(.num)
            }
        }
        t["NETWORKDAYS"] = { a, c in
            guard a.count >= 2, case .success(let s1) = _n(a[0], c), case .success(let s2) = _n(a[1], c) else { return .error(.value) }
            var holidays: Set<Int> = []
            if a.count >= 3 { for v in c.engine.grid(c.engine.evaluate(a[2], c), c).flatMap({ $0 }) { if let n = v.number { holidays.insert(Int(n)) } } }
            let lo = Int(min(s1, s2)), hi = Int(max(s1, s2))
            var n = 0
            for d in lo ... hi {
                let w = ExcelDate.weekday(Double(d))
                if w != 1 && w != 7 && !holidays.contains(d) { n += 1 }
            }
            return .number(Double(s1 <= s2 ? n : -n))
        }
        // Finance.
        t["PMT"] = { a, c in
            guard a.count >= 3, case .success(let rate) = _n(a[0], c), case .success(let n) = _n(a[1], c),
                  case .success(let pv) = _n(a[2], c) else { return .error(.value) }
            let fv = a.count >= 4 ? ((try? _n(a[3], c).get()) ?? 0) : 0
            let type = a.count >= 5 ? ((try? _n(a[4], c).get()) ?? 0) : 0
            guard n != 0 else { return .error(.num) }
            if rate == 0 { return .number(-(pv + fv) / n) }
            let f = pow(1 + rate, n)
            return .number(-(rate * (pv * f + fv)) / ((1 + rate * type) * (f - 1)))
        }
        t["FV"] = { a, c in
            guard a.count >= 3, case .success(let rate) = _n(a[0], c), case .success(let n) = _n(a[1], c),
                  case .success(let pmt) = _n(a[2], c) else { return .error(.value) }
            let pv = a.count >= 4 ? ((try? _n(a[3], c).get()) ?? 0) : 0
            let type = a.count >= 5 ? ((try? _n(a[4], c).get()) ?? 0) : 0
            if rate == 0 { return .number(-(pv + pmt * n)) }
            let f = pow(1 + rate, n)
            return .number(-(pv * f + pmt * (1 + rate * type) * (f - 1) / rate))
        }
        t["PV"] = { a, c in
            guard a.count >= 3, case .success(let rate) = _n(a[0], c), case .success(let n) = _n(a[1], c),
                  case .success(let pmt) = _n(a[2], c) else { return .error(.value) }
            let fv = a.count >= 4 ? ((try? _n(a[3], c).get()) ?? 0) : 0
            let type = a.count >= 5 ? ((try? _n(a[4], c).get()) ?? 0) : 0
            if rate == 0 { return .number(-(fv + pmt * n)) }
            let f = pow(1 + rate, n)
            return .number(-(fv + pmt * (1 + rate * type) * (f - 1) / rate) / f)
        }
        t["NPV"] = { a, c in
            guard a.count >= 2, case .success(let rate) = _n(a[0], c) else { return .error(.value) }
            var total = 0.0, k = 1.0
            for arg in a.dropFirst() {
                var err: ExcelError? = nil
                _each(arg, c, direct: { v in
                    switch CalcEngine.toNumber(v) { case .success(let x): total += x / pow(1 + rate, k); k += 1; case .failure(let e): err = e }
                }, inRange: { v in if let x = v.number { total += x / pow(1 + rate, k); k += 1 } })
                if let err { return .error(err) }
            }
            return .number(total)
        }
        return t
    }()

    // MARK: Helpers

    static func _n(_ e: FormulaExpr, _ c: EvalContext) -> Result<Double, ExcelError> {
        c.engine.number(c.engine.evaluate(e, c), c)
    }

    static func _t(_ e: FormulaExpr, _ c: EvalContext) -> Result<String, ExcelError> {
        CalcEngine.toText(c.engine.scalar(c.engine.evaluate(e, c), c))
    }

    /// An omitted branch of IF gives 0, as Excel's does.
    static func _orZero(_ e: FormulaExpr, _ c: EvalContext) -> EvalValue {
        e == .missing ? .number(0) : c.engine.evaluate(e, c)
    }

    /// Each value of an argument: `direct` for a value written in place,
    /// `inRange` for each cell of a range or array.
    static func _each(_ e: FormulaExpr, _ c: EvalContext, direct: (CellValue) -> Void, inRange: (CellValue) -> Void) {
        switch c.engine.evaluate(e, c) {
        case .scalar(let v):
            if case .ref = e { inRange(v) } else { direct(v) }
        case .range(let s, let r): for v in c.engine.values(s, r) { inRange(v) }
        case .array(let rows): for row in rows { for v in row { inRange(v) } }
        }
    }

    static func _aggregate(_ args: [FormulaExpr], _ c: EvalContext, _ f: ([Double]) -> Double?) -> EvalValue {
        var xs: [Double] = []
        for arg in args {
            var err: ExcelError? = nil
            _each(arg, c, direct: { v in
                guard err == nil, !v.isEmpty else { return }
                switch CalcEngine.toNumber(v) { case .success(let n): xs.append(n); case .failure(let e): err = e }
            }, inRange: { v in
                guard err == nil else { return }
                if let e = v.error { err = e } else if let n = v.number { xs.append(n) }
            })
            if let err { return .error(err) }
        }
        guard let r = f(xs) else { return .error(.div0) }
        return .number(r)
    }

    static func _stdev(_ xs: [Double], sample: Bool) -> Double? {
        let n = Double(xs.count)
        guard xs.count >= (sample ? 2 : 1) else { return nil }
        let mean = xs.reduce(0, +) / n
        let ss = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (ss / (sample ? n - 1 : n)).squareRoot()
    }

    static func _num1(_ a: [FormulaExpr], _ c: EvalContext, _ f: (Double) -> Double) -> EvalValue {
        guard a.count == 1 else { return .error(.value) }
        switch _n(a[0], c) { case .success(let x): return .number(f(x)); case .failure(let e): return .error(e) }
    }

    static func _num2(_ a: [FormulaExpr], _ c: EvalContext, defaultSecond: Double? = nil,
                      _ f: (Double, Double) -> Double) -> EvalValue {
        guard a.count == 2 || (a.count == 1 && defaultSecond != nil) else { return .error(.value) }
        let y: Result<Double, ExcelError> = a.count == 2 ? _n(a[1], c) : .success(defaultSecond!)
        switch (_n(a[0], c), y) {
        case (.success(let x), .success(let y)): return .number(f(x, y))
        case (.failure(let e), _), (_, .failure(let e)): return .error(e)
        }
    }

    static func _round(_ x: Double, _ digits: Int, _ rule: FloatingPointRoundingRule) -> Double {
        let p = pow(10.0, Double(digits))
        // Nudge by an ulp so 2.675 rounds as Excel shows it.
        let scaled = x * p
        let nudged = scaled + (scaled >= 0 ? 1 : -1) * scaled.ulp * 4
        return (rule == .toNearestOrAwayFromZero ? nudged : scaled).rounded(rule) / p
    }

    static func _is(_ a: [FormulaExpr], _ c: EvalContext, _ test: (CellValue) -> Bool) -> EvalValue {
        guard a.count == 1 else { return .error(.value) }
        return .scalar(.bool(test(c.engine.scalar(c.engine.evaluate(a[0], c), c))))
    }

    static func _logic(_ a: [FormulaExpr], _ c: EvalContext, and: Bool) -> EvalValue {
        var any = false, all = true, seen = false
        for arg in a {
            var err: ExcelError? = nil
            _each(arg, c, direct: { v in
                switch CalcEngine.toBool(v) {
                case .success(let b): seen = true; any = any || b; all = all && b
                case .failure(let e): err = e
                }
            }, inRange: { v in
                if let e = v.error { err = e; return }
                if case .bool(let b) = v { seen = true; any = any || b; all = all && b }
                else if let n = v.number { seen = true; any = any || n != 0; all = all && n != 0 }
            })
            if let err { return .error(err) }
        }
        guard seen else { return .error(.value) }
        return .scalar(.bool(and ? all : any))
    }

    static func _text1(_ a: [FormulaExpr], _ c: EvalContext, _ f: (String) -> EvalValue) -> EvalValue {
        guard a.count == 1 else { return .error(.value) }
        switch _t(a[0], c) { case .success(let s): return f(s); case .failure(let e): return .error(e) }
    }

    static func _textN(_ a: [FormulaExpr], _ c: EvalContext, defaultN: Int, _ f: (String, Int) -> String) -> EvalValue {
        guard a.count == 1 || a.count == 2, case .success(let s) = _t(a[0], c) else { return .error(.value) }
        var n = defaultN
        if a.count == 2 { guard case .success(let x) = _n(a[1], c), x >= 0 else { return .error(.value) }; n = Int(x) }
        return .scalar(.text(f(s, n)))
    }

    static func _concat(_ args: [FormulaExpr], _ c: EvalContext, separator: String, skipEmpty: Bool) -> EvalValue {
        var parts: [String] = []
        for arg in args {
            var err: ExcelError? = nil
            let add: (CellValue) -> Void = { v in
                switch CalcEngine.toText(v) {
                case .success(let s): if !(skipEmpty && s.isEmpty) { parts.append(s) }
                case .failure(let e): err = e
                }
            }
            _each(arg, c, direct: add, inRange: add)
            if let err { return .error(err) }
        }
        return .scalar(.text(parts.joined(separator: separator)))
    }

    static func _find(_ a: [FormulaExpr], _ c: EvalContext, caseSensitive: Bool) -> EvalValue {
        guard a.count >= 2, case .success(let needle) = _t(a[0], c), case .success(let hay) = _t(a[1], c) else { return .error(.value) }
        var start = 1
        if a.count >= 3 { guard case .success(let s) = _n(a[2], c), s >= 1 else { return .error(.value) }; start = Int(s) }
        let h = Array(caseSensitive ? hay : hay.lowercased())
        let n = Array(caseSensitive ? needle : needle.lowercased())
        guard start - 1 <= h.count else { return .error(.value) }
        if n.isEmpty { return .number(Double(start)) }
        if !caseSensitive && (n.contains("*") || n.contains("?")) {
            for i in (start - 1) ..< h.count where _globMatchPrefix(Array(h[i...]), n) { return .number(Double(i + 1)) }
            return .error(.value)
        }
        guard h.count >= n.count else { return .error(.value) }
        var i = start - 1
        while i + n.count <= h.count {
            if Array(h[i ..< i + n.count]) == n { return .number(Double(i + 1)) }
            i += 1
        }
        return .error(.value)
    }

    static func _date1(_ a: [FormulaExpr], _ c: EvalContext, _ f: (Int, Int, Int) -> Double) -> EvalValue {
        guard a.count == 1, case .success(let s) = _n(a[0], c) else { return .error(.value) }
        guard s >= 0 else { return .error(.num) }
        let (y, m, d) = ExcelDate.ymd(s)
        return .number(f(y, m, d))
    }

    // MARK: Criteria

    /// A SUMIF/COUNTIF criterion: "5", ">5", "<>x", "a*", or a value.
    struct Criterion {
        let op: BinaryOp
        let value: CellValue
        let glob: [Character]?

        init(_ v: CellValue) {
            guard case .text(let s) = v else { op = .eq; value = v; glob = nil; return }
            var rest = Substring(s)
            var o = BinaryOp.eq
            for p in ["<=", ">=", "<>", "<", ">", "="] where rest.hasPrefix(p) {
                o = BinaryOp(rawValue: p)!; rest = rest.dropFirst(p.count); break
            }
            op = o
            let text = String(rest)
            if let n = InputParser.number(text) { value = .number(n.value); glob = nil }
            else if text.uppercased() == "TRUE" { value = .bool(true); glob = nil }
            else if text.uppercased() == "FALSE" { value = .bool(false); glob = nil }
            else {
                value = text.isEmpty ? .empty : .text(text)
                glob = (o == .eq || o == .ne) && (text.contains("*") || text.contains("?") || text.contains("~"))
                    ? Array(text.lowercased()) : nil
            }
        }

        func matches(_ cell: CellValue) -> Bool {
            if let glob {
                let hit: Bool
                if case .text(let s) = cell { hit = SheetFunctions._globMatch(Array(s.lowercased()), glob) } else { hit = false }
                return op == .eq ? hit : !hit
            }
            // "" or "=" matches blanks; "<>" matches non-blanks.
            if value.isEmpty {
                let blank = cell.isEmpty || cell == .text("")
                return op == .ne ? !blank : (op == .eq ? blank : false)
            }
            // A number criterion only matches numbers, text only text.
            switch (value, cell) {
            case (.number, .number), (.text, .text), (.bool, .bool): break
            default: return op == .ne
            }
            let c = CalcEngine.compare(cell, value)
            switch op {
            case .eq: return c == 0
            case .ne: return c != 0
            case .lt: return c < 0
            case .gt: return c > 0
            case .le: return c <= 0
            case .ge: return c >= 0
            default: return false
            }
        }
    }

    static func _globMatch(_ s: [Character], _ p: [Character]) -> Bool {
        var si = 0, pi = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "~", pi + 1 < p.count, p[pi + 1] == s[si] { si += 1; pi += 2; continue }
            if pi < p.count, p[pi] == "?" || (p[pi] == s[si] && p[pi] != "*") { si += 1; pi += 1; continue }
            if pi < p.count, p[pi] == "*" { star = pi; mark = si; pi += 1; continue }
            if star >= 0 { pi = star + 1; mark += 1; si = mark; continue }
            return false
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    static func _globMatchPrefix(_ s: [Character], _ p: [Character]) -> Bool {
        _globMatch(s, p + ["*"])
    }

    static func _wildcard(_ key: CellValue, _ v: CellValue) -> Bool {
        guard case .text(let k) = key else { return CalcEngine.compare(key, v) == 0 }
        guard case .text(let s) = v else { return false }
        return _globMatch(Array(s.lowercased()), Array(k.lowercased()))
    }

    /// SUMIFS and friends: the cells of `target` (or of the first range)
    /// whose rows meet every criterion.
    static func _conditional(ranges: [FormulaExpr], criteria: [FormulaExpr], target: FormulaExpr?,
                             _ c: EvalContext, _ f: ([Double]) -> Double?) -> EvalValue {
        var areas: [(Int, CellRange)] = []
        for r in ranges {
            guard case .range(let s, let rg) = c.engine.evaluate(r, c) else {
                // A single-cell reference evaluates to its value; rebuild it.
                if case .ref(let fr) = r, fr.isCell {
                    let sheet = fr.sheet.flatMap { c.engine.book.sheet(named: $0) } ?? c.sheet
                    areas.append((sheet, fr.range)); continue
                }
                return .error(.value)
            }
            areas.append((s, rg))
        }
        guard let first = areas.first else { return .error(.value) }
        let crits = criteria.map { Criterion(c.engine.scalar(c.engine.evaluate($0, c), c)) }
        var targetArea: (Int, CellRange)? = nil
        if let target {
            switch c.engine.evaluate(target, c) {
            case .range(let s, let rg): targetArea = (s, rg)
            default:
                if case .ref(let fr) = target, fr.isCell {
                    targetArea = (fr.sheet.flatMap { c.engine.book.sheet(named: $0) } ?? c.sheet, fr.range)
                } else { return .error(.value) }
            }
        }
        // Rows and columns beyond the data cannot match a non-blank criterion;
        // clip whole columns to the used area.
        let used = c.engine.usedExtent(first.0)
        let rows = min(first.1.rows, max(0, used.row - first.1.top + 1))
        let cols = min(first.1.cols, max(0, used.col - first.1.left + 1))
        var xs: [Double] = []
        var count = 0
        // Each area's cells once (shared with every other formula reading
        // the same range this pass), then the criteria over plain arrays.
        let r = max(rows, 0), cc = max(cols, 0)
        if r > 0 && cc > 0 {
            func block(_ area: (Int, CellRange)) -> [CellValue] {
                let rg = CellRange(top: area.1.top, left: area.1.left, bottom: area.1.top + r - 1, right: area.1.left + cc - 1)
                guard rg.bottom < CellAddress.maxRows, rg.right < CellAddress.maxCols else { return [] }
                return c.engine.rangeValues(area.0, rg)
            }
            let blocks = areas.map(block)
            let targetBlock = targetArea.map(block)
            for i in 0 ..< r * cc {
                var ok = true
                for k in 0 ..< blocks.count where !crits[k].matches(i < blocks[k].count ? blocks[k][i] : .empty) { ok = false; break }
                guard ok else { continue }
                count += 1
                if let t = targetBlock, i < t.count, let n = t[i].number { xs.append(n) }
            }
        }
        // Cells past the used area are blank: they count when every
        // criterion accepts a blank (COUNTIF(D:D,"") counts the column).
        if target == nil, crits.allSatisfy({ $0.matches(.empty) }) {
            count += first.1.rows * first.1.cols - max(rows, 0) * max(cols, 0)
        }
        if target == nil { return .number(Double(count)) }
        guard let r = f(xs) else { return .error(.div0) }
        return .number(r)
    }

    // MARK: Lookup

    static func _match(_ key: CellValue, _ list: [CellValue], mode: Int) -> Int? {
        switch mode {
        case 0: return list.firstIndex { _wildcard(key, $0) && !$0.isEmpty }
        case -1: return _approx(key, list, smaller: false, sortedDescending: true)
        default: return _approx(key, list, smaller: true)
        }
    }

    /// The largest value ≤ key (smaller) or smallest ≥ key, in a list
    /// sorted the way Excel assumes; exact matches win.
    static func _approx(_ key: CellValue, _ list: [CellValue], smaller: Bool, sortedDescending: Bool = false) -> Int? {
        var best: Int? = nil
        for (i, v) in list.enumerated() where !v.isEmpty && v.error == nil {
            let c = CalcEngine.compare(v, key)
            if c == 0 { return i }
            if smaller && c < 0 {
                if best == nil || CalcEngine.compare(v, list[best!]) > 0 { best = i }
            } else if !smaller && c > 0 {
                if best == nil || CalcEngine.compare(v, list[best!]) < 0 { best = i }
            }
            if sortedDescending && c < 0 { break }
        }
        return best
    }

    static func _hvlookup(_ a: [FormulaExpr], _ c: EvalContext, vertical: Bool) -> EvalValue {
        guard a.count >= 3 else { return .error(.value) }
        let key = c.engine.scalar(c.engine.evaluate(a[0], c), c)
        if let e = key.error { return .error(e) }
        var g = c.engine.grid(c.engine.evaluate(a[1], c), c)
        if !vertical {
            // Transpose so the code below reads rows.
            let cols = g.first?.count ?? 0
            g = (0 ..< cols).map { col in g.map { $0[col] } }
        }
        guard case .success(let idx) = _n(a[2], c) else { return .error(.value) }
        let k = Int(idx)
        guard k >= 1 else { return .error(.value) }
        var exact = false
        if a.count >= 4, a[3] != .missing {
            switch CalcEngine.toBool(c.engine.scalar(c.engine.evaluate(a[3], c), c)) {
            case .success(let b): exact = !b
            case .failure(let e): return .error(e)
            }
        }
        let keys = g.map { $0.first ?? .empty }
        let found = exact ? keys.firstIndex { _wildcard(key, $0) && !$0.isEmpty } : _approx(key, keys, smaller: true)
        guard let i = found else { return .error(.na) }
        guard k <= g[i].count else { return .error(.ref) }
        return .scalar(g[i][k - 1])
    }
}

extension CellValue {
    var isText: Bool { if case .text = self { return true }; return false }
}

extension EvalValue {
    /// A 1/0 number result as TRUE/FALSE (ISEVEN, ISODD).
    var asBool: EvalValue {
        if case .scalar(.number(let n)) = self { return .scalar(.bool(n != 0)) }
        return self
    }

    func map(_ f: (Double) -> EvalValue) -> EvalValue {
        if case .scalar(.number(let n)) = self { return f(n) }
        return self
    }
}
