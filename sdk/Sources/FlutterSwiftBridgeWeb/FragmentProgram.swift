// Fragment programs and shaders: runtime effects, over skwasm's
// runtimeEffect_* and shader_createRuntimeEffectShader.
import CSkwasm
import Foundation

// MARK: - Reading the shader bundle

/// What a fragment program needs from its asset: the SkSL, and how many
/// uniforms of each kind it declares.
private struct ShaderBundle {
    var sksl: [UInt8]
    var uniformFloatCount: Int
    var samplerCount: Int
}

private struct ShaderBundleError: Error {
    let message: String
}

/// Just enough of a FlatBuffers reader for impellerc's runtime stage file
/// (impeller/runtime_stage/runtime_stage_types.fbs). Every read is bounds
/// checked: the bytes are an asset, not something we produced.
private struct FlatBuffer {
    let bytes: [UInt8]

    func u16(_ at: Int) -> Int? {
        guard at >= 0, at + 2 <= bytes.count else { return nil }
        return Int(bytes[at]) | Int(bytes[at + 1]) << 8
    }

    func u32(_ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << UInt32(8 * $1) }
    }

    func u64(_ at: Int) -> UInt64? {
        guard let low = u32(at), let high = u32(at + 4) else { return nil }
        return UInt64(low) | UInt64(high) << 32
    }

    /// Follows the offset stored at `at` (tables, vectors and strings are all
    /// reached through one, relative to where it is stored).
    func indirect(_ at: Int) -> Int? {
        guard let offset = u32(at), offset <= UInt32(Int32.max) else { return nil }
        let target = at + Int(offset)
        return target < bytes.count ? target : nil
    }

    /// Where field number `index` of the table at `table` is stored, or nil
    /// when the writer left it out (it then has its default value).
    func field(_ table: Int, _ index: Int) -> Int? {
        guard let back = u32(table) else { return nil }
        let vtable = table - Int(Int32(bitPattern: back))
        guard let vtableSize = u16(vtable) else { return nil }
        let slot = 4 + 2 * index
        guard slot + 2 <= vtableSize, let offset = u16(vtable + slot), offset != 0 else {
            return nil
        }
        return table + offset
    }

    func table(_ table: Int, _ index: Int) -> Int? {
        field(table, index).flatMap(indirect)
    }

    /// A vector field: where its first element is, and how many there are.
    func vector(_ table: Int, _ index: Int, elementSize: Int) -> (start: Int, count: Int)? {
        guard let at = self.table(table, index), let count = u32(at),
              count <= UInt32(Int32.max),
              at + 4 + Int(count) * elementSize <= bytes.count
        else { return nil }
        return (at + 4, Int(count))
    }

    func scalar64(_ table: Int, _ index: Int) -> Int {
        guard let at = field(table, index), let value = u64(at) else { return 0 }
        return Int(clamping: value)
    }

    func scalar32(_ table: Int, _ index: Int) -> Int {
        guard let at = field(table, index), let value = u32(at) else { return 0 }
        return Int(clamping: value)
    }
}

/// The `.iplr` file impellerc writes: a FlatBuffer holding one runtime stage
/// per backend. Only the SkSL stage is of any use to skwasm.
private func readRuntimeStages(_ bytes: [UInt8]) throws -> ShaderBundle {
    let buffer = FlatBuffer(bytes: bytes)
    guard let root = buffer.indirect(0) else {
        throw ShaderBundleError(message: "Data does not contain any shader data.")
    }
    // RuntimeStages.sksl is field 0.
    guard let stage = buffer.table(root, 0) else {
        throw ShaderBundleError(
            message: "Data does not contain appropriate runtime stage data for "
                + "current backend (SkSL).")
    }
    // RuntimeStage: uniforms is field 3, shader is field 4.
    guard let shader = buffer.vector(stage, 4, elementSize: 1) else {
        throw ShaderBundleError(message: "Data does not contain any shader data.")
    }
    var samplerCount = 0
    var uniformBytes = 0
    if let uniforms = buffer.vector(stage, 3, elementSize: 4) {
        for i in 0..<uniforms.count {
            guard let uniform = buffer.indirect(uniforms.start + 4 * i) else { continue }
            // UniformDescription: type 3, bit_width 4, rows 5, columns 6,
            // array_elements 7, struct_layout 8. Type 1 is kSampledImage.
            if buffer.scalar32(uniform, 3) == 1 {
                samplerCount += 1
                continue
            }
            // RuntimeUniformDescription::GetSize.
            var size = buffer.scalar64(uniform, 5) &* buffer.scalar64(uniform, 6)
                &* buffer.scalar64(uniform, 4) / 8
            let arrayElements = buffer.scalar64(uniform, 7)
            if arrayElements > 0 { size = size &* arrayElements }
            if let layout = buffer.vector(uniform, 8, elementSize: 1) {
                size = size &+ 4 &* layout.count
            }
            uniformBytes = uniformBytes &+ size
        }
    }
    var sksl = Array(bytes[shader.start..<shader.start + shader.count])
    // impellerc stores the source as a C string; the terminator is not SkSL.
    while sksl.last == 0 { sksl.removeLast() }
    return ShaderBundle(
        sksl: sksl,
        uniformFloatCount: max(0, (uniformBytes &+ 3) / 4),
        samplerCount: samplerCount)
}

/// The JSON that `impellerc --json` writes, which is what Flutter's own web
/// build ships: {"sksl": {"shader": "<source>", "uniforms": [...]}}.
/// impellerc's JSON: `{"sksl": {"shader": "...", "uniforms": [...]}}`.
///
/// Read by a parser of its own, forty lines for this one shape.
/// JSONDecoder would be the obvious choice, and it costs 3 MB here: it
/// parses ISO-8601 dates, which brings Calendar, which brings the regex
/// engine (docs/plans/wasm-size.md). JSONSerialization is the legacy
/// Foundation layer, which this build does not link at all.
private func readJSONBundle(_ bytes: [UInt8]) throws -> ShaderBundle {
    let invalid = ShaderBundleError(message: "Invalid Shader Data")
    var json = MiniJSON(bytes)
    guard case .object(let top)? = try? json.parse(),
          case .object(let root)? = top["sksl"],
          case .string(let source)? = root["shader"],
          case .array(let uniforms)? = root["uniforms"]
    else { throw invalid }
    var samplerCount = 0
    var floatCount = 0
    for entry in uniforms {
        guard case .object(let uniform) = entry, case .number(let type)? = uniform["type"]
        else { throw invalid }
        // 12 is SampledImage in the JSON's uniform type numbering.
        if Int(type) == 12 {
            samplerCount += 1
            continue
        }
        guard case .number(let bitWidth)? = uniform["bit_width"],
              case .number(let rows)? = uniform["rows"],
              case .number(let columns)? = uniform["columns"],
              case .number(let arrayElements)? = uniform["array_elements"]
        else { throw invalid }
        var count = (Int(bitWidth) / 32) &* Int(rows) &* Int(columns)
        if Int(arrayElements) > 1 { count = count &* Int(arrayElements) }
        floatCount = floatCount &+ count
    }
    return ShaderBundle(
        sksl: Array(source.utf8), uniformFloatCount: max(0, floatCount),
        samplerCount: samplerCount)
}

/// Enough JSON for the bundle above: objects, arrays, strings with the
/// standard escapes, numbers, the three literals.
private struct MiniJSON {
    indirect enum Value {
        case object([String: Value]), array([Value]), string(String), number(Double)
        case bool(Bool), null
    }
    struct Malformed: Error {}

    private let bytes: [UInt8]
    private var i = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func parse() throws -> Value {
        let value = try parseValue()
        skipSpace()
        guard i == bytes.count else { throw Malformed() }
        return value
    }

    private mutating func skipSpace() {
        while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
    }

    private mutating func expect(_ literal: String) throws {
        for byte in literal.utf8 {
            guard i < bytes.count, bytes[i] == byte else { throw Malformed() }
            i += 1
        }
    }

    private mutating func parseValue() throws -> Value {
        skipSpace()
        guard i < bytes.count else { throw Malformed() }
        switch bytes[i] {
        case UInt8(ascii: "{"):
            i += 1
            var object: [String: Value] = [:]
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(object) }
            while true {
                skipSpace()
                guard case .string(let key) = try parseValue() else { throw Malformed() }
                skipSpace()
                try expect(":")
                object[key] = try parseValue()
                skipSpace()
                guard i < bytes.count else { throw Malformed() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect("}")
                return .object(object)
            }
        case UInt8(ascii: "["):
            i += 1
            var array: [Value] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(array) }
            while true {
                array.append(try parseValue())
                skipSpace()
                guard i < bytes.count else { throw Malformed() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                try expect("]")
                return .array(array)
            }
        case UInt8(ascii: "\""):
            i += 1
            var scalars = String.UnicodeScalarView()
            while true {
                guard i < bytes.count else { throw Malformed() }
                let c = bytes[i]
                i += 1
                if c == UInt8(ascii: "\"") { break }
                if c == UInt8(ascii: "\\") {
                    guard i < bytes.count else { throw Malformed() }
                    let e = bytes[i]
                    i += 1
                    switch e {
                    case UInt8(ascii: "n"): scalars.append("\n")
                    case UInt8(ascii: "t"): scalars.append("\t")
                    case UInt8(ascii: "r"): scalars.append("\r")
                    case UInt8(ascii: "b"): scalars.append("\u{8}")
                    case UInt8(ascii: "f"): scalars.append("\u{C}")
                    case UInt8(ascii: "u"):
                        guard i + 4 <= bytes.count,
                              let code = UInt32(String(decoding: bytes[i..<i + 4], as: UTF8.self), radix: 16),
                              let scalar = Unicode.Scalar(code)
                        else { throw Malformed() }
                        i += 4
                        scalars.append(scalar)
                    default: scalars.append(Unicode.Scalar(e))
                    }
                } else {
                    // Multi-byte UTF-8 passes through: collect the run and decode it.
                    var run = [c]
                    while i < bytes.count, bytes[i] & 0xC0 == 0x80 { run.append(bytes[i]); i += 1 }
                    scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
                }
            }
            return .string(String(scalars))
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default:
            let start = i
            while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
            guard i > start, let number = Double(String(decoding: bytes[start..<i], as: UTF8.self))
            else { throw Malformed() }
            return .number(number)
        }
    }
}

private func readShaderBundle(_ bytes: [UInt8]) throws -> ShaderBundle {
    // A FlatBuffer carries its file identifier after the root offset.
    if bytes.count >= 8, Array(bytes[4..<8]) == Array("IPLR".utf8) {
        return try readRuntimeStages(bytes)
    }
    if bytes.first(where: { !" \t\r\n".utf8.contains($0) }) == UInt8(ascii: "{") {
        return try readJSONBundle(bytes)
    }
    throw ShaderBundleError(message: "Data does not contain any shader data.")
}

extension flutter.swift_bridge {

    // MARK: - FragmentProgramBridge

    public final class FragmentProgramBridge {
        /// Which of the asset's runtime stages to load. Raw values are the
        /// C++ enum's.
        public enum Backend: Int32 {
            case kSkSL = 0
            case kMetal = 1
            case kOpenGLES = 2
            case kVulkan = 3
            case kOpenGLES3 = 4
        }

        /// The `SkRuntimeEffect*`. 0 until InitFromData succeeds.
        public private(set) var skHandle: sk_ptr = 0
        private var uniformFloatCount: Int32 = 0
        private var samplerCount: Int32 = 0

        public init() {}

        deinit { release() }

        private func release() {
            if skHandle != 0 { runtimeEffect_dispose(skHandle) }
            skHandle = 0
        }

        /// The size skwasm requires of this effect's uniform block, in bytes.
        public var uniformSize: Int {
            skHandle != 0 ? Int(runtimeEffect_getUniformSize(skHandle)) : 0
        }

        /// Returns nil on success, otherwise a message the caller `free`s —
        /// the C++ contract, so the string is malloc'd.
        ///
        /// `backend` is ignored: skwasm is Skia, so the stage to load is
        /// always the SkSL one, whatever the caller believes it is running on.
        public func InitFromData(
            _ data: UnsafePointer<UInt8>?, _ data_size: Int, _ backend: Backend
        ) -> UnsafePointer<CChar>? {
            guard let data, data_size > 0 else {
                return UnsafePointer(strdup("No shader data provided"))
            }
            let bundle: ShaderBundle
            do {
                bundle = try readShaderBundle(
                    Array(UnsafeBufferPointer(start: data, count: data_size)))
            } catch let error as ShaderBundleError {
                return UnsafePointer(strdup(error.message))
            } catch {
                return UnsafePointer(strdup("Invalid Shader Data"))
            }

            let source = skString_allocate(UInt32(bundle.sksl.count))
            bundle.sksl.withUnsafeBufferPointer {
                skWrite(skString_getData(source), $0.baseAddress, count: $0.count)
            }
            let effect = runtimeEffect_create(source)
            skString_free(source)
            guard effect != 0 else {
                // skwasm prints Skia's own error text to the console and
                // returns only null, so the message cannot carry it.
                let sksl = String(decoding: bundle.sksl, as: UTF8.self)
                return UnsafePointer(
                    strdup("Invalid SkSL:\n\(sksl)\nSkSL Error: see the browser console."))
            }
            // Replaces a previous effect on hot reload (reinitializeShader).
            release()
            skHandle = effect
            uniformFloatCount = Int32(clamping: bundle.uniformFloatCount)
            samplerCount = Int32(clamping: bundle.samplerCount)
            return nil
        }

        public func GetUniformFloatCount() -> Int32 { uniformFloatCount }
        public func GetSamplerCount() -> Int32 { samplerCount }

        // MakeColorSource and MakeImageFilter, which in C++ return a
        // heap-allocated shared_ptr for another C++ class to adopt, have no
        // Swift caller and are not re-created: FragmentShaderBridge builds
        // its shader directly.
    }

    // MARK: - FragmentShaderBridge

    public final class FragmentShaderBridge {
        private var program: FragmentProgramBridge?
        private let floatCount: Int
        // The float uniforms, then two floats (width, height) per sampler —
        // the layout the engine's ReusableFragmentShader keeps.
        private var uniforms: [Float]
        // One image shader per sampler; 0 where none has been set. Owned.
        private var samplers: [sk_ptr]
        private var images: [ImageBridge?]
        // Built on demand and thrown away whenever a uniform or sampler
        // changes: a skwasm shader is immutable once made.
        private var shader: sk_ptr = 0
        private var disposed = false

        public init(_ program: FragmentProgramBridge?, _ float_uniforms: Int32, _ sampler_uniforms: Int32) {
            self.program = program
            floatCount = Int(max(0, float_uniforms))
            let samplerCount = Int(max(0, sampler_uniforms))
            uniforms = [Float](repeating: 0, count: floatCount + 2 * samplerCount)
            samplers = [sk_ptr](repeating: 0, count: samplerCount)
            images = [ImageBridge?](repeating: nil, count: samplerCount)
        }

        deinit {
            invalidate()
            for sampler in samplers where sampler != 0 { shader_dispose(sampler) }
        }

        private func invalidate() {
            if shader != 0 { shader_dispose(shader) }
            shader = 0
        }

        /// The `sp_wrapper<DlColorSource>*` for the current uniforms, or 0
        /// when there is nothing to draw with: disposed, no program, or a
        /// sampler still unset.
        public var skHandle: sk_ptr {
            if shader != 0 { return shader }
            guard !disposed, let program, program.skHandle != 0 else { return 0 }
            // skwasm dereferences every child, so an unset sampler cannot be
            // passed as null the way the engine does.
            guard !samplers.contains(0) else { return 0 }

            // Skia rejects a uniform block that is not exactly the size the
            // effect declares, so that size rules and ours is fitted to it.
            let size = program.uniformSize
            let block = uniformData_create(Int32(size))
            defer { uniformData_dispose(block) }
            let byteCount = min(size, uniforms.count * MemoryLayout<Float>.stride)
            uniforms.withUnsafeBufferPointer {
                skWrite(
                    uniformData_getPointer(block), $0.baseAddress,
                    count: byteCount / MemoryLayout<Float>.stride)
            }
            // The shader shares ownership of the block's bytes, so the block
            // itself can go as soon as the shader exists.
            shader = withSkStack { stack in
                shader_createRuntimeEffectShader(
                    program.skHandle, block, stack.pointers(samplers), UInt32(samplers.count))
            }
            return shader
        }

        public func SetFloat(_ index: Int32, _ value: Float) {
            guard !disposed, index >= 0, Int(index) < uniforms.count else { return }
            uniforms[Int(index)] = value
            invalidate()
        }

        public func GetFloat(_ index: Int32) -> Float {
            guard !disposed, index >= 0, Int(index) < uniforms.count else { return 0 }
            return uniforms[Int(index)]
        }

        public func SetImageSampler(_ index: Int32, _ image: ImageBridge?) -> Bool {
            guard !disposed, index >= 0, Int(index) < samplers.count else { return false }
            guard let image, !image.IsDisposed(), image.skHandle != 0 else { return false }
            let i = Int(index)
            // Clamped and unfiltered (quality 0), as the engine samples.
            let sampler = shader_createFromImage(image.skHandle, 0, 0, 0, 0)
            guard sampler != 0 else { return false }
            invalidate()
            if samplers[i] != 0 { shader_dispose(samplers[i]) }
            samplers[i] = sampler
            images[i] = image
            uniforms[floatCount + 2 * i] = Float(image.Width())
            uniforms[floatCount + 2 * i + 1] = Float(image.Height())
            return true
        }

        public func ValidateSamplers() -> Bool {
            !disposed && !samplers.contains(0)
        }

        /// An image filter's first sampler is its input and need not be set;
        /// the rest must be.
        public func ValidateImageFilter() -> Bool {
            !disposed && !samplers.isEmpty && !samplers.dropFirst().contains(0)
        }

        public func GetFloatCount() -> Int32 { Int32(floatCount) }
        public func GetSamplerCount() -> Int32 { Int32(samplers.count) }

        public func GetShaderPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }

        // MakeColorSource and MakeImageFilter are not re-created; see
        // FragmentProgramBridge. WEB-TODO: the image filter form needs a
        // skwasm export that does not exist (see ImageFilterBridge.InitShader).

        public func Dispose() {
            guard !disposed else { return }
            invalidate()
            for sampler in samplers where sampler != 0 { shader_dispose(sampler) }
            samplers = []
            images = []
            uniforms = []
            program = nil
            disposed = true
        }

        public func IsDisposed() -> Bool { disposed }
    }
}
