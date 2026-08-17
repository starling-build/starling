// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import DmaBufBridge
import Foundation
import Glibc

/// Renders a Flutter widget tree offscreen and writes pixels to a GBM buffer
/// object (GPU memory) for cross-process compositing via DMA-BUF.
///
/// This replaces `ShmRenderer` when DMA-BUF is available. Instead of POSIX
/// shared memory (3 CPU copies per frame), the parent imports the DMA-BUF fd
/// as an EGLImage for zero-copy GPU texture sharing.
///
/// Fallback: If GBM BO creation fails (e.g., VMware driver), returns nil from
/// init so the caller can fall back to ShmRenderer.
class DmaBufRenderer {

    let width: Int
    let height: Int

    private let buildOwner: BuildOwner
    private let pipelineOwner: PipelineOwner
    private let renderView: RenderView
    private var rootElement: RenderObjectToWidgetElement?

    private var timer: Timer?

    // GBM state
    private let renderFd: Int32
    private let gbmDevice: OpaquePointer          // gbm_device*
    private let gbmBo: OpaquePointer              // gbm_bo*
    private let dmaFd: Int32                      // DMA-BUF fd from gbm_bo_get_fd
    private let stride: Int32                     // Row stride in bytes

    // Socket to parent
    private let socketFd: Int32

    // MARK: - Init

    /// Creates a DmaBufRenderer. Returns nil if GBM setup fails (caller should
    /// fall back to ShmRenderer).
    init?(width: Int, height: Int, socketPath: String) {
        self.width = width
        self.height = height

        // 1. Open render node (no root needed)
        let fd = Glibc.open("/dev/dri/renderD128", O_RDWR)
        guard fd >= 0 else {
            print("[DmaBufRenderer] Cannot open /dev/dri/renderD128: \(String(cString: strerror(errno)))")
            return nil
        }
        renderFd = fd

        // 2. Create GBM device
        guard let dev = gbm_create_device(fd) else {
            print("[DmaBufRenderer] gbm_create_device failed")
            Glibc.close(fd)
            return nil
        }
        gbmDevice = dev

        // 3. Create GBM buffer object
        // GBM_FORMAT_ABGR8888 = __gbm_fourcc_code('A', 'B', '2', '4') = 0x34324241
        // Matches Skia's RGBA byte order.
        let formatABGR8888: UInt32 = 0x34324241
        // GBM_BO_USE_LINEAR = (1 << 4), GBM_BO_USE_RENDERING = (1 << 2)
        let useFlags = GBM_BO_USE_LINEAR.rawValue | GBM_BO_USE_RENDERING.rawValue
        guard let bo = gbm_bo_create(dev, UInt32(width), UInt32(height),
                                     formatABGR8888, useFlags) else {
            print("[DmaBufRenderer] gbm_bo_create failed")
            gbm_device_destroy(dev)
            Glibc.close(fd)
            return nil
        }
        gbmBo = bo

        // 4. Get DMA-BUF fd and stride
        let dmaBufFd = gbm_bo_get_fd(bo)
        guard dmaBufFd >= 0 else {
            print("[DmaBufRenderer] gbm_bo_get_fd failed")
            gbm_bo_destroy(bo)
            gbm_device_destroy(dev)
            Glibc.close(fd)
            return nil
        }
        dmaFd = dmaBufFd
        stride = Int32(gbm_bo_get_stride(bo))

        // 5. Connect to parent's Unix domain socket
        let sock = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard sock >= 0 else {
            print("[DmaBufRenderer] socket() failed: \(String(cString: strerror(errno)))")
            Glibc.close(dmaBufFd)
            gbm_bo_destroy(bo)
            gbm_device_destroy(dev)
            Glibc.close(fd)
            return nil
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            let bound = pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                socketPath.withCString { src in
                    strncpy(buf, src, 107)
                    return true
                }
            }
            _ = bound
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Glibc.connect(sock, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            print("[DmaBufRenderer] connect(\(socketPath)) failed: \(String(cString: strerror(errno)))")
            Glibc.close(sock)
            Glibc.close(dmaBufFd)
            gbm_bo_destroy(bo)
            gbm_device_destroy(dev)
            Glibc.close(fd)
            return nil
        }
        socketFd = sock

        // 6. Send DMA-BUF fd + metadata to parent
        var meta = DmaBufMeta(
            width: Int32(width),
            height: Int32(height),
            stride: stride,
            fourcc: formatABGR8888,
            flags: 0  // a real GBM buffer — never the CPU/memfd path
        )
        let sendResult = dmabuf_send_fd(sock, dmaBufFd, &meta,
                                        MemoryLayout<DmaBufMeta>.size)
        guard sendResult == 0 else {
            print("[DmaBufRenderer] Failed to send DMA-BUF fd to parent")
            Glibc.close(sock)
            Glibc.close(dmaBufFd)
            gbm_bo_destroy(bo)
            gbm_device_destroy(dev)
            Glibc.close(fd)
            return nil
        }

        print("[DmaBufRenderer] Connected to parent, sent DMA-BUF fd (stride=\(stride))")

        // Build rendering pipeline
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

        buildOwner.onBuildScheduled = {}
    }

    deinit {
        stop()
        Glibc.close(socketFd)
        Glibc.close(dmaFd)
        gbm_bo_destroy(gbmBo)
        gbm_device_destroy(gbmDevice)
        Glibc.close(renderFd)
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

        // Extract PictureLayer from layer tree
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

        // Map GBM BO and copy pixels
        var mapData: UnsafeMutableRawPointer? = nil
        var mapStride: UInt32 = 0
        guard let mapped = gbm_bo_map(gbmBo, 0, 0, UInt32(width), UInt32(height),
                                      GBM_BO_TRANSFER_WRITE.rawValue,
                                      &mapStride, &mapData) else {
            return
        }

        // Copy row-by-row respecting stride
        rgbaData.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            let rowBytes = width * 4
            let srcStride = rowBytes
            let dstStride = Int(mapStride)
            for y in 0..<height {
                memcpy(mapped + y * dstStride, src + y * srcStride, rowBytes)
            }
        }

        gbm_bo_unmap(gbmBo, mapData)

        // Signal parent that a new frame is ready (single byte)
        var signal: UInt8 = 0x46  // 'F'
        _ = Glibc.write(socketFd, &signal, 1)
    }

    // MARK: - Layer Tree Traversal

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
