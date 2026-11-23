import Foundation

/// What a BIFF8 formula's tokens refer to: the EXTERNSHEET table, sheet names and defined names.
struct XlsFormulaContext {
    /// (first sheet index, SUPBOOK index) per EXTERNSHEET entry.
    var xtis: [(Int, Int)] = []
    var internalBooks: Set<Int> = []
    var sheetNames: [String] = []
    var names: [String] = []
}

/// Turns a BIFF8 formula (reverse Polish tokens) back into the text Excel shows.
/// Returns nil for anything it cannot render faithfully, so the cell keeps its cached value.
enum XlsFormula {
    /// id -> (name, argument count of the fixed-count token; -1 where the function is only written with a count)
    static let functions: [Int: (String, Int)] = [
        0: ("COUNT", -1), 1: ("IF", -1), 2: ("ISNA", 1), 3: ("ISERROR", 1), 4: ("SUM", -1), 5: ("AVERAGE", -1), 6: ("MIN", -1), 7: ("MAX", -1),
        8: ("ROW", -1), 9: ("COLUMN", -1), 10: ("NA", 0), 11: ("NPV", -1), 12: ("STDEV", -1), 13: ("DOLLAR", -1), 14: ("FIXED", -1),
        15: ("SIN", 1), 16: ("COS", 1), 17: ("TAN", 1), 18: ("ATAN", 1), 19: ("PI", 0), 20: ("SQRT", 1), 21: ("EXP", 1), 22: ("LN", 1),
        23: ("LOG10", 1), 24: ("ABS", 1), 25: ("INT", 1), 26: ("SIGN", 1), 27: ("ROUND", 2), 28: ("LOOKUP", -1), 29: ("INDEX", -1),
        30: ("REPT", 2), 31: ("MID", 3), 32: ("LEN", 1), 33: ("VALUE", 1), 34: ("TRUE", 0), 35: ("FALSE", 0), 36: ("AND", -1), 37: ("OR", -1),
        38: ("NOT", 1), 39: ("MOD", 2), 40: ("DCOUNT", 3), 41: ("DSUM", 3), 42: ("DAVERAGE", 3), 43: ("DMIN", 3), 44: ("DMAX", 3),
        45: ("DSTDEV", 3), 46: ("VAR", -1), 47: ("DVAR", 3), 48: ("TEXT", 2), 49: ("LINEST", -1), 50: ("TREND", -1), 51: ("LOGEST", -1),
        52: ("GROWTH", -1), 56: ("PV", -1), 57: ("FV", -1), 58: ("NPER", -1), 59: ("PMT", -1), 60: ("RATE", -1), 61: ("MIRR", 3),
        62: ("IRR", -1), 63: ("RAND", 0), 64: ("MATCH", -1), 65: ("DATE", 3), 66: ("TIME", 3), 67: ("DAY", 1), 68: ("MONTH", 1),
        69: ("YEAR", 1), 70: ("WEEKDAY", -1), 71: ("HOUR", 1), 72: ("MINUTE", 1), 73: ("SECOND", 1), 74: ("NOW", 0), 75: ("AREAS", 1),
        76: ("ROWS", 1), 77: ("COLUMNS", 1), 78: ("OFFSET", -1), 82: ("SEARCH", -1), 83: ("TRANSPOSE", 1), 86: ("TYPE", 1),
        97: ("ATAN2", 2), 98: ("ASIN", 1), 99: ("ACOS", 1), 100: ("CHOOSE", -1), 101: ("HLOOKUP", -1), 102: ("VLOOKUP", -1),
        105: ("ISREF", 1), 109: ("LOG", -1), 111: ("CHAR", 1), 112: ("LOWER", 1), 113: ("UPPER", 1), 114: ("PROPER", 1), 115: ("LEFT", -1),
        116: ("RIGHT", -1), 117: ("EXACT", 2), 118: ("TRIM", 1), 119: ("REPLACE", 4), 120: ("SUBSTITUTE", -1), 121: ("CODE", 1),
        124: ("FIND", -1), 125: ("CELL", -1), 126: ("ISERR", 1), 127: ("ISTEXT", 1), 128: ("ISNUMBER", 1), 129: ("ISBLANK", 1),
        130: ("T", 1), 131: ("N", 1), 140: ("DATEVALUE", 1), 141: ("TIMEVALUE", 1), 142: ("SLN", 3), 143: ("SYD", 4), 144: ("DDB", -1),
        148: ("INDIRECT", -1), 162: ("CLEAN", 1), 163: ("MDETERM", 1), 164: ("MINVERSE", 1), 165: ("MMULT", 2), 167: ("IPMT", -1),
        168: ("PPMT", -1), 169: ("COUNTA", -1), 183: ("PRODUCT", -1), 184: ("FACT", 1), 189: ("DPRODUCT", 3), 190: ("ISNONTEXT", 1),
        193: ("STDEVP", -1), 194: ("VARP", -1), 195: ("DSTDEVP", 3), 196: ("DVARP", 3), 197: ("TRUNC", -1), 198: ("ISLOGICAL", 1),
        199: ("DCOUNTA", 3), 212: ("ROUNDUP", 2), 213: ("ROUNDDOWN", 2), 216: ("RANK", -1), 219: ("ADDRESS", -1), 220: ("DAYS360", -1),
        221: ("TODAY", 0), 222: ("VDB", -1), 227: ("MEDIAN", -1), 228: ("SUMPRODUCT", -1), 229: ("SINH", 1), 230: ("COSH", 1),
        231: ("TANH", 1), 232: ("ASINH", 1), 233: ("ACOSH", 1), 234: ("ATANH", 1), 235: ("DGET", 3), 244: ("INFO", 1), 247: ("DB", -1),
        252: ("FREQUENCY", 2), 261: ("ERROR.TYPE", 1), 269: ("AVEDEV", -1), 270: ("BETADIST", -1), 271: ("GAMMALN", 1),
        272: ("BETAINV", -1), 273: ("BINOMDIST", 4), 274: ("CHIDIST", 2), 275: ("CHIINV", 2), 276: ("COMBIN", 2), 277: ("CONFIDENCE", 3),
        278: ("CRITBINOM", 3), 279: ("EVEN", 1), 280: ("EXPONDIST", 3), 281: ("FDIST", 3), 282: ("FINV", 3), 283: ("FISHER", 1),
        284: ("FISHERINV", 1), 285: ("FLOOR", 2), 286: ("GAMMADIST", 4), 287: ("GAMMAINV", 3), 288: ("CEILING", 2), 289: ("HYPGEOMDIST", 4),
        290: ("LOGNORMDIST", 3), 291: ("LOGINV", 3), 292: ("NEGBINOMDIST", 3), 293: ("NORMDIST", 4), 294: ("NORMSDIST", 1),
        295: ("NORMINV", 3), 296: ("NORMSINV", 1), 297: ("STANDARDIZE", 3), 298: ("ODD", 1), 299: ("PERMUT", 2), 300: ("POISSON", 3),
        301: ("TDIST", 3), 302: ("WEIBULL", 4), 303: ("SUMXMY2", 2), 304: ("SUMX2MY2", 2), 305: ("SUMX2PY2", 2), 306: ("CHITEST", 2),
        307: ("CORREL", 2), 308: ("COVAR", 2), 309: ("FORECAST", 3), 310: ("FTEST", 2), 311: ("INTERCEPT", 2), 312: ("PEARSON", 2),
        313: ("RSQ", 2), 314: ("STEYX", 2), 315: ("SLOPE", 2), 316: ("TTEST", 4), 317: ("PROB", -1), 318: ("DEVSQ", -1),
        319: ("GEOMEAN", -1), 320: ("HARMEAN", -1), 321: ("SUMSQ", -1), 322: ("KURT", -1), 323: ("SKEW", -1), 324: ("ZTEST", -1),
        325: ("LARGE", 2), 326: ("SMALL", 2), 327: ("QUARTILE", 2), 328: ("PERCENTILE", 2), 329: ("PERCENTRANK", -1), 330: ("MODE", -1),
        331: ("TRIMMEAN", 2), 332: ("TINV", 2), 336: ("CONCATENATE", -1), 337: ("POWER", 2), 342: ("RADIANS", 1), 343: ("DEGREES", 1),
        344: ("SUBTOTAL", -1), 345: ("SUMIF", -1), 346: ("COUNTIF", 2), 347: ("COUNTBLANK", 1), 350: ("ISPMT", 4), 351: ("DATEDIF", 3),
        359: ("HYPERLINK", -1), 361: ("AVERAGEA", -1), 362: ("MAXA", -1), 363: ("MINA", -1), 364: ("STDEVPA", -1), 365: ("VARPA", -1),
        366: ("STDEVA", -1), 367: ("VARA", -1),
    ]

    private static func u16(_ t: [UInt8], _ k: Int) -> Int { k + 1 < t.count ? Int(t[k]) | Int(t[k + 1]) << 8 : 0 }

    /// `relative`: the tokens belong to a shared formula or a name, where relative references are offsets from the cell.
    static func decompile(_ t: [UInt8], row: Int, col: Int, relative: Bool, ctx: XlsFormulaContext) -> String? {
        var st: [String] = []
        var i = 0
        func pop() -> String? { st.popLast() }

        func cell(_ r: Int, _ cf: Int, _ off: Bool) -> String {
            var rr = r, cc = cf & 0xFF
            let rowRel = cf & 0x8000 != 0, colRel = cf & 0x4000 != 0
            if off {
                if rowRel { rr = (row + Int(Int16(truncatingIfNeeded: r))) & 0xFFFF }
                if colRel { cc = (col + Int(Int8(truncatingIfNeeded: cf & 0xFF))) & 0xFF }
            }
            return (colRel ? "" : "$") + XlsBuild.colName(cc) + (rowRel ? "" : "$") + String(rr + 1)
        }
        func area(_ r1: Int, _ r2: Int, _ c1: Int, _ c2: Int, _ off: Bool) -> String {
            let wholeCols = r1 == 0 && r2 == 0xFFFF, wholeRows = c1 & 0xFF == 0 && c2 & 0xFF == 0xFF && !off
            if wholeCols && !off {
                return (c1 & 0x4000 != 0 ? "" : "$") + XlsBuild.colName(c1 & 0xFF) + ":" + (c2 & 0x4000 != 0 ? "" : "$") + XlsBuild.colName(c2 & 0xFF)
            }
            if wholeRows {
                return (r1 >= 0 && c1 & 0x8000 != 0 ? "" : "$") + String(r1 + 1) + ":" + (c2 & 0x8000 != 0 ? "" : "$") + String(r2 + 1)
            }
            return cell(r1, c1, off) + ":" + cell(r2, c2, off)
        }
        func sheet(_ ixti: Int) -> String? {
            guard ixti < ctx.xtis.count else { return nil }
            let (n, sup) = ctx.xtis[ixti]
            guard ctx.internalBooks.contains(sup), n < ctx.sheetNames.count else { return nil }
            return XlsBuild.quotedSheet(ctx.sheetNames[n]) + "!"
        }
        func binary(_ op: String) -> Bool {
            guard let b = pop(), let a = pop() else { return false }
            st.append(a + op + b)
            return true
        }
        while i < t.count {
            let raw = Int(t[i])
            let id = raw >= 0x20 ? (raw & 0x1F) | 0x20 : raw
            switch id {
            case 0x03: guard binary("+") else { return nil }; i += 1
            case 0x04: guard binary("-") else { return nil }; i += 1
            case 0x05: guard binary("*") else { return nil }; i += 1
            case 0x06: guard binary("/") else { return nil }; i += 1
            case 0x07: guard binary("^") else { return nil }; i += 1
            case 0x08: guard binary("&") else { return nil }; i += 1
            case 0x09: guard binary("<") else { return nil }; i += 1
            case 0x0A: guard binary("<=") else { return nil }; i += 1
            case 0x0B: guard binary("=") else { return nil }; i += 1
            case 0x0C: guard binary(">=") else { return nil }; i += 1
            case 0x0D: guard binary(">") else { return nil }; i += 1
            case 0x0E: guard binary("<>") else { return nil }; i += 1
            case 0x0F: guard binary(" ") else { return nil }; i += 1
            case 0x10: guard binary(",") else { return nil }; i += 1
            case 0x11: guard binary(":") else { return nil }; i += 1
            case 0x12: guard let a = pop() else { return nil }; st.append("+" + a); i += 1
            case 0x13: guard let a = pop() else { return nil }; st.append("-" + a); i += 1
            case 0x14: guard let a = pop() else { return nil }; st.append(a + "%"); i += 1
            case 0x15: guard let a = pop() else { return nil }; st.append("(" + a + ")"); i += 1
            case 0x16: st.append(""); i += 1
            case 0x17:
                guard i + 2 <= t.count else { return nil }
                let n = Int(t[i + 1]), wide = i + 2 < t.count && t[i + 2] & 1 == 1
                let width = wide ? 2 * n : n
                guard i + 3 + width <= t.count else { return nil }
                var s = ""
                if wide {
                    var u: [UInt16] = []
                    for k in 0 ..< n { u.append(UInt16(t[i + 3 + 2 * k]) | UInt16(t[i + 4 + 2 * k]) << 8) }
                    s = String(decoding: u, as: UTF16.self)
                } else {
                    var u = String.UnicodeScalarView()
                    for k in 0 ..< n { u.append(Unicode.Scalar(t[i + 3 + k])) }
                    s = String(u)
                }
                st.append("\"" + s.split(separator: "\"", omittingEmptySubsequences: false).joined(separator: "\"\"") + "\"")
                i += 3 + width
            case 0x19:
                guard i + 4 <= t.count else { return nil }
                let g = Int(t[i + 1]), data = u16(t, i + 2)
                if g & 0x04 != 0 { i += 4 + 2 * (data + 1) }
                else if g & 0x10 != 0 { guard let a = pop() else { return nil }; st.append("SUM(" + a + ")"); i += 4 }
                else { i += 4 }
            case 0x1C: guard i + 2 <= t.count else { return nil }; st.append(XlsBuild.errorText(Int(t[i + 1]))); i += 2
            case 0x1D: guard i + 2 <= t.count else { return nil }; st.append(t[i + 1] == 0 ? "FALSE" : "TRUE"); i += 2
            case 0x1E: guard i + 3 <= t.count else { return nil }; st.append(String(u16(t, i + 1))); i += 3
            case 0x1F:
                guard i + 9 <= t.count else { return nil }
                var b: UInt64 = 0
                for k in 0 ..< 8 { b |= UInt64(t[i + 1 + k]) << UInt64(8 * k) }
                let d = Double(bitPattern: b)
                guard d.isFinite else { return nil }
                st.append(XlsBuild.num(d)); i += 9
            case 0x21, 0x22:
                var name: String, n: Int, len: Int
                if id == 0x21 {
                    guard i + 3 <= t.count, let f = functions[u16(t, i + 1)], f.1 >= 0 else { return nil }
                    name = f.0; n = f.1; len = 3
                } else {
                    guard i + 4 <= t.count, let f = functions[u16(t, i + 2)] else { return nil }
                    name = f.0; n = Int(t[i + 1]) & 0x7F; len = 4
                }
                guard st.count >= n else { return nil }
                let args = Array(st.suffix(n)); st.removeLast(n)
                st.append(name + "(" + args.joined(separator: ",") + ")")
                i += len
            case 0x23:
                guard i + 5 <= t.count else { return nil }
                let k = u16(t, i + 1)
                guard k >= 1, k <= ctx.names.count, !ctx.names[k - 1].isEmpty else { return nil }
                st.append(ctx.names[k - 1]); i += 5
            case 0x24, 0x2C:
                guard i + 5 <= t.count else { return nil }
                st.append(cell(u16(t, i + 1), u16(t, i + 3), id == 0x2C)); i += 5
            case 0x25, 0x2D:
                guard i + 9 <= t.count else { return nil }
                st.append(area(u16(t, i + 1), u16(t, i + 3), u16(t, i + 5), u16(t, i + 7), id == 0x2D)); i += 9
            case 0x26, 0x29: i += id == 0x26 ? 7 : 3   // the tokens of the sub-expression follow
            case 0x27, 0x28: i += 7
            case 0x2A: st.append("#REF!"); i += 5
            case 0x2B: st.append("#REF!"); i += 9
            case 0x3A:
                guard i + 7 <= t.count, let p = sheet(u16(t, i + 1)) else { return nil }
                st.append(p + cell(u16(t, i + 3), u16(t, i + 5), relative)); i += 7
            case 0x3B:
                guard i + 11 <= t.count, let p = sheet(u16(t, i + 1)) else { return nil }
                st.append(p + area(u16(t, i + 3), u16(t, i + 5), u16(t, i + 7), u16(t, i + 9), relative)); i += 11
            case 0x3C: st.append("#REF!"); i += 7
            case 0x3D: st.append("#REF!"); i += 11
            default: return nil
            }
        }
        return st.count == 1 ? st[0] : nil
    }
}
