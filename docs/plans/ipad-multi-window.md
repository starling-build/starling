# iPad multi-window: design for review

Status: **reviewed 2026-11-23: GO on option B (board/20261123-152204-amd-opus.md), with the changes folded in below. Nothing built.** Author: mac-ipad session, 2026-11-23. The ask: two documents
open side by side as two windows of the Office app (Split View of the app with itself, Stage Manager
windows, "Open in New Window", drag a file out of the browser).

What works today without any of this: one window of the app resizes freely and shares the screen with
other apps (Split View, Slide Over; #2362). What does not: a second *scene* of our own app.

## What is process-wide today

| Layer | What | Where |
|---|---|---|
| Host | one scene-less `UIApplicationDelegate`, one `FlutterEngine`, one `FlutterViewController`, one `UIWindow`; `g_window_size`, `g_on_started` (the tree is mounted once) are file statics | `sdk/Sources/FlutterUIKitBridge/fluikit_host.m` |
| Framework | the binding singletons: `WidgetsBinding.instance`, `GestureBinding.instance`/`_instance`, `PaintingBinding.instance`, `FocusManager.instance`, `FrameCallbackScheduler.shared`, `TickerScheduler.shared`, `SystemFontsNotifier.shared`, ... (12 `static` singletons) | `sdk/Sources/Flutter/*` |
| Framework | `PlatformDispatcher.instance` is read at 76 sites; `GestureBinding.instance` 22; `FocusManager.instance` 23 | |
| Framework | `runApp` -> `_setupWidgetBinding` builds exactly one `RenderView`, one `PipelineOwner`, one `BuildOwner`, one tree, for the implicit view (id 0) | `Widgets/Framework/Adapter.swift` |
| App | `OfficeHost` is all statics: `documentSaved`, `openRequested`, `openPath`, `exportRequested`, `editMenuRequested/Dismissed`, `toolbarChanged`, `toolbarOwner` | `OfficeHost.swift` |
| App | `OfficeNativeShell` (the UIKit browser/toolbar/edit menu) is created once by the root factory | `OfficeUIKit/` |
| Fonts | `OfficeFonts` / `RichTextTheme` tables are loaded once; fine to share | |
| Threads | builds run on the engine's platform thread (see the shell-framework-thread note); a second engine means a second UI thread running into the same statics | |

## What already points at multi-view

The port kept Dart's multi-view shape, so option B starts nearer than it looks:

- `PlatformDispatcher._views: [Int: FlutterView]`, `view(id:)`, `_implicitViewId`.
- `RendererBinding._viewIdToRenderView` keyed by viewId (`add(renderView:)`/`remove`).
- The engine's `SwiftRuntimeController::AddView/RemoveView` call `add_view/remove_view` runtime callbacks.

What is missing: nothing creates a second view's render tree or routes its input; the iOS
embedder (`FlutterEngine.mm`) has no add-view path (only `FlutterViewController` for the implicit view).

## Option A: one engine per scene

Each scene gets its own `FlutterEngine`, started exactly as today.

- **Engine repo:** nothing structural; iOS already allows several engines. Memory: roughly another
  engine's worth (fonts are registered per collection - measure).
- **Framework:** the singletons must become per-engine. Both engines call back into Swift on their own
  UI threads, so a plain global is a data race. The way through is a "current binding set" looked up per
  call (thread-local, set by the runtime callbacks) behind `WidgetsBinding.instance` and friends; ~125
  call sites keep their spelling, 12 singletons change shape. Everything that caches a binding
  (timers, `Ticker`, the `FocusManager`'s key handler) needs auditing. Risk: high and diffuse; a missed
  global shows up as a second window typing into the first.
- **App:** per-scene `OfficeScene` replacing the statics, as in the common section.

## Option B: one engine, several views (recommended)

One engine and one isolate-less runtime, with a `FlutterView` per scene.

- **Engine repo (`starling`): this is the real work, and it is the raster side, not the add-view call.**
  The runtime controller side is there, but `shell/common/rasterizer.cc` draws every view into ONE
  `surface_`, and iOS (`PlatformViewIOS`: one `ios_surface_`, one `owner_controller_`) is not on the
  embedder API that the other platforms use to give each view a drawable. A second view reaches its own
  drawable only through the external view embedder (`PrepareFlutterView` / `SubmitFlutterView(view_id)`).
  So: an iOS external view embedder mapping view id to a `CAMetalLayer` (not a second `surface_` in the
  rasterizer); `rasterizer.cc:715` `GetRootCanvas()` has no view id yet (an upstream TODO). Patches live in
  our own embedder files (small hooks in `FlutterEngine.mm` / `FlutterViewController.mm`, the `patches/`
  series), since upstream iOS has no multi-view to be shaped like. This is the one part that can sink the plan.
- **Framework (`sdk/`):** `runApp` stays for the first view; a `runView(id:, _ app:)` (or a `View`
  widget under a collection root, as Flutter's `runWidget`) creates a `RenderView` + tree per view and
  registers it with the existing keyed maps. `FocusManager` becomes per-view focus scopes (today one
  tree); text input routes by view id. The 12 singletons **stay** singletons - they are per-process in
  Flutter too.
- **Cost / risk:** more engine work, much less framework churn, one engine's memory, shared font and
  image caches. Two heavy layouts serialise on the one UI thread - acceptable for two documents.

## Common to both (app side, ~1 PR each)

1. `fluikit_host.m`: adopt the scene lifecycle - `UIApplicationSceneManifest` with
   `UIApplicationSupportsMultipleScenes`, a `UIWindowSceneDelegate` that builds window + root per scene;
   `openURL` becomes `scene:openURLContexts:`; `g_window_size`/`g_on_started` become per scene.
2. `OfficeHost` statics -> an `OfficeScene` object (one per window) handed down from `OfficeRoot`;
   the toolbar owner, edit-menu hook and `openPath` are per scene.
3. One document, one window: opening a file already open elsewhere must focus that window (or refuse),
   and the recovery/AutoSave directory is keyed by document path, so two windows on one file would race.
4. Entry points: "Open in New Window" in the browser's context menu and the document picker
   (`UIApplication.requestSceneSessionActivation`), drag-out, and state restoration per scene.

## Lifecycle (added in review)

- A scene that goes to the background drops only ITS view's surface. The engine's GPU-disabled switch and
  `AppLifecycleState` are process-wide today and driven by the one view controller; Metal work from a
  backgrounded app is a kill, so only "every scene in the background" pauses the engine.
- iOS disconnects background scenes whenever it likes. That is `RemoveView` plus unmounting that view's tree,
  with the document saved first, and a rebuild from the scene's restoration activity on return. Per-view
  unmount has never run in this port: open and close the second window 50 times, watching memory and tickers.

## Input routing (added in review) - check each

- Pointer device ids: each `FlutterViewController` numbers its touches itself, and the engine's packet
  converter and the `GestureBinding` hit-test table are keyed by device/pointer, so two windows touched at
  once must not collide.
- Text input and key events: one plugin per engine, bound to one controller; route by the key scene and carry
  the view id on the text client. Keyboard insets per view. The UIKit edit menu and toolbar owner per scene.
- Framework audit: 65 uses of `renderView`/implicit view in sdk; 5 files read `implicitView` directly
  (`Adapter.swift`, `TerminalView.swift`; Office: `ScriptedInput`, `WikiShell`, `SiteShell`). Each takes its
  view from context (`View.of`) or is marked first-view-only. Focus: keep the ONE `FocusManager`, with one focus
  scope per view plus the view-focus event when a scene becomes key (as Flutter's `View` widget does).

## Displays, accessibility, platform views

A Stage Manager window can sit on an external display with another scale and refresh rate: scale is per view
(`addView` carries it); the single frame clock follows the display link of the key scene. Accessibility (one
bridge per engine today) and iOS platform views are out of scope here.

## Recommendation and order

Option B, in the reviewed order. Multiple scenes stay OFF (`UIApplicationSupportsMultipleScenes` = NO)
until the last step: with it on the system itself offers "new window" (Stage Manager, App Exposé, drag to
the edge), and a scene we cannot serve is an empty window on the user's screen.

1. **Engine spike (first, about a week):** a second `CAMetalLayer` in the same window showing a second
   trivial view from one engine, through an iOS external view embedder. If it is not drawing in a week, back
   to the board; never fall back to option A silently.
2. Scene host with multiple scenes OFF: the scene lifecycle (manifest, window-scene delegate, `openURL` as
   `scene:openURLContexts:`), no change in behaviour.
3. `runView` + the second real view (render tree, hit test, metrics) in a test host.
4. `OfficeScene` split, focus and input, lifecycle (above).
5. Entry points (Open in New Window, drag-out, restoration), one-document-one-window, THEN turn scenes on.

Answered in review: a shared UI thread is acceptable and must not force option A (builds already run on the
platform thread, so a heavy Sheets recalculation stalls its own window today; moving recalculation off that
thread helps one window as much as two). The engine patch goes in our own embedder files.
