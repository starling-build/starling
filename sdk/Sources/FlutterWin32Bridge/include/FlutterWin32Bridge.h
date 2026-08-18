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

// Shell chrome. `edge` is 0=top 1=bottom 2=left 3=right; `thickness` is in
// PHYSICAL pixels (the engine applies the monitor's DPI to the tree inside);
// `monitor` is an index into flwin32_monitor_rect, or -1 for the primary.
void flwin32_host_set_panel(FlWin32Host* host,
                            int32_t edge,
                            int32_t thickness,
                            int32_t monitor);

int32_t flwin32_monitor_count(void);
int32_t flwin32_monitor_rect(int32_t index,
                             int32_t* x,
                             int32_t* y,
                             int32_t* width,
                             int32_t* height,
                             int32_t* primary);

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

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_WIN32_BRIDGE_H
