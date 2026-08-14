// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import Foundation
import Glibc

/// Runs an independent Flutter widget tree offscreen, rasterizes its output,
/// and writes pixels to a POSIX shared memory segment for cross-process
/// compositing.
///
/// This is the Linux equivalent of `IOSurfaceRenderer` (macOS). Instead of
/// IOSurface, it uses `shm_open` + `mmap` for cross-process pixel sharing.
///
/// The parent process opens the same shm segment read-only, reads pixel data
/// on each `F` signal, and uploads to a GL texture via `LinuxTextureRegistry`.
///
/// Usage:
/// ```swift
/// let renderer = ShmRenderer(width: 640, height: 480)
/// renderer.mountWidget { MyWidget() }
/// renderer.start(fps: 30)
/// ```
class ShmRenderer {

    let width: Int
    let height: Int

    private let buildOwner: BuildOwner
    private let pipelineOwner: PipelineOwner
    private let renderView: RenderView
    private var rootElement: RenderObjectToWidgetElement?

    private var timer: Timer?
    private var isFirstFrame: Bool = true

    // Shared memory
    private let shmName: String
    private let shmFd: Int32
    private let shmSize: Int
    private let shmPtr: UnsafeMutableRawPointer

    // MARK: - Init

    init(width: Int, height: Int) {
        self.width = width
        self.height = height

        // Create POSIX shared memory segment
        let pid = getpid()
        shmName = "/flutter_surface_\(pid)"
        let bytesPerPixel = 4
        shmSize = width * height * bytesPerPixel

        // O_CREAT | O_RDWR, mode 0666
        let fd = shm_open(shmName, O_CREAT | O_RDWR, 0o666)
        guard fd >= 0 else {
            fatalError("[ShmRenderer] shm_open failed: \(String(cString: strerror(errno)))")
        }
        shmFd = fd

        // Set size
        guard ftruncate(fd, off_t(shmSize)) == 0 else {
            fatalError("[ShmRenderer] ftruncate failed: \(String(cString: strerror(errno)))")
        }

        // mmap read-write
        guard let ptr = mmap(nil, shmSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              ptr != MAP_FAILED else {
            fatalError("[ShmRenderer] mmap failed: \(String(cString: strerror(errno)))")
        }
        shmPtr = ptr

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

    deinit {
        stop()
        munmap(shmPtr, shmSize)
        close(shmFd)
        shm_unlink(shmName)
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

        // Write RGBA pixels directly to shared memory (no BGRA swizzle —
        // Linux GL uses RGBA natively, LinuxTextureRegistry expects RGBA)
        rgbaData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            memcpy(shmPtr, src, shmSize)
        }

        // IPC: signal parent process via stdout.
        // Use write() syscall directly — unbuffered, works when stdout is a pipe.
        // Swift print() is fully buffered when stdout is a pipe.
        if isFirstFrame {
            let msg = "SURFACE:\(shmName):\(width):\(height)\n"
            msg.utf8.withContiguousStorageIfAvailable { buf in
                _ = Glibc.write(STDOUT_FILENO, buf.baseAddress, buf.count)
            }
            isFirstFrame = false
        } else {
            _ = Glibc.write(STDOUT_FILENO, "F\n", 2)
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
