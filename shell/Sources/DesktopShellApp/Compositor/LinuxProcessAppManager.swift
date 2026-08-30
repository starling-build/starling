// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import FlutterEmbedderBridge
import DmaBufBridge
import Flutter
import FlutterSwiftBridge
import Foundation
import Glibc

/// Thread-safe mutable box for sharing state across threads.
private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    init(_ value: T) { self._value = value }

    /// Atomic read-modify-write. Producers MUST use this (not get+set,
    /// which is two lock acquisitions and loses concurrent updates —
    /// every child's socket-reader thread appends to these boxes).
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&_value)
    }

    /// Atomically take the current value, leaving `empty` behind — the
    /// drain side of the producer/consumer queues in tick().
    func take(_ empty: T) -> T {
        lock.lock(); defer { lock.unlock() }
        let v = _value
        _value = empty
        return v
    }
}

/// The connected child socket, shared between its reader thread and the
/// platform thread. The reader is the ONLY closer; every other touch goes
/// through the same lock, and close invalidates the fd under that lock —
/// so once the kernel recycles the number, nothing here can reach the
/// stranger now holding it. destroyApp used to close this fd directly
/// while the reader thread still owned it: the second close landed on
/// whatever the number had become — once, the portal picker's stdout
/// pipe, whose EBADF Foundation's internal `try!` turned into a shell
/// abort. destroyApp gets shutdown() instead, which unblocks the reader's
/// recv with EOF (a close from another thread does not) and frees nothing.
private final class ChildSocket: @unchecked Sendable {
    private let box: AtomicBox<Int32>

    init(adopting fd: Int32) { box = AtomicBox(fd) }

    /// Platform thread: send one message. Silently dropped once the
    /// socket is gone — the child is exiting, there is no one to tell.
    func write(_ buf: UnsafeRawPointer, _ count: Int) {
        box.withLock { fd in
            guard fd >= 0 else { return }
            _ = Glibc.write(fd, buf, count)
        }
    }

    /// Platform thread (destroyApp): wake the reader out of its blocked
    /// recv so it can perform the one true close.
    func shutdown() {
        box.withLock { fd in
            guard fd >= 0 else { return }
            _ = Glibc.shutdown(fd, Int32(SHUT_RDWR))
        }
    }

    /// Reader thread only, at loop exit.
    func close() {
        box.withLock { fd in
            guard fd >= 0 else { return }
            _ = Glibc.close(fd)
            fd = -1
        }
    }
}

/// Pending DMA-BUF resize — child sent a new fd + metadata after resizing.
private struct PendingDmaBufResize: @unchecked Sendable {
    let textureId: Int64
    let dmaFd: Int32
    let width: Int
    let height: Int
    let stride: Int
    let fourcc: UInt32
    /// The child's DMABUF_META_FLAG_* bits. Carried because a CPU child's
    /// "fd" is a memfd, not a DMA-BUF, and the two are re-adopted in
    /// completely different ways — dropping this is what left a resized CPU
    /// child mapped at its old size.
    let flags: UInt32
}

/// Pending DMA-BUF launch result — zero-copy path via Unix socket + SCM_RIGHTS.
private struct PendingDmaBufLaunch: @unchecked Sendable {
    let pid: pid_t
    let sock: ChildSocket         // connected client socket for frame signals
    let dmaFd: Int32              // DMA-BUF fd, or a memfd when `cpu`
    let width: Int
    let height: Int
    let stride: Int
    let fourcc: UInt32
    /// The child had no DRM device and sent linear pixels in a memfd
    /// instead. Its frames are mapped and uploaded rather than imported.
    let cpu: Bool
    let onReady: (Int64) -> Void
    let onTerminated: () -> Void
    let launchState: AtomicBox<(texId: Int64, earlyFrame: Bool)>
}

/// Manages child processes that render via DMA-BUF for zero-copy cross-process
/// compositing into the desktop shell via the embedder's texture registry.
///
/// **DRM mode compatibility:** Does not use `DispatchQueue.main.async` (which
/// never fires when the main thread runs the C++ epoll loop). Instead,
/// socket accepting happens on a background GCD thread, and the results
/// are consumed via `tick()` called from the vsync frame callback.
class LinuxProcessAppManager {

    private let engine: OpaquePointer
    private let textureRegistry: LinuxTextureRegistry

    /// Active process apps keyed by their texture ID.
    private var apps: [Int64: ProcessAppEntry] = [:]

    /// Pending DMA-BUF launch results from background socket-accepting threads.
    private let pendingDmaBufLaunches = AtomicBox<[PendingDmaBufLaunch]>([])

    /// Pending DMA-BUF frame signals (texture IDs — no pixel copy needed).
    private let pendingDmaBufFrames = AtomicBox<[Int64]>([])
    private var cpuFrameLogged = 0

    /// Pending DMA-BUF resizes from child processes.
    private let pendingDmaBufResizes = AtomicBox<[PendingDmaBufResize]>([])

    /// Pending termination callbacks.
    private let pendingTerminations = AtomicBox<[() -> Void]>([])

    /// Pending DPI change requests from child processes.
    private let pendingDpiChanges = AtomicBox<[Double]>([])

    /// Callback invoked on platform thread when a child requests a DPI change.
    var onDpiChangeRequested: ((Double) -> Void)?

    /// Pending appearance change requests (true = dark) from child processes.
    private let pendingThemeChanges = AtomicBox<[Bool]>([])

    /// Callback invoked on platform thread when a child requests an
    /// appearance change (Settings' Dark Mode toggle).
    var onThemeChangeRequested: ((Bool) -> Void)?

    /// Fired on the platform thread from tick() when a child (SettingsApp's
    /// Tiling toggle) asks to switch the window-manager layout.
    var onLayoutChangeRequested: ((Bool) -> Void)?

    /// The shell's current layout, pushed to children at connect so the
    /// Settings toggle reflects reality (kept in sync by _setTiling).
    nonisolated(unsafe) var currentLayoutIsTiling: Bool = false
    /// The active style's index in the shell's registry, mirrored here so a
    /// child that connects later inherits it like every other desktop-wide
    /// setting.
    nonisolated(unsafe) var currentStyleIndex: Int = 0

    private let pendingLayoutRequests = AtomicBox<[Bool]>([])

    /// Fired on the platform thread when a child (SettingsApp's wallpaper
    /// picker) asks to switch the desktop wallpaper preset.
    var onWallpaperChangeRequested: ((Int) -> Void)?
    var onStyleChangeRequested: ((Int) -> Void)?

    /// The shell's current wallpaper preset raw value, pushed to children at
    /// connect so the Settings picker reflects reality (kept in sync by
    /// _setWallpaper).
    nonisolated(unsafe) var currentWallpaper: Int = 0

    private let pendingWallpaperRequests = AtomicBox<[Int]>([])
    private let pendingStyleRequests = AtomicBox<[Int]>([])

    /// Fired on the platform thread when a child (SettingsApp's Screensaver
    /// picker) asks to change the idle timeout. Seconds; 0 = never.
    var onScreensaverChangeRequested: ((Int) -> Void)?

    /// The shell's current screensaver idle timeout in seconds, pushed to
    /// children at connect so the Settings picker reflects reality (kept in
    /// sync by _setScreensaverIdle).
    nonisolated(unsafe) var currentScreensaverIdle: Int =
        Int(_DesktopShellState.kDefaultIdleSeconds)

    private let pendingScreensaverRequests = AtomicBox<[Int]>([])

    /// Fired on the platform thread when a child (SettingsApp's Sharing
    /// pane) asks to turn remote desktop on or off.
    var onRdpChangeRequested: ((Bool) -> Void)?

    /// Remote desktop as the shell last settled it, pushed to children at
    /// connect and re-broadcast on every change (kept in sync by
    /// `broadcastRdp`).
    nonisolated(unsafe) var currentRdpEnabled: Bool = false

    private let pendingRdpRequests = AtomicBox<[Bool]>([])

    /// Fired on the platform thread when a child (SettingsApp's Displays pane)
    /// asks to make an output the primary display.
    var onPrimaryDisplayChangeRequested: ((Int) -> Void)?

    /// The connected displays as the shell sees them, pushed to children at
    /// connect and re-broadcast whenever the arrangement changes (hotplug, a
    /// new primary). Kept in sync by `broadcastDisplays`.
    nonisolated(unsafe) var currentDisplays: [ChildDisplay] = []

    /// What a child is told about one display. The shell's `DisplayOutput`
    /// minus everything a child has no business acting on (origins, which
    /// output hosts the shell's own view).
    struct ChildDisplay: Equatable {
        var id: Int
        var name: String
        var physicalWidth: Int
        var physicalHeight: Int
        var scale: Double
        var isPrimary: Bool
    }

    private let pendingPrimaryDisplayRequests = AtomicBox<[Int]>([])

    /// Pending caret reports from child processes (textureId, x, y, width,
    /// height in the child's logical content coords, visible).
    private let pendingCaretUpdates =
        AtomicBox<[(Int64, Double, Double, Double, Double, Bool)]>([])

    /// Fired when a child reports its text caret — drives the shell's IME
    /// candidate panel placement.
    var onCaretChanged: ((_ textureId: Int64, _ x: Double, _ y: Double,
                          _ width: Double, _ height: Double,
                          _ visible: Bool) -> Void)?

    /// One-shot callbacks fired when the first DMA-BUF frame arrives for a texture.
    private var firstFrameCallbacks: [Int64: () -> Void] = [:]

    /// Broker hook (Murmuration): invoked for every child frame signal with
    /// the texture id — the raw material for await_settled's frame-quiet
    /// detection. Called from tick().
    var onChildFrame: ((Int64) -> Void)?

    /// The current DMA-BUF backing a child's texture, for CPU readback
    /// (per-window capture). Children render into linear buffers, so the
    /// broker can mmap the fd directly. Returns nil for unknown textures.
    func dmaBufInfo(textureId: Int64) -> (fd: Int32, width: Int, height: Int, stride: Int, fourcc: UInt32)? {
        guard let entry = apps[textureId], entry.dmaFd >= 0 else { return nil }
        return (entry.dmaFd, entry.width, entry.height, entry.dmaBufStride, entry.dmaBufFourcc)
    }

    /// Register a callback to fire when the first frame arrives for this texture.
    func onFirstFrame(textureId: Int64, callback: @escaping () -> Void) {
        firstFrameCallbacks[textureId] = callback
    }

    init(engine: OpaquePointer, textureRegistry: LinuxTextureRegistry) {
        self.engine = engine
        self.textureRegistry = textureRegistry
    }

    /// Processes pending events from background threads.
    /// Must be called from the platform thread (e.g., from vsync frame callback
    /// via FrameCallbackScheduler).
    func tick() {
        // Process pending DMA-BUF launches
        let dmaBufLaunches = pendingDmaBufLaunches.take([])
        if !dmaBufLaunches.isEmpty {
            for launch in dmaBufLaunches {
                let texId = textureRegistry.registerTexture(engine: engine)
                let earlyFrame = launch.launchState.withLock {
                    (s: inout (texId: Int64, earlyFrame: Bool)) -> Bool in
                    s.texId = texId
                    return s.earlyFrame
                }

                var entry = ProcessAppEntry(
                    pid: launch.pid,
                    textureId: texId,
                    width: launch.width,
                    height: launch.height,
                    onTerminated: launch.onTerminated,
                    dmaFd: launch.dmaFd,
                    sock: launch.sock,
                    dmaBufStride: launch.stride,
                    dmaBufFourcc: launch.fourcc
                )
                apps[texId] = entry

                // Newly connected child inherits the current desktop
                // appearance (further switches arrive via broadcastTheme).
                sendTheme(textureId: texId, dark: shellTheme.isDark)
                sendStyle(textureId: texId, index: currentStyleIndex)
                sendLayout(textureId: texId, tiling: currentLayoutIsTiling)
                sendWallpaper(textureId: texId, preset: currentWallpaper)
                sendScreensaver(textureId: texId, seconds: currentScreensaverIdle)
                sendRdp(textureId: texId)
                sendDisplays(textureId: texId)

                if launch.cpu {
                    // No DRM device on the child's side: its frames arrive
                    // as linear pixels in a memfd. Map it once — the child
                    // renders into the same buffer for its whole life — and
                    // upload on each frame signal below.
                    let size = launch.stride * launch.height
                    let map = mmap(nil, size, PROT_READ, MAP_SHARED,
                                   launch.dmaFd, 0)
                    if map == MAP_FAILED {
                        FileHandle.standardError.write(Data(
                            "[ProcessApp] mmap of child memfd failed: \(errno)\n".utf8))
                    } else {
                        entry.cpuMap = map
                        entry.cpuMapSize = size
                        apps[texId] = entry
                    }
                } else {
                    // Import DMA-BUF as EGLImage → GL texture (zero-copy)
                    textureRegistry.importDmaBuf(
                        engine: engine,
                        id: texId,
                        fd: launch.dmaFd,
                        width: launch.width,
                        height: launch.height,
                        stride: launch.stride,
                        fourcc: launch.fourcc
                    )
                }

                launch.onReady(texId)

                // The child signaled its first frame before the texture was
                // registered — deliver it now or the window never appears.
                if earlyFrame {
                    FlutterEngineMarkExternalTextureFrameAvailable(engine, texId)
                    if let cb = firstFrameCallbacks.removeValue(forKey: texId) {
                        cb()
                    }
                    onChildFrame?(texId)
                    FrameCallbackScheduler.shared.noteTextureUpdate(texId)
                }
            }
        }

        // Process pending DMA-BUF resizes (child sent new fd after buffer resize)
        let dmaBufResizes = pendingDmaBufResizes.take([])
        if !dmaBufResizes.isEmpty {
            for resize in dmaBufResizes {
                guard var entry = apps[resize.textureId] else {
                    Glibc.close(resize.dmaFd)
                    continue
                }
                if entry.dmaFd >= 0 {
                    Glibc.close(entry.dmaFd)
                }
                entry.dmaFd = resize.dmaFd
                entry.width = resize.width
                entry.height = resize.height
                entry.dmaBufStride = resize.stride
                entry.dmaBufFourcc = resize.fourcc

                // A CPU child (no DRM device — WSL, and any headless box)
                // sends a memfd, not a DMA-BUF: it cannot be imported as an
                // EGLImage, and the mapping we upload from every frame is
                // the old, smaller one. Re-map before anything reads at the
                // new size, or the per-frame upload runs off the end of the
                // old buffer.
                let isCpuChild = entry.cpuMap != nil
                    || (resize.flags & UInt32(DMABUF_META_FLAG_CPU)) != 0
                if isCpuChild {
                    if let oldMap = entry.cpuMap, entry.cpuMapSize > 0 {
                        munmap(oldMap, entry.cpuMapSize)
                    }
                    entry.cpuMap = nil
                    entry.cpuMapSize = 0
                    let size = resize.stride * resize.height
                    let map = mmap(nil, size, PROT_READ, MAP_SHARED,
                                   resize.dmaFd, 0)
                    if map == MAP_FAILED {
                        FileHandle.standardError.write(Data(
                            "[ProcessApp] resize: mmap of child memfd failed: \(errno)\n".utf8))
                    } else {
                        entry.cpuMap = map
                        entry.cpuMapSize = size
                    }
                    apps[resize.textureId] = entry
                    FileHandle.standardError.write(Data(
                        "[ProcessApp] cpu resize tex=\(resize.textureId) -> \(resize.width)x\(resize.height) stride=\(resize.stride) mapped=\(entry.cpuMapSize)\n".utf8))
                    cpuFrameLogged = 0   // log the next few frames' dimensions
                    continue
                }

                apps[resize.textureId] = entry

                textureRegistry.reimportDmaBuf(
                    engine: engine,
                    id: resize.textureId,
                    fd: resize.dmaFd,
                    width: resize.width,
                    height: resize.height,
                    stride: resize.stride,
                    fourcc: resize.fourcc
                )
            }
        }

        // Process pending DMA-BUF frame signals (zero-copy — just mark dirty).
        let dmaBufFrameTexIds = pendingDmaBufFrames.take([])
        if !dmaBufFrameTexIds.isEmpty {
            for texId in dmaBufFrameTexIds {
                // A CPU child's pixels are only in its memfd; the texture
                // has to be re-uploaded from the mapping every frame. (The
                // dma-buf path imports once and the GPU sees the writes.)
                if let e = apps[texId], let map = e.cpuMap {
                    cpuFrameLogged += 1
                    if cpuFrameLogged <= 3 {
                        FileHandle.standardError.write(Data(
                            "[ProcessApp] CPU frame #\(cpuFrameLogged) tex=\(texId) \(e.width)x\(e.height)\n".utf8))
                    }
                    textureRegistry.updatePixelData(
                        engine: engine, id: texId, data: map,
                        width: e.width, height: e.height)
                } else if apps[texId] != nil, cpuFrameLogged == 0 {
                    cpuFrameLogged = -1
                    FileHandle.standardError.write(Data(
                        "[ProcessApp] frame for tex=\(texId) but no cpuMap (dma-buf app)\n".utf8))
                }
                FlutterEngineMarkExternalTextureFrameAvailable(engine, texId)
                if let cb = firstFrameCallbacks.removeValue(forKey: texId) {
                    cb()
                }
                onChildFrame?(texId)
                FrameCallbackScheduler.shared.noteTextureUpdate(texId)
            }
        }

        // Process pending DPI changes from child processes
        let dpiChanges = pendingDpiChanges.take([])
        if !dpiChanges.isEmpty {
            if let lastDpi = dpiChanges.last {
                onDpiChangeRequested?(lastDpi)
            }
        }

        // Process pending appearance changes from child processes
        let layoutRequests = pendingLayoutRequests.take([])
        if !layoutRequests.isEmpty {
            if let lastTiling = layoutRequests.last {
                onLayoutChangeRequested?(lastTiling)
            }
        }

        let themeChanges = pendingThemeChanges.take([])
        if !themeChanges.isEmpty {
            if let lastDark = themeChanges.last {
                onThemeChangeRequested?(lastDark)
            }
        }

        let wallpaperRequests = pendingWallpaperRequests.take([])
        if !wallpaperRequests.isEmpty {
            if let lastPreset = wallpaperRequests.last {
                onWallpaperChangeRequested?(lastPreset)
            }
        }

        let styleRequests = pendingStyleRequests.take([])
        if !styleRequests.isEmpty {
            if let lastStyle = styleRequests.last {
                onStyleChangeRequested?(lastStyle)
            }
        }

        let screensaverRequests = pendingScreensaverRequests.take([])
        if !screensaverRequests.isEmpty {
            if let lastIdle = screensaverRequests.last {
                onScreensaverChangeRequested?(lastIdle)
            }
        }

        let primaryDisplayRequests = pendingPrimaryDisplayRequests.take([])
        if !primaryDisplayRequests.isEmpty {
            if let lastOutputId = primaryDisplayRequests.last {
                onPrimaryDisplayChangeRequested?(lastOutputId)
            }
        }

        let rdpRequests = pendingRdpRequests.take([])
        if !rdpRequests.isEmpty {
            if let lastEnabled = rdpRequests.last {
                onRdpChangeRequested?(lastEnabled)
            }
        }

        // Process pending caret reports (IME panel placement)
        let caretUpdates = pendingCaretUpdates.take([])
        if !caretUpdates.isEmpty {
            for u in caretUpdates {
                onCaretChanged?(u.0, u.1, u.2, u.3, u.4, u.5)
            }
        }

        // Process pending terminations
        let terminations = pendingTerminations.take([])
        if !terminations.isEmpty {
            for callback in terminations {
                callback()
            }
        }
    }

    /// Resolves the on-disk path to a child-app executable by name.
    ///
    /// Each child app (SettingsApp, FileExplorerApp, …) is now its own SwiftPM
    /// package, so its binary is no longer colocated with DesktopShellApp the way
    /// it was when they were all products of one package. Search, in order:
    ///   1. `$FLUTTER_APPS_DIR/<name>` — explicit staging/deploy directory.
    ///   2. `<self dir>/<name>` — colocated sibling (deployed / staged layout).
    ///   3. Walking up from the binary, `<dir>/<name>/.build/<config>/<name>` —
    ///      the sibling package's SwiftPM dev build (e.g. `apps/SettingsApp/
    ///      .build/debug/SettingsApp`). `.build/<config>` is a symlink SwiftPM
    ///      maintains to the arch-triple build dir.
    /// Returns the first existing path, or nil if none is found.
    static func resolveAppExecutable(_ executableName: String) -> String? {
        let fm = FileManager.default

        // 1. Explicit override / deploy staging directory.
        if let appsDir = ProcessInfo.processInfo.environment["FLUTTER_APPS_DIR"] {
            let p = appsDir + "/" + executableName
            if fm.fileExists(atPath: p) { return p }
        }

        guard let real = realpath("/proc/self/exe", nil) else { return nil }
        defer { free(real) }
        let selfPath = String(cString: real)
        let selfDir = (selfPath as NSString).deletingLastPathComponent

        // 2. Colocated sibling (staged / deployed layout).
        let colocated = selfDir + "/" + executableName
        if fm.fileExists(atPath: colocated) { return colocated }

        // 3. Sibling SwiftPM package dev build. `selfDir` ends in the build
        //    config (`debug`/`release`); mirror it for the sibling package.
        let config = (selfDir as NSString).lastPathComponent
        var dir = selfDir
        for _ in 0..<8 {
            let candidate = "\(dir)/\(executableName)/.build/\(config)/\(executableName)"
            if fm.fileExists(atPath: candidate) { return candidate }
            // Repo layout: apps live under <repo>/apps/, the shell under
            // <repo>/shell/ — so from the shell binary the sibling packages
            // sit one directory over.
            let nested = "\(dir)/apps/\(executableName)/.build/\(config)/\(executableName)"
            if fm.fileExists(atPath: nested) { return nested }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }

        return nil
    }

    /// Launches a child process using DMA-BUF for zero-copy GPU buffer sharing.
    /// Creates a Unix domain socket, passes its path to the child via environment,
    /// and receives the DMA-BUF fd via SCM_RIGHTS.
    ///
    /// Returns `true` if the child process was spawned (in which case exactly one
    /// of `onReady`/`onTerminated` will eventually fire), or `false` if the launch
    /// could not even be started (executable missing, socket setup failed) — in
    /// which case neither callback fires and the caller must clean up itself.
    @discardableResult
    func launchDmaBufApp(
        executableName: String,
        contentWidth: Int? = nil,
        contentHeight: Int? = nil,
        extraArgs: [String] = [],
        extraEnv: [String: String] = [:],
        onExit: ((_ stdout: String, _ exitStatus: Int32) -> Void)? = nil,
        onReady: @escaping (Int64) -> Void,
        onTerminated: @escaping () -> Void
    ) -> Bool {
        guard let siblingPath = Self.resolveAppExecutable(executableName) else {
            FileHandle.standardError.write(Data((
                "DesktopShell: cannot launch child app '\(executableName)': " +
                "executable not found. Build it (cd apps/\(executableName) && " +
                "swift build) or set FLUTTER_APPS_DIR to a directory containing it.\n"
            ).utf8))
            return false
        }

        // Create Unix domain socket
        let pid = getpid()
        let socketPath = "/tmp/flutter_dmabuf_\(pid)_\(nextSocketId).sock"
        nextSocketId += 1

        unlink(socketPath)

        // SOCK_CLOEXEC on the shell's own fds: every app spawned later
        // inherits anything here that lacks it, and a stray copy of one
        // child's channel in another child outlives the first.
        let listenSock = socket(AF_UNIX,
                                Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard listenSock >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                socketPath.withCString { src in
                    strncpy(buf, src, 107)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenSock, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Glibc.close(listenSock)
            return false
        }

        guard listen(listenSock, 1) == 0 else {
            Glibc.close(listenSock)
            unlink(socketPath)
            return false
        }

        // Launch child with FLUTTER_DMABUF_SOCKET env var.
        //
        // posix_spawn + a blocking waitpid thread, NOT Foundation.Process:
        // Process watches for exit through a socketpair whose child end
        // survives exec, so every descendant the app forks inherits it — and
        // one descendant that outlives the app (a `setsid`/`nohup` job in
        // the terminal, a daemon) held it open, the EOF never came, and
        // Foundation neither reaped the child nor ran terminationHandler.
        // The app sat in the process table as a zombie, onTerminated never
        // fired, and the dock spent the rest of the session focusing a dead
        // window (relaunch impossible: the launcher saw the app "running").
        // waitpid reports the child's death itself, which no descendant can
        // postpone.
        var env = ProcessInfo.processInfo.environment
        env["FLUTTER_DMABUF_SOCKET"] = socketPath
        // The system clipboard: the SDK connects back as a data-control client
        // so a copy here pastes into Chrome. Deliberately NOT WAYLAND_DISPLAY —
        // that name would tell toolkits linked into the app to switch to a
        // Wayland backend instead of rendering through the dma-buf socket. The
        // socket name is dynamic (an unclean exit leaves wayland-0.lock behind
        // and the next run listens on wayland-1), so it must be read from the
        // live server rather than assumed.
        if let socketName = waylandIntegration?.socketName, !socketName.isEmpty {
            env["STARLING_WAYLAND_DISPLAY"] = socketName
        }
        for (k, v) in extraEnv { env[k] = v }
        // Host-GL dev mode (tools/run-shell-gpu.sh sets the flag): the shell
        // renders on Starling's own Mesa (zink), but child apps must use the
        // host GL stack — zink's GBM/EGL combo fails to re-import its own
        // linear dma-buf (eglCreateImageKHR EGL_BAD_ALLOC), while host-Mesa
        // buffers import into the shell's zink display fine.
        if env["STARLING_CHILD_HOST_GL"] != nil {
            for key in ["MESA_LOADER_DRIVER_OVERRIDE", "GBM_BACKENDS_PATH",
                        "VK_ICD_FILENAMES", "LD_LIBRARY_PATH"] {
                env.removeValue(forKey: key)
            }
        }

        // Capture stdout only for callers that asked for it (the portal
        // picker reads the child's selection from it). Everyone else
        // inherits the shell's stdout: a pipe nobody drains blocks the
        // child's first print after 64 KB.
        var stdoutPipe: [Int32] = [-1, -1]
        if onExit != nil {
            guard pipe(&stdoutPipe) == 0 else {
                Glibc.close(listenSock)
                unlink(socketPath)
                return false
            }
            _ = fcntl(stdoutPipe[0], F_SETFD, FD_CLOEXEC)
            _ = fcntl(stdoutPipe[1], F_SETFD, FD_CLOEXEC)
        }

        var fileActions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&fileActions)
        if stdoutPipe[1] >= 0 {
            // dup2 clears CLOEXEC on the child's copy; the parent-side flag
            // above keeps the ends out of every OTHER child.
            posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], 1)
        }
        var argvC: [UnsafeMutablePointer<CChar>?] = [strdup(siblingPath)]
        for arg in extraArgs { argvC.append(strdup(arg)) }
        argvC.append(nil)
        var envpC: [UnsafeMutablePointer<CChar>?] =
            env.map { strdup("\($0.key)=\($0.value)") }
        envpC.append(nil)
        var childPid: pid_t = 0
        let spawnRc = posix_spawn(&childPid, siblingPath, &fileActions, nil,
                                  &argvC, &envpC)
        posix_spawn_file_actions_destroy(&fileActions)
        argvC.forEach { free($0) }
        envpC.forEach { free($0) }
        // The write end now lives in the child as its stdout; the parent's
        // copy must go, or the pipe never reads EOF.
        if stdoutPipe[1] >= 0 { Glibc.close(stdoutPipe[1]) }
        guard spawnRc == 0 else {
            if stdoutPipe[0] >= 0 { Glibc.close(stdoutPipe[0]) }
            Glibc.close(listenSock)
            unlink(socketPath)
            return false
        }
        let spawnedPid = childPid

        let launchState = AtomicBox<(texId: Int64, earlyFrame: Bool)>((0, false))
        let pendingDmaBufLaunches = self.pendingDmaBufLaunches
        let pendingDmaBufFrames = self.pendingDmaBufFrames
        let pendingDmaBufResizes = self.pendingDmaBufResizes
        let pendingDpiChanges = self.pendingDpiChanges
        let pendingThemeChanges = self.pendingThemeChanges
        let pendingLayoutRequests = self.pendingLayoutRequests
        let pendingWallpaperRequests = self.pendingWallpaperRequests
        let pendingStyleRequests = self.pendingStyleRequests
        let pendingScreensaverRequests = self.pendingScreensaverRequests
        let pendingPrimaryDisplayRequests = self.pendingPrimaryDisplayRequests
        let pendingRdpRequests = self.pendingRdpRequests
        let pendingCaretUpdates = self.pendingCaretUpdates
        let pendingTerminations = self.pendingTerminations
        let capturedEngine = unsafeBitCast(engine, to: Int.self)

        let sendableOnReady = unsafeBitCast(onReady, to: (@Sendable (Int64) -> Void).self)
        let sendableOnTerminated = unsafeBitCast(onTerminated, to: (@Sendable () -> Void).self)

        let capturedSocketPath = socketPath
        let capturedListenSock = listenSock

        // Accept connection on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let clientSock = accept(capturedListenSock, nil, nil)
            Glibc.close(capturedListenSock)
            unlink(capturedSocketPath)

            guard clientSock >= 0 else { return }
            _ = fcntl(clientSock, F_SETFD, FD_CLOEXEC)

            // Send configure message with content area dimensions
            if let w = contentWidth, let h = contentHeight {
                var configure = DmaBufConfigure(
                    width: Int32(w), height: Int32(h),
                    type: DMABUF_CONFIGURE, _reserved: 0
                )
                _ = withUnsafePointer(to: &configure) { ptr in
                    send(clientSock, ptr, MemoryLayout<DmaBufConfigure>.size, 0)
                }
            }

            // Receive DMA-BUF fd + metadata from child
            var meta = DmaBufMeta(width: 0, height: 0, stride: 0, fourcc: 0, flags: 0)
            let receivedFd = dmabuf_recv_fd(clientSock, &meta,
                                            MemoryLayout<DmaBufMeta>.size)
            guard receivedFd >= 0 else {
                Glibc.close(clientSock)
                return
            }

            // From here the fd is shared (tick hands it to the entry), so
            // it moves into a ChildSocket: this thread keeps the raw fd
            // for its recv loop and remains the only closer.
            let sock = ChildSocket(adopting: clientSock)

            // Queue for tick() on platform thread
            pendingDmaBufLaunches.withLock { $0.append(PendingDmaBufLaunch(
                pid: spawnedPid,
                sock: sock,
                dmaFd: receivedFd,
                width: Int(meta.width),
                height: Int(meta.height),
                stride: Int(meta.stride),
                fourcc: meta.fourcc,
                cpu: (meta.flags & UInt32(DMABUF_META_FLAG_CPU)) != 0,
                onReady: sendableOnReady,
                onTerminated: sendableOnTerminated,
                launchState: launchState
            )) }

            FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))

            // Read frame signals and resize responses from child socket.
            var buf = [UInt8](repeating: 0, count: 128)

            while true {
                var receivedFd: Int32 = -1
                let n = dmabuf_recv_with_fd(clientSock, &buf, buf.count, &receivedFd)
                if n <= 0 {
                    // This loop IS the child->shell control channel (DPI,
                    // theme, primary display, caret) — its death must never
                    // be silent again. n==0 is the child closing (normal
                    // exit); anything else deserves an errno in the log.
                    // EINTR is retried inside dmabuf_recv_with_fd.
                    if n < 0 {
                        FileHandle.standardError.write(Data(
                            "[ProcessApp] child socket reader exiting: recv=\(n) errno=\(errno)\n".utf8))
                    }
                    break
                }

                let texId = launchState.value.texId

                if receivedFd >= 0 && n >= MemoryLayout<DmaBufMeta>.size {
                    // Resize response: data contains DmaBufMeta, fd is the new DMA-BUF
                    var meta = DmaBufMeta(width: 0, height: 0, stride: 0, fourcc: 0, flags: 0)
                    memcpy(&meta, &buf, MemoryLayout<DmaBufMeta>.size)

                    if texId != 0 {
                        pendingDmaBufResizes.withLock { $0.append(PendingDmaBufResize(
                            textureId: texId,
                            dmaFd: receivedFd,
                            width: Int(meta.width),
                            height: Int(meta.height),
                            stride: Int(meta.stride),
                            fourcc: meta.fourcc,
                            flags: meta.flags
                        )) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    }
                } else if receivedFd < 0 && n >= MemoryLayout<DmaBufInputEvent>.size {
                    var event = DmaBufInputEvent(x: 0, y: 0, buttons: 0, type: 0, phase: 0)
                    memcpy(&event, &buf, MemoryLayout<DmaBufInputEvent>.size)
                    if event.type == DMABUF_CONTROL_SET_DPI {
                        pendingDpiChanges.withLock { $0.append(event.x) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_THEME {
                        pendingThemeChanges.withLock { $0.append(event.x > 0.5) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_LAYOUT {
                        pendingLayoutRequests.withLock { $0.append(event.x > 0.5) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_WALLPAPER {
                        pendingWallpaperRequests.withLock { $0.append(Int(event.x)) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_STYLE {
                        pendingStyleRequests.withLock { $0.append(Int(event.x)) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_SCREENSAVER {
                        pendingScreensaverRequests.withLock { $0.append(Int(event.x)) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_PRIMARY_DISPLAY {
                        pendingPrimaryDisplayRequests.withLock { $0.append(Int(event.x)) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CONTROL_SET_RDP {
                        pendingRdpRequests.withLock { $0.append(event.x > 0.5) }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    } else if event.type == DMABUF_CARET {
                        let bits = UInt64(bitPattern: event.buttons)
                        let w = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
                        let h = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits >> 32)))
                        pendingCaretUpdates.withLock {
                            $0.append((texId, event.x, event.y, w, h, event.phase != 0))
                        }
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    }
                } else {
                    // Frame signal. If it beats tick()'s registration, latch
                    // it in the launch state so tick can fire the callback.
                    let frameTexId = launchState.withLock {
                        (s: inout (texId: Int64, earlyFrame: Bool)) -> Int64 in
                        if s.texId == 0 { s.earlyFrame = true }
                        return s.texId
                    }
                    if frameTexId != 0 {
                        pendingDmaBufFrames.withLock { $0.append(frameTexId) }
                        // A first-party child renders into ONE gbm_bo for
                        // its whole life — the buffer is imported once and
                        // never again, so this signal is the only evidence
                        // its pixels changed. An app recording needs it.
                        RecordingService.noteSourceContentChanged(
                            textureId: frameTexId)
                        FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
                    }
                }
            }

            sock.close()
        }

        // The reaper: one thread parked in waitpid for this child's whole
        // life, the mirror of its socket-reader thread above. It answers for
        // the child's DEATH — exit, crash, or kill — where every fd-based
        // signal in this file answers only for fds, which descendants can
        // keep alive after the child is gone.
        let capturedStdoutFd = stdoutPipe[0]
        let sendableOnExit = onExit.map {
            unsafeBitCast($0, to: (@Sendable (String, Int32) -> Void).self)
        }
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while waitpid(spawnedPid, &status, 0) == -1 && errno == EINTR {}
            // Deliver captured stdout (used by the portal file chooser to
            // read the picker's selected URIs) before signaling termination.
            if let onExit = sendableOnExit {
                var data = Data()
                if capturedStdoutFd >= 0 {
                    var buf = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let n = Glibc.read(capturedStdoutFd, &buf, buf.count)
                        if n < 0 && errno == EINTR { continue }
                        if n <= 0 { break }
                        data.append(contentsOf: buf[0..<n])
                    }
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                // Foundation's terminationStatus convention: the exit code
                // for a normal exit, the signal number for a killed child.
                let exitedNormally = (status & 0x7f) == 0
                let code = exitedNormally ? (status >> 8) & 0xff : status & 0x7f
                onExit(text, code)
            }
            if capturedStdoutFd >= 0 { Glibc.close(capturedStdoutFd) }
            pendingTerminations.withLock { $0.append { sendableOnTerminated() } }
            FlutterEngineScheduleFrame(unsafeBitCast(capturedEngine, to: OpaquePointer.self))
        }
        return true
    }

    private var nextSocketId: Int = 0

    /// Pushes the desktop appearance to one child over its socket.
    func sendTheme(textureId: Int64, dark: Bool) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: dark ? 1 : 0, y: 0, buttons: 0,
                                     type: Int32(DMABUF_CONTROL_SET_THEME),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Appearance switch: push the new theme to every child app.
    func broadcastTheme(dark: Bool) {
        for texId in apps.keys {
            sendTheme(textureId: texId, dark: dark)
        }
    }

    /// Pushes the desktop style to one child. The value is the style's index
    /// in the shell's registry; the child treats it as opaque.
    func sendStyle(textureId: Int64, index: Int) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: Double(index), y: 0, buttons: 0,
                                     type: Int32(DMABUF_CONTROL_SET_STYLE),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Style switch: push to every child so their own chrome can follow.
    func broadcastStyle(index: Int) {
        currentStyleIndex = index
        for texId in apps.keys {
            sendStyle(textureId: texId, index: index)
        }
    }

    /// Pushes the window-manager layout to one child (true = tiling).
    func sendLayout(textureId: Int64, tiling: Bool) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: tiling ? 1 : 0, y: 0, buttons: 0,
                                     type: Int32(DMABUF_CONTROL_SET_LAYOUT),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Layout switch: push to every child so Settings toggles stay live.
    func broadcastLayout(tiling: Bool) {
        currentLayoutIsTiling = tiling
        for texId in apps.keys {
            sendLayout(textureId: texId, tiling: tiling)
        }
    }

    /// Pushes the wallpaper preset to one child.
    func sendWallpaper(textureId: Int64, preset: Int) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: Double(preset), y: 0, buttons: 0,
                                     type: Int32(DMABUF_CONTROL_SET_WALLPAPER),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Wallpaper switch: push to every child so Settings pickers stay live.
    func broadcastWallpaper(preset: Int) {
        currentWallpaper = preset
        for texId in apps.keys {
            sendWallpaper(textureId: texId, preset: preset)
        }
    }

    /// Pushes the screensaver idle timeout (seconds, 0 = never) to one child.
    func sendScreensaver(textureId: Int64, seconds: Int) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: Double(seconds), y: 0, buttons: 0,
                                     type: Int32(DMABUF_CONTROL_SET_SCREENSAVER),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Idle-timeout change: push to every child so Settings pickers stay live.
    func broadcastScreensaver(seconds: Int) {
        currentScreensaverIdle = seconds
        for texId in apps.keys {
            sendScreensaver(textureId: texId, seconds: seconds)
        }
    }

    /// Pushes the settled remote-desktop state to one child.
    func sendRdp(textureId: Int64) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(
            x: currentRdpEnabled ? 1 : 0, y: 0, buttons: 0,
            type: Int32(DMABUF_CONTROL_SET_RDP), phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Remote-desktop change: push to every child so the Sharing switch shows
    /// what actually happened rather than what was clicked.
    func broadcastRdp(enabled: Bool) {
        currentRdpEnabled = enabled
        for texId in apps.keys {
            sendRdp(textureId: texId)
        }
    }

    /// Pushes the whole display list to one child: each display's name in
    /// 8-byte chunks, then its info record. The run is self-delimiting
    /// (index/count in `phase`), so a child that connects mid-change still
    /// assembles exactly one complete list.
    func sendDisplays(textureId: Int64) {
        guard let entry = apps[textureId], !currentDisplays.isEmpty else { return }
        // Capped so `index << 16` cannot overflow the Int32 `phase` field —
        // a trap, not a wrong number. DRM tops out at a couple of dozen
        // connectors, so this only ever bites a bug.
        let count = min(currentDisplays.count, 64)
        for (index, display) in currentDisplays.prefix(count).enumerated() {
            var bytes = Array(display.name.utf8)
            // The child reads chunks until the run's info record; a name
            // longer than the connector names DRM produces is truncated
            // rather than spilling into the next display's.
            if bytes.count > 32 { bytes = Array(bytes.prefix(32)) }
            for chunk in stride(from: 0, to: max(bytes.count, 1), by: 8) {
                var packed: UInt64 = 0
                for i in 0..<8 where chunk + i < bytes.count {
                    packed |= UInt64(bytes[chunk + i]) << (8 * UInt64(i))
                }
                var nameEvent = DmaBufInputEvent(
                    x: Double(chunk / 8), y: 0,
                    buttons: Int64(bitPattern: packed),
                    type: Int32(DMABUF_DISPLAY_NAME), phase: 0)
                entry.sock.write(&nameEvent, MemoryLayout<DmaBufInputEvent>.size)
            }
            var packed = UInt64(UInt16(truncatingIfNeeded: display.id))
            if display.isPrimary { packed |= 1 << 16 }
            packed |= UInt64(Float(display.scale).bitPattern) << 32
            var event = DmaBufInputEvent(
                x: Double(display.physicalWidth),
                y: Double(display.physicalHeight),
                buttons: Int64(bitPattern: packed),
                type: Int32(DMABUF_DISPLAY_INFO),
                phase: Int32(index << 16 | count))
            entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
        }
    }

    /// Arrangement change (hotplug, or a new primary): push to every child so
    /// the Displays pane stays live.
    func broadcastDisplays(_ displays: [ChildDisplay]) {
        currentDisplays = displays
        for texId in apps.keys {
            sendDisplays(textureId: texId)
        }
    }

    /// Sends a pointer event to the child process via the Unix socket.
    func sendPointerEvent(textureId: Int64, phase: Int32, x: Double, y: Double, buttons: Int64) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: x, y: y, buttons: buttons,
                                     type: Int32(DMABUF_INPUT_POINTER),
                                     phase: phase)
        if ProcessInfo.processInfo.environment["STARLING_SWAPCHAIN_DEBUG"] == "1",
           phase != 6, phase != 3 {
            FileHandle.standardError.write(Data(
                "[ProcessApp] fwd ptr tex=\(textureId) phase=\(phase) x=\(x) y=\(y)\n".utf8))
        }
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Sends a keyboard event to the child process via the Unix socket.
    /// `physical`/`logical` mirror KeyData (HID code / keysym); `character`
    /// is the Unicode scalar of the typed character, or 0 for none. Both fit
    /// losslessly in the event's double fields. `phase`: 0=down, 1=up,
    /// 2=repeat.
    func sendKeyEvent(textureId: Int64, physical: Int64, logical: Int64,
                      character: UInt32, phase: Int32) {
        guard let entry = apps[textureId] else { return }
        var event = DmaBufInputEvent(x: Double(physical), y: Double(logical),
                                     buttons: Int64(character),
                                     type: Int32(DMABUF_INPUT_KEY),
                                     phase: phase)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Sends a mouse-wheel scroll to the child. Deltas are packed as two
    /// Float32 bit patterns in the event's buttons field (dx low, dy high) —
    /// DmaBufInputEvent has no spare double fields.
    func sendScrollEvent(textureId: Int64, x: Double, y: Double,
                         dx: Double, dy: Double) {
        guard let entry = apps[textureId] else { return }
        let packed = UInt64(Float(dx).bitPattern)
            | (UInt64(Float(dy).bitPattern) << 32)
        var event = DmaBufInputEvent(x: x, y: y,
                                     buttons: Int64(bitPattern: packed),
                                     type: Int32(DMABUF_INPUT_SCROLL),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Sends a DPI change to all child processes via their Unix sockets.
    func broadcastDpiChange(_ dpi: Double) {
        for (_, entry) in apps {
            var event = DmaBufInputEvent(x: dpi, y: 0, buttons: 0,
                                         type: DMABUF_CONTROL_SET_DPI, phase: 0)
            entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
        }
    }

    /// Sends a resize event to the child process via the Unix socket.
    func sendResize(textureId: Int64, width: Int, height: Int) {
        guard let entry = apps[textureId] else { return }
        guard width != entry.width || height != entry.height else { return }
        var event = DmaBufInputEvent(x: Double(width), y: Double(height), buttons: 0,
                                     type: Int32(DMABUF_INPUT_RESIZE),
                                     phase: 0)
        entry.sock.write(&event, MemoryLayout<DmaBufInputEvent>.size)
    }

    /// Terminates the child process and unregisters its texture.
    func destroyApp(textureId: Int64) {
        guard let entry = apps.removeValue(forKey: textureId) else { return }
        // A SIGTERM at a pid this process spawned and has not yet reaped can
        // never hit a stranger; if the child already died it is a no-op and
        // the waitpid thread finishes the story.
        if entry.pid > 0 {
            kill(entry.pid, SIGTERM)
        }
        if entry.dmaFd >= 0 {
            Glibc.close(entry.dmaFd)
        }
        entry.sock.shutdown()
        textureRegistry.unregisterTexture(engine: engine, id: textureId)
    }
}

/// Internal bookkeeping for a single process app instance.
private struct ProcessAppEntry {
    let pid: pid_t
    let textureId: Int64
    var width: Int
    var height: Int
    let onTerminated: () -> Void

    var dmaFd: Int32 = -1
    let sock: ChildSocket
    var dmaBufStride: Int = 0
    var dmaBufFourcc: UInt32 = 0
    /// CPU children only: the mapped memfd their frames land in, and its
    /// size. Non-nil is what marks this app as one whose frames must be
    /// uploaded per signal rather than imported once.
    var cpuMap: UnsafeMutableRawPointer? = nil
    var cpuMapSize: Int = 0
}

#endif
