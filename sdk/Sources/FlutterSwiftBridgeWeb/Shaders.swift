// Shaders: the base class, gradients and image shaders, over skwasm's
// shaders.cpp. Fragment shaders are in FragmentProgram.swift.
import CSkwasm

// MARK: - Argument conversions

/// The engine's SafeNarrow: a double as a float, saturating rather than
/// overflowing to infinity. Infinities and NaN pass through.
func skNarrow(_ value: Double) -> Float {
    if value.isInfinite || value.isNaN { return Float(value) }
    if value > Double(Float.greatestFiniteMagnitude) { return Float.greatestFiniteMagnitude }
    if value < -Double(Float.greatestFiniteMagnitude) { return -Float.greatestFiniteMagnitude }
    return Float(value)
}

/// dart:ui's TileMode index as skwasm's DlTileMode. The two agree (clamp,
/// repeat, mirror, decal); anything else is clamp, as in the engine.
func skTileMode(_ index: Int32) -> Int32 {
    (0...3).contains(index) ? index : 0
}

/// A column-major 4x4 as the row-major 3x3 skwasm takes: the z row and column
/// are dropped. Same picks as convertMatrix4toSkMatrix in skwasm_impl.
func skMatrix33(_ matrix4: UnsafePointer<Double>) -> [Float] {
    [0, 4, 12, 1, 5, 13, 3, 7, 15].map { skNarrow(matrix4[$0]) }
}

/// The matrix on skwasm's stack, or 0 (identity) when there is none.
func skMatrix33(_ stack: SkStack, _ matrix4: UnsafePointer<Double>?) -> sk_ptr {
    guard let matrix4 else { return 0 }
    return stack.floats(skMatrix33(matrix4))
}

extension flutter.swift_bridge {

    // MARK: - ShaderBridge

    /// The base Shader's bridge: dispose tracking and nothing else. The
    /// shader itself lives in the subclass's own bridge.
    public final class ShaderBridge {
        /// Always 0: the base class wraps no skwasm object.
        public let skHandle: sk_ptr = 0
        private var debugDisposed = false

        public init() {}

        public func DebugDisposed() -> Bool { debugDisposed }
        public func Dispose() { debugDisposed = true }
    }

    // MARK: - GradientBridge

    public final class GradientBridge {
        /// The `sp_wrapper<DlColorSource>*`. 0 until an Init… and after Dispose.
        public private(set) var skHandle: sk_ptr = 0
        private var debugDisposed = false

        public init() {}

        deinit { release() }

        private func release() {
            if skHandle != 0 { shader_dispose(skHandle) }
            skHandle = 0
        }

        /// `colors` is 4 floats per colour — alpha, red, green, blue, in
        /// extended sRGB — because that is what the native DisplayList takes.
        /// skwasm takes 32-bit ARGB, so each component is clamped to 0...1.
        // WEB-TODO: wide-gamut gradient colours are clamped to sRGB; skwasm
        // exports no gradient factory that takes float colours.
        private static func argb(_ colors: UnsafePointer<Float>?, _ count: Int32) -> [UInt32] {
            guard let colors, count > 0 else { return [] }
            func byte(_ component: Float) -> UInt32 {
                // NaN fails both comparisons and lands on 0.
                let clamped = component >= 1 ? 1 : (component > 0 ? component : 0)
                return UInt32((clamped * 255).rounded())
            }
            return (0..<Int(count)).map { i in
                let c = colors + i * 4
                return byte(c[0]) << 24 | byte(c[1]) << 16 | byte(c[2]) << 8 | byte(c[3])
            }
        }

        /// Runs `create` with the colours, stops and matrix laid out on
        /// skwasm's stack, and keeps the shader it returns.
        private func make(
            _ colors: UnsafePointer<Float>?, _ colorCount: Int32,
            _ colorStops: UnsafePointer<Float>?, _ stopCount: Int32,
            _ matrix4: UnsafePointer<Double>?,
            _ create: (SkStack, _ colors: sk_ptr, _ stops: sk_ptr, _ matrix: sk_ptr) -> sk_ptr
        ) {
            release()
            let argb = Self.argb(colors, colorCount)
            guard !argb.isEmpty else { return }
            skHandle = withSkStack { stack in
                // skwasm reads one stop per colour, so a shorter list is the
                // same as none: evenly spaced.
                let stops = stopCount >= colorCount
                    ? stack.copy(colorStops, count: Int(colorCount)) : 0
                return create(stack, stack.array(argb), stops, skMatrix33(stack, matrix4))
            }
        }

        public func InitLinear(
            _ from_x: Double, _ from_y: Double, _ to_x: Double, _ to_y: Double,
            _ colors: UnsafePointer<Float>?, _ color_count: Int32,
            _ color_stops: UnsafePointer<Float>?, _ stop_count: Int32,
            _ tile_mode: Int32, _ matrix4: UnsafePointer<Double>?
        ) {
            make(colors, color_count, color_stops, stop_count, matrix4) { stack, colors, stops, matrix in
                let endPoints = stack.floats([
                    skNarrow(from_x), skNarrow(from_y), skNarrow(to_x), skNarrow(to_y),
                ])
                return shader_createLinearGradient(
                    endPoints, colors, stops, color_count, skTileMode(tile_mode), matrix)
            }
        }

        public func InitRadial(
            _ center_x: Double, _ center_y: Double, _ radius: Double,
            _ colors: UnsafePointer<Float>?, _ color_count: Int32,
            _ color_stops: UnsafePointer<Float>?, _ stop_count: Int32,
            _ tile_mode: Int32, _ matrix4: UnsafePointer<Double>?
        ) {
            make(colors, color_count, color_stops, stop_count, matrix4) { _, colors, stops, matrix in
                shader_createRadialGradient(
                    skNarrow(center_x), skNarrow(center_y), skNarrow(radius),
                    colors, stops, color_count, skTileMode(tile_mode), matrix)
            }
        }

        public func InitConical(
            _ focal_x: Double, _ focal_y: Double, _ focal_radius: Double,
            _ center_x: Double, _ center_y: Double, _ radius: Double,
            _ colors: UnsafePointer<Float>?, _ color_count: Int32,
            _ color_stops: UnsafePointer<Float>?, _ stop_count: Int32,
            _ tile_mode: Int32, _ matrix4: UnsafePointer<Double>?
        ) {
            make(colors, color_count, color_stops, stop_count, matrix4) { stack, colors, stops, matrix in
                // Start circle first: the focal point, then the centre.
                let endPoints = stack.floats([
                    skNarrow(focal_x), skNarrow(focal_y), skNarrow(center_x), skNarrow(center_y),
                ])
                return shader_createConicalGradient(
                    endPoints, skNarrow(focal_radius), skNarrow(radius),
                    colors, stops, color_count, skTileMode(tile_mode), matrix)
            }
        }

        public func InitSweep(
            _ center_x: Double, _ center_y: Double,
            _ colors: UnsafePointer<Float>?, _ color_count: Int32,
            _ color_stops: UnsafePointer<Float>?, _ stop_count: Int32,
            _ tile_mode: Int32, _ start_angle: Double, _ end_angle: Double,
            _ matrix4: UnsafePointer<Double>?
        ) {
            make(colors, color_count, color_stops, stop_count, matrix4) { _, colors, stops, matrix in
                // Radians in, degrees out — as the engine's gradient.cc does.
                shader_createSweepGradient(
                    skNarrow(center_x), skNarrow(center_y), colors, stops, color_count,
                    skTileMode(tile_mode),
                    skNarrow(start_angle) * 180 / Float.pi,
                    skNarrow(end_angle) * 180 / Float.pi,
                    matrix)
            }
        }

        public func DebugDisposed() -> Bool { debugDisposed }

        public func Dispose() {
            debugDisposed = true
            release()
        }

        public func GetShaderPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }
    }

    // MARK: - ImageShaderBridge

    public final class ImageShaderBridge {
        /// The `sp_wrapper<DlColorSource>*`. 0 until InitWithImage and after Dispose.
        public private(set) var skHandle: sk_ptr = 0
        private var debugDisposed = false
        // The shader holds its own reference to the SkImage inside skwasm;
        // this keeps the Swift object alive alongside it, as the C++ does.
        private var image: ImageBridge?

        public init() {}

        deinit { release() }

        private func release() {
            if skHandle != 0 { shader_dispose(skHandle) }
            skHandle = 0
            image = nil
        }

        public func InitWithImage(
            _ image_bridge: ImageBridge?, _ tmx: Int32, _ tmy: Int32,
            _ filter_quality_index: Int32, _ matrix4: UnsafePointer<Double>?
        ) -> Bool {
            guard let image_bridge, !image_bridge.IsDisposed(), image_bridge.skHandle != 0 else {
                return false
            }
            release()
            // No quality given means linear. The engine's image shader has no
            // cubic sampling and draws "high" as mipmapped, which is skwasm's
            // "medium" (2).
            let quality = filter_quality_index < 0 ? 1 : min(filter_quality_index, 2)
            skHandle = withSkStack { stack in
                shader_createFromImage(
                    image_bridge.skHandle, skTileMode(tmx), skTileMode(tmy), quality,
                    skMatrix33(stack, matrix4))
            }
            image = image_bridge
            return skHandle != 0
        }

        public func DebugDisposed() -> Bool { debugDisposed }

        public func Dispose() {
            debugDisposed = true
            release()
        }

        public func GetShaderPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }
    }
}
