// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import DmaBufBridge
import FlutterDRMBridge
import Foundation
import Glibc

/// Stage B of the NVIDIA-view plan (docs/plans/nv-view.md): runs one
/// per-screen shell as a child process — rendering on its own GPU through
/// GpuDmaBufRenderer's swapchain — and feeds its frames to an externally
/// sourced engine output (fl_drm_view_push_external_frame) instead of a
/// composited window texture. Same socket protocol as
/// LinuxProcessAppManager's launches; deliberately separate from it
/// because nothing here is a window: no texture, no chrome, no dock
/// presence. Input forwarding and the recording tap are the next stages.
final class ExternalScreenShell: @unchecked Sendable {
    private let view: OpaquePointer
    private let outputId: UInt32
    private let logicalWidth: Int32
    private let logicalHeight: Int32
    private let scale: Double
    private let device: String
    private var process: Process?

    init(view: OpaquePointer, outputId: Int, logicalWidth: Int,
         logicalHeight: Int, scale: Double, device: String) {
        self.view = view
        self.outputId = UInt32(outputId)
        self.logicalWidth = Int32(logicalWidth)
        self.logicalHeight = Int32(logicalHeight)
        self.scale = scale
        self.device = device
    }

    func start() {
        Thread.detachNewThread { [self] in run() }
    }

    private func log(_ msg: String) {
        FileHandle.standardError.write(Data(
            "[ScreenShell out=\(outputId)] \(msg)\n".utf8))
    }

    private func run() {
        let sockPath = "/tmp/starling-screen-shell-\(getpid())-\(outputId).sock"
        unlink(sockPath)
        let listenFd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard listenFd >= 0 else {
            log("socket() failed: \(String(cString: strerror(errno)))")
            return
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                sockPath.withCString { _ = strncpy(buf, $0, 107) }
            }
        }
        let bound = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.bind(listenFd, $0, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listenFd, 1) == 0 else {
            log("bind/listen failed: \(String(cString: strerror(errno)))")
            Glibc.close(listenFd)
            return
        }

        let env0 = ProcessInfo.processInfo.environment
        let exe = (env0["FLUTTER_APPS_DIR"] ?? ".") + "/ScreenShellApp"
        var env = env0
        env["FLUTTER_DMABUF_SOCKET"] = sockPath
        env["STARLING_APP_DRM_DEVICE"] = device
        env["FLUTTER_DRM_DPI"] = String(scale)
        // Same scrub as LinuxProcessAppManager's children: the shell's own
        // GL selection must not leak into the child (zink cannot re-import
        // its own linear dma-buf).
        for k in ["MESA_LOADER_DRIVER_OVERRIDE", "GBM_BACKENDS_PATH",
                  "VK_ICD_FILENAMES", "LD_LIBRARY_PATH"] {
            env.removeValue(forKey: k)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.environment = env
        do {
            try p.run()
        } catch {
            log("spawn \(exe) failed: \(error)")
            Glibc.close(listenFd)
            return
        }
        process = p
        log("spawned \(exe) (pid \(p.processIdentifier)) on \(device)")

        let clientFd = accept(listenFd, nil, nil)
        Glibc.close(listenFd)
        guard clientFd >= 0 else {
            log("accept failed: \(String(cString: strerror(errno)))")
            return
        }

        var cfg = DmaBufConfigure(width: logicalWidth, height: logicalHeight,
                                  type: DMABUF_CONFIGURE, _reserved: 0)
        _ = withUnsafePointer(to: &cfg) {
            send(clientFd, $0, MemoryLayout<DmaBufConfigure>.size, 0)
        }

        // Every fd-carrying message is a swapchain front buffer; push it to
        // the external output (which dups) and close ours. Frame signals
        // ('F') carry no information the push didn't already.
        var buf = [UInt8](repeating: 0, count: 128)
        var frames = 0
        while true {
            var fd: Int32 = -1
            let n = dmabuf_recv_with_fd(clientFd, &buf, buf.count, &fd)
            if n <= 0 {
                log("child socket reader exiting: recv=\(n) errno=\(errno)")
                break
            }
            if fd >= 0 && n >= MemoryLayout<DmaBufMeta>.size {
                var meta = DmaBufMeta(width: 0, height: 0, stride: 0, fourcc: 0)
                memcpy(&meta, &buf, MemoryLayout<DmaBufMeta>.size)
                _ = fl_drm_view_push_external_frame(
                    view, outputId, fd, UInt32(meta.stride), 0,
                    meta.fourcc, 0)
                Glibc.close(fd)
                frames += 1
                if frames == 1 {
                    log("first frame (\(meta.width)x\(meta.height) " +
                        "fourcc=0x\(String(meta.fourcc, radix: 16)))")
                }
            }
        }
        Glibc.close(clientFd)
    }
}
