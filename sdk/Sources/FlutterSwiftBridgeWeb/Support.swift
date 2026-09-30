// Crossing into skwasm's memory. Shared by every class in this module.
import CSkwasm

/// Scratch space on skwasm's stack for arguments it takes by pointer. The
/// counterpart of `withStackScope` in Flutter's skwasm_impl.
public struct SkStack {
    private let saved = skwasm_stack_save()

    public func alloc(_ byteCount: Int) -> sk_ptr {
        skwasm_stack_alloc(UInt32(byteCount))
    }

    /// Copies `count` elements starting at `source` (an address in OUR
    /// memory) onto skwasm's stack.
    public func copy<T>(_ source: UnsafePointer<T>?, count: Int) -> sk_ptr {
        guard let source, count > 0 else { return 0 }
        let bytes = count * MemoryLayout<T>.stride
        let p = alloc(bytes)
        starling_host_write(p, source, UInt32(bytes))
        return p
    }

    public func array<T>(_ values: [T]) -> sk_ptr {
        values.withUnsafeBufferPointer { copy($0.baseAddress, count: $0.count) }
    }

    public func floats(_ values: [Float]) -> sk_ptr { array(values) }
    public func pointers(_ values: [sk_ptr]) -> sk_ptr { array(values) }

    public func rect(_ l: Float, _ t: Float, _ r: Float, _ b: Float) -> sk_ptr {
        array([l, t, r, b])
    }

    /// Reads `count` elements back out of skwasm's memory.
    public func read<T>(_ source: sk_ptr, count: Int, as: T.Type = T.self) -> [T] {
        skRead(source, count: count)
    }

    public func restore() { skwasm_stack_restore(saved) }
}

public func withSkStack<T>(_ body: (SkStack) -> T) -> T {
    let stack = SkStack()
    defer { stack.restore() }
    return body(stack)
}

/// Reads `count` values of a trivial type from skwasm's memory.
public func skRead<T>(_ source: sk_ptr, count: Int) -> [T] {
    guard source != 0, count > 0 else { return [] }
    return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
        starling_host_read(
            buffer.baseAddress, source, UInt32(count * MemoryLayout<T>.stride))
        initialized = count
    }
}

/// Writes `count` elements at `source` (OUR memory) to `destination` (skwasm's).
public func skWrite<T>(_ destination: sk_ptr, _ source: UnsafePointer<T>?, count: Int) {
    guard let source, destination != 0, count > 0 else { return }
    starling_host_write(destination, source, UInt32(count * MemoryLayout<T>.stride))
}

/// An SkString holding `text` as UTF-8. The caller frees it (skString_free).
public func makeSkString(_ text: String) -> sk_ptr {
    let utf8 = Array(text.utf8)
    let s = skString_allocate(UInt32(utf8.count))
    utf8.withUnsafeBufferPointer { skWrite(skString_getData(s), $0.baseAddress, count: $0.count) }
    return s
}

/// A std::u16string holding `text`. The caller frees it (skString16_free).
public func makeSkString16(_ text: String) -> sk_ptr {
    let utf16 = Array(text.utf16)
    let s = skString16_allocate(UInt32(utf16.count))
    utf16.withUnsafeBufferPointer {
        skWrite(skString16_getData(s), $0.baseAddress, count: $0.count)
    }
    return s
}

// MARK: - Handles that travel as `const void*`

// Several bridge methods hand an object to another as a bare `const void*`
// (GetShaderPtr, GetFilterPtr, GetDisplayListPtr → the canvas). Natively that
// is a real address. Here it is an sk_ptr wearing a pointer's type: the bits
// are the handle, and it must never be dereferenced — only unwrapped again
// with `skHandle(from:)`.

public func skOpaque(_ handle: sk_ptr) -> UnsafeRawPointer? {
    UnsafeRawPointer(bitPattern: UInt(handle))
}

public func skHandle(from pointer: UnsafeRawPointer?) -> sk_ptr {
    guard let pointer else { return 0 }
    return sk_ptr(UInt(bitPattern: pointer))
}
