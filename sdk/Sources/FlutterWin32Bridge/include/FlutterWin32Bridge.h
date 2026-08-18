// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The Win32 host for a FlutterSwift app: the engine's real Windows embedder
// (flutter_windows.dll — the view controller, input, IME, a11y) inside an
// ordinary top-level window, with the engine started in Swift mode so the
// Swift framework drives frames instead of a Dart isolate.
//
// This header is the whole Swift-visible surface. <windows.h> and the
// flutter_windows types stay behind it — the C glue includes them, the
// C++-interop importer never sees them. That matters more here than on Linux:
// windows.h defines several thousand macros, and letting it reach the importer
// collides with ordinary Swift names.

#ifndef FLUTTER_WIN32_BRIDGE_H
#define FLUTTER_WIN32_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlWin32Host FlWin32Host;

// Registers the window class, creates the top-level window and the engine,
// puts the engine into Swift mode with `runtime_controller` (a
// SwiftRuntimeCallbacks*, which must outlive the host), and creates the view
// controller — which is what starts the engine.
//
// `title` is UTF-8 and is converted to UTF-16 internally.
//
// Returns NULL if the window or the engine could not be created; the reason
// lands on stderr.
FlWin32Host* flwin32_host_create(const char* title,
                                 int32_t width,
                                 int32_t height,
                                 const void* runtime_controller);

// Borrows the launching console, if the app was launched from one.
//
// A GUI-subsystem binary (which is what an app with a window should be —
// see the /SUBSYSTEM:WINDOWS note in the app's Package.swift) starts with no
// console, so `printf` and Swift's `print` go nowhere. Run from a shell that
// is a problem; run from Explorer it is the entire point. This resolves both:
// attach to the parent's console when there is one, leave a redirected stream
// alone, and do nothing at all under Explorer.
//
// Call once, before anything prints. Safe to call from a console-subsystem
// build, where it returns immediately.
void flwin32_attach_parent_console(void);

// Shows the window.
void flwin32_host_show(FlWin32Host* host);

// Runs the Win32 message loop (with the GCD main queue drained on a timer so
// @MainActor / DispatchQueue.main work). Returns when the window is closed.
void flwin32_host_run(FlWin32Host* host);

// Fullscreens or restores the window.
void flwin32_host_set_fullscreen(FlWin32Host* host, int32_t fullscreen);

// Shell chrome. `edge` is 0=top 1=bottom 2=left 3=right; `monitor` is an
// index into flwin32_monitor_rect, or -1 for the primary.
//
// `thickness` is in LOGICAL POINTS, not pixels: it is multiplied by the
// target monitor's scale here, and re-derived on every WM_DPICHANGED. A bar
// asking for 44 is 44px at 100% and 88px at 200%, and its widget tree sees
// 44 either way. Pixels would have been the smaller change and are wrong on
// exactly the machines this has to look right on.
//
// `takes_focus` = 0 gives the window WS_EX_NOACTIVATE, which is what makes it
// chrome: clicking it does not move the keyboard away from whatever the user
// was typing in. Pass non-zero only for a panel that has a text field.
//
// `transparent` makes anything the tree paints as pure black disappear, and
// lets clicks there fall through — how a dock floats over the wallpaper
// instead of sitting in a black strip. It costs the ability to paint true
// black in that panel.
//
// `overhang` (logical points) makes the WINDOW extend that much further in
// from the edge than the strip it reserves. A dock needs it to draw above
// itself — a hover label, a right-click menu — because a window is a hard
// clip. It is transparent and click-through until something paints there.
void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor,
                            int32_t takes_focus,
                            int32_t transparent,
                            int32_t overhang);

// Register (or remove) the window as an appbar, so Windows reserves the strip
// and maximized windows stop at it. Call after flwin32_host_set_panel, which
// is where the edge and thickness come from. Returns non-zero on success.
int32_t flwin32_host_set_appbar(FlWin32Host* host, int32_t enable);

// ── overlays ────────────────────────────────────────────────────────────────
//
// A full-screen surface that is usually not there: the launcher, and later
// Mission Control. Unlike a panel it covers the monitor, reserves nothing,
// TAKES focus, and spends most of its life hidden — hidden rather than not
// running, because starting an engine takes about a second and a launcher has
// to appear the instant it is asked for.
//
// `alpha` is the whole surface's opacity, 0-255; -1 keeps the current one.
void flwin32_host_set_overlay(FlWin32Host* host, int32_t monitor, int32_t alpha);
void flwin32_host_set_visible(FlWin32Host* host, int32_t visible);
int32_t flwin32_host_is_visible(FlWin32Host* host);

// Cross-process toggle. The bar and the launcher are separate processes (the
// framework mounts one widget root per process), so a click on the bar
// reaches the launcher as a broadcast of a registered window message — the
// documented way for unrelated processes to talk with no socket or pipe.
void flwin32_host_on_toggle(FlWin32Host* host,
                            void (*callback)(void* user),
                            void* user);
void flwin32_shell_broadcast_toggle(void);

int32_t flwin32_monitor_count(void);
int32_t flwin32_monitor_rect(int32_t index,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height,
                             int32_t* primary);
// The monitor's DPI, where 96 is 100%. Falls back to 96 rather than failing:
// a wrong scale draws a bar at the wrong size, no scale at all draws nothing.
int32_t flwin32_monitor_dpi(int32_t index);

// Clipboard. Text is UTF-8 on this boundary and converted to/from UTF-16
// inside, so the Swift side never handles wide strings.
//
// Unlike the Wayland and GTK backends this is synchronous: Win32 hands over
// the data itself rather than asking the current owner to write it, so there
// is nothing to wait on and no way for another process to stall a paste.

// Puts UTF-8 `text` on the clipboard. Returns 1 on success.
int32_t flwin32_clipboard_set_text(const char* text);

// Reads the clipboard as UTF-8 into `out`. Returns the number of bytes
// written including the terminator, 0 when the clipboard holds no text, or
// -1 if `out` is too small (retry with a larger buffer).
int32_t flwin32_clipboard_get_text(char* out, int32_t out_size);

// ── window management ───────────────────────────────────────────────────────
//
// Starling on Windows cannot own other people's pixels — DWM is not
// replaceable — so it manages their windows instead: enumerate them, move
// them, raise them, and watch them come and go. This is the half of the port
// that stands in for the compositor, and everything below is plain user32.
//
// The window LIST is a snapshot object rather than a callback or an array of
// structs: enumerating twice (once to count, once to fill) races against
// windows opening, and a struct carrying fixed-size char arrays imports into
// Swift as tuples. So enumerate once, hold the result, read scalars and
// strings out of it by index, release it.

typedef struct FlWin32WindowList FlWin32WindowList;

// Scalars for one window in a snapshot. Strings come out separately, through
// flwin32_wm_title / _class / _exe.
typedef struct {
  uint64_t handle;  // the HWND, opaque on this side of the boundary
  uint32_t pid;
  // The VISIBLE frame, in virtual-desktop pixels: DWM's extended frame
  // bounds, not GetWindowRect, which on Windows 10+ includes an invisible
  // resize border ~7px wide on each side. A tiler that uses the raw rect
  // leaves gaps it cannot explain.
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  int32_t monitor;  // index into flwin32_monitor_rect, or -1
  int32_t minimized;
  int32_t maximized;
  int32_t foreground;
} FlWin32WindowInfo;

// Enumerates the manageable top-level windows — what a taskbar would show.
// Never NULL unless allocation failed. Release with flwin32_wm_release.
FlWin32WindowList* flwin32_wm_snapshot(void);
int32_t flwin32_wm_count(FlWin32WindowList* list);
int32_t flwin32_wm_info(FlWin32WindowList* list,
                        int32_t index,
                        FlWin32WindowInfo* out);
// UTF-8 out, same convention as flwin32_clipboard_get_text: bytes written
// including the terminator, or -1 if `out` is too small.
int32_t flwin32_wm_title(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size);
int32_t flwin32_wm_class(FlWin32WindowList* list,
                         int32_t index,
                         char* out,
                         int32_t out_size);
int32_t flwin32_wm_exe(FlWin32WindowList* list,
                       int32_t index,
                       char* out,
                       int32_t out_size);
void flwin32_wm_release(FlWin32WindowList* list);

// Raises `handle` and gives it the keyboard. Returns non-zero on success.
int32_t flwin32_wm_activate(uint64_t handle);

// Moves and resizes so the VISIBLE frame lands on the given rectangle — the
// DWM correction described above is applied here, so callers can hand this
// the rectangle they actually want covered. Un-maximizes first; a maximized
// window ignores SetWindowPos.
int32_t flwin32_wm_move(uint64_t handle,
                        int32_t x,
                        int32_t y,
                        int32_t width,
                        int32_t height);

// 0 = restore, 1 = minimize, 2 = maximize.
int32_t flwin32_wm_set_state(uint64_t handle, int32_t state);

// Asks the window to close (WM_CLOSE), the way clicking its X does — the
// app may refuse or prompt. Never TerminateProcess.
int32_t flwin32_wm_close(uint64_t handle);

uint64_t flwin32_wm_foreground(void);

// The work area of a monitor: its rectangle minus the taskbar and any
// appbars, i.e. where a tiler should lay windows out. `monitor` is an index
// into flwin32_monitor_rect, or -1 for the primary.
int32_t flwin32_wm_work_area(int32_t monitor,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height);

// Window-list changes. The event ids:
#define FLWIN32_WM_EVENT_ADDED 1       // a manageable window appeared
#define FLWIN32_WM_EVENT_REMOVED 2     // destroyed or hidden
#define FLWIN32_WM_EVENT_FOREGROUND 3  // focus moved (handle = the new one)
#define FLWIN32_WM_EVENT_TITLE 4       // title changed
#define FLWIN32_WM_EVENT_MOVED 5       // a user drag/resize finished
#define FLWIN32_WM_EVENT_MINIMIZED 6   // minimized or restored

typedef void (*FlWin32WmEventCallback)(int32_t event,
                                       uint64_t handle,
                                       void* user);

// Installs the WinEvent hooks. Delivery is on the thread that calls this,
// through its message loop — so call it from the UI thread, after the host
// exists, and the callback arrives where the widget tree lives.
//
// Deliberately NOT hooked: EVENT_OBJECT_LOCATIONCHANGE, which fires per
// mouse-move for the whole drag and would rebuild the tree hundreds of times
// a second. MOVESIZEEND is the useful edge.
int32_t flwin32_wm_watch(FlWin32WmEventCallback callback, void* user);
void flwin32_wm_unwatch(void);

// ── app icons ───────────────────────────────────────────────────────────────
//
// The other half of a dock: the app's OWN icon rather than a glyph guessed
// from its executable name. Windows keeps it inside the window or inside the
// exe and hands it out as an HICON — a GDI object, not an image — so it has
// to be rasterized.

// Rasterizes `window`'s icon to premultiplied RGBA at `size` x `size`.
// Returns 1 and sets `*out_pixels` to a buffer the caller owns (release it
// with flwin32_icon_free), or 0 when the window has no icon to give.
int32_t flwin32_icon_rasterize(uint64_t window,
                               int32_t size,
                               uint8_t** out_pixels,
                               int32_t* out_width,
                               int32_t* out_height);
// The same, for a file — an .exe, or (usually) a Start Menu .lnk, whose icon
// is a property of the shortcut rather than of what it starts.
int32_t flwin32_icon_rasterize_path(const char* path,
                                    int32_t size,
                                    uint8_t** out_pixels,
                                    int32_t* out_width,
                                    int32_t* out_height);
void flwin32_icon_free(uint8_t* pixels);

// Rasterizes the icon and registers it with the engine as an external
// texture, so a `TextureWidget` can draw it. Returns the texture id, or -1.
// The pixels are held for the texture's lifetime and released when it is
// unregistered — the engine's own release_callback is not used, because the
// buffer is not per-frame.
int64_t flwin32_host_register_icon_texture(FlWin32Host* host,
                                           uint64_t window,
                                           int32_t size);

// Unregisters a texture from flwin32_host_register_icon_texture and frees its
// pixels. Unregistration is asynchronous inside the engine; the free happens
// in its completion callback, so the buffer outlives any frame still in
// flight.
int64_t flwin32_host_register_icon_texture_path(FlWin32Host* host,
                                                const char* path,
                                                int32_t size);

void flwin32_host_unregister_texture(FlWin32Host* host, int64_t texture_id);

// ── system status ───────────────────────────────────────────────────────────
//
// What a status bar is supposed to show, read from the system rather than
// drawn as decoration. Each comes from a different place and none of them is
// the obvious one — see flwin32_status.c.

// Battery. `present` is 0 on a desktop; `percent` is -1 when Windows will not
// say; `charging` means "on mains", which is what a bar should show even for
// a full battery. Returns non-zero if the status could be read at all.
int32_t flwin32_power_status(int32_t* present, int32_t* percent, int32_t* charging);

// Network. `kind` is 0 none, 1 ethernet, 2 wifi; `signal` is 0-100 and only
// meaningful for wifi; `ssid` is UTF-8 and may be empty.
int32_t flwin32_network_status(int32_t* kind,
                               int32_t* signal,
                               char* ssid,
                               int32_t ssid_size);

// The default output device's volume, 0-100, and whether it is muted.
int32_t flwin32_volume_status(int32_t* percent, int32_t* muted);

// ── installed applications ──────────────────────────────────────────────────
//
// Windows has no app registry the way Starling does on Linux. What it has is
// the START MENU: a tree of .lnk shortcuts in a machine-wide folder and a
// per-user one. That is the catalog Explorer itself reads, and the one the
// dock and the launcher enumerate.

// Resolves a .lnk to the path it starts. UTF-8 out, the usual convention:
// bytes written including the terminator, 0 when it is not a shortcut we can
// read, -1 when `out` is too small.
//
// A .lnk is a structured binary file, not a symlink; IShellLink is the only
// supported way to read one, and the target may be an item-ID list rather
// than a path, which nothing but the shell can resolve.
int32_t flwin32_shortcut_target(const char* shortcut_path,
                                char* out,
                                int32_t out_size);

// The Start Menu program folders: 0 = machine-wide, 1 = this user's. Both are
// needed — an app installed for all users is only in the first, and one
// installed for the current user only in the second, which on a modern
// Windows is most of them.
// The icon a shortcut DECLARES — a file path and an index into it, which is
// what most .lnk files carry. Worth asking before the shell's own answer:
// SHGetFileInfo on a shortcut composes the little overlay arrow into the
// icon, and in a dock that badge means nothing.
int32_t flwin32_shortcut_icon(const char* shortcut_path,
                              char* out,
                              int32_t out_size,
                              int32_t* index);

int32_t flwin32_known_folder(int32_t which, char* out, int32_t out_size);

// Starts an app, document or URL through the shell (ShellExecuteW), which is
// the only thing that knows how to open a .lnk. `arguments` may be NULL.
// Returns non-zero on success.
int32_t flwin32_launch(const char* path, const char* arguments);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_WIN32_BRIDGE_H
