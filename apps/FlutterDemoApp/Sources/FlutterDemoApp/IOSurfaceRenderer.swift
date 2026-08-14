// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(macOS)
import CoreVideo
import Flutter
import FlutterSwiftBridge
import Foundation
import IOSurface

/// Runs an independent Flutter widget tree offscreen, rasterizes its output,
/// and writes pixels to an IOSurface for cross-process compositing.
///
/// The parent process can look up the surface by ID and wrap it as a
/// FlutterTexture for zero-copy compositing.
///
/// Usage:
/// ```swift
/// let renderer = IOSurfaceRenderer(width: 640, height: 480)
/// renderer.mountWidget { MyWidget() }
/// renderer.start(fps: 30)
/// ```
class IOSurfaceRenderer {

    let width: Int
    let height: Int

    private let buildOwner: BuildOwner
    private let pipelineOwner: PipelineOwner
    private let renderView: RenderView
    private var rootElement: RenderObjectToWidgetElement?

    private var timer: Timer?
    private let surface: IOSurface
    private var isFirstFrame: Bool = true

    // MARK: - Init

    init(width: Int, height: Int) {
        self.width = width
        self.height = height

        // Create IOSurface with BGRA pixel format
        let bytesPerElement = 4
        let bytesPerRow = width * bytesPerElement
        let allocSize = bytesPerRow * height

        var properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: bytesPerElement,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: UInt32(kCVPixelFormatType_32BGRA),
            .allocSize: allocSize,
        ]
        // Mark as globally visible so other processes can look it up by ID.
        // kIOSurfaceIsGlobal is deprecated but still functional on macOS 14+.
        let isGlobalKey = IOSurfacePropertyKey(rawValue: "IOSurfaceIsGlobal")
        properties[isGlobalKey] = true
        surface = IOSurface(properties: properties as [IOSurfacePropertyKey: Any])!

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
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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

        // Rasterize to Image
        guard let image = picture.toImageSync(width: width, height: height)
        else { return }

        // Get raw RGBA bytes
        guard let rgbaData = try? image.toByteData(format: .rawRgba) else {
            image.dispose()
            return
        }
        image.dispose()

        // Write BGRA pixels to IOSurface
        surface.lock(options: [], seed: nil)

        let baseAddress = surface.baseAddress
        let pixelCount = width * height
        rgbaData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            let srcPtr = src.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
            let dstPtr = baseAddress.bindMemory(to: UInt8.self, capacity: pixelCount * 4)
            for i in 0..<pixelCount {
                let si = i * 4
                dstPtr[si + 0] = srcPtr[si + 2]  // B <- R
                dstPtr[si + 1] = srcPtr[si + 1]  // G <- G
                dstPtr[si + 2] = srcPtr[si + 0]  // R <- B
                dstPtr[si + 3] = srcPtr[si + 3]  // A <- A
            }
        }

        surface.unlock(options: [], seed: nil)

        // IPC: signal parent process via stdout
        if isFirstFrame {
            let surfaceId = IOSurfaceGetID(unsafeBitCast(surface, to: IOSurfaceRef.self))
            print("SURFACE:\(surfaceId):\(width):\(height)")
            isFirstFrame = false
        } else {
            print("F")
        }
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
