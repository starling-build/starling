# iPad multi-window: design for review

Status: **reviewed 2026-11-23: GO on option B (board/20261123-152204-amd-opus.md), with the changes folded in below. Built so far (2026-11-23): engine raster side (starling-engine 1a36a4fe3c8: view id to CAMetalLayer, add/resize/remove, touches by view id), the per-view leak fixed (four ARC cycles, #2515), scene host with scenes off, `runView` with a real scrolling list in view 1 (test host, env-gated). Steps 4-5 not started.** Author: mac-ipad session, 2026-11-23. The ask: two documents
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

## Step 4 findings: what a second window's input reaches today (code read, 2026-11-23)

Read from the code, then measured with the `STARLING_SPIKE_INPUT` driver (`UIKitScriptedInput.swift`: a script of tap/drag/type/key lines injected per view id from inside the app, no Mac mouse involved).

- **Touches: fine.** Each touch becomes a pointer with `device = the UITouch's address`, so two windows touched at
  once cannot collide, and the packet converter numbers them. The framework already hit-tests by view id
  (`RenderingBinding.hitTestInView` -> `_viewIdToRenderView[viewId]`).
- **Focus: ONE global node.** `FocusManager.instance.focusedNode` is a single `FocusNode?`; `_setFocus` tells the old
  node it lost focus and the new one it gained it, whichever window each is in. So tapping a text box in window B
  blurs the caret in window A (and `SoftKeyboard.focusMoved()` may dismiss the keyboard). The plan's "one focus
  scope per view" is therefore not a refinement but the fix: `focusedNode` becomes per view id, plus a "key view"
  (the one whose scene is active / last touched) that `dispatchKeyData` routes to.
  `FocusNode.requestFocus()` takes no context, so a node needs its view: set it from the pointer event being
  dispatched (`event.viewId`) or from the view whose tree is building (`autofocus` at mount); `FocusNode` is a
  ~40-line stub (no scopes), so this is a small change.
- **Soft-keyboard text: ONE responder, in view 0.** `fluikit_keyboard_attach` adds a single `FlUIKitKeyInputView`
  to the first controller's view (`g_key_view`); `show` makes it first responder; every keystroke reaches
  `UIKitSoftKeyboard._post` -> `PlatformDispatcher.onKeyData` -> `FocusManager.dispatchKeyData` -> whichever node is
  focused. Works for a second window by accident while its node is the focused one. Needed: `show(viewId)` moves
  the responder into that view's host `UIView` (it must stay inside the Flutter view so hardware keys still reach
  the engine), and the key view follows.
- **Hardware keys: view 0 only.** UIPresses go up the responder chain to the `FlutterViewController`; an extra
  view's `UIView` has no controller, so with the responder inside it a Magic Keyboard types nothing. `FlUIKitExtraView`
  needs `pressesBegan/Ended` forwarding to the engine's keyboard manager. `KeyData` carries no view id; routing by
  "key view" (above) is the whole story.
- **Keyboard insets: view 0 only.** `FlutterViewController` turns the keyboard frame into `viewInsets` for the
  implicit view. An extra view needs the keyboard frame intersected with its own frame in window coordinates and
  sent through `SetViewportMetrics(viewId, ...)`, else a lower window's caret hides behind the keyboard.
- **Text: the plugin channel, one client at a time (revised after measuring).** An editor attached to the
  text-input plugin takes its characters from `flutter/textinput`, not from key events (`RichEditable` declines
  them), and that channel has one listener and one client id: `TextInputChannel.listen` replaces the owner. That
  is Flutter's own model (one active client), and it turns out to serve two windows: the tap that focuses an
  editor in window B attaches B's connection, B's `setClient` replaces A's, and typing goes to B.
  **Measured** with the driver (`STARLING_SPIKE_INPUT`, 2026-11-23, simulator, ex.docx in view 0 and sa2.docx in
  view 1): alternating tap+type view 1, view 0, view 1, view 0 put each text in the document that was tapped, four
  of four. The one failure seen was a tap at 2 s after launch, before view 1 had laid out: its text went to view 0.
  What stays view-0-only is the geometry the plugin is told (`setCaretRect`/editable transform are in view 0's
  coordinates: wrong for the IME candidate window and the system's loupe in window B) and the native toolbar.
- **The edit menu / toolbar:** per window already (`OfficeScene`, step 4a), but the host side
  (`OfficeNativeShell`) still installs on `OfficeScene.main` only; a second window's scene needs its own native
  toolbar hosted over its own view.
- **Lifecycle:** untouched so far (see above).

## Step 4 status (2026-11-23 night; PR #2587)

Done and measured in the simulator with the in-app driver (no unit tests: the iPad session is exempt):

- **Idle first view:** a view added over a quiet or hidden first view got no first frame, and a touch before its first
  layout crashed in hit-test. Fixed in `Adapter.swift`; `test/ios-selftest.sh` (STARLING_SELFTEST=multiview, 9 checks)
  is the regression check, 9/9 idle and with a document open, heap growth ~0 MB over 20 add/remove cycles.
- **Keyboard insets per view:** `fluikit_view_add/resize/remove` watch the keyboard frame (docked only) and send each
  view its own overlap through the engine's `insetBottom` resize. A 520x1000 view reads 219 px with view 0 at 809 px.
- **Caret geometry:** `TextInputChannel.windowTransform(of:)` adds the view's origin (hook `viewOrigin`); view 1's
  editable origin is 492,302, view 0's 0,222.
- **Toolbar and edit menu:** `connectNativeHooks(scene, viewId:)` in main.swift wires both windows; the edit menu is
  offset by the view's origin; the bar is one for the screen and follows the window last touched (`OfficeScene.activate`).
- **Lifecycle:** `OfficeScene.flushPendingSaves` (Writer/Slides AutoSave body, Sheets write-to-own-file) runs for every
  window when the app goes to the background. Proven with OFFICE_AUTOSAVE_DELAY_MS=60000: file untouched after typing,
  rewritten within a second of backgrounding. View 1's frames stop in the background and resume (sim; not shown on a device).
- **Hardware keys, focus:** key events carry no view id and reach the one global `FocusManager`, so keys follow the
  editor last tapped; with a plugin client attached they arrive through the text-input view, which is first responder.
  NOT verified: a Magic Keyboard (the simulator needs the Mac's keyboard, which a test run may not drive), and the
  case with no text client attached while the responder sits in view 0. Per-view focus scopes are still the plan's
  fix for "typing in B blurs A's caret".

## Step 5 status (2026-11-24; PR #2587)

Scenes are ON for Office (`MULTI_SCENES` in `build/ios-app.sh`; `UIApplicationSupportsMultipleScenes` plus
`NSUserActivityTypes`). Other iOS apps stay single-scene.

- **Scene = engine view.** The first scene is view 0 (the engine's implicit view); each later scene gets the next
  id (`g_next_scene_view`), a `FlUIKitSceneEditorViewController` that places the view at the safe-area frame, and
  its own `OfficeScene` + `OfficeNativeShell` (browser, editor, toolbar, edit menu, write-back, endSession).
  `sceneConnected(viewId)` runs before the root factory; `sceneDisconnected(viewId)` flushes pending saves, then
  the view is removed. View 0's tree cannot be removed (implicit view): its document claim is released instead.
- **Focus scopes.** `FocusManager` has one scope per window (`runView`); a node takes its scope from the view its
  owner is MOUNTED in (`State.bind`, walking to the `RenderView`), not from whoever first asks for focus, so a late
  async request lands in its own window. `keys=` in the driver report is the key scope; touching a window makes it
  the key scope and moves the text-input hider there (`fluikit_text_input_host`, engine patch
  `starlingHostView`). `STARLING_FOCUS_LOG=1` traces each request: bound view, scope, windows, key scope.
  Measured: two windows, taps and typing alternating (AA/BB/CC/DD), each document got only its own text.
- **One document, one window.** A document's identity is its original URL; a second open of a file already in a
  window raises that window (`focusIfOpen` -> `fluikit_scene_activate`) instead of opening it again.
- **Entry points.** "Open in New Window" is a `UIDocumentBrowserAction`; `scene:openURLContexts:` and
  `connectionOptions.userActivities` hand a URL to the scene's shell. Test hooks: `OFFICE_NEW_WINDOW_AFTER=<ms>[:<path>]`,
  `OFFICE_OPEN_AFTER`, `STARLING_CLOSE_RESTORED_WINDOWS=1` (the simulator restores the last run's windows blank).
- **Toolbar.** One format bar per window; each shows only while its window is the key window.

NOT verified: Magic Keyboard (real iPad list), drag-out, state restoration, Save As per scene, 50 open/close
cycles on a device, frames stopping when a scene is backgrounded on a device.

## Step 5 follow-up (2026-11-24; PR #2587)

- **Focus scope comes from the element chain.** A `FocusNode` took its window from the render tree's root view; a
  focus request made in `initState` (before the element is attached) had no render object, so the node stayed in
  scope 0 and typing went to window 0. `State.bind` now falls back to walking the element chain to the
  `RenderObjectToWidgetAdapter`. Single-view: the walk returns view 0, as before. `STARLING_FOCUS_LOG=1` traces
  which scope a touch moves the keys to. The hold/replay of early keys was tried and removed: clients attach at
  touch-down, so nothing arrives in between. The driver's lost keystrokes at 0.1 s are the capacity-1 textinput
  channel buffer being evicted by `onConnectionClosed`, not routing.
- **A closed window is released.** `releaseView(id:)` drops the builder and the focus scope and schedules a frame;
  the iOS host calls it after the engine has removed the view (`fluikit_host_set_view_gone_handler`).
- **Leak.** Laid-out paragraph frames were kept alive by closures they stored on themselves (fixed in
  `RichLayout+Paragraph.swift`): +5.5 MB per window open/close cycle became +0.8 MB. Still open: one
  `RichDocumentController` per closed document window is retained by something outside the session, shell, editor
  and layout (all freed). `OFFICE_WINDOW_CYCLES=<n>[:<path>]` and `OFFICE_HEAP_DUMP=<dir>` find it (live counts in
  the `[cycle]` line, class histogram diff).
- **Save As is per window.** `OfficeNativeShell.export` goes to `shells[viewId]` and presents over that window's own
  editor; `OFFICE_EXPORT_AFTER=<ms>:<viewId>` drives it. Seen in the simulator in Split View: the picker covers
  the window of view 1 only.
- Not seen: Magic Keyboard, drag-out to a new window, the system popover tap itself, frames stopping when
  backgrounded (all on the real-iPad list).

## Step 5, round 3 (2026-11-24)

- **"Open in New Window" and the claim, through the real action.** The browser's own action
  (`OFFICE_BROWSER_ACTION_AFTER=<ms>:<viewId>:<path>`) opens a second scene; on an already-open file it focuses
  the window that has it instead (`focusIfOpen` is asked first, else a blank duplicate window appeared).
  `fluikit_scene_activate` passes a `requestingScene`: without it the simulator sent the whole app home when
  a window was claimed.
- **A closed window no longer keeps its document.** The toolbar buttons and the touch edit menu are closures
  handed to UIKit, which keeps its menu objects past the window; they held the controller strongly, so every
  closed Writer window kept its whole document. They hold it weakly now (Writer, Sheets; Slides' toolbar
  already held `self` weakly, and its edit menu goes through the shared `showTouchMenu`). Found with the
  backward scan in `OFFICE_HEAP_DUMP` (`heap-<n>.txt.retainers.txt`) and `LeakProbe`'s live counts. Eight or
  sixteen open/close cycles: live RichDocumentController / DeckController / WorkbookController stay flat;
  malloc still creeps ~0.5 MB per window (small 32-64 byte blocks, not a document; unnamed).
- **State restoration.** The scene delegate returns an `NSUserActivity` (`build.starling.window`) from
  `stateRestorationActivityForScene:` whose token comes from the app (`fluikit_host_set_restoration_handlers`);
  the app's token is a base64 bookmark to the window's original document. On the next launch
  `willConnectToSession` hands the token back for any window not made for a document, and the app opens it
  through the same path as a file handed to a window. Seen in the simulator: two Writer windows (ex.docx, sa2.docx),
  app sent to the background by launching Settings, `simctl terminate`, relaunch with no env hooks: both windows
  came back in Split View with their documents. A file that is gone leaves the window blank. A window with no
  document saves nothing. All in the bridge/app; with one window nothing changes (view 0 reopens its last
  document, which is what restoration means).

## Slides in a narrow window (2026-11-24)

Found in round 4 (a 375 pt Split View pane): the slide showed about 100 pt wide beside the thumbnail rail, and a text
box's 6 pt grip bands (selection/drag, on the box's edges) covered a small box entirely, so a tap selected it and
never put the caret in its text. Two changes: the rail is hidden below 600 pt of window width (the slide gets the
width; the sorter still lists every slide; `SizeReporter` at the shell's root, the shell has no LayoutBuilder), and
the band is at most a quarter of the box's shorter drawn side (6 pt on a slide at full size, a line keeps 6). Measured
in the simulator (Split View, ex.docx | sl.pptx, 375 pt pane): the slide is 312 pt wide and a tap on the subtitle
box starts a text client and typed text lands in it ("[input] type view 1 ... focus=slide shape 2", text in the
box). A "Slides" button in the status bar (narrow windows only) brings the rail back (measured: a tap on it shows the
rail beside the slide; the status bar drops the language label to make room). Not done: touch targets for resize
handles on a tiny slide.

## Step 5, round 4: the "check each" lists (2026-11-24)

Driven in the simulator with the in-app driver (`STARLING_SPIKE_INPUT`), no Mac input.

- **A deck, a workbook and a document in a SECOND window: open, edit, type, save, close.** Done for all three
  (view 0 = ex.docx, view 1 = the file). Slides: a tap in the notes pane starts a text client in view 1, the text
  is in `ppt/notesSlides/notesSlide1.xml` after the window closes. Sheets: tap a cell, type, Return: in
  `sharedStrings.xml` after close. Writer: in `word/document.xml`. The first window's file never gets the second's
  text. `OFFICE_CLOSE_WINDOW_AFTER=<ms>:<viewId>` closes a window the way the user does.
- **Found and fixed: closing a window dropped its last save.** `writeBack` looked the editing session up on its
  own queue, after the closing window had already ended it (`windowClosed`), so the close-time flush logged
  `write-back skipped ... is not the open document` and wrote nothing. Writer and Slides hid it behind AutoSave
  (a timer saves before the user closes); Sheets has no AutoSave, so closing a Sheets window lost every edit
  since the last explicit Save. The session is now taken by the caller. Checked with a close 200 ms after typing
  (Writer, Slides) and a Sheets close with no save: all three write back ok and the text is in the file.
- **Slides' slide canvas is not editable in a Split View pane (375 pt).** The slide shows at about 100 pt wide;
  the 6 pt grip bands around a text box are not scaled, so on a box 14 pt tall they cover it and a tap selects
  the shape instead of editing its text (hit log: only the band is hit). Not a multi-window bug (a narrow pane
  does it), and not fixed here: the window needs a narrow layout (hide the rail, scale the bands).
- **Two windows touched at the same time.** Taps and 60-step drags in view 0 and view 1 at the same millisecond
  (`STARLING_HIT_LOG=1` prints each pointer-down's view, pointer, device and hit path): four pointers, four
  different ids, each hit its own window's tree, each window ended with its own selection and its own edit
  menu. The driver's pointer ids are unique by construction, so this does not exercise the engine's packet
  converter with real touches: that, with two hands, stays on the real-iPad list. By code, a touch's device id is
  the UITouch's address.
- **implicitView audit.** `View.of` was a `fatalError` stub; `View.maybeOf(context)` / `View.of(context)` now walk
  up to the tree's own `RenderObjectToWidgetAdapter` and return its view (self-test step: each probe tree finds
  its own view, not view 0). Terminal (`_flutterView`, five uses), WikiShell and SiteShell take their view from
  context. Adapter.swift's three uses are the first-view pipeline and the by-view-id routing to secondary
  pipelines: first view only by design, now commented as such. Office's `ScriptedInput` is the macOS single-window
  driver: marked first-view-only. Desktop apps outside the iPad (ImageViewer, VideoPlayer, TextEditor, TerminalApp,
  FlutterDemo) still read the implicit view; they are single-window.

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
