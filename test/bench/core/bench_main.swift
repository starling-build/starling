// Offline throughput of the Swift emulator core: feed a captured byte stream
// through TerminalEmulator with NO rendering, no Flutter, no compositor.
// Isolates parse + grid-write cost, which is what a C++ core would replace.
import Foundation

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
                                           : "/var/tmp/bench/doomstream.bin"
let reps = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 3
let chunkSize = 65536      // matches the PTY read buffer the app uses

guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("cannot read \(path)\n".utf8)); exit(1)
}
let bytes = [UInt8](data)
print("stream \(bytes.count / 1_000_000) MB, chunk \(chunkSize), grid 47x201")

for r in 1...reps {
    let em = TerminalEmulator(cols: 201, rows: 47)
    var i = 0
    let t0 = DispatchTime.now().uptimeNanoseconds
    while i < bytes.count {
        let end = min(i + chunkSize, bytes.count)
        em.feed(Array(bytes[i..<end]))
        i = end
    }
    let t1 = DispatchTime.now().uptimeNanoseconds
    let secs = Double(t1 - t0) / 1e9
    let mbs = Double(bytes.count) / 1e6 / secs
    print(String(format: "run %d  %.3f s  %.1f MB/s  cellwrites %llu", r, secs, mbs, BENCH_CELL_WRITES))
    BENCH_CELL_WRITES = 0
}
