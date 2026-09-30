// Colour filters and image filters, over skwasm's filters.cpp.
import CSkwasm

// SK_ScalarNearlyZero: below this the DisplayList factories treat a blur
// sigma or a morphology radius as zero.
private let nearlyZero: Float = 1.0 / 4096.0

extension flutter.swift_bridge {

    // MARK: - ColorFilterBridge

    public final class ColorFilterBridge {
        /// The `sp_wrapper<const DlColorFilter>*`. 0 until an Init….
        public private(set) var skHandle: sk_ptr = 0

        public init() {}

        deinit { release() }

        private func release() {
            if skHandle != 0 { colorFilter_dispose(skHandle) }
            skHandle = 0
        }

        /// `color` is ARGB carried as a signed int; `blend_mode` is dart:ui's
        /// BlendMode index, which is DlBlendMode's.
        public func InitMode(_ color: Int32, _ blend_mode: Int32) {
            release()
            skHandle = colorFilter_createMode(UInt32(bitPattern: color), blend_mode)
        }

        /// 20 floats, row-major 4x5.
        public func InitMatrix(_ matrix: UnsafePointer<Float>?) {
            release()
            guard let matrix else { return }
            var normalized = Array(UnsafeBufferPointer(start: matrix, count: 20))
            // Flutter gives the translation column in 0...255; Skia wants 0...1.
            for i in [4, 9, 14, 19] { normalized[i] *= 1.0 / 255 }
            skHandle = withSkStack { stack in
                colorFilter_createMatrix(stack.floats(normalized))
            }
        }

        public func InitLinearToSrgbGamma() {
            release()
            skHandle = colorFilter_createLinearToSRGBGamma()
        }

        public func InitSrgbToLinearGamma() {
            release()
            skHandle = colorFilter_createSRGBToLinearGamma()
        }

        public func GetFilterPtr() -> UnsafeRawPointer? { skOpaque(skHandle) }
    }

    // MARK: - ImageFilterBridge

    public final class ImageFilterBridge {
        /// The `sp_wrapper<DlImageFilter>*`. 0 until an Init…, and for a
        /// filter that does nothing (the engine holds a null filter there).
        /// A blur with no tile mode of its own is built with clamp here; see
        /// `GetFilterPtr` for the other modes.
        public private(set) var skHandle: sk_ptr = 0

        // A blur created without a tile mode takes the one its user asks for
        // (decal for a saveLayer, mirror for a backdrop, …). The engine
        // rebuilds the blur when asked for a different mode; so do we, and
        // keep the last one so the pointer handed out stays valid.
        private var isDynamicTileMode = false
        private var sigmaX: Float = 0
        private var sigmaY: Float = 0
        private var resolved: sk_ptr = 0
        private var resolvedTileMode: Int32 = 0

        public init() {}

        deinit { release() }

        private func release() {
            if skHandle != 0 { imageFilter_dispose(skHandle) }
            if resolved != 0 { imageFilter_dispose(resolved) }
            skHandle = 0
            resolved = 0
            isDynamicTileMode = false
        }

        public func InitBlur(_ sigma_x: Double, _ sigma_y: Double, _ tile_mode_index: Int32) {
            release()
            let x = skNarrow(sigma_x), y = skNarrow(sigma_y)
            // The same test as DlBlurImageFilter::Make, which returns null.
            guard x.isFinite, y.isFinite, !(x < nearlyZero && y < nearlyZero) else { return }
            sigmaX = x
            sigmaY = y
            isDynamicTileMode = tile_mode_index < 0
            skHandle = imageFilter_createBlur(x, y, isDynamicTileMode ? 0 : skTileMode(tile_mode_index))
        }

        private static func isMorphologyRadius(_ x: Float, _ y: Float) -> Bool {
            x.isFinite && x > nearlyZero && y.isFinite && y > nearlyZero
        }

        public func InitDilate(_ radius_x: Double, _ radius_y: Double) {
            release()
            let x = skNarrow(radius_x), y = skNarrow(radius_y)
            guard Self.isMorphologyRadius(x, y) else { return }
            skHandle = imageFilter_createDilate(x, y)
        }

        public func InitErode(_ radius_x: Double, _ radius_y: Double) {
            release()
            let x = skNarrow(radius_x), y = skNarrow(radius_y)
            guard Self.isMorphologyRadius(x, y) else { return }
            skHandle = imageFilter_createErode(x, y)
        }

        // WEB-TODO: skwasm's matrix filter is 3x3, so a matrix with
        // perspective through z or any z component loses it. The native
        // bridge passes all 16 entries.
        public func InitMatrix(_ matrix4: UnsafePointer<Double>?, _ filter_quality_index: Int32) {
            release()
            guard let matrix4 else { return }
            let m = skMatrix33(matrix4)
            // DlMatrixImageFilter::Make: null unless finite and not identity.
            let identity: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
            guard m.allSatisfy({ $0.isFinite }), m != identity else { return }
            // dart:ui's FilterQuality index is skwasm's; out of range
            // saturates, as SamplingFromIndex does.
            let quality = max(0, min(filter_quality_index, 3))
            skHandle = withSkStack { stack in
                imageFilter_createMatrix(stack.floats(m), quality)
            }
        }

        public func InitColorFilter(_ color_filter: ColorFilterBridge?) {
            release()
            guard let color_filter, color_filter.skHandle != 0 else { return }
            skHandle = imageFilter_createFromColorFilter(color_filter.skHandle)
        }

        public func InitComposed(_ outer: ImageFilterBridge?, _ inner: ImageFilterBridge?) {
            release()
            guard let outer, let inner else { return }
            guard outer.skHandle != 0 || inner.skHandle != 0 else { return }
            // With one side empty the composition IS the other side
            // (DlComposeImageFilter::Make), but skwasm needs a box for both.
            // A zero blur is how to get a box holding no filter.
            let empty = outer.skHandle == 0 || inner.skHandle == 0
                ? imageFilter_createBlur(0, 0, 0) : 0
            skHandle = imageFilter_compose(
                outer.skHandle != 0 ? outer.skHandle : empty,
                inner.skHandle != 0 ? inner.skHandle : empty)
            if empty != 0 { imageFilter_dispose(empty) }
        }

        // WEB-TODO: skwasm exports no image filter made from a runtime
        // effect (DlImageFilter::MakeRuntimeEffect), so
        // ImageFilter.shader(...) is an empty filter on the web and draws
        // its input unchanged. Needs a new skwasm export.
        public func InitShader(_ shader: FragmentShaderBridge?) {
            release()
        }

        /// Identity, as in the engine: two bridges are equal when they hold
        /// the same filter object, or both hold none.
        public func Equals(_ other: ImageFilterBridge?) -> Bool {
            guard let other else { return false }
            return skHandle == other.skHandle
        }

        public func IsDynamicTileMode() -> Bool { isDynamicTileMode }

        /// The filter, with `tile_mode_index` standing in for a blur's missing
        /// tile mode. Negative means no preference.
        public func resolvedHandle(tileMode tile_mode_index: Int32) -> sk_ptr {
            guard skHandle != 0, isDynamicTileMode, tile_mode_index >= 0 else { return skHandle }
            let tileMode = skTileMode(tile_mode_index)
            // skHandle itself was built with clamp (0).
            if tileMode == 0 { return skHandle }
            if resolved == 0 || resolvedTileMode != tileMode {
                if resolved != 0 { imageFilter_dispose(resolved) }
                resolved = imageFilter_createBlur(sigmaX, sigmaY, tileMode)
                resolvedTileMode = tileMode
            }
            return resolved
        }

        public func GetFilterPtr(_ tile_mode_index: Int32) -> UnsafeRawPointer? {
            skOpaque(resolvedHandle(tileMode: tile_mode_index))
        }
    }
}
