// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The UIKit host for a FlutterSwift app: the engine's real iOS embedder
// (Flutter.framework — FlutterViewController, Metal rendering, touch input,
// the software keyboard, a11y) inside an ordinary UIWindow, with the engine
// started in Swift mode so the Swift framework drives frames instead of a
// Dart isolate.
//
// This header is the whole Swift-visible surface. <UIKit/UIKit.h> and the
// Flutter* ObjC classes stay behind it — the glue imports them, the
// C++-interop importer never sees them. Same containment the Cocoa bridge
// gives FlutterMacOS, the GTK bridge gives flutter_linux and the Win32 bridge
// gives flutter_windows.

#ifndef FLUTTER_UIKIT_BRIDGE_H
#define FLUTTER_UIKIT_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Called on the main thread once the engine is running in Swift mode and
// before any view is attached to it, which is the only window in which the
// widget tree can be mounted: the engine asks for its first frame as soon as
// the view reports its size, and a frame with no tree behind it composites
// nothing and is never retried.
typedef void (*FlUIKitStartedCallback)(void* user_data);

// Runs the whole application: installs an app delegate, enters UIKit's run
// loop, and on launch creates the engine, starts it in Swift mode with
// `runtime_controller` (a SwiftRuntimeCallbacks*, which must outlive the
// process), calls `on_started`, and puts a FlutterViewController on screen.
//
// Unlike the Cocoa host there is no create/show/run split, because iOS does
// not offer one: UIApplicationMain owns the launch sequence and everything an
// app does at startup happens inside a delegate callback it drives. So this
// takes the callback instead of handing back a host object.
//
// Assets and ICU data are resolved from the app bundle — `flutter_assets` in
// the bundle root and `icudtl.dat` inside Flutter.framework, which is where
// the framework's own lookup goes. That is the reverse of the Cocoa host,
// which must pass explicit paths precisely because a `swift build` executable
// is not a bundle; here there always is one.
//
// Must be called on the main thread. Does not return: UIApplicationMain exits
// the process rather than unwinding. Returns non-zero only if UIKit could not
// be entered at all.
int32_t fluikit_host_run(const char* title,
                         const void* runtime_controller,
                         FlUIKitStartedCallback on_started,
                         void* user_data);

// The size in logical pixels of the window the app was given, valid once
// `on_started` has been called. iOS decides this, not the app — there is no
// requested width and height to honour — so the Swift side reads it rather
// than passing one in.
void fluikit_host_window_size(double* out_width, double* out_height);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_UIKIT_BRIDGE_H
