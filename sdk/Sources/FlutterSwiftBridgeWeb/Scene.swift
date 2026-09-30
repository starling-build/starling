// SceneBuilder, Scene, EngineLayer and RenderView.
//
// Natively these build the engine's `flow` layer tree, which the rasterizer
// walks on its own thread. skwasm has no layer tree — upstream's web engine
// keeps its own, in Dart — so the tree lives here, and RenderView flattens
// it into one picture: each layer becomes the save/transform/clip/saveLayer
// it stands for, wrapped around its children.
import CSkwasm

/// One node of the scene. A class hierarchy rather than an enum because
/// EngineLayerBridge hands nodes back to the framework by identity.
public class WebLayer {
    fileprivate(set) var children: [WebLayer] = []

    /// Emits this layer's effect, then `paintChildren`, then undoes it.
    func paint(on canvas: sk_ptr) { paintChildren(on: canvas) }

    final func paintChildren(on canvas: sk_ptr) {
        for child in children { child.paint(on: canvas) }
    }
}

// Clip.none, .hardEdge, .antiAlias, .antiAliasWithSaveLayer.
private func antiAlias(_ clipBehavior: Int32) -> Bool { clipBehavior >= 2 }
private func savesLayer(_ clipBehavior: Int32) -> Bool { clipBehavior == 3 }

/// Wraps `body` in the save (or saveLayer) a clip of this behavior needs.
private func clipped(
    _ canvas: sk_ptr, _ clipBehavior: Int32, clip: () -> Void, body: () -> Void
) {
    guard clipBehavior != 0 else { return body() }
    canvas_save(canvas)
    clip()
    if savesLayer(clipBehavior) { canvas_saveLayer(canvas, 0, 0, 0) }
    body()
    if savesLayer(clipBehavior) { canvas_restore(canvas) }
    canvas_restore(canvas)
}

final class TransformLayer: WebLayer {
    let matrix: [Float]
    init(_ matrix: [Float]) { self.matrix = matrix }
    override func paint(on canvas: sk_ptr) {
        canvas_save(canvas)
        withSkStack { canvas_transform(canvas, $0.array(matrix)) }
        paintChildren(on: canvas)
        canvas_restore(canvas)
    }
}

final class OffsetLayer: WebLayer {
    let dx: Float, dy: Float
    init(_ dx: Float, _ dy: Float) { self.dx = dx; self.dy = dy }
    override func paint(on canvas: sk_ptr) {
        canvas_save(canvas)
        canvas_translate(canvas, dx, dy)
        paintChildren(on: canvas)
        canvas_restore(canvas)
    }
}

final class ClipRectLayer: WebLayer {
    let rect: [Float], behavior: Int32
    init(_ rect: [Float], _ behavior: Int32) { self.rect = rect; self.behavior = behavior }
    override func paint(on canvas: sk_ptr) {
        clipped(canvas, behavior) {
            // 1 is DlClipOp::kIntersect.
            withSkStack { canvas_clipRect(canvas, $0.array(rect), 1, antiAlias(behavior)) }
        } body: {
            paintChildren(on: canvas)
        }
    }
}

final class ClipRRectLayer: WebLayer {
    let rrect: [Float], behavior: Int32
    init(_ rrect: [Float], _ behavior: Int32) { self.rrect = rrect; self.behavior = behavior }
    override func paint(on canvas: sk_ptr) {
        clipped(canvas, behavior) {
            withSkStack { canvas_clipRRect(canvas, $0.array(rrect), antiAlias(behavior)) }
        } body: {
            paintChildren(on: canvas)
        }
    }
}

final class ClipPathLayer: WebLayer {
    let path: flutter.swift_bridge.PathBridge, behavior: Int32
    init(_ path: flutter.swift_bridge.PathBridge, _ behavior: Int32) {
        self.path = path
        self.behavior = behavior
    }
    override func paint(on canvas: sk_ptr) {
        clipped(canvas, behavior) {
            canvas_clipPath(canvas, path.skHandle, antiAlias(behavior))
        } body: {
            paintChildren(on: canvas)
        }
    }
}

final class OpacityLayer: WebLayer {
    let alpha: UInt32, dx: Float, dy: Float
    init(_ alpha: Int32, _ dx: Float, _ dy: Float) {
        self.alpha = UInt32(max(0, min(255, alpha)))
        self.dx = dx
        self.dy = dy
    }
    override func paint(on canvas: sk_ptr) {
        let paint = WebPaint(color: alpha << 24)
        canvas_save(canvas)
        canvas_translate(canvas, dx, dy)
        canvas_saveLayer(canvas, 0, paint.skHandle, 0)
        paintChildren(on: canvas)
        canvas_restore(canvas)
        canvas_restore(canvas)
        paint.dispose()
    }
}

final class ColorFilterLayer: WebLayer {
    let filter: flutter.swift_bridge.ColorFilterBridge
    init(_ filter: flutter.swift_bridge.ColorFilterBridge) { self.filter = filter }
    override func paint(on canvas: sk_ptr) {
        let paint = WebPaint()
        paint_setColorFilter(paint.skHandle, skHandle(from: filter.webFilterPointer))
        canvas_saveLayer(canvas, 0, paint.skHandle, 0)
        paintChildren(on: canvas)
        canvas_restore(canvas)
        paint.dispose()
    }
}

final class ImageFilterLayer: WebLayer {
    let filter: flutter.swift_bridge.ImageFilterBridge, dx: Float, dy: Float
    init(_ filter: flutter.swift_bridge.ImageFilterBridge, _ dx: Float, _ dy: Float) {
        self.filter = filter
        self.dx = dx
        self.dy = dy
    }
    override func paint(on canvas: sk_ptr) {
        let paint = WebPaint()
        paint_setImageFilter(paint.skHandle, skHandle(from: filter.webFilterPointer))
        canvas_save(canvas)
        canvas_translate(canvas, dx, dy)
        canvas_saveLayer(canvas, 0, paint.skHandle, 0)
        paintChildren(on: canvas)
        canvas_restore(canvas)
        canvas_restore(canvas)
        paint.dispose()
    }
}

final class BackdropFilterLayer: WebLayer {
    let filter: flutter.swift_bridge.ImageFilterBridge, blendMode: Int32
    init(_ filter: flutter.swift_bridge.ImageFilterBridge, _ blendMode: Int32) {
        self.filter = filter
        self.blendMode = blendMode
    }
    override func paint(on canvas: sk_ptr) {
        let paint = WebPaint(blendMode: blendMode)
        canvas_saveLayer(
            canvas, 0, paint.skHandle, skHandle(from: filter.webFilterPointer))
        paintChildren(on: canvas)
        canvas_restore(canvas)
        paint.dispose()
    }
}

final class ShaderMaskLayer: WebLayer {
    let shader: sk_ptr, rect: [Float], blendMode: Int32
    init(_ shader: sk_ptr, _ rect: [Float], _ blendMode: Int32) {
        self.shader = shader
        self.rect = rect
        self.blendMode = blendMode
    }
    override func paint(on canvas: sk_ptr) {
        // The children in a layer of their own, then the shader drawn over
        // them with the mask's blend mode. The shader is defined in the mask
        // rect's coordinates, hence the translate.
        canvas_saveLayer(canvas, 0, 0, 0)
        paintChildren(on: canvas)
        let paint = WebPaint(blendMode: blendMode)
        paint_setShader(paint.skHandle, shader)
        canvas_translate(canvas, rect[0], rect[1])
        withSkStack {
            canvas_drawRect(
                canvas, $0.rect(0, 0, rect[2] - rect[0], rect[3] - rect[1]),
                paint.skHandle)
        }
        canvas_restore(canvas)
        paint.dispose()
    }
}

final class PictureLayer: WebLayer {
    let picture: flutter.swift_bridge.PictureBridge, dx: Float, dy: Float
    init(_ picture: flutter.swift_bridge.PictureBridge, _ dx: Float, _ dy: Float) {
        self.picture = picture
        self.dx = dx
        self.dy = dy
    }
    override func paint(on canvas: sk_ptr) {
        // Read at paint time: the framework may have disposed it since.
        let handle = picture.skHandle
        guard handle != 0 else { return }
        if dx == 0, dy == 0 {
            canvas_drawPicture(canvas, handle)
        } else {
            canvas_save(canvas)
            canvas_translate(canvas, dx, dy)
            canvas_drawPicture(canvas, handle)
            canvas_restore(canvas)
        }
    }
}

// The filter bridges are another file's; this is the one thing the layer
// tree needs from them, spelled so that a rename there fails here.
extension flutter.swift_bridge.ColorFilterBridge {
    fileprivate var webFilterPointer: UnsafeRawPointer? { UnsafeRawPointer(GetFilterPtr()) }
}
extension flutter.swift_bridge.ImageFilterBridge {
    // -1: no tile mode override, the value Paint passes for a layer's filter.
    fileprivate var webFilterPointer: UnsafeRawPointer? { UnsafeRawPointer(GetFilterPtr(-1)) }
}

extension flutter.swift_bridge {
    public final class EngineLayerBridge {
        fileprivate var layer: WebLayer?

        init(_ layer: WebLayer) { self.layer = layer }

        /// The native constructor's shape. The pointer is one GetLayerPtr
        /// returned: an unretained reference to a WebLayer.
        public init(_ layerPointer: UnsafeRawPointer?) {
            layer = layerPointer.map {
                Unmanaged<WebLayer>.fromOpaque($0).takeUnretainedValue()
            }
        }

        public func Dispose() { layer = nil }
        public func IsDisposed() -> Bool { layer == nil }
        public func GetLayerPtr() -> UnsafeRawPointer? {
            layer.map { UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque()) }
        }
    }

    public final class SceneBridge {
        fileprivate var root: WebLayer?

        init(_ root: WebLayer) { self.root = root }

        public init(_ rootLayerPointer: UnsafeRawPointer?) {
            root = rootLayerPointer.map {
                Unmanaged<WebLayer>.fromOpaque($0).takeUnretainedValue()
            }
        }

        public func Dispose() { root = nil }
        public func IsDisposed() -> Bool { root == nil }
        public func GetRootLayerPtr() -> UnsafeRawPointer? {
            root.map { UnsafeRawPointer(Unmanaged.passUnretained($0).toOpaque()) }
        }
    }

    // `oldLayer` is the retained-rendering hint: natively it lets the engine
    // reuse the previous frame's raster cache for an unchanged subtree. There
    // is no raster cache here, so it is accepted and ignored.
    public final class SceneBuilderBridge {
        private let root = WebLayer()
        private var stack: [WebLayer]

        public init() { stack = [root] }

        private func push(_ layer: WebLayer) -> EngineLayerBridge? {
            stack[stack.count - 1].children.append(layer)
            stack.append(layer)
            return EngineLayerBridge(layer)
        }

        public func PushTransform(
            _ matrix4: UnsafePointer<Double>?, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let matrix4 else { return push(WebLayer()) }
            return push(TransformLayer((0..<16).map { Float(matrix4[$0]) }))
        }

        public func PushOffset(
            _ dx: Double, _ dy: Double, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            push(OffsetLayer(Float(dx), Float(dy)))
        }

        public func PushClipRect(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ clipBehavior: Int32, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            push(
                ClipRectLayer(
                    [Float(left), Float(top), Float(right), Float(bottom)], clipBehavior))
        }

        public func PushClipRRect(
            _ rrect: UnsafePointer<Float>?, _ clipBehavior: Int32,
            _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let rrect else { return push(WebLayer()) }
            return push(ClipRRectLayer((0..<12).map { rrect[$0] }, clipBehavior))
        }

        // WEB-TODO: a rounded rectangle stands in; see CanvasBridge.ClipRSuperellipse.
        public func PushClipRSuperellipse(
            _ left: Double, _ top: Double, _ right: Double, _ bottom: Double,
            _ tlX: Double, _ tlY: Double, _ trX: Double, _ trY: Double,
            _ brX: Double, _ brY: Double, _ blX: Double, _ blY: Double,
            _ clipBehavior: Int32, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            push(
                ClipRRectLayer(
                    [left, top, right, bottom, tlX, tlY, trX, trY, brX, brY, blX, blY]
                        .map { Float($0) }, clipBehavior))
        }

        public func PushClipPath(
            _ path: PathBridge?, _ clipBehavior: Int32, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let path else { return push(WebLayer()) }
            return push(ClipPathLayer(path, clipBehavior))
        }

        public func PushOpacity(
            _ alpha: Int32, _ dx: Double, _ dy: Double, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            push(OpacityLayer(alpha, Float(dx), Float(dy)))
        }

        public func PushColorFilter(
            _ filter: ColorFilterBridge?, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let filter else { return push(WebLayer()) }
            return push(ColorFilterLayer(filter))
        }

        public func PushImageFilter(
            _ filter: ImageFilterBridge?, _ dx: Double, _ dy: Double,
            _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let filter else { return push(WebLayer()) }
            return push(ImageFilterLayer(filter, Float(dx), Float(dy)))
        }

        public func PushBackdropFilter(
            _ filter: ImageFilterBridge?, _ blendMode: Int32, _ backdropId: Int64,
            _ hasBackdropId: Bool, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            guard let filter else { return push(WebLayer()) }
            return push(BackdropFilterLayer(filter, blendMode))
        }

        public func PushShaderMask(
            _ shader: UnsafeRawPointer?, _ left: Double, _ top: Double,
            _ right: Double, _ bottom: Double, _ blendMode: Int32,
            _ filterQuality: Int32, _ oldLayer: EngineLayerBridge?
        ) -> EngineLayerBridge? {
            push(
                ShaderMaskLayer(
                    skHandle(from: shader),
                    [Float(left), Float(top), Float(right), Float(bottom)], blendMode))
        }

        public func Pop() {
            // The root is never popped, as natively.
            if stack.count > 1 { stack.removeLast() }
        }

        /// A subtree from an earlier frame, added again as it was.
        public func AddRetained(_ retained: EngineLayerBridge?) {
            guard let layer = retained?.layer else { return }
            stack[stack.count - 1].children.append(layer)
        }

        public func AddPicture(
            _ dx: Double, _ dy: Double, _ picture: PictureBridge?, _ hints: Int32
        ) {
            guard let picture else { return }
            stack[stack.count - 1].children.append(
                PictureLayer(picture, Float(dx), Float(dy)))
        }

        // WEB-TODO: no performance overlay, external textures or platform
        // views. The last would be DOM elements layered with the canvas.
        public func AddPerformanceOverlay(
            _ enabledOptions: UInt64, _ left: Double, _ top: Double, _ right: Double,
            _ bottom: Double
        ) {}

        public func AddTexture(
            _ dx: Double, _ dy: Double, _ width: Double, _ height: Double,
            _ textureId: Int64, _ freeze: Bool, _ filterQuality: Int32
        ) {}

        public func AddPlatformView(
            _ dx: Double, _ dy: Double, _ width: Double, _ height: Double,
            _ viewId: Int64
        ) {}

        public func Build() -> SceneBridge? {
            stack = [root]
            return SceneBridge(root)
        }
    }
}

// MARK: - Putting a scene on screen

/// The one surface: skwasm's WebGL canvas, whose finished frames the page
/// moves to the visible `<canvas>`.
public enum WebSurface {
    nonisolated(unsafe) private static var surface: sk_ptr = 0

    /// True from a render until the page reports it presented. The host
    /// uses it to keep to one frame in flight.
    nonisolated(unsafe) public private(set) static var frameInFlight = false

    /// Called by the host when the page calls `starling_frame_presented`.
    public static func framePresented() { frameInFlight = false }

    /// The skwasm Surface, created on first use. Image decoding needs it
    /// too: a decoded bitmap becomes a texture in the surface's GL context.
    public static var handle: sk_ptr {
        if surface == 0 {
            surface = surface_create()
            surface_setCallbackHandler(surface, starling_host_render_callback())
        }
        return surface
    }

    static func render(_ root: WebLayer, width: Int32, height: Int32) {
        guard width > 0, height > 0 else { return }
        let surface = handle

        let recorder = pictureRecorder_create()
        let canvas = withSkStack {
            pictureRecorder_beginRecording(
                recorder, $0.rect(0, 0, Float(width), Float(height)))
        }
        root.paint(on: canvas)
        let picture = pictureRecorder_endRecording(recorder)
        pictureRecorder_dispose(recorder)

        frameInFlight = true
        _ = withSkStack {
            surface_renderPictures(surface, $0.pointers([picture]), width, height, 1)
        }
        // renderPictures took its own reference.
        picture_dispose(picture)
    }
}

extension flutter.swift_bridge {
    /// `width` and `height` are physical pixels; the framework's root layer
    /// already carries the device-pixel-ratio transform.
    public static func RenderView(
        _ viewId: Int64, _ scene: SceneBridge?, _ width: Double, _ height: Double
    ) {
        guard let root = scene?.root else { return }
        WebSurface.render(root, width: Int32(width), height: Int32(height))
    }
}
