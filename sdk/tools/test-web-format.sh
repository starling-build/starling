#!/usr/bin/env bash
# Checks the web build's printf (Sources/FlutterSwiftBridgeWeb/Format.swift)
# against Foundation's String(format:), natively, on every specifier the
# framework uses (docs/plans/wasm-size.md, phase 1). Run on any change to
# that file:
#
#   sdk/tools/test-web-format.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
let cases: [(String, [CVarArg])] = [
    ("%.1f", [0.05]), ("%.1f", [0.15]), ("%.1f", [0.25]), ("%.1f", [2.675]), ("%.1f", [-0.04]),
    ("%.1f", [123456.789]), ("%.1f", [-3.0]), ("%.1f", [Float(1.25)]), ("%.1f", [Double.nan]),
    ("%.1f", [Double.infinity]), ("%.2f", [1.005]), ("%.2f", [99.995]), ("%.3f", [0.0005]),
    ("%.4f", [3.14159265]), ("%.6f", [1.0 / 3.0]), ("%.0f", [0.5]), ("%.0f", [1.5]), ("%.0f", [2.5]),
    ("%02X", [15]), ("%02X", [255]), ("%02X", [UInt8(7)]), ("%08X", [0xDEADBEEF as UInt32]),
    ("%05X", [0xABC]), ("%05x", [0xABC]), ("%04X", [1]),
    ("%02d", [5]), ("%02d", [-5]), ("%02d", [123]), ("%d", [Int32(-7)]),
    ("%5d", [42]), ("%-5d|", [42]), ("%+d", [42]), ("% d", [42]),
    ("%g", [0.0001]), ("%g", [100000.0]), ("%g", [1000000.0]), ("%g", [0.00001]), ("%g", [123.456]),
    ("%.3g", [3.14159]), ("%.3g", [0.000123456]), ("%.3g", [1234.5]), ("%.3g", [0.0]), ("%g", [1.0]),
    ("%e", [12345.678]), ("%.2e", [0.000123]), ("%e", [0.0]),
    ("%%", []), ("%d%%", [50]), ("%.1f%%", [99.5]),
    // Not compared: %d and %x read their argument as a C int, 32 bits, so
    // Foundation prints Int64.max as -1 and -1 as ffffffff. Ours prints the
    // value. No framework site formats a 64-bit value or a negative in hex.
    ("a %d b %.2f c", [1, 2.5]), ("%@", ["x"]), ("%.1f %@", [2.5, "MB"]),
]
var failures = 0
for (format, args) in cases {
    let expected = String(format: format, arguments: args)
    let got = webFormat(format, args)
    if expected != got {
        failures += 1
        print("FAIL \(format) \(args): foundation=\(expected) web=\(got)")
    }
}
print(failures == 0 ? "ok: \(cases.count) formats agree" : "\(failures) of \(cases.count) differ")
exit(failures == 0 ? 0 : 1)
SWIFT
swiftc -O -o "$TMP/t" "$HERE/Sources/FlutterSwiftBridgeWeb/Format.swift" "$TMP/main.swift" 2>&1 | grep -E "error" && exit 1
"$TMP/t"
