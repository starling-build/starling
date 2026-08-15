// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#include "include/FlutterUIKitBridge.h"

#import <UIKit/UIKit.h>

// The process's real argc/argv. UIApplicationMain declares both _Nonnull and
// forwards them to the app; Swift's `main` has already consumed them by the
// time this is called, and these two are how libc hands them back.
#include <crt_externs.h>
#include <stdio.h>

// Direct inclusion of the vendored framework headers, the same way the Cocoa,
// GTK and Win32 bridges include theirs. They import each other by bare
// filename — the framework flattens ios/ and darwin/common/ into one Headers
// directory and the sources are written for that — so the vendored copies sit
// flat here and need no include path.
#import "flutter_ios/FlutterEngine.h"
#import "flutter_ios/FlutterViewController.h"

// UIApplicationMain takes a delegate *class name* and constructs the instance
// itself, so there is no way to hand the delegate its arguments. They go here
// instead. One app per process, so file statics are the whole story — the
// same shape as the Cocoa host's single FlCocoaHost, minus the handle, since
// nothing on this platform can outlive UIApplicationMain to hold one.
static const void* g_runtime_controller = NULL;
static FlUIKitStartedCallback g_on_started = NULL;
static void* g_user_data = NULL;
static NSString* g_title = nil;
static CGSize g_window_size = {0, 0};

// Hosts the FlutterViewController as a child, pinned to the safe-area layout
// guide rather than to the window's edges.
//
// The ported framework has no MediaQuery padding and no SafeArea widget — it
// grew up on a desktop, where nothing overlaps a window — so a tree given the
// whole screen draws its first row under the status bar and its last behind
// the home indicator. Insetting the view instead of teaching the framework
// about padding fixes it for every app at once and keeps working through
// rotation and a raised keyboard, because the constraints are UIKit's and it
// re-lays them out; the engine simply sees the view resize and sends new
// viewport metrics, which is a path that already works.
//
// The cost is that the inset area is this container's background rather than
// app content — correct for a terminal, and a decision to revisit if an app
// ever wants to draw under the status bar.
@interface FlUIKitRootViewController : UIViewController
- (instancetype)initWithFlutterViewController:(UIViewController*)flutter;
@end

@implementation FlUIKitRootViewController {
  UIViewController* _flutter;
}

- (instancetype)initWithFlutterViewController:(UIViewController*)flutter {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _flutter = flutter;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;

  [self addChildViewController:_flutter];
  UIView* child = _flutter.view;
  child.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:child];
  UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
  // The bottom edge follows the KEYBOARD, not the safe area: the guide's top
  // sits at the safe-area bottom while no keyboard is up, and rides the
  // keyboard's top edge while one is — so the Flutter view shrinks, the
  // framework gets a metrics event, and a terminal refits its rows with the
  // prompt landing just above the keys instead of underneath them.
  [NSLayoutConstraint activateConstraints:@[
    [child.topAnchor constraintEqualToAnchor:safe.topAnchor],
    [child.bottomAnchor
        constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
    [child.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
    [child.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
  ]];
  [_flutter didMoveToParentViewController:self];

  // The key-input responder goes inside the Flutter view, not beside it — see
  // fluikit_keyboard.m for why the responder chain makes that load-bearing.
  fluikit_keyboard_attach((__bridge void*)child);
}

// The status bar over a terminal is white-on-black like everything else here.
- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

@end

@interface FlUIKitAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@property(nonatomic, strong) FlutterEngine* engine;
@property(nonatomic, strong) FlutterViewController* viewController;
@end

@implementation FlUIKitAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  // A bundle-relative project: `flutter_assets` in the bundle root and
  // icudtl.dat inside Flutter.framework. Passing nil means the main bundle,
  // and FLTAssetsPathFromBundle falls back to a bare `flutter_assets` lookup
  // when there is no App.framework — which is exactly our layout, since a
  // Swift app has no Dart kernel to put in one.
  FlutterDartProject* project = [[FlutterDartProject alloc] initWithPrecompiledDartBundle:nil];

  FlutterEngine* engine = [[FlutterEngine alloc] initWithName:@"starling"
                                                      project:project
                                       allowHeadlessExecution:NO];
  if (engine == nil) {
    fprintf(stderr, "[FlUIKitHost] could not create the engine\n");
    return NO;
  }

  // Swift mode before any view controller exists. The iOS embedder is the
  // mirror image of the Cocoa one here: FlutterViewController's Dart-running
  // path is initWithProject:, which builds an engine and runs it, while
  // initWithEngine: takes an engine as given and never starts one. So unlike
  // macOS there is no race to win against viewWillAppear — the requirement is
  // only that the engine is already running by the time we hand it over, and
  // running it first is also what lets the widget tree be mounted before the
  // view reports a size and asks for the first frame.
  if (![engine runSwiftWithRuntimeCallbacks:g_runtime_controller]) {
    fprintf(stderr, "[FlUIKitHost] the engine refused to start in Swift mode — "
                    "check that flutter_assets is in the app bundle and that "
                    "Flutter.framework carries icudtl.dat\n");
    return NO;
  }
  self.engine = engine;

  UIWindow* window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  g_window_size = window.bounds.size;

  // Mount the tree now: after the engine is up (the Swift runtime callbacks
  // are live, so runApp can schedule a frame) and before the view controller
  // is attached (which is what makes the engine ask for one).
  if (g_on_started != NULL) {
    g_on_started(g_user_data);
  }

  FlutterViewController* controller = [[FlutterViewController alloc] initWithEngine:engine
                                                                            nibName:nil
                                                                             bundle:nil];
  self.viewController = controller;
  window.rootViewController =
      [[FlUIKitRootViewController alloc] initWithFlutterViewController:controller];
  self.window = window;
  [window makeKeyAndVisible];
  return YES;
}

@end

int32_t fluikit_host_run(const char* title,
                         const void* runtime_controller,
                         FlUIKitStartedCallback on_started,
                         void* user_data) {
  if (![NSThread isMainThread]) {
    fprintf(stderr, "[FlUIKitHost] must be run on the main thread\n");
    return 1;
  }
  if (runtime_controller == NULL) {
    fprintf(stderr, "[FlUIKitHost] a runtime controller is required\n");
    return 1;
  }

  g_runtime_controller = runtime_controller;
  g_on_started = on_started;
  g_user_data = user_data;
  g_title = [NSString stringWithUTF8String:title != NULL ? title : "Flutter"];

  @autoreleasepool {
    // Does not return. The delegate is named rather than passed, which is why
    // the arguments above had to go through statics.
    return (int32_t)UIApplicationMain(*_NSGetArgc(), *_NSGetArgv(), nil,
                                      NSStringFromClass([FlUIKitAppDelegate class]));
  }
}

void fluikit_host_window_size(double* out_width, double* out_height) {
  if (out_width != NULL) {
    *out_width = g_window_size.width;
  }
  if (out_height != NULL) {
    *out_height = g_window_size.height;
  }
}
