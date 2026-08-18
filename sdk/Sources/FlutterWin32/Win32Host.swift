// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Runs a FlutterSwift app the way a real Flutter Windows app runs: inside the
// engine's Win32 embedder (flutter_windows.dll), which owns the view, the
// rendering surface, pointer/keyboard input, IME and accessibility. The engine
// is started in Swift mode, so this framework drives frames through the
// SwiftRuntimeCallbacks table instead of a Dart isolate.
//
// All Win32/embedder mechanics live in the C glue (FlutterWin32Bridge); this
// type only owns the callback table's lifetime and the run sequence. The
// counterpart of FlutterGTK's GTKHost.

#if os(Windows)
import Flutter
import FlutterSwiftBridge
import SwiftRuntime
import FlutterWin32Bridge
import Foundation

public final class Win32Host {

    private let host: OpaquePointer
    // The engine holds this pointer for its lifetime; heap-allocate so it
    // never moves and never dies before the process does.
    private let callbacks: UnsafeMutablePointer<SwiftRuntimeCallbacks>

    /// Creates the window, the engine and the view; the engine starts inside
    /// view-controller creation. Returns nil if the window or the engine could
    /// not be created.
    public init?(width: Int, height: Int, title: String) {
        callbacks = UnsafeMutablePointer<SwiftRuntimeCallbacks>.allocate(capacity: 1)
        callbacks.initialize(to: createRuntimeCallbacks())
        guard let host = flwin32_host_create(title, Int32(width), Int32(height),
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
        runApp(builder())
    }

    /// Shows the window and runs the Win32 message loop. Returns when the
    /// window is closed.
    public func run() {
        flwin32_host_show(host)
        flwin32_host_run(host)
    }

    /// Fullscreens or restores the window.
    public func setFullscreen(_ fullscreen: Bool) {
        flwin32_host_set_fullscreen(host, fullscreen ? 1 : 0)
    }

    /// Registers `window`'s application icon with the engine as an external
    /// texture and returns its id for a `TextureWidget`, or nil when the
    /// window has no icon to give.
    ///
    /// One texture per icon, not per window: they are never freed
    /// automatically, so a caller that registers one per window in a list has
    /// to unregister them as windows close. `Win32Window.executablePath` is
    /// the natural cache key — same exe, same icon.
    public func registerIconTexture(window handle: UInt64, size: Int = 32) -> Int? {
        let id = flwin32_host_register_icon_texture(host, handle, Int32(size))
        return id > 0 ? Int(id) : nil
    }

    /// Releases a texture from `registerIconTexture`. Safe to call with an id
    /// that is already gone.
    public func unregisterTexture(_ id: Int) {
        flwin32_host_unregister_texture(host, Int64(id))
    }

    /// Restyles the window into shell chrome: undecorated, always on top, and
    /// pinned to a screen edge. Call before `run()` — it is a restyle of an
    /// existing HWND, so the engine's view follows the new client area, but
    /// doing it mid-run makes the first frames arrive at the old size.
    public func setPanel(_ placement: PanelPlacement) {
        flwin32_host_set_panel(host, placement.edge.rawValue,
                               Int32(placement.thickness),
                               Int32(placement.monitor ?? -1),
                               placement.takesFocus ? 1 : 0)
        // After set_panel, never before: the appbar reserves the geometry the
        // panel was just given, and registering first would reserve the
        // window's pre-panel rectangle.
        if placement.reserveSpace {
            if flwin32_host_set_appbar(host, 1) == 0 {
                FileHandle.standardError.write(Data(
                    "[Win32Host] appbar registration refused; the bar will overlay\n".utf8))
            }
        }
    }
}
#endif
