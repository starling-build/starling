// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "include/FlutterCocoaBridge.h"

#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>

// Direct inclusion of the vendored framework headers, the same way the GTK and
// Win32 bridges include theirs. They import each other by bare filename — the
// framework flattens macos/ and darwin/common/ into one Headers directory and
// the sources are written for that — so the vendored copies sit flat here and
// need no include path.
#import "flutter_macos/FlutterEngine.h"
#import "flutter_macos/FlutterViewController.h"

// FlutterDartProject's assets initializer is declared in
// FlutterDartProject_Internal.h, which the framework does not publish, so it
// cannot be reached through the vendored public headers. Redeclaring the
// selector is enough: ObjC dispatches by selector, the implementation is
// compiled into the framework we link, and nothing here needs the internal
// header's other contents.
//
// The alternative is the bundle-relative path
// (initWithPrecompiledDartBundle:), which resolves assets under
// Contents/Frameworks/App.framework — correct for a .app, and nothing a
// `swift build` executable has. Pointing at explicit paths is what the GTK and
// Win32 hosts do too (<exe dir>/data), so the three hosts agree.
@interface FlutterDartProject (StarlingAssets)
- (nonnull instancetype)initWithAssetsPath:(nonnull NSString*)assets
                               ICUDataPath:(nonnull NSString*)icuPath;
@end

// The engine's own embedder owns the view; ours is only the window that hosts
// it, so the state here is small. Strong references, because nothing else
// retains these: the window would otherwise be released as soon as create()
// returns, and AppKit would tear down the view controller with it.
struct FlCocoaHost {
  void* window;            // NSWindow*
  void* view_controller;   // FlutterViewController*
  void* engine;            // FlutterEngine*
  void* delegate;          // FlCocoaAppDelegate*
};

// Quits the loop when the window closes. A bare NSWindow does not terminate
// the app on close — without this the window disappears and the process keeps
// running with no way to reach it. (This is what NSApplicationMain gets from
// the nib's "terminate on last window closed"; a nib-less app has to say so.)
@interface FlCocoaAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation FlCocoaAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  return YES;
}
@end

// A menu bar with one item: Quit. An app with no menu at all still shows its
// name in the menu bar under the Regular activation policy, but ⌘Q does
// nothing — the shortcut is a menu item's key equivalent, not a system
// binding, so without this the only way out is the window's close button.
// A .app gets this from MainMenu.nib; a bare executable has to build it.
static void install_minimal_menu(NSApplication* app, const char* title) {
  NSString* name = [NSString stringWithUTF8String:title != NULL ? title : "Flutter"];
  NSMenu* bar = [[NSMenu alloc] init];
  NSMenuItem* appItem = [[NSMenuItem alloc] init];
  [bar addItem:appItem];
  NSMenu* appMenu = [[NSMenu alloc] init];
  [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name]
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  appItem.submenu = appMenu;
  app.mainMenu = bar;
}

FlCocoaHost* flcocoa_host_create(const char* title,
                                 int32_t width,
                                 int32_t height,
                                 const char* assets_path,
                                 const char* icu_data_path,
                                 const void* runtime_controller) {
  if (![NSThread isMainThread]) {
    fprintf(stderr, "[FlCocoaHost] must be created on the main thread\n");
    return NULL;
  }
  if (assets_path == NULL || icu_data_path == NULL) {
    fprintf(stderr, "[FlCocoaHost] assets_path and icu_data_path are required\n");
    return NULL;
  }

  @autoreleasepool {
    NSApplication* app = [NSApplication sharedApplication];
    // Regular, not Accessory/Prohibited: a bare Mach-O executable launched from
    // a terminal is treated as a background process by default, so its windows
    // never take focus and no menu bar or Dock tile appears. An app bundle gets
    // this from Info.plist; we have no bundle, so say it here.
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];

    FlCocoaAppDelegate* delegate = [[FlCocoaAppDelegate alloc] init];
    app.delegate = delegate;
    install_minimal_menu(app, title);

    FlutterDartProject* project = [[FlutterDartProject alloc]
        initWithAssetsPath:[NSString stringWithUTF8String:assets_path]
               ICUDataPath:[NSString stringWithUTF8String:icu_data_path]];

    FlutterEngine* engine =
        [[FlutterEngine alloc] initWithName:@"starling"
                                    project:project
                     allowHeadlessExecution:NO];
    if (engine == nil) {
      fprintf(stderr, "[FlCocoaHost] could not create the engine\n");
      return NULL;
    }

    // initWithEngine: registers the controller with the engine (CommonInit ->
    // addViewController:), which is what satisfies runSwift's "no view
    // controller without headless mode" check below. The view itself is not
    // loaded yet — that happens when the window takes it as its content.
    FlutterViewController* controller =
        [[FlutterViewController alloc] initWithEngine:engine nibName:nil bundle:nil];

    NSRect frame = NSMakeRect(0, 0, width, height);
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = [NSString stringWithUTF8String:title != NULL ? title : "Flutter"];
    window.releasedWhenClosed = NO;

    // Load the view before running the engine, and run the engine before the
    // window is shown. Both halves of that matter, and they are what pins this
    // between the two things the embedder does on its own:
    //
    //  - contentViewController loads the view (loadView needs only the Metal
    //    device, which the engine has from its own init). The engine's run
    //    sends the initial FlutterWindowMetricsEvent for every registered
    //    controller, and updateWindowMetricsForViewController returns early
    //    for a controller whose view is not loaded — so running first means
    //    the engine never learns the view's size, and nothing composites.
    //    Upstream gets this ordering for free: it runs the engine from
    //    viewWillAppear, by which point the view exists.
    //  - The window is NOT shown yet. Showing it fires viewWillAppear, which
    //    launches the engine itself if it is not already running — through
    //    runWithEntrypoint:, the Dart path. Getting there first is what makes
    //    this Swift mode rather than an engine looking for a Dart isolate.
    window.contentViewController = controller;

    // Re-apply the size, then centre. Assigning contentViewController makes
    // AppKit resize the window to the view's *fitting size*, and a FlutterView
    // is a bare NSView with no intrinsic content size and no constraints — so
    // the requested 480x720 collapses to a 1pt-wide sliver of title bar. The
    // window is still there and the engine still renders into it, which is the
    // confusing part: frames flow, the widget tree builds, and there is simply
    // nothing on screen to see. Setting the content size afterwards is what
    // Flutter's own macOS runner does (MainFlutterWindow sets its frame after
    // assigning the controller).
    [window setContentSize:NSMakeSize(width, height)];
    [window center];

    // Optional explicit placement, for the same reason the callers expose the
    // size: putting this window beside another terminal is the only way to
    // film or measure the two head-to-head. Top-left corner in points from
    // the main screen's top-left; both unset (or empty — an empty env var
    // must mean "unset", never "0") keeps the centred default.
    const char* pos_x = getenv("STARLING_WINDOW_X");
    const char* pos_y = getenv("STARLING_WINDOW_Y");
    if (pos_x != NULL && pos_x[0] != '\0' && pos_y != NULL && pos_y[0] != '\0') {
      NSRect screen = [NSScreen mainScreen].frame;
      [window setFrameTopLeftPoint:NSMakePoint(NSMinX(screen) + strtod(pos_x, NULL),
                                               NSMaxY(screen) - strtod(pos_y, NULL))];
    }

    if (![engine runSwiftWithRuntimeCallbacks:runtime_controller]) {
      fprintf(stderr, "[FlCocoaHost] the engine refused to start in Swift mode "
                      "(assets: %s, icu: %s)\n",
              assets_path, icu_data_path);
      return NULL;
    }

    FlCocoaHost* host = (FlCocoaHost*)calloc(1, sizeof(FlCocoaHost));
    if (host == NULL) {
      return NULL;
    }
    // CFBridgingRetain: these outlive the autorelease pool and the C caller has
    // no ARC to keep them alive.
    host->window = (void*)CFBridgingRetain(window);
    host->view_controller = (void*)CFBridgingRetain(controller);
    host->engine = (void*)CFBridgingRetain(engine);
    host->delegate = (void*)CFBridgingRetain(delegate);
    return host;
  }
}

void flcocoa_host_show(FlCocoaHost* host) {
  if (host == NULL) {
    return;
  }
  @autoreleasepool {
    NSWindow* window = (__bridge NSWindow*)host->window;
    [window makeKeyAndOrderFront:nil];
    // The window is created before the app finishes launching, so it needs an
    // explicit activation to come to the front of a terminal-launched process.
    [NSApp activateIgnoringOtherApps:YES];
    // Keyboard input goes to the first responder; the FlutterView is what the
    // embedder listens on.
    [window makeFirstResponder:window.contentViewController.view];
  }
}

void flcocoa_host_run(FlCocoaHost* host) {
  if (host == NULL) {
    return;
  }
  // No GCD drain timer here, unlike the GTK and Win32 hosts. On Darwin
  // libdispatch installs the main queue onto the main run loop itself
  // (_dispatch_main_queue_callback_4CF is CFRunLoop's own hook), so
  // DispatchQueue.main and @MainActor work under [NSApp run] with nothing
  // added.
  [NSApp run];
}

void flcocoa_host_set_fullscreen(FlCocoaHost* host, int32_t fullscreen) {
  if (host == NULL) {
    return;
  }
  @autoreleasepool {
    NSWindow* window = (__bridge NSWindow*)host->window;
    BOOL isFullscreen = (window.styleMask & NSWindowStyleMaskFullScreen) != 0;
    if (isFullscreen != (fullscreen != 0)) {
      [window toggleFullScreen:nil];
    }
  }
}
