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
    /// The C host, for the sibling that manages popup surfaces
    /// (Win32PopupSurfaces) — the one other owner of flwin32_ calls that
    /// take the host.
    var cHost: OpaquePointer { host }
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
    ///
    /// An overlay is NOT shown: it parked itself hidden when it was set up
    /// and stays that way until something asks for it. It used to park on
    /// screen and transparent, which is why this once showed everything
    /// unconditionally — and why, once parking started hiding, the launcher
    /// came up on screen at login and stayed there. See flwin32_host_show.
    public func run() {
        flwin32_host_show(host)
        flwin32_host_run(host)
    }

    /// Fullscreens or restores the window.
    public func setFullscreen(_ fullscreen: Bool) {
        flwin32_host_set_fullscreen(host, fullscreen ? 1 : 0)
    }

    /// Comes up as a full-screen overlay — the launcher, and later Mission
    /// Control — hidden until `setVisible(true)`.
    ///
    /// Hidden rather than not running: starting an engine costs about a
    /// second, which is fine for an app and wrong for something the user
    /// expects the instant they ask for it.
    public func setOverlay(monitor: Int?, opacity: Double,
                           size: (width: Double, height: Double)? = nil,
                           bottomMargin: Double = 12,
                           rightMargin: Double? = nil,
                           leftMargin: Double? = nil,
                           channel: String? = nil,
                           transparent: Bool = false,
                           passive: Bool = false) {
        // Anchor and channel BEFORE set_overlay: that call positions the
        // window, and an anchor set afterwards would leave it centred until
        // the next monitor change rederived it.
        if let rightMargin {
            flwin32_host_set_overlay_anchor_right(host, Int32(rightMargin))
        }
        if let leftMargin {
            flwin32_host_set_overlay_anchor_left(host, Int32(leftMargin))
        }
        if let channel {
            flwin32_host_set_overlay_channel(host, channel)
        }
        if transparent {
            flwin32_host_set_overlay_colorkey(host)
        }
        if passive {
            flwin32_host_set_overlay_passive(host)
        }
        flwin32_host_set_overlay(host, Int32(monitor ?? -1),
                                 Int32((opacity * 255).rounded()),
                                 Int32(size?.width ?? 0),
                                 Int32(size?.height ?? 0),
                                 Int32(bottomMargin))
    }

    /// Restyles the window into THE DESKTOP: full monitor, pinned to the
    /// bottom of the z-order, focusable but never raised — the plane
    /// explorer's Progman is. Call before `run()`, like the other restyles.
    public func setDesktop(monitor: Int?) {
        flwin32_host_set_desktop(host, Int32(monitor ?? -1))
    }

    public func setVisible(_ visible: Bool) {
        flwin32_host_set_visible(host, visible ? 1 : 0)
    }

    public var isVisible: Bool { flwin32_host_is_visible(host) != 0 }

    /// Rasterize now, visible or not.
    ///
    /// For a surface that resets itself on the way DOWN: the tree is put back
    /// to its opening state while hidden, and this pushes that through the
    /// engine, so showing it later is a window becoming visible and nothing
    /// else.
    public func requestRedraw() {
        flwin32_host_request_redraw(host)
    }

    /// Give the caption to the widget tree: the app draws the titlebar (tabs,
    /// caption buttons) and owes the window `beginDrag`, `minimize`,
    /// `toggleMaximize` and `closeWindow` in return. Resize borders stay the
    /// system's.
    public func setCustomTitlebar(_ enable: Bool = true) {
        flwin32_host_set_custom_titlebar(host, enable ? 1 : 0)
    }

    /// Hand a press on the app-drawn titlebar to the frame as a caption
    /// click -- Windows runs its own move loop, snap layouts included. Call
    /// during the pointer-down.
    public func beginDrag() {
        flwin32_host_begin_drag(host)
    }

    public func minimize() { flwin32_host_minimize(host) }
    public func toggleMaximize() { flwin32_host_toggle_maximize(host) }
    public var isMaximized: Bool { flwin32_host_is_maximized(host) != 0 }
    public func closeWindow() { flwin32_host_close_window(host) }

    /// The host's TOP-LEVEL window, for the Win32 calls that take an HWND
    /// rather than a view -- a DWM thumbnail's destination is the first of
    /// them. Not the engine's child view: a thumbnail placed against that
    /// would be in the wrong coordinate space and clipped to it.
    public var windowHandle: UInt64 { flwin32_host_window(host) }

    /// The client area in LOGICAL POINTS -- the units the widget tree lays
    /// out in -- or nil if the window will not say.
    ///
    /// For a tree that has to place something against its own window: this
    /// one is resizable, and a menu that runs off the bottom of it is clipped
    /// rather than flipped, because a window is a hard clip.
    public var clientSize: (width: Double, height: Double)? {
        var width: Int32 = 0
        var height: Int32 = 0
        guard flwin32_host_client_size(host, &width, &height) != 0 else { return nil }
        return (Double(width), Double(height))
    }

    /// Called when any Starling surface broadcasts a toggle. Runs on the UI
    /// thread, inside the message loop.
    public func onToggle(_ handler: @escaping () -> Void) {
        Win32Host.toggleHandler = handler
        flwin32_host_on_toggle(host, { _ in Win32Host.toggleHandler?() }, nil)
    }

    /// Global for the same reason the window-manager hook is: there is one UI
    /// thread and one window per process.
    nonisolated(unsafe) private static var toggleHandler: (() -> Void)?

    /// Called when the system's light/dark theme flips (WM_SETTINGCHANGE
    /// with "ImmersiveColorSet"). Runs on the UI thread; the registry
    /// already holds the new value, so re-read it with
    /// `Win32SystemInfo.appsUseLightTheme()`.
    public func onThemeChange(_ handler: @escaping () -> Void) {
        Win32Host.themeHandler = handler
        flwin32_host_on_theme_change(host, { _ in Win32Host.themeHandler?() }, nil)
    }

    nonisolated(unsafe) private static var themeHandler: (() -> Void)?

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

    /// The same for a file — an executable, or a Start Menu `.lnk`, whose icon
    /// is a property of the shortcut. This is how the dock draws an app that
    /// is not running and so has no window to ask.
    public func registerIconTexture(path: String, size: Int = 48) -> Int? {
        let id = flwin32_host_register_icon_texture_path(host, path, Int32(size))
        return id > 0 ? Int(id) : nil
    }

    /// Registers pixels produced by `Win32Icon.rasterize` as a texture.
    ///
    /// **Platform thread only.** This is the half that talks to the engine;
    /// the expensive half is `Win32Icon.rasterize`, which is deliberately a
    /// free function so it can be called from a `Task.detached`.
    public func registerPixels(_ bitmap: Win32Icon.Bitmap) -> Int? {
        let id = flwin32_host_register_pixels(host, bitmap.pixels,
                                              Int32(bitmap.width),
                                              Int32(bitmap.height))
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
    /// Moves an existing panel to another edge, at runtime.
    ///
    /// Unlike `setPanel`, this one IS meant to be called mid-run: the window
    /// changes shape and the tree lays itself out again on the other side of
    /// the resize, which is the point.
    public func movePanel(to edge: PanelEdge) {
        flwin32_host_move_panel(host, edge.rawValue)
    }

    public func setPanel(_ placement: PanelPlacement) {
        flwin32_host_set_panel(host, placement.edge.rawValue,
                               Int32(placement.thickness),
                               Int32(placement.monitor ?? -1),
                               placement.takesFocus ? 1 : 0,
                               placement.transparent ? 1 : 0,
                               Int32(placement.overhang))
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
