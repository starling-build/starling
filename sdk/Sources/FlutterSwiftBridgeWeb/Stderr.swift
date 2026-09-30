// Standard error without Foundation's FileHandle, which on this target
// brings the legacy Foundation module along. fd 2 is the page's
// console.error (web/host/starling.js).
import CSkwasm
import WASILibc

public func webWriteStandardError(_ bytes: UnsafeRawBufferPointer) {
    var offset = 0
    while offset < bytes.count {
        let n = write(2, bytes.baseAddress! + offset, bytes.count - offset)
        if n <= 0 { return }
        offset += n
    }
}

public func webWriteStandardError(_ text: String) {
    var text = text
    text.withUTF8 { webWriteStandardError(UnsafeRawBufferPointer($0)) }
}
