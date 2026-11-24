// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The UIKit host for a FlutterSwift app: the engine's real iOS embedder
// (Flutter.framework — FlutterViewController, Metal rendering, touch input,
// a11y) inside an ordinary UIWindow, with the engine started in Swift mode so
// the Swift framework drives frames instead of a Dart isolate.
//
// The software keyboard is the one thing the embedder does NOT give us. Its
// FlutterTextInputPlugin only raises a keyboard once the framework opens a
// flutter/textinput client, which a Swift framework with no Dart text-editing
// layer never does — so this bridge implements UIKeyInput itself. Why that is
// also the right answer rather than a stopgap: fluikit_keyboard.m.
//
// This header is the whole Swift-visible surface. <UIKit/UIKit.h> and the
// Flutter* ObjC classes stay behind it — the glue imports them, the
// C++-interop importer never sees them. Same containment the Cocoa bridge
// gives FlutterMacOS, the GTK bridge gives flutter_linux and the Win32 bridge
// gives flutter_windows.

#ifndef FLUTTER_UIKIT_BRIDGE_H
#define FLUTTER_UIKIT_BRIDGE_H

#include <stdbool.h>
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

// MARK: - Embedding: an app's own native screens around the Flutter view
//
// By default the Flutter view IS the app: the root view controller is the
// host's own, a FlutterViewController pinned to the safe area. An app that
// wants native UIKit around its widget tree — a document browser, a settings
// screen, native toolbars — installs a root factory before fluikit_host_run.
//
// The factory is handed the "editor" view controller (the host's wrapper
// around the Flutter view, not yet loaded: do not touch its `view`, or the
// engine is asked for a frame before anything is ready to show it) and returns
// the app's real root, which presents or embeds the editor when it likes. The
// returned UIViewController* is a +1 reference (CFBridgingRetain); the editor
// pointer is borrowed.
//
// All pointers are UIViewController*, passed as void* because UIKit stays
// behind this header.
typedef void* (*FlUIKitRootFactory)(void* editor_view_controller, void* user);
void fluikit_host_set_root_factory(FlUIKitRootFactory factory, void* user);

// A file or URL handed to the app from outside — "Open in…", a Files tap, the
// share sheet, `xcrun simctl openurl`. `url` is the absolute URL string as
// UTF-8 (a file: URL for documents). Return true if handled. Called on the main
// thread. Without a handler the host ignores it.
typedef bool (*FlUIKitOpenURLCallback)(void* user, const char* url);
void fluikit_host_set_open_url_handler(FlUIKitOpenURLCallback handler, void* user);

// MARK: - Software keyboard
//
// See fluikit_keyboard.m for why this exists at all: iOS emits key events only
// for a hardware keyboard, so a framework that reads keys gets nothing from the
// on-screen one until something implements UIKeyInput.

// Named keys the on-screen keyboard and its accessory bar can produce. The
// values are X11 keysyms because that is what TerminalInput already switches
// on, so a synthesized key needs no translation table of its own.
typedef enum {
  kFlUIKitKeyBackspace = 0xFF08,
  kFlUIKitKeyTab = 0xFF09,
  kFlUIKitKeyEnter = 0xFF0D,
  kFlUIKitKeyEscape = 0xFF1B,
  kFlUIKitKeyLeft = 0xFF51,
  kFlUIKitKeyUp = 0xFF52,
  kFlUIKitKeyRight = 0xFF53,
  kFlUIKitKeyDown = 0xFF54,
} FlUIKitKey;

// One keystroke. Exactly one of the two arrows is taken:
//   `text` non-NULL — characters that were typed, UTF-8, with Ctrl already
//                     folded in (Ctrl+C arrives as 0x03, as from a hardware
//                     keyboard), and `keysym` is 0.
//   `text` NULL     — `keysym` is one of FlUIKitKey.
// `shift` is set when the bar's Shift was armed for this key; it matters for
// the chords the bar exists to send, Shift+Tab above all.
//
// Called on the main thread.
typedef void (*FlUIKitKeyCallback)(void* user,
                                   const char* text,
                                   int32_t keysym,
                                   int32_t shift);

// Installs the key-input responder inside the given FlutterView. Under the
// Flutter view rather than beside it, so an unhandled hardware press keeps
// travelling up the responder chain into the engine.
void fluikit_keyboard_attach(void* flutter_view);

// Views beyond the first, each a UIView with a CAMetalLayer of its own at `x, y, w, h` (points, in the key
// window), showing view `view_id` of the same engine (docs/plans/ipad-multi-window.md). `done` is called on
// the platform thread with whether the engine took the add / remove. Resize moves the engine's size too.
// Used by the host's self-test; the product's windows will come through scenes.
typedef void (*FlUIKitViewDone)(int64_t view_id, bool ok, void* user);
void fluikit_view_add(int64_t view_id, double x, double y, double w, double h, FlUIKitViewDone done, void* user);
void fluikit_view_resize(int64_t view_id, double w, double h);
void fluikit_view_remove(int64_t view_id, FlUIKitViewDone done, void* user);
double fluikit_screen_scale(void);

void fluikit_keyboard_set_callback(FlUIKitKeyCallback cb, void* user);

// Raise and dismiss the on-screen keyboard. Showing it is what makes the
// accessory bar appear too, so a hardware-keyboard user who wants Escape and
// the arrows asks for this as well.
void fluikit_keyboard_show(void);
void fluikit_keyboard_hide(void);
bool fluikit_keyboard_visible(void);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_UIKIT_BRIDGE_H
