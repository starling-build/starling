// Differential harness, Swift side. Prints the identical canonical dump the C
// side prints, so `diff` decides whether the port preserved semantics.
import Foundation

var h: UInt64 = 1469598103934665603
func fnv(_ h: inout UInt64, _ bytes: [UInt8]) {
    for b in bytes { h ^= UInt64(b); h = h &* 1099511628211 }
}
func fnv32(_ h: inout UInt64, _ v: UInt32) {
    withUnsafeBytes(of: v) { raw in for b in raw { h ^= UInt64(b); h = h &* 1099511628211 } }
}
func fnv8(_ h: inout UInt64, _ v: UInt8) { h ^= UInt64(v); h = h &* 1099511628211 }

let args = CommandLine.arguments
guard args.count >= 4, let cols = Int(args[2]), let rows = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: diff_swift <stream> <cols> <rows> [chunk]\n".utf8))
    exit(2)
}
let chunk = args.count > 4 ? Int(args[4])! : 65536
guard let data = FileManager.default.contents(atPath: args[1]) else {
    FileHandle.standardError.write(Data("cannot read \(args[1])\n".utf8)); exit(1)
}
let bytes = [UInt8](data)

var rhash: UInt64 = 1469598103934665603
let em = TerminalEmulator(cols: cols, rows: rows)
em.onResponse = { s in fnv(&rhash, Array(s.utf8)) }

var i = 0
while i < bytes.count {
    let end = min(i + chunk, bytes.count)
    em.feed(Array(bytes[i..<end]))
    i = end
}

let sb = em.scrollbackCount
let all = em.scrollback + em.grid
func fit(_ line: [TermCell]) -> [TermCell] {
    if line.count == em.cols { return line }
    if line.count > em.cols { return Array(line[0..<em.cols]) }
    return line + Array(repeating: TermCell(), count: em.cols - line.count)
}
for line in all {
    for c in fit(line) {
        fnv32(&h, c.scalar); fnv32(&h, c.fg); fnv32(&h, c.bg); fnv8(&h, c.attrs.rawValue)
    }
}
print(String(format: "cols=%d rows=%d cur=%d,%d vis=%d appkeys=%d bpaste=%d sb=%d cells=%016llx resp=%016llx",
             em.cols, em.rows, em.cursorRow, em.cursorCol,
             em.cursorVisible ? 1 : 0, em.applicationCursorKeys ? 1 : 0,
             em.bracketedPaste ? 1 : 0, sb, h, rhash))
