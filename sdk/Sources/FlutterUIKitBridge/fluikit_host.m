// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#include "include/FlutterUIKitBridge.h"

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
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
static FlUIKitRootFactory g_root_factory = NULL;
static void* g_root_factory_user = NULL;
static FlUIKitOpenURLCallback g_open_url = NULL;
static void* g_open_url_user = NULL;

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
  [NSLayoutConstraint activateConstraints:@[
    [child.topAnchor constraintEqualToAnchor:safe.topAnchor],
    [child.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
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

// Our own additions to the engine's iOS embedder (FlutterEngine+StarlingViews.h in
// starling-engine): views beyond the first, each with a CAMetalLayer of its own.
@interface FlutterEngine (StarlingViews)
- (void)starlingAddViewWithId:(int64_t)viewId
                        layer:(CAMetalLayer*)layer
                         size:(CGSize)size
                   pixelRatio:(double)pixelRatio
                         done:(void (^)(BOOL added))done;
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
  UIViewController* editor =
      [[FlUIKitRootViewController alloc] initWithFlutterViewController:controller];
  UIViewController* root = editor;
  if (g_root_factory != NULL) {
    // The app's own screen takes the editor and decides when it is shown. The
    // factory returns a +1 reference, so the transfer hands ARC that one.
    UIViewController* custom =
        (__bridge_transfer UIViewController*)g_root_factory((__bridge void*)editor,
                                                           g_root_factory_user);
    if (custom != nil) root = custom;
  }
  window.rootViewController = root;
  self.window = window;
  [window makeKeyAndVisible];
  [self spikeSecondViewIfAsked:window];
  return YES;
}

// The second-surface spike (docs/plans/ipad-multi-window.md, step 1): with
// STARLING_SPIKE_SECOND_VIEW set, a second CAMetalLayer in a corner of the window
// shows view 1 of the same engine. Off unless asked; nothing here is product code.
- (void)spikeSecondViewIfAsked:(UIWindow*)window {
  if (getenv("STARLING_SPIKE_SECOND_VIEW") == NULL) return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    CGFloat scale = UIScreen.mainScreen.scale;
    CGSize size = CGSizeMake(260, 180);
    UIView* host = [[UIView alloc] initWithFrame:CGRectMake(window.bounds.size.width - size.width - 20, 80, size.width, size.height)];
    host.userInteractionEnabled = NO;
    CAMetalLayer* layer = [CAMetalLayer layer];
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.opaque = YES;
    layer.contentsScale = scale;
    layer.frame = host.bounds;
    layer.drawableSize = CGSizeMake(size.width * scale, size.height * scale);
    [host.layer addSublayer:layer];
    [window addSubview:host];
    [self.engine starlingAddViewWithId:1 layer:layer size:size pixelRatio:scale done:^(BOOL added) {
      fprintf(stderr, "[spike] AddView(1) -> %s\n", added ? "added" : "REFUSED");
    }];
  });
}

// A document handed to the app from outside. Forwarded verbatim; the app owns
// what an URL means (the host has no idea what a .docx is).
- (BOOL)application:(UIApplication*)app
            openURL:(NSURL*)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options {
  if (g_open_url == NULL) return NO;
  return g_open_url(g_open_url_user, url.absoluteString.UTF8String) ? YES : NO;
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

void fluikit_host_set_root_factory(FlUIKitRootFactory factory, void* user) {
  g_root_factory = factory;
  g_root_factory_user = user;
}

void fluikit_host_set_open_url_handler(FlUIKitOpenURLCallback handler, void* user) {
  g_open_url = handler;
  g_open_url_user = user;
}

void fluikit_host_window_size(double* out_width, double* out_height) {
  if (out_width != NULL) {
    *out_width = g_window_size.width;
  }
  if (out_height != NULL) {
    *out_height = g_window_size.height;
  }
}
