// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import Foundation

/// Runs an independent Flutter widget tree offscreen, rasterizes its output,
/// and provides raw RGBA pixel data for compositing via the embedder's
/// external texture API.
///
/// This is the Linux equivalent of `OffscreenFlutterApp` (macOS). Instead of
/// CVPixelBuffer, it outputs raw RGBA `Data` suitable for direct GL upload.
///
/// Usage:
/// ```swift
/// let app = LinuxOffscreenFlutterApp(width: 400, height: 300)
/// app.mountWidget { MyWidget() }
/// app.start(fps: 30)
/// ```
class LinuxOffscreenFlutterApp {

    let width: Int
    let height: Int

    /// Called on the main RunLoop when a new frame is ready.
    /// Parameters: (rgbaData, width, height)
    var onFrameReady: ((Data, Int, Int) -> Void)?

    private let buildOwner: BuildOwner
    private let pipelineOwner: PipelineOwner
    private let renderView: RenderView
    private var rootElement: RenderObjectToWidgetElement?

    private var timer: Timer?

    // MARK: - Init

    init(width: Int, height: Int) {
        self.width = width
        self.height = height

        // Build pipeline
        buildOwner = BuildOwner()
        pipelineOwner = PipelineOwner()

        let view = PlatformDispatcher.instance.implicitView!
        renderView = RenderView(view: view)

        let constraints = BoxConstraints.tight(Size(Double(width), Double(height)))
        let config = RenderViewConfiguration(
            physicalConstraints: constraints,
            logicalConstraints: constraints,
            devicePixelRatio: 1.0
        )
        renderView.configuration = config
        renderView.attach(pipelineOwner)
        renderView.prepareInitialFrame()

        // No-op: we drive frames ourselves via the timer.
        buildOwner.onBuildScheduled = {}
    }

    // MARK: - Widget Mounting

    func mountWidget(_ builder: () -> Widget) {
        let adapter = RenderObjectToWidgetAdapter(
            child: builder(),
            container: renderView
        )
        rootElement = adapter.attachToRenderTree(buildOwner)
    }

    // MARK: - Lifecycle

    func start(fps: Int = 30) {
        let interval = 1.0 / Double(fps)
        // On Linux, Timer closures are @Sendable. Use unsafeBitCast to bridge.
        let block: (Timer) -> Void = { [weak self] _ in
            self?.renderFrame()
        }
        let sendableBlock = unsafeBitCast(block, to: (@Sendable (Timer) -> Void).self)
        let t = Timer(timeInterval: interval, repeats: true, block: sendableBlock)
        Foundation.RunLoop.main.add(t, forMode: .default)
        Foundation.RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Vsync-driven rendering (DRM mode)

    private var lastRenderTime: UInt64 = 0
    private var renderIntervalNanos: UInt64 = 33_333_333  // ~30fps

    /// Called externally (e.g. from vsync) to render a frame.
    /// Throttled to renderIntervalNanos to avoid rendering at full vsync rate.
    func tickRender(currentTimeNanos: UInt64) {
        guard currentTimeNanos - lastRenderTime >= renderIntervalNanos else { return }
        lastRenderTime = currentTimeNanos
        renderFrame()
    }

    // MARK: - Rendering

    private func renderFrame() {
        guard let rootElement = rootElement else { return }

        // Build dirty elements
        buildOwner.buildScopeWithCallback(rootElement) {}

        // Layout
        renderView.performLayout()

        // Paint
        PaintingContext.repaintCompositedChild(renderView)

        // Extract PictureLayer from layer tree.
        guard let rootLayer = renderView.layer else { return }
        guard let pictureLayer = findPictureLayer(rootLayer) else { return }
        guard let picture = pictureLayer.picture as? NativePicture else { return }

        // Rasterize to Image. Optional since the iOS round routed
        // toImageSync through the rasteriser's own snapshot — a headless
        // frame can miss it and answer nil.
        guard let image = picture.toImageSync(width: width, height: height)
        else { return }

        // Get raw RGBA bytes
        guard let rgbaData = try? image.toByteData(format: .rawRgba) else {
            image.dispose()
            return
        }
        image.dispose()

        // Output RGBA data directly — no BGRA swizzle needed for GL
        onFrameReady?(rgbaData, width, height)
    }

    // MARK: - Layer Tree Traversal

    /// Depth-first search for the first PictureLayer in the layer tree.
    private func findPictureLayer(_ layer: Layer) -> PictureLayer? {
        if let pl = layer as? PictureLayer {
            return pl
        }
        if let container = layer as? ContainerLayer {
            var child = container.firstChild
            while let current = child {
                if let found = findPictureLayer(current) {
                    return found
                }
                child = current.nextSibling
            }
        }
        return nil
    }
}
#endif
