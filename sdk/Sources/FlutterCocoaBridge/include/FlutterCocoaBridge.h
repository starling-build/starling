// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The Cocoa host for a FlutterSwift app: the engine's real macOS embedder
// (FlutterMacOS.framework — FlutterViewController, Metal rendering, input,
// IME, a11y) inside an ordinary NSWindow, with the engine started in Swift
// mode so the Swift framework drives frames instead of a Dart isolate.
//
// This header is the whole Swift-visible surface. <Cocoa/Cocoa.h> and the
// Flutter* ObjC classes stay behind it — the glue imports them, the
// C++-interop importer never sees them. Same containment the GTK bridge gives
// flutter_linux and the Win32 bridge gives flutter_windows.

#ifndef FLUTTER_COCOA_BRIDGE_H
#define FLUTTER_COCOA_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FlCocoaHost FlCocoaHost;

// Creates the NSApplication, the window, the engine and the view controller,
// and starts the engine in Swift mode with `runtime_controller` (a
// SwiftRuntimeCallbacks*, which must outlive the host).
//
// `assets_path` and `icu_data_path` are absolute paths to flutter_assets and
// icudtl.dat. They are not optional: a SwiftPM executable is a bare Mach-O,
// not a .app, so FlutterDartProject's bundle-relative lookup has nothing to
// find.
//
// Must be called on the main thread. Returns NULL if the engine could not be
// created or started; the reason lands on stderr.
FlCocoaHost* flcocoa_host_create(const char* title,
                                 int32_t width,
                                 int32_t height,
                                 const char* assets_path,
                                 const char* icu_data_path,
                                 const void* runtime_controller);

// Shows the window and brings the app to the front.
void flcocoa_host_show(FlCocoaHost* host);

// Runs the AppKit event loop. Returns when the window is closed.
void flcocoa_host_run(FlCocoaHost* host);

// Fullscreens or restores the window.
void flcocoa_host_set_fullscreen(FlCocoaHost* host, int32_t fullscreen);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_COCOA_BRIDGE_H
