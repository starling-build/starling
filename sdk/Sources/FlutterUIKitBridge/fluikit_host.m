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
static FlUIKitSceneCallback g_scene_connected = NULL;
static FlUIKitSceneCallback g_scene_disconnected = NULL;
static FlUIKitRestoreSaveCallback g_restore_save = NULL;
static FlUIKitRestoreCallback g_restore = NULL;
static void* g_restore_user = NULL;
static void* g_scene_user = NULL;

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
- (void)starlingResizeViewWithId:(int64_t)viewId
                            size:(CGSize)size
                      pixelRatio:(double)pixelRatio
                     insetBottom:(double)insetBottom;
- (void)starlingRemoveViewWithId:(int64_t)viewId done:(void (^)(BOOL removed))done;
- (void)starlingSetTextInputHostView:(UIView*)view;
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
// Builds the window's view controllers over the one engine and shows the window. `scene` is nil in a
// bundle without a scene manifest (the window then belongs to the application alone, as before).
- (UIWindow*)installWindowInScene:(UIWindowScene*)scene;
// The window of a scene beyond the first, showing engine view `view_id`.
- (UIWindow*)installExtraWindowInScene:(UIWindowScene*)scene viewId:(int64_t)viewId;
@end

// The scene host (docs/plans/ipad-multi-window.md, step 2). Info.plist names this class for the
// application's scenes. UIApplicationSupportsMultipleScenes stays NO, so iOS still makes exactly one
// scene and nothing changes for the user; the window just comes from a scene now, which is the shape a
// second window needs. Documents handed to the app arrive here as scene:openURLContexts:, not as
// application:openURL: (UIKit stops calling that one once a bundle has a scene manifest).
@interface FlUIKitSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow* window;
@property(nonatomic, assign) int64_t viewId;
@end

@interface FlUIKitSceneEditorViewController : UIViewController
@property(nonatomic, assign) int64_t viewId;
@end

// The windows the system has made, by the engine view each shows. The first takes view 0; the others a fresh id.
static NSMutableDictionary<NSNumber*, UIWindowScene*>* g_scenes;
static BOOL g_primary_taken = NO;
static int64_t g_next_scene_view = 1;

static void FlUIKitAddViewIn(UIView* container, int64_t view_id, CGRect frame, FlUIKitViewDone done, void* user);
static void FlUIKitPlaceView(int64_t view_id, CGRect frame);

// The editor of a window beyond the first: a plain view controller whose view holds an extra view of the engine (the
// first window's holds the FlutterViewController's, which can only be one per engine). Same contract as
// FlUIKitRootViewController: the app's root presents it when it likes, and its view is not loaded before that.
@implementation FlUIKitSceneEditorViewController {
  BOOL _added;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;
}

// The engine's view fills the safe area, as the first window's does.
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGRect frame = self.view.safeAreaLayoutGuide.layoutFrame;
  if (CGRectIsEmpty(frame) || self.view.window == nil) return;
  if (!_added) {
    _added = YES;
    FlUIKitAddViewIn(self.view, self.viewId, frame, NULL, NULL);
  } else {
    FlUIKitPlaceView(self.viewId, frame);
  }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

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

  // The window's size, as the tree is mounted: the screen's, which is what the window was made with
  // before scenes (a window in Split View is resized by its scene right after).
  g_window_size = UIScreen.mainScreen.bounds.size;

  // Mount the tree now: after the engine is up (the Swift runtime callbacks
  // are live, so runApp can schedule a frame) and before the view controller
  // is attached (which is what makes the engine ask for one).
  if (g_on_started != NULL) {
    g_on_started(g_user_data);
  }

  // With a scene manifest the window is made when UIKit connects the scene (FlUIKitSceneDelegate),
  // after this returns; without one, now, as before scenes.
  if ([NSBundle.mainBundle objectForInfoDictionaryKey:@"UIApplicationSceneManifest"] == nil) {
    [self installWindowInScene:nil];
  }
  return YES;
}

- (UIWindow*)installWindowInScene:(UIWindowScene*)scene {
  FlutterViewController* controller = [[FlutterViewController alloc] initWithEngine:self.engine
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
        (__bridge_transfer UIViewController*)g_root_factory((__bridge void*)editor, 0,
                                                           g_root_factory_user);
    if (custom != nil) root = custom;
  }
  UIWindow* window = scene != nil ? [[UIWindow alloc] initWithWindowScene:scene]
                                  : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  window.rootViewController = root;
  self.window = window;
  [window makeKeyAndVisible];
  [self spikeSecondViewIfAsked:window];
  return window;
}

- (UIWindow*)installExtraWindowInScene:(UIWindowScene*)scene viewId:(int64_t)viewId {
  FlUIKitSceneEditorViewController* editor = [FlUIKitSceneEditorViewController new];
  editor.viewId = viewId;
  // The app registers what this view shows before the view exists (the engine asks for its first frame as soon
  // as the view reports a size, and a frame with no tree behind it is never retried).
  if (g_scene_connected != NULL) g_scene_connected(g_scene_user, viewId);
  UIViewController* root = editor;
  if (g_root_factory != NULL) {
    UIViewController* custom =
        (__bridge_transfer UIViewController*)g_root_factory((__bridge void*)editor, viewId, g_root_factory_user);
    if (custom != nil) root = custom;
  }
  UIWindow* window = [[UIWindow alloc] initWithWindowScene:scene];
  window.rootViewController = root;
  [window makeKeyAndVisible];
  return window;
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
    if (cycles <= 0) {
      // The single view goes through the product's own entry point (keyboard insets and all).
      BOOL sized = getenv("STARLING_SPIKE_VIEW_W") != NULL && getenv("STARLING_SPIKE_VIEW_H") != NULL;
      double w = sized ? atoi(getenv("STARLING_SPIKE_VIEW_W")) : 340, h = sized ? atoi(getenv("STARLING_SPIKE_VIEW_H")) : 260;
      fluikit_view_add(1, window.bounds.size.width - w - 20, 80, w, h, NULL, NULL);
      return;
    }
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
  // STARLING_SPIKE_VIEW_W/H: a view big enough for an editor (and it is not grown afterwards).
  BOOL sized = getenv("STARLING_SPIKE_VIEW_W") != NULL && getenv("STARLING_SPIKE_VIEW_H") != NULL;
  if (sized) size = CGSizeMake(atoi(getenv("STARLING_SPIKE_VIEW_W")), atoi(getenv("STARLING_SPIKE_VIEW_H")));
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
      CGSize bigger = sized ? size : CGSizeMake(340, 260);
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

// MARK: - Extra views (C entry points)

static NSMutableDictionary<NSNumber*, FlUIKitExtraView*>* g_extra_views;
static NSMutableDictionary<NSNumber*, CAMetalLayer*>* g_extra_layers;
static NSMutableDictionary<NSNumber*, NSNumber*>* g_extra_insets;   // the keyboard's share of each view, points
static id g_keyboard_observer;
static CGRect g_keyboard_frame;     // the last keyboard frame the system reported (screen coordinates)
static BOOL g_keyboard_docked;
// The window whose text input owns the keyboard (nil: view 0's). The keyboard is the system's, one for the screen, and
// the frame it reports is the same to every window; only the window it is attached to shrinks (as view 0's
// FlutterViewController does for itself), not a neighbour in Split View that merely lies under its rectangle.
static UIView* g_text_input_container;
static void FlUIKitSetOrigin(int64_t view_id, CGPoint* p);

// The docked keyboard covers the bottom of every extra view it overlaps: tell each view how much (its
// viewInsets.bottom), as the view controller does for view 0. The frame is in screen coordinates.
static void FlUIKitUpdateExtraInsets(CGRect keyboardFrame, BOOL docked) {
  FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
  CGFloat scale = UIScreen.mainScreen.scale;
  g_keyboard_frame = keyboardFrame;
  g_keyboard_docked = docked;
  UIWindow* keyboardWindow = g_text_input_container != nil ? g_text_input_container.window : delegate.window;
  for (NSNumber* key in g_extra_views.allKeys) {
    FlUIKitExtraView* host = g_extra_views[key];
    UIWindow* window = host.window;   // each window (scene) has its own, and the keyboard is over one of them
    if (window == nil) continue;
    CGRect inWindow = [window convertRect:keyboardFrame fromCoordinateSpace:window.screen.coordinateSpace];
    double inset = 0;
    if (docked && !CGRectIsEmpty(keyboardFrame) && window == keyboardWindow) {
      CGRect hit = CGRectIntersection(inWindow, [host convertRect:host.bounds toView:window]);
      if (!CGRectIsNull(hit)) inset = CGRectGetHeight(hit);
    }
    if (getenv("STARLING_KEYBOARD_LOG")) {
      fprintf(stderr, "[kb] view %lld: keyboard %.0f,%.0f %.0fx%.0f docked=%d in window %.0f,%.0f %.0fx%.0f host %.0f,%.0f %.0fx%.0f -> inset %.0f (was %.0f)\n",
              key.longLongValue, keyboardFrame.origin.x, keyboardFrame.origin.y, keyboardFrame.size.width, keyboardFrame.size.height,
              docked, inWindow.origin.x, inWindow.origin.y, inWindow.size.width, inWindow.size.height,
              [host convertRect:host.bounds toView:window].origin.x, [host convertRect:host.bounds toView:window].origin.y,
              host.bounds.size.width, host.bounds.size.height, inset, g_extra_insets[key].doubleValue);
    }
    if (inset == g_extra_insets[key].doubleValue) continue;
    g_extra_insets[key] = @(inset);
    [delegate.engine starlingResizeViewWithId:key.longLongValue size:host.bounds.size pixelRatio:scale insetBottom:inset];
  }
}

double fluikit_screen_scale(void) { return UIScreen.mainScreen.scale; }

// Adds extra view `view_id` inside `container` at `frame` (the container's coordinates). Main thread.
static void FlUIKitAddViewIn(UIView* container, int64_t view_id, CGRect frame, FlUIKitViewDone done, void* user) {
  FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
  if (container == nil || delegate.engine == nil) { if (done) done(view_id, false, user); return; }
  if (g_extra_views == nil) {
    g_extra_views = [NSMutableDictionary new];
    g_extra_layers = [NSMutableDictionary new];
    g_extra_insets = [NSMutableDictionary new];
    void (^onKeyboard)(NSNotification*) = ^(NSNotification* n) {
      CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
      BOOL hide = [n.name isEqualToString:UIKeyboardWillHideNotification];
      UIScreen* screen = UIScreen.mainScreen;
      // Docked: the keyboard's bottom edge is the screen's (a floating one has an inset of none).
      BOOL docked = !hide && CGRectGetMaxY(end) >= CGRectGetHeight(screen.bounds) - 0.5;
      if (getenv("STARLING_KEYBOARD_LOG")) fprintf(stderr, "[kb] %s end %.0f,%.0f %.0fx%.0f screen %.0fx%.0f\n", n.name.UTF8String, end.origin.x, end.origin.y, end.size.width, end.size.height, screen.bounds.size.width, screen.bounds.size.height);
      FlUIKitUpdateExtraInsets(end, docked);
    };
    for (NSNotificationName name in @[UIKeyboardWillChangeFrameNotification, UIKeyboardWillHideNotification]) {
      g_keyboard_observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:onKeyboard];
    }
  }
  g_extra_insets[@(view_id)] = @0;
  CGFloat scale = UIScreen.mainScreen.scale;
  double w = frame.size.width, h = frame.size.height;
  FlUIKitExtraView* host = [[FlUIKitExtraView alloc] initWithFrame:frame];
  host.engine = delegate.engine;
  host.viewId = view_id;
  CAMetalLayer* layer = [CAMetalLayer layer];
  layer.device = MTLCreateSystemDefaultDevice();
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  layer.opaque = YES;
  layer.contentsScale = scale;
  layer.frame = host.bounds;
  layer.drawableSize = CGSizeMake(w * scale, h * scale);
  [host.layer addSublayer:layer];
  [container addSubview:host];
  g_extra_views[@(view_id)] = host;
  g_extra_layers[@(view_id)] = layer;
  { CGPoint o = host.frame.origin; FlUIKitSetOrigin(view_id, &o); }
  [delegate.engine starlingAddViewWithId:view_id layer:layer size:CGSizeMake(w, h) pixelRatio:scale
                                    done:^(BOOL added) {
    if (!added) { [host removeFromSuperview]; [g_extra_views removeObjectForKey:@(view_id)]; [g_extra_layers removeObjectForKey:@(view_id)]; }
    if (done) done(view_id, added, user);
  }];
}

// Moves and resizes extra view `view_id` within its container, and tells the engine the new size. Main thread.
static void FlUIKitPlaceView(int64_t view_id, CGRect frame) {
  FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
  FlUIKitExtraView* host = g_extra_views[@(view_id)];
  CAMetalLayer* layer = g_extra_layers[@(view_id)];
  if (host == nil || layer == nil) return;
  if (CGRectEqualToRect(host.frame, frame)) return;
  CGFloat scale = UIScreen.mainScreen.scale;
  host.frame = frame;
  layer.frame = host.bounds;
  layer.drawableSize = CGSizeMake(frame.size.width * scale, frame.size.height * scale);
  { CGPoint o = frame.origin; FlUIKitSetOrigin(view_id, &o); }
  [delegate.engine starlingResizeViewWithId:view_id size:frame.size pixelRatio:scale insetBottom:g_extra_insets[@(view_id)].doubleValue];
}

void fluikit_view_add(int64_t view_id, double x, double y, double w, double h, FlUIKitViewDone done, void* user) {
  dispatch_async(dispatch_get_main_queue(), ^{
    FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
    FlUIKitAddViewIn(delegate.window, view_id, CGRectMake(x, y, w, h), done, user);
  });
}


void fluikit_view_resize(int64_t view_id, double w, double h) {
  dispatch_async(dispatch_get_main_queue(), ^{
    FlUIKitExtraView* host = g_extra_views[@(view_id)];
    if (host == nil) return;
    FlUIKitPlaceView(view_id, CGRectMake(host.frame.origin.x, host.frame.origin.y, w, h));
  });
}

// Read from the engine's platform thread on every paint of an editable, so a lock-guarded copy, not a main-thread hop.
static NSMutableDictionary<NSNumber*, NSValue*>* g_extra_origins;
static void FlUIKitSetOrigin(int64_t view_id, CGPoint* p) {
  @synchronized([NSObject class]) {
    if (g_extra_origins == nil) g_extra_origins = [NSMutableDictionary new];
    if (p) g_extra_origins[@(view_id)] = [NSValue valueWithCGPoint:*p]; else [g_extra_origins removeObjectForKey:@(view_id)];
  }
}

bool fluikit_view_origin(int64_t view_id, double* x, double* y) {
  @synchronized([NSObject class]) {
    NSValue* v = g_extra_origins[@(view_id)];
    if (v == nil) return false;
    *x = v.CGPointValue.x; *y = v.CGPointValue.y;
    return true;
  }
}

void fluikit_view_raise(int64_t view_id) {
  dispatch_async(dispatch_get_main_queue(), ^{
    FlUIKitExtraView* host = g_extra_views[@(view_id)];
    if (host != nil) [host.superview bringSubviewToFront:host];
  });
}

static FlUIKitSceneCallback g_view_gone;
static void* g_view_gone_user;

void fluikit_host_set_view_gone_handler(FlUIKitSceneCallback gone, void* user) {
  g_view_gone = gone;
  g_view_gone_user = user;
}

void fluikit_view_remove(int64_t view_id, FlUIKitViewDone done, void* user) {
  dispatch_async(dispatch_get_main_queue(), ^{
    FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
    FlUIKitExtraView* host = g_extra_views[@(view_id)];
    [delegate.engine starlingRemoveViewWithId:view_id done:^(BOOL removed) {
      if (done) done(view_id, removed, user);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (g_view_gone != NULL) g_view_gone(g_view_gone_user, view_id);
      });
    }];
    [host removeFromSuperview];
    [g_extra_views removeObjectForKey:@(view_id)];
    [g_extra_layers removeObjectForKey:@(view_id)];
    [g_extra_insets removeObjectForKey:@(view_id)];
    FlUIKitSetOrigin(view_id, NULL);
  });
}

// A document handed to the app from outside. Forwarded verbatim; the app owns
// what an URL means (the host has no idea what a .docx is).
- (BOOL)application:(UIApplication*)app
            openURL:(NSURL*)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options {
  if (g_open_url == NULL) return NO;
  return g_open_url(g_open_url_user, 0, url.absoluteString.UTF8String) ? YES : NO;
}

@end

@implementation FlUIKitSceneDelegate

- (void)scene:(UIScene*)scene
    willConnectToSession:(UISceneSession*)session
                 options:(UISceneConnectionOptions*)connectionOptions {
  if (![scene isKindOfClass:UIWindowScene.class]) return;
  FlUIKitAppDelegate* app = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
  if (g_scenes == nil) g_scenes = [NSMutableDictionary new];
  if (!g_primary_taken) {
    g_primary_taken = YES;
    self.viewId = 0;
    self.window = [app installWindowInScene:(UIWindowScene*)scene];
  } else {
    // STARLING_CLOSE_RESTORED_WINDOWS=1 (a test): iPadOS brings back the windows of the last run, blank. A window
    // made for something (a file, a new-window request) has an activity; a restored one has none.
    if (getenv("STARLING_CLOSE_RESTORED_WINDOWS") != NULL && connectionOptions.userActivities.count == 0 &&
        connectionOptions.URLContexts.count == 0) {
      [UIApplication.sharedApplication requestSceneSessionDestruction:session options:nil errorHandler:nil];
      return;
    }
    self.viewId = g_next_scene_view++;
    self.window = [app installExtraWindowInScene:(UIWindowScene*)scene viewId:self.viewId];
  }
  g_scenes[@(self.viewId)] = (UIWindowScene*)scene;
  // A document the app was launched with (Open In, a tap in Files) or that "Open in New Window" put in this
  // window's activity: the tree is up now.
  [self openURLContexts:connectionOptions.URLContexts];
  for (NSUserActivity* activity in connectionOptions.userActivities) {
    NSString* url = activity.userInfo[@"url"];
    if ([url isKindOfClass:NSString.class] && g_open_url != NULL) g_open_url(g_open_url_user, self.viewId, url.UTF8String);
  }
  // A window the system brings back from the last run (not one made for a document): what it showed.
  if (g_restore != NULL && connectionOptions.userActivities.count == 0 && connectionOptions.URLContexts.count == 0) {
    NSString* token = session.stateRestorationActivity.userInfo[@"restore"];
    if ([token isKindOfClass:NSString.class]) g_restore(g_restore_user, self.viewId, token.UTF8String);
  }
}

// What this window shows, for the system to hand back on the next launch.
- (NSUserActivity*)stateRestorationActivityForScene:(UIScene*)scene {
  if (g_restore_save == NULL) return nil;
  char* token = g_restore_save(g_restore_user, self.viewId);
  if (token == NULL) return nil;
  NSString* s = [NSString stringWithUTF8String:token];
  free(token);
  if (s == nil) return nil;
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"build.starling.window"];
  activity.userInfo = @{@"restore": s};
  return activity;
}

// The system dropped this window (the user closed it, or iOS reclaimed a background one). Its document is saved
// first, then its view goes; the engine and the other windows carry on.
- (void)sceneDidDisconnect:(UIScene*)scene {
  if (self.window == nil) return;   // a window refused at connect (a restored one a test closed)
  if (g_scene_disconnected != NULL) g_scene_disconnected(g_scene_user, self.viewId);
  if (self.viewId != 0) fluikit_view_remove(self.viewId, NULL, NULL);
  [g_scenes removeObjectForKey:@(self.viewId)];
}

// The window that was touched or brought forward has the keyboard.
- (void)sceneDidBecomeActive:(UIScene*)scene {
  fluikit_text_input_host(self.viewId);
}

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts {
  [self openURLContexts:URLContexts];
}

- (void)openURLContexts:(NSSet<UIOpenURLContext*>*)contexts {
  if (g_open_url == NULL) return;
  for (UIOpenURLContext* context in contexts) {
    g_open_url(g_open_url_user, self.viewId, context.URL.absoluteString.UTF8String);
  }
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

void fluikit_host_set_restoration_handlers(FlUIKitRestoreSaveCallback save, FlUIKitRestoreCallback restore, void* user) {
  g_restore_save = save;
  g_restore = restore;
  g_restore_user = user;
}

void fluikit_host_set_scene_handlers(FlUIKitSceneCallback connected, FlUIKitSceneCallback disconnected, void* user) {
  g_scene_connected = connected;
  g_scene_disconnected = disconnected;
  g_scene_user = user;
}

void fluikit_scene_request_new(const char* file_url) {
  NSString* url = file_url != NULL ? [NSString stringWithUTF8String:file_url] : nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"build.starling.new-window"];
    if (url != nil) activity.userInfo = @{@"url": url};
    [UIApplication.sharedApplication requestSceneSessionActivation:nil
                                                      userActivity:activity
                                                           options:nil
                                                      errorHandler:^(NSError* error) {
      fprintf(stderr, "[FlUIKitHost] a new window was refused: %s\n", error.localizedDescription.UTF8String);
    }];
  });
}

void fluikit_scene_activate(int64_t view_id) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindowScene* scene = g_scenes[@(view_id)];
    if (scene == nil) return;
    // Asked as one window of the app bringing another forward (requestingScene): without it the simulator sent the
    // whole app to the home screen when the window asked for was the first one.
    UIWindowSceneActivationRequestOptions* options = [UIWindowSceneActivationRequestOptions new];
    for (NSNumber* key in g_scenes) {
      if (key.longLongValue != view_id) { options.requestingScene = g_scenes[key]; break; }
    }
    [UIApplication.sharedApplication requestSceneSessionActivation:scene.session
                                                      userActivity:nil
                                                           options:options
                                                      errorHandler:^(NSError* error) {
      fprintf(stderr, "[FlUIKitHost] could not bring window %lld forward: %s\n", view_id, error.localizedDescription.UTF8String);
    }];
  });
}

void fluikit_scene_close(int64_t view_id) {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindowScene* scene = g_scenes[@(view_id)];
    if (scene == nil || view_id == 0) return;
    [UIApplication.sharedApplication requestSceneSessionDestruction:scene.session options:nil errorHandler:^(NSError* error) {
      fprintf(stderr, "[FlUIKitHost] could not close window %lld: %s\n", view_id, error.localizedDescription.UTF8String);
    }];
  });
}

void fluikit_text_input_host(int64_t view_id) {
  void (^switchHost)(void) = ^{
    FlUIKitAppDelegate* delegate = (FlUIKitAppDelegate*)UIApplication.sharedApplication.delegate;
    FlUIKitExtraView* host = view_id == 0 ? nil : g_extra_views[@(view_id)];
    [delegate.engine starlingSetTextInputHostView:host.superview];
    // The keyboard moves with the text input: the window it left stops being covered, the one it joined starts.
    g_text_input_container = host.superview;
    if (g_extra_views.count > 0) FlUIKitUpdateExtraInsets(g_keyboard_frame, g_keyboard_docked);
  };
  // On the main thread at once: a focus request that follows this call in the same turn must find its
  // window's hider already parented there, not the previous window's.
  if ([NSThread isMainThread]) switchHost(); else dispatch_async(dispatch_get_main_queue(), switchHost);
}
