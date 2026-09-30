// printf-style formatting without Foundation.
//
// `String(format:)` is the framework's most common reach into the legacy
// Foundation module — forty sites, mostly `"%.1f"` — and on this target that
// module brings ICU with it, 40 MB (docs/plans/wasm-size.md). This is the
// subset of printf those sites use: `d i u`, `x X o`, `f e g`, `@`, `%`,
// with flags, width and precision. The `Flutter` and `FlutterSwiftBridge`
// modules each declare a `String(format:_:)` over it, which shadows
// Foundation's inside them, so no call site changes.
//
// Pure Swift, no imports: sdk/tools/test-web-format.sh compiles this file
// natively next to Foundation and checks the two agree.

/// Formats `arguments` by `format`. An unknown conversion is left in the
/// output as written (`%q`), so a new site stands out instead of crashing.
public func webFormat(_ format: String, _ arguments: [CVarArg]) -> String {
    var out = ""
    var args = arguments.makeIterator()
    var chars = format.makeIterator()
    var pending: Character? = nil

    func next() -> Character? {
        if let c = pending { pending = nil; return c }
        return chars.next()
    }

    while let c = next() {
        guard c == "%" else { out.append(c); continue }

        // %[flags][width][.precision]conversion
        var leftAlign = false, plus = false, space = false, zero = false, alt = false
        var width = 0
        var precision: Int? = nil
        var conversion: Character? = nil
        var spec = "%"

        flags: while let f = next() {
            spec.append(f)
            switch f {
            case "-": leftAlign = true
            case "+": plus = true
            case " ": space = true
            case "0": zero = true
            case "#": alt = true
            default: pending = f; spec.removeLast(); break flags
            }
        }
        while let d = next() {
            if let v = d.wholeNumberValue, d.isASCII { width = width * 10 + v; spec.append(d) }
            else { pending = d; break }
        }
        if let dot = next() {
            if dot == "." {
                spec.append(dot)
                var p = 0
                while let d = next() {
                    if let v = d.wholeNumberValue, d.isASCII { p = p * 10 + v; spec.append(d) }
                    else { pending = d; break }
                }
                precision = p
            } else {
                pending = dot
            }
        }
        if let k = next() { conversion = k; spec.append(k) }

        var body: String
        var negative = false
        var digitsStart = 0  // where zero padding goes: after any sign or prefix

        switch conversion {
        case "%":
            out.append("%")
            continue
        case "d", "i", "u":
            guard let v = integer(args.next()) else { out += spec; continue }
            negative = v < 0
            body = String(v.magnitude)
            if let p = precision, body.count < p { body = String(repeating: "0", count: p - body.count) + body }
        case "x", "X", "o":
            guard let v = integer(args.next()) else { out += spec; continue }
            let radix = conversion == "o" ? 8 : 16
            // Negative values print as their two's complement, as C does.
            let bits = v < 0 ? UInt64(bitPattern: Int64(v)) : UInt64(v)
            body = String(bits, radix: radix, uppercase: conversion == "X")
            if let p = precision, body.count < p { body = String(repeating: "0", count: p - body.count) + body }
            if alt, v != 0 { body = (conversion == "o" ? "0" : (conversion == "X" ? "0X" : "0x")) + body; digitsStart = 2 }
        case "f", "F":
            guard let v = double(args.next()) else { out += spec; continue }
            negative = v.sign == .minus && !v.isNaN
            body = fixed(v.magnitude, precision ?? 6, alt: alt)
        case "e", "E":
            guard let v = double(args.next()) else { out += spec; continue }
            negative = v.sign == .minus && !v.isNaN
            body = exponential(v.magnitude, precision ?? 6, alt: alt, upper: conversion == "E")
        case "g", "G":
            guard let v = double(args.next()) else { out += spec; continue }
            negative = v.sign == .minus && !v.isNaN
            body = general(v.magnitude, precision ?? 6, alt: alt, upper: conversion == "G")
        case "@", "s":
            guard let a = args.next() else { out += spec; continue }
            body = String(describing: a)
            if let p = precision { body = String(body.prefix(p)) }
            zero = false
        case "c":
            guard let v = integer(args.next()), let scalar = Unicode.Scalar(UInt32(clamping: v)) else { out += spec; continue }
            body = String(Character(scalar))
            zero = false
        default:
            out += spec
            continue
        }

        if body.hasPrefix("inf") || body.hasPrefix("nan") { zero = false }

        let sign = negative ? "-" : (plus ? "+" : (space ? " " : ""))
        let pad = width - sign.count - body.count
        if pad > 0 {
            if leftAlign {
                body = sign + body + String(repeating: " ", count: pad)
            } else if zero {
                let prefix = String(body.prefix(digitsStart))
                body = sign + prefix + String(repeating: "0", count: pad) + body.dropFirst(digitsStart)
            } else {
                body = String(repeating: " ", count: pad) + sign + body
            }
        } else {
            body = sign + body
        }
        out += body
    }
    return out
}

private func integer(_ a: CVarArg?) -> Int64? {
    switch a {
    case let v as Int: return Int64(v)
    case let v as Int64: return v
    case let v as Int32: return Int64(v)
    case let v as Int16: return Int64(v)
    case let v as Int8: return Int64(v)
    case let v as UInt: return Int64(clamping: v)
    case let v as UInt64: return Int64(clamping: v)
    case let v as UInt32: return Int64(v)
    case let v as UInt16: return Int64(v)
    case let v as UInt8: return Int64(v)
    case let v as Bool: return v ? 1 : 0
    case let v as Double: return Int64(exactly: v.rounded(.towardZero))
    case let v as Float: return Int64(exactly: Double(v).rounded(.towardZero))
    default: return nil
    }
}

private func double(_ a: CVarArg?) -> Double? {
    switch a {
    case let v as Double: return v
    case let v as Float: return Double(v)
    case let v as Int: return Double(v)
    case let v as Int64: return Double(v)
    case let v as Int32: return Double(v)
    case let v as UInt: return Double(v)
    case let v as UInt32: return Double(v)
    default: return nil
    }
}

private func nonFinite(_ v: Double) -> String? {
    if v.isNaN { return "nan" }
    if v.isInfinite { return "inf" }
    return nil
}

/// `v` (non-negative) with exactly `precision` digits after the point.
///
/// printf rounds the EXACT binary value, so `%.1f` of 0.05 is "0.1" (the
/// double is a hair above 0.05) while `%.0f` of 2.5 is "2" (an exact tie,
/// half to even). Scaling by 10^p and rounding the product would get the
/// first wrong: the product rounds to exactly 0.5. The residual of the
/// multiplication, which fma gives exactly, says which side of the tie the
/// true value is on.
private func fixed(_ v: Double, _ precision: Int, alt: Bool) -> String {
    if let s = nonFinite(v) { return s }
    let p = max(0, min(precision, 17))
    var scale = 1.0
    for _ in 0..<p { scale *= 10 }
    let product = v * scale
    let residual = (-product).addingProduct(v, scale)  // v*scale - product, exactly
    let floor = product.rounded(.down)
    let scaled: Double
    if product - floor == 0.5 {
        if residual > 0 { scaled = floor + 1 }
        else if residual < 0 { scaled = floor }
        else { scaled = product.rounded(.toNearestOrEven) }
    } else {
        scaled = product.rounded(.toNearestOrEven)
    }
    guard scaled < 9.0e18 else {
        // Beyond what an integer can carry; the shortest round-trip
        // representation is the best available without libc.
        return String(v)
    }
    let whole = UInt64(scaled)
    var digits = String(whole)
    if digits.count <= p { digits = String(repeating: "0", count: p - digits.count + 1) + digits }
    let split = digits.index(digits.endIndex, offsetBy: -p)
    let intPart = String(digits[..<split])
    let fracPart = String(digits[split...])
    if p == 0 { return alt ? intPart + "." : intPart }
    return intPart + "." + fracPart
}

private func exponential(_ v: Double, _ precision: Int, alt: Bool, upper: Bool) -> String {
    if let s = nonFinite(v) { return s }
    var exponent = 0
    var mantissa = v
    if v != 0 {
        exponent = Int(v.log10Floor)
        mantissa = v / pow10(exponent)
        // Rounding can carry the mantissa to 10.0.
        if fixed(mantissa, precision, alt: false).hasPrefix("10") {
            exponent += 1
            mantissa = v / pow10(exponent)
        }
    }
    let e = upper ? "E" : "e"
    let sign = exponent < 0 ? "-" : "+"
    let mag = exponent.magnitude < 10 ? "0\(exponent.magnitude)" : "\(exponent.magnitude)"
    return fixed(mantissa, precision, alt: alt) + e + sign + mag
}

private func general(_ v: Double, _ precision: Int, alt: Bool, upper: Bool) -> String {
    if let s = nonFinite(v) { return s }
    let p = precision == 0 ? 1 : precision
    let exponent = v == 0 ? 0 : Int(v.log10Floor)
    // C: use %e if the exponent is < -4 or >= the precision.
    var s: String
    if exponent < -4 || exponent >= p {
        s = exponential(v, p - 1, alt: alt, upper: upper)
        // Trailing zeros in the mantissa go, unless '#'.
        if !alt, let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            var m = String(s[..<e])
            if m.contains(Character(".")) {
                while m.hasSuffix("0") { m.removeLast() }
                if m.hasSuffix(".") { m.removeLast() }
            }
            s = m + s[e...]
        }
    } else {
        s = fixed(v, p - 1 - exponent, alt: alt)
        if !alt, s.contains(Character(".")) {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
    }
    return s
}

private func pow10(_ n: Int) -> Double {
    var r = 1.0
    if n >= 0 { for _ in 0..<n { r *= 10 } } else { for _ in 0..<(-n) { r /= 10 } }
    return r
}

extension Double {
    /// floor(log10(self)) for a positive finite value, without libm.
    fileprivate var log10Floor: Double {
        var e = 0
        var m = self
        if m >= 10 {
            while m >= 10 { m /= 10; e += 1 }
        } else if m < 1 {
            while m < 1 { m *= 10; e -= 1 }
        }
        return Double(e)
    }
}
