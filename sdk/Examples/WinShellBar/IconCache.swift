// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One place that turns a window or an installed app into a texture id.
//
// Both the bar and the dock need icons, and both would otherwise rasterize
// the same PNG twice and leak one of them. The cache is keyed by executable
// rather than by window — five Explorer windows are one icon — and gives
// textures back when the app they belong to has nothing on screen any more.

#if os(Windows)
import Flutter
import FlutterWin32
import Foundation

final class IconCache {
    private var textures: [String: Int] = [:]
    /// Keys we have already failed on. Without this, an app whose icon cannot
    /// be resolved is re-rasterized on every refresh, which for a Start Menu
    /// with a few hundred entries is not free.
    private var attempted: Set<String> = []

    /// The cache key for a window: its executable, so windows of the same app
    /// share a texture. The handle is the fallback only for a window whose
    /// process would not open — a service, or a higher integrity level —
    /// where sharing would be wrong anyway.
    static func key(for window: Win32Window) -> String {
        window.executablePath.isEmpty
            ? "hwnd:\(window.handle)" : window.executablePath.lowercased()
    }

    /// The cache key for an installed app: the executable it starts, so a
    /// running app and its dock entry resolve to the SAME texture and the
    /// dock does not draw two subtly different icons for one thing.
    static func key(for app: Win32App) -> String {
        app.target.isEmpty ? app.shortcutPath.lowercased() : app.target
    }

    func texture(_ key: String) -> Int? { textures[key] }

    /// Rasterizes from a live window. Preferred over the path form when the
    /// app is running: a window's own icon is the one it chose to show, which
    /// for a browser is the profile or the site, not the generic app icon.
    func ensure(window: Win32Window, size: Int = 32) {
        let key = Self.key(for: window)
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        if let id = Win32WindowedHost.host?.registerIconTexture(
            window: window.handle, size: size) {
            textures[key] = id
        }
    }

    /// Rasterizes for an app that is not running, from the executable the
    /// shortcut points at rather than from the shortcut itself.
    ///
    /// That distinction is visible: the shell draws a .lnk's icon with the
    /// little curved ARROW overlaid on it, because in Explorer that badge
    /// means "this is a shortcut". In a dock it means nothing and every
    /// pinned app wears one. Falling back to the shortcut when there is no
    /// target keeps Store apps — whose .lnk holds an item-ID list, not a
    /// path — showing something rather than nothing.
    func ensure(app: Win32App, size: Int = 48) {
        let key = Self.key(for: app)
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        let source = app.target.isEmpty ? app.shortcutPath : app.target
        if let id = Win32WindowedHost.host?.registerIconTexture(
            path: source, size: size) {
            textures[key] = id
        }
    }

    /// Releases everything not in `live`. Called from the refresh, so an app
    /// closing gives its icon back rather than holding it for the session.
    func retain(only live: Set<String>) {
        for (key, id) in textures where !live.contains(key) {
            Win32WindowedHost.host?.unregisterTexture(id)
            textures.removeValue(forKey: key)
            attempted.remove(key)
        }
    }

    func releaseAll() {
        for id in textures.values { Win32WindowedHost.host?.unregisterTexture(id) }
        textures.removeAll()
        attempted.removeAll()
    }

    /// The icon widget, or nil when there is no texture — callers draw a
    /// fallback glyph then.
    func view(_ key: String, side: Double) -> Widget? {
        guard let id = textures[key] else { return nil }
        return SizedBox(width: side, height: side) {
            TextureWidget(textureId: id)
        }
    }
}
#endif
