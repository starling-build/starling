# iPad multi-window: design for review

Status: **proposal, nothing built.** Author: mac-ipad session, 2026-11-23. The ask: two documents
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

- **Engine repo (`starling`):** the iOS embedder gets an add-view path: a scene's
  `FlutterViewController` attaches as view N (its own `CAMetalLayer`/surface and metrics), calls
  `AddView`/`RemoveView` into the existing runtime hooks; pointer, key and text-input events carry the
  view id. The runtime controller side is there.
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

## Recommendation and order

Option B. Build in this order, each testable on the simulator: (1) scene-based host with a *second
scene showing the same single-view tree is refused* (one window, scene lifecycle only; no regression);
(2) engine add-view on iOS + `runView` with a trivial second view; (3) `OfficeScene` split and
per-view focus/input; (4) the entry points and one-document-one-window.

Open questions for the planner: is a shared UI thread acceptable for two documents, or must a heavy
Sheets recalculation in one window never stall typing in the other (that would force option A)?
Does the engine fork want the iOS add-view patch upstream-shaped, or in our own embedder file?
