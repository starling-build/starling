// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#include "include/FlutterUIKitBridge.h"

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <malloc/malloc.h>

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
- (void)starlingResizeViewWithId:(int64_t)viewId size:(CGSize)size pixelRatio:(double)pixelRatio;
- (void)starlingRemoveViewWithId:(int64_t)viewId done:(void (^)(BOOL removed))done;
- (void)starlingDispatchTouches:(NSSet<UITouch*>*)touches inView:(UIView*)view viewId:(int64_t)viewId;
@end

// The UIView of an extra view: UIKit touches on it go to the engine as that view's pointer events.
@interface FlUIKitExtraView : UIView
@property(nonatomic, weak) FlutterEngine* engine;
@property(nonatomic, assign) int64_t viewId;
@end

@implementation FlUIKitExtraView
- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self.engine starlingDispatchTouches:touches inView:self viewId:self.viewId];
}
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self.engine starlingDispatchTouches:touches inView:self viewId:self.viewId];
}
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self.engine starlingDispatchTouches:touches inView:self viewId:self.viewId];
}
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self.engine starlingDispatchTouches:touches inView:self viewId:self.viewId];
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
  // STARLING_SPIKE_CYCLES=N: add, resize and remove N views one after another (fresh ids), logging the
  // process's memory footprint every 10; without it, one view stays.
  int cycles = getenv("STARLING_SPIKE_CYCLES") ? atoi(getenv("STARLING_SPIKE_CYCLES")) : 0;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (cycles <= 0) { [self spikeOneViewIn:window id:1 cyclesLeft:0 total:0]; return; }
    fprintf(stderr, "[spike] footprint at start: %.1f MB, heap %.1f MB\n", [self spikeFootprintMB], [self spikeHeapMB]);
    [self spikeOneViewIn:window id:1 cyclesLeft:cycles total:cycles];
  });
}

// The malloc heap's bytes in use, all zones: with the footprint, tells a heap leak (objects)
// from the rest (textures, mapped memory).
- (double)spikeHeapMB {
  malloc_statistics_t st = {0};
  malloc_zone_statistics(NULL, &st);
  return st.size_in_use / 1048576.0;
}

- (double)spikeFootprintMB {
  task_vm_info_data_t info;
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return -1;
  return info.phys_footprint / 1048576.0;
}

- (void)spikeOneViewIn:(UIWindow*)window id:(int64_t)viewId cyclesLeft:(int)left total:(int)total {
  CGFloat scale = UIScreen.mainScreen.scale;
  CGSize size = CGSizeMake(260, 180);
  FlUIKitExtraView* host = [[FlUIKitExtraView alloc] initWithFrame:CGRectMake(window.bounds.size.width - size.width - 20, 80, size.width, size.height)];
  host.engine = self.engine;
  host.viewId = viewId;
  // STARLING_SPIKE_NULL: the same timers and logging with no view at all (the app's own idle drift).
  BOOL nullRun = getenv("STARLING_SPIKE_NULL") != NULL;
  CAMetalLayer* layer = nullRun ? nil : [CAMetalLayer layer];
  layer.device = MTLCreateSystemDefaultDevice();
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.opaque = YES;
  layer.contentsScale = scale;
  layer.frame = host.bounds;
  layer.drawableSize = CGSizeMake(size.width * scale, size.height * scale);
  if (!nullRun) {
    [host.layer addSublayer:layer];
    [window addSubview:host];
  }
  // STARLING_SPIKE_UI_ONLY: the UIView and its CAMetalLayer come and go, the engine is never told (isolates the leak).
  BOOL uiOnly = nullRun || getenv("STARLING_SPIKE_UI_ONLY") != NULL;
  FlutterEngine* engine = uiOnly ? nil : self.engine;
  [engine starlingAddViewWithId:viewId layer:layer size:size pixelRatio:scale done:^(BOOL added) {
    fprintf(stderr, "[spike] AddView(%lld) -> %s\n", viewId, added ? "added" : "REFUSED");
  }];
  if (left == 0) {
    // The single-view run: it stays, grown to 340 x 260 after 2 s (it must draw whole at the new size).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      CGSize bigger = CGSizeMake(340, 260);
      host.frame = CGRectMake(window.bounds.size.width - bigger.width - 20, 80, bigger.width, bigger.height);
      layer.frame = host.bounds;
      layer.drawableSize = CGSizeMake(bigger.width * scale, bigger.height * scale);
      [engine starlingResizeViewWithId:viewId size:bigger pixelRatio:scale];
    });
    return;
  }
  // Resize after half the view's life (600 ms; STARLING_SPIKE_LIFE_MS), remove at the end of it, the next view 100 ms later.
  int64_t life = getenv("STARLING_SPIKE_LIFE_MS") ? atoi(getenv("STARLING_SPIKE_LIFE_MS")) : 600;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (life / 2) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    CGSize bigger = CGSizeMake(320, 240);
    host.frame = CGRectMake(window.bounds.size.width - bigger.width - 20, 80, bigger.width, bigger.height);
    layer.frame = host.bounds;
    layer.drawableSize = CGSizeMake(bigger.width * scale, bigger.height * scale);
    [engine starlingResizeViewWithId:viewId size:bigger pixelRatio:scale];
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, life * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    [engine starlingRemoveViewWithId:viewId done:^(BOOL removed) {
      if (!removed) fprintf(stderr, "[spike] RemoveView(%lld) REFUSED\n", viewId);
    }];
    [host removeFromSuperview];
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (life + 100) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
    int done = total - left + 1;
    if (done % 10 == 0) fprintf(stderr, "[spike] %d cycles done, footprint %.1f MB, heap %.1f MB\n", done, [self spikeFootprintMB], [self spikeHeapMB]);
    if (left > 1) [self spikeOneViewIn:window id:viewId + 1 cyclesLeft:left - 1 total:total];
    else fprintf(stderr, "[spike] all %d cycles done, footprint %.1f MB, heap %.1f MB\n", total, [self spikeFootprintMB], [self spikeHeapMB]);
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
