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
    /// Called on the main thread when a texture has arrived, so the surface
    /// that asked for it can rebuild. Rasterizing happens off the UI thread
    /// now, so `view(_:side:)` returns nil for a frame or two and the tile
    /// draws its fallback glyph until this fires.
    var onTextureReady: (() -> Void)?

    private var textures: [String: Int] = [:]
    /// Keys we have already failed on. Without this, an app whose icon cannot
    /// be resolved is re-rasterized on every refresh, which for a Start Menu
    /// with a few hundred entries is not free.
    private var attempted: Set<String> = []

    /// The cache key for a window: what identifies the APP behind it, so
    /// windows of the same app share a texture — and, more importantly, so a
    /// running window and the dock's pin for the same app resolve to the same
    /// string. `key(for: Win32App)` is the other half of that contract and
    /// the two must stay in step.
    ///
    /// A packaged app is keyed by its AppUserModelID, not its executable,
    /// because its executable identifies nothing: the path is versioned and
    /// changes under it on every update, and every CoreWindow-generation app
    /// (Settings, Calculator, the Store) reports the same
    /// `ApplicationFrameHost.exe`, which collapsed all of them onto one dock
    /// tile wearing the placeholder glyph. The `shell:AppsFolder\` prefix is
    /// not decoration: it is exactly how the catalog spells such an entry, so
    /// the two sides meet.
    ///
    /// The handle is the last fallback, for a window whose process would not
    /// open — a service, or a higher integrity level — where sharing a
    /// texture would be wrong anyway.
    static func key(for window: Win32Window) -> String {
        if !window.appUserModelID.isEmpty {
            return "shell:appsfolder\\" + window.appUserModelID.lowercased()
        }
        return window.executablePath.isEmpty
            ? "hwnd:\(window.handle)" : window.executablePath.lowercased()
    }

    /// Every string a window may be known by, best first.
    ///
    /// A packaged app answers to two: its id, and the executable behind it.
    /// Which one the dock's pin holds depends on where the catalog entry came
    /// from — the AppsFolder gives an id, a Start Menu shortcut gives a path,
    /// and some packaged apps ship both — so a pin claims a window that
    /// answers to EITHER, and only the first is used to group windows that no
    /// pin claimed.
    static func keys(for window: Win32Window) -> [String] {
        let primary = key(for: window)
        let exe = window.executablePath.lowercased()
        guard !exe.isEmpty, exe != primary else { return [primary] }
        return [primary, exe]
    }

    /// The cache key for an installed app: the executable it starts, so a
    /// running app and its dock entry resolve to the SAME texture and the
    /// dock does not draw two subtly different icons for one thing. A
    /// packaged app has no executable to name, and its `shortcutPath` is the
    /// `shell:AppsFolder\<id>` parsing name that `key(for: Win32Window)`
    /// reconstructs from the window.
    ///
    /// Lowercased on BOTH branches. The catalog already lowercases every
    /// target it stores, so this changes no key today — but the window side
    /// lowercases unconditionally, and a one-sided normalisation is a trap
    /// waiting for the first target that arrives in the case it was written.
    static func key(for app: Win32App) -> String {
        app.target.isEmpty
            ? app.shortcutPath.lowercased() : app.target.lowercased()
    }

    func texture(_ key: String) -> Int? { textures[key] }

    /// Rasterizes from a live window. Preferred over the path form when the
    /// app is running: a window's own icon is the one it chose to show, which
    /// for a browser is the profile or the site, not the generic app icon.
    func ensure(window: Win32Window, size: Int = 32) {
        ensure(key: Self.key(for: window), window: window, size: size)
    }

    /// The same, filed under a key the caller chose.
    ///
    /// The dock needs this because a tile is drawn from ITS key, which is the
    /// pin's, and a pin and the window it claims can spell the same app two
    /// ways (see `keys(for:)`). Registering under the window's own key then
    /// leaves the tile looking for a texture nobody filed.
    func ensure(key: String, window: Win32Window, size: Int = 32) {
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        let handle = window.handle
        rasterize(key: key) { Win32Icon.rasterize(window: handle, size: size) }
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
        ensure(key: Self.key(for: app), app: app, size: size)
    }

    /// The same, filed under a key the caller chose — see the window form.
    func ensure(key: String, app: Win32App, size: Int = 48) {
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        let source = app.target.isEmpty ? app.shortcutPath : app.target
        rasterize(key: key) { Win32Icon.rasterize(path: source, size: size) }
    }

    /// Rasterizes for an arbitrary key and path — the file explorer's case,
    /// where the key is a TYPE (a directory, or an extension) and the path is
    /// merely the first file seen of that type. Every `.png` in a folder
    /// shares one texture; a thousand files do not mean a thousand icons.
    func ensure(key: String, path: String, size: Int = 32) {
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        rasterize(key: key) { Win32Icon.rasterize(path: path, size: size) }
    }

    /// Rasterizes a file's THUMBNAIL -- per FILE, unlike everything above,
    /// because a thousand photos are a thousand pictures where they were one
    /// type icon. A type with no thumbnail handler fails inside and lands in
    /// `attempted`, so the row keeps its type icon and the miss is not
    /// retried on every rebuild.
    func ensure(thumbnailKey key: String, path: String, size: Int) {
        guard textures[key] == nil, !attempted.contains(key) else { return }
        attempted.insert(key)
        rasterize(key: key) { Win32Icon.thumbnail(path: path, side: size) }
    }

    /// Rasterizes a tray icon, which arrives as a HANDLE rather than a path:
    /// the app drew it, and there is no file anywhere to point at.
    ///
    /// The handle belongs to this call from here on, whether or not it is
    /// used — it was taken out of a snapshot that has already been freed, so
    /// the alternative to destroying it here is leaking one icon per refresh,
    /// and the refresh runs whenever any app touches its tray icon.
    func ensure(trayKey key: String, icon handle: UInt64, size: Int = 32) {
        guard handle != 0 else { return }
        guard textures[key] == nil, !attempted.contains(key) else {
            Win32Icon.destroy(handle)
            return
        }
        attempted.insert(key)
        rasterize(key: key) {
            defer { Win32Icon.destroy(handle) }
            return Win32Icon.rasterize(icon: handle, size: size)
        }
    }

    /// Rasterize off the UI thread, register on it.
    ///
    /// The expensive half is the shell asking for an HICON and drawing it into
    /// a DIB — 79 of them measured 607ms, which is a third of a second of a
    /// frozen dock if it happens where the frames are drawn. The engine half
    /// has to be on the platform thread, so it goes back there and no further.
    ///
    /// `attempted` is marked before dispatching, so a rebuild that runs while
    /// this is in flight does not queue the same icon twice.
    /// ONE serial queue, not a task per icon.
    ///
    /// `Task.detached` per icon puts all 79 onto the cooperative pool at once,
    /// and the shell does not enjoy being asked for 79 icons simultaneously:
    /// measured, 15 of them came back empty and drew a generic glyph, while
    /// the same 79 done one after another all succeeded. Icon extraction is
    /// also genuinely serial work — it is one shell, one icon cache — so
    /// queueing it costs nothing and removes the contention.
    private static let queue = DispatchQueue(label: "starling.icons.rasterize",
                                             qos: .userInitiated)

    private func rasterize(key: String, _ make: @escaping @Sendable () -> Win32Icon.Bitmap?) {
        Self.queue.async {
            guard let bitmap = make() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    // Nobody left to own it, so it must not be leaked.
                    bitmap.discard()
                    return
                }
                guard self.textures[key] == nil else {
                    bitmap.discard()
                    return
                }
                guard let id = Win32WindowedHost.host?.registerPixels(bitmap) else {
                    return
                }
                self.textures[key] = id
                self.scheduleReady()
            }
        }
    }

    /// Coalesces the "a texture landed" notification.
    ///
    /// The launcher registers 79 of them within a few hundred milliseconds of
    /// startup, and one rebuild each would be 79 rebuilds of a 79-tile grid.
    /// One per turn of the main queue is enough — every texture that arrived
    /// in that window is picked up by the same rebuild.
    private var readyScheduled = false

    private func scheduleReady() {
        guard !readyScheduled else { return }
        readyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            readyScheduled = false
            onTextureReady?()
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
