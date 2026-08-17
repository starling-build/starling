// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Runs a FlutterSwift app the way a real Flutter Linux app runs: inside the
// engine's GTK embedder (FlView in a GtkWindow), which owns the window,
// rendering surface, pointer/keyboard/touch input, IME and accessibility.
// The engine is started in Swift mode, so this framework drives frames
// through the SwiftRuntimeCallbacks table instead of a Dart isolate.
//
// All GTK/embedder mechanics live in the C glue (FlutterGTKBridge); this
// type only owns the callback table's lifetime and the run sequence.

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import Foundation
import SwiftRuntime
import FlutterGTKBridge

public final class GTKHost {

    private let host: OpaquePointer
    // The engine holds this pointer for its lifetime; heap-allocate so it
    // never moves and never dies before the process does.
    private let callbacks: UnsafeMutablePointer<SwiftRuntimeCallbacks>

    /// Creates the window and view; the engine starts when run() shows the
    /// window. Returns nil when no Wayland/X11 display is reachable.
    public init?(width: Int, height: Int, title: String) {
        GTKHost.ensureEngineData()
        callbacks = UnsafeMutablePointer<SwiftRuntimeCallbacks>.allocate(capacity: 1)
        callbacks.initialize(to: createRuntimeCallbacks())
        guard let host = flgtk_host_create(title, Int32(width), Int32(height),
                                           UnsafeRawPointer(callbacks)) else {
            callbacks.deinitialize(count: 1)
            callbacks.deallocate()
            return nil
        }
        self.host = host
    }

    /// Sets up the widget binding. Call before run() — the tree must be
    /// mounted by the time the engine requests the first frame.
    public func mountWidget(_ builder: () -> Widget) {
        // Without FLUTTER_DMABUF_SOCKET set this only installs the binding;
        // the engine is ours and starts inside the GTK realize path.
        runApp(builder())
    }

    /// Shows the window (which starts the engine) and runs the GTK main
    /// loop. Returns when the window is closed.
    public func run() {
        flgtk_host_show(host)
        flgtk_host_run(host)
    }

    /// Fullscreens or restores the window.
    public func setFullscreen(_ fullscreen: Bool) {
        flgtk_host_set_fullscreen(host, fullscreen ? 1 : 0)
    }

    /// Registers a DMA-BUF-backed external texture with the engine, or nil
    /// if the texture registrar is unavailable.
    public func makeDmaBufTexture() -> GTKDmaBufTexture? {
        guard let texture = flgtk_host_create_dmabuf_texture(host) else { return nil }
        return GTKDmaBufTexture(texture: texture)
    }

    /// Engine data for a standalone run. The embedder resolves both files as
    /// `<executable dir>/data/{icudtl.dat,flutter_assets}` — a staged desktop
    /// tree and a packaged app ship that directory, a `swift build` does not —
    /// so link them in from wherever this package's engine came from: an SDK
    /// bundle carries its own pair under `engine/share`, a checkout has them
    /// in the engine's out directory.
    ///
    /// This belongs to the host that starts the engine, not to
    /// GTKWindowedHost, which is only one of the ways in. A consumer who
    /// builds a GTKHost directly — the shape the bundle's own README
    /// describes — bypassed the bootstrap entirely and reached the engine's
    /// `Check failed: context->IsValid()` abort with the ICU data sitting
    /// unread inside the bundle it had just linked against.
    public static func ensureEngineData() {
        let fm = FileManager.default
        guard let exe = try? fm.destinationOfSymbolicLink(atPath: "/proc/self/exe")
        else { return }
        let dataDir = (exe as NSString).deletingLastPathComponent + "/data"
        if fm.fileExists(atPath: dataDir + "/icudtl.dat") { return }

        // …/sdk/Sources/FlutterGTK/GTKHost.swift → sdk/
        let sdkDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().path

        var icuCandidates: [String] = []
        let env = ProcessInfo.processInfo.environment
        for key in ["FLUTTER_SWIFT_ENGINE_OUT", "FLUTTER_ENGINE_OUT"] {
            if let v = env[key], !v.isEmpty { icuCandidates.append(v + "/icudtl.dat") }
        }
        icuCandidates += [
            // A distribution bundle (tools/make-bundle.sh), which is the only
            // engine an external consumer has.
            sdkDir + "/engine/share/icudtl.dat",
            // The starling repo's engine symlink, one level above sdk/.
            sdkDir + "/../engine/src/out/host_debug/icudtl.dat",
        ]
        guard let icu = icuCandidates.first(where: { fm.fileExists(atPath: $0) })
        else {
            FileHandle.standardError.write(Data((
                "[GTKHost] no data/ next to the executable and no engine data "
                + "to link from — tried "
                + icuCandidates.joined(separator: ", ") + "\n").utf8))
            return
        }
        try? fm.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: dataDir + "/icudtl.dat",
                                   withDestinationPath: icu)
        // Assets sit in Resources/ in a checkout and in engine/share in a
        // bundle, which does not ship Resources/ at all.
        let assetCandidates = [sdkDir + "/Resources/flutter_assets",
                               sdkDir + "/engine/share/flutter_assets"]
        if let assets = assetCandidates.first(where: { fm.fileExists(atPath: $0) }) {
            try? fm.createSymbolicLink(atPath: dataDir + "/flutter_assets",
                                       withDestinationPath: assets)
        }
    }
}

/// An external texture whose frames arrive as dma-buf fds: the raster thread
/// samples the producer's GPU memory directly (EGLImage import, cached per
/// buffer identity) — no CPU pixel copies, no per-frame GL uploads. Show it
/// with `TextureWidget(textureId: Int(texture.textureId))`.
public final class GTKDmaBufTexture {

    private let texture: OpaquePointer
    public let textureId: Int64

    fileprivate init(texture: OpaquePointer) {
        self.texture = texture
        self.textureId = flgtk_dmabuf_texture_get_id(texture)
    }

    /// Hands over the next frame. Takes ownership of `fd` — dup(2) a pooled
    /// buffer's fd before passing it. Callable from any thread.
    public func update(
        fd: Int32, width: Int32, height: Int32, stride: Int32,
        fourcc: UInt32, modifier: UInt64
    ) {
        flgtk_dmabuf_texture_update(texture, fd, width, height, stride, fourcc, modifier)
    }

    deinit {
        flgtk_dmabuf_texture_destroy(texture)
    }
}
#endif
