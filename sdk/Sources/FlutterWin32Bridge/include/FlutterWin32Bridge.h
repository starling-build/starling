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
void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor,
                            int32_t takes_focus);

// Register (or remove) the window as an appbar, so Windows reserves the strip
// and maximized windows stop at it. Call after flwin32_host_set_panel, which
// is where the edge and thickness come from. Returns non-zero on success.
int32_t flwin32_host_set_appbar(FlWin32Host* host, int32_t enable);

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

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_WIN32_BRIDGE_H
