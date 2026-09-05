# Guest agents — M3, "an agent drives a Windows app"

Draft for approval, 2026-09-04. Three decisions are open at the foot, each
with a recommendation and what it costs.

M2 made every Windows app a window of its own (`docs/plans/guest-seamless.md`).
M3 lets an agent own one: launch it through the broker, screenshot it, click
and type into it, read its UI tree, and act on that tree — the same four
ops the broker offers a Linux window, with the same scope boundary. The
design is `docs/plans/windows-home-vm.md` §"Layer 4 — agents"; this is the
how, plus the one piece M2 deferred here (its Phase 4, the empty session).

## What the survey found, which changes the estimate

Read on 2026-09-04; file references are to that tree.

**The broker's scope boundary is kind-agnostic.** `ownedWindow()`
(`AgentBroker.swift:740`) is the single chokepoint every op goes through:
`ownerAgentId` on the `WindowInfo`, and `humanHoldsControl` for take-over.
Nothing in it asks what kind of window it is. What refuses a guest app
today is one `case` in the launch op (`case .x11, .android, .vm, .guestApp`)
with a reason that was true for the console and is not for a `Kind=guest-app`
record: "one window for a whole other operating system". A guest app IS one
window, with an identity of its own (M2 Phase 5). So M3's broker work is
the launch arm and ownership tagging, not a new model.

**Pointer injection already works for a guest window.** The broker's
`click`/`hover`/`scroll`/`drag` family delivers through the window's own
`onPointerEvent` (`AgentBroker.swift:917`, `:1021`), and for a seamless
window that is `GuestSeamless.forwardPointer` — the crop's frame origin
plus the position, into `guest_display_mouse_abs`. It is the exact path the
human's pointer takes. Keys do not: `key`/`text` switch on kind (a Wayland
surface takes the agent seat; a DMA-BUF child gets its socket) and a guest
window falls to `fail("bad key")`. The human's keys reach the guest through
`GuestSession.sendKey(hid:)` and the HID→qnum table; the agent's take the
same door.

**Capture cannot use the GPU path as it stands.** `capture` reads "the
window's own texture" through `fl_drm_view_capture_texture_once` — which for
a seamless window is the WHOLE scanout, every guest window and the guest's
desktop with it. That breaks the content-local property the broker is built
on. Two ways back, and the cheap one is not the design's:

- The design named per-window `Windows.Graphics.Capture` streamed over
  IVSHMEM. That is a streaming answer to a one-shot question: an agent's
  `screenshot` is a frame per action, not a feed.
- `flwin32_capture_window` exists (`flwin32_capture.c`): PrintWindow with
  `PW_RENDERFULLCONTENT`, measured on a real machine to return full content
  for Chromium, Windows Terminal, UWP and the desktop — occluded or not —
  and black only for the shell's own Flutter window, which no agent will
  ask for. Its limit is a minimised window, which is the crop's limit too.

  So capture is a helper op: `capture {hwnd, max_side}` → the window's own
  pixels, occlusion-proof, at the size the shim asks for, over the channel
  we have. The shim grows nothing, as the design promised: the broker
  returns the same `rgba`/`stride`/`row_order` reply it does for every other
  kind (`AgentBroker.swift`, the capture reply), sourced from the helper.
  1280 px on the long edge is ~3.5 MB of RGBA, ~5 MB as base64, per
  screenshot; virtio-serial carries that in well under a second, and if it
  does not, PNG in the helper is one line of System.Drawing. Measure
  before optimising.

**Semantics is a proxy the broker already has.** `semantic_tree` /
`perform_action` (`AgentBroker.swift:1385`) forward `{id, op, node,
action}` to a per-window unix socket (`agentEndpointPath`). The bridge's
channel was given the broker's vocabulary in M2 Phase 1 for exactly this
moment: a guest window's endpoint is its session's bridge, and the helper
answers with UI Automation — `System.Windows.Automation` ships in .NET
Framework, so the C# fixture can do it with no toolchain either.

**`await_settled` is per texture.** It measures frame-quiet on the window's
texture (`:1284`) — the shared scanout, for a guest window, so any guest
activity anywhere counts. Acceptable for v1 (it errs toward waiting);
`WaitForInputIdle` plus UIA quiescence from the helper is the sharper
answer and can come later.

**The seat lease has a home.** `humanHoldsControl` is take-over at window
granularity; the design wants it at VM granularity, because a Windows
session has one input queue and one foreground window (M2's Trap: "One
input queue, one foreground window"). The lease is a check in the same
chokepoint: while the person has ANY window of that domain focused, the
ops that need the foreground (`click` family, `key`, `text`) fail with a
distinct error so a batch stops cleanly; `capture`, `list_windows`,
`semantic_tree`, `perform_action` proceed — UIA patterns act without focus
or cursor, which is why semantic-first is the right default for a shared
VM. When the agent does act, the person sees the guest cursor move. The
notice says so.

**Ownership by launch needs a pairing rule.** A Linux launch pairs by
process ancestry; a guest launch cannot. The helper's `launch` gets the
started pid back from `Process.Start`, but a packaged app is started through
a broker process and Chrome is many processes, so pid alone pairs nothing.
The rule: after an agent's launch of record R, the first window that
appears within a bounded window (10 s) whose identity — AUMID or executable,
the same identity Phase 5 uses for records — is R's, is the agent's; later
windows of that identity are not. It is a heuristic and it is the same one
a person uses watching a launch; the trap is a second instance the human
opened in those ten seconds, and the notice covers it.

**The empty session stays blocked where M2 left it.** `WinShellBar
--session` as the guest's shell is soak-passed (winshell Phase 5,
2026-08-21) and is Swift: it needs the Windows toolchain the dev box and
the guest do not have, and the C# fixture cannot stand in for a shell. What
seamless mode actually needs from "empty" is smaller: no explorer taskbar
in the guest's work area, so a maximised guest window is the whole output,
and no desktop furniture in the scanout. Both are one helper op away
(`ShowWindow(Shell_TrayWnd, SW_HIDE)` and the desktop's `Progman`
listview), reversible on the switch back to the console. That is the v1
of Phase 4; the real shell replacement waits for the toolchain.

So M3 is, again, mostly wiring: one launch arm, one ownership rule, one
lease check, and four helper ops — of which two (`capture`, the furniture
hide) are transcriptions of C the bridge already has.

## Shape

```
  AGENT (MCP shim)          BROKER (shell)                    GUEST (helper)
  ────────────────          ──────────────                    ──────────────
  launch guest-…-notepad ─▶ Kind=guest-app arm ─▶ bridge.launch ─▶ ShellExecute
                            pair: first window of that      │
                            identity within 10 s → owner    ◀── windows event (pid, aumid)
  screenshot ─────────────▶ capture ─▶ bridge.capture{hwnd} ──▶ PrintWindow → RGBA
  click / key / text ─────▶ lease? ─▶ onPointerEvent / sendKey(hid)   (the human's paths)
  semantic_tree ──────────▶ proxy ─▶ bridge.semantic_tree{hwnd} ─▶ UIA CacheRequest
  perform_action ─────────▶ proxy ─▶ bridge.perform_action ────▶ Invoke/Value/Toggle/…
  await_settled ──────────▶ scanout frame-quiet (v1)
```

Decisions fixed here, each with the reason:

1. **Capture is the helper's PrintWindow, one shot per request.** Measured
   full content through occlusion for the apps that matter; no second
   transport; the shim's contract unchanged. Streaming capture is not an
   agent need and is deferred with the rest of WGC.
2. **The lease is per domain, not per window.** One input queue; a lease
   narrower than the queue would be a lie.
3. **Identity pairs launches, not pids.** The helper's pid is kept in the
   reply for the log, never trusted for ownership.
4. **The C# fixture carries all four ops** as the protocol reference, as in
   M2; the real helper transcribes them. `flwin32_capture_window` is the
   C side of `capture` already.
5. **"Empty" means hidden furniture**, until the toolchain exists.

## Phase 1 — the broker: launch, own, inject, lease

- `AgentBroker` launch op: `.guestApp` leaves the refusal case. The arm is
  `DesktopShell._launchGuestApp` with an agent: it records a pending pairing
  `(agentId, record, deadline)` on the session.
- `GuestSeamless.reconcile`: a window whose owner record matches a pending
  pairing within its deadline gets `ownerAgentId`, `spaceId = kNoSpaceId`,
  and the rail entry — exactly what `addWindow(ownerAgentId:)` does for a
  child, reached the same way. The pairing is consumed.
- Keys: the `key`/`text` switch gains the guest branch — `session.sendKey`,
  with the agent's modifier state the broker already tracks. Text is typed
  the way the human's is.
- The lease: in `ownedWindow()`'s neighbourhood, a `foregroundNeeded` flag
  per op; for a guest window, if the domain's session has a window the
  human focused (`windowManager.focusedWindowId` owned by no agent and
  `session.owns(it)`), fail with `"the human is using Windows"` — distinct,
  so the shim's batch stops cleanly.
- `list_windows` already scopes by owner; nothing to do.
- `guest_state` reports pairings and the lease, for the tier.

**BUILT 2026-09-04 (Phase 1).** `GuestSession` keeps the agent pairings
(`expectAgentWindow`, ten-second deadline, consumed by the reconcile through
`takeAgentPairing` by record id) and answers the lease (`humanIsUsing`: the
focused desktop window is human-owned and this guest's); `GuestSeamless`
passes the pairing's agent to `addWindow(ownerAgentId:)`, so an agent's
window has no space, no focus and no dock presence from its first frame,
and its guest-side foreground raises nothing on the desktop. Ownership
then follows the PROCESS for the rest of the launch's ten seconds, by the
window's own pid: Notepad restored four windows of its last session in one
burst on the first live run and only the first was the agent's, the rest
fell to the human. Bounded to the ten seconds because a single-instance app
is one process for everyone, and a person launching Notepad a minute later
must keep the window they get; a launch that lands in a process the human
already had pairs its one window only; the broker's
launch arm handles `Kind=guest-app` with the same `ReplyOnce` shape as a
host launch (25 s bail cancels the pairing); `inject` refuses with "the
human is using Windows" while the lease is theirs, activates the window in
the guest before any input (the op re-enters once the helper has answered;
`lastFg` is set optimistically so the reconcile's echo raises nothing),
and routes keys and text through `GuestSession.sendKey`, the human's own
door. `guest_state` reports `humanUsing`, `pairings` and each window's
`owner`. Phase 4's half that Phase 1 could not do without landed here too:
the guest's scanout updates feed `noteFrame`, so `await_settled` on a guest
window waits for the guest's SCREEN to go quiet (measured: text typed the
instant `launch` answered was lost with ok:true, Notepad having no edit
control yet; after a settle, or three seconds, it lands). One consequence worth knowing: an agent launching a guest app
switches the session to seamless mode, which closes the human's console
if it was open (the mutual exclusivity of M2 applies to agents too).
Check: "agents: a guest app is launched, owned, and typed into".

## Phase 2 — capture through the helper

- Helper: `capture {hwnd, max_side}` → PrintWindow `PW_RENDERFULLCONTENT`
  into a DIB, scaled so the long edge is `max_side`, returned as base64
  RGBA top-down with `w`,`h`. (`flwin32_capture_window` transcribed; the
  fixture's System.Drawing makes the scale one call.) A minimised window
  returns `ok:false, error:"minimised"` — the crop cannot show it either.
- Broker `capture`: for a guest window, round-trip the bridge instead of
  the engine, same reply shape, `max_px` forwarded as `max_side`.
- Measure: bytes and latency at 1280 px; switch to PNG in the helper only
  if a screenshot takes longer than a frame of the agent's patience.

**BUILT 2026-09-04 (Phase 2), verified live.** Helper `capture {hwnd,
max_side}` → PrintWindow `PW_RENDERFULLCONTENT` into a DIB, scaled so the
long edge is `max_side`. It returns **PNG**, not raw RGBA: the decision to
"switch to PNG only if a screenshot takes longer than a frame of the agent's
patience" was forced immediately — a 1280px window as raw base64 is ~5 MB
over the serial channel and took **over ten seconds** to write (a 640px one
9.2 s), where the same window as PNG is ~7.6 KB and arrives in ~240 ms. The
broker round-trips the helper for a guest window (no GPU path, whose texture
is the whole scanout; no lease and no activate, because capture reads pixels
and touches no input) and returns `format:"png"`; `agent-client.py`'s
`capture_to_rgba` gained a stdlib PNG decoder so every existing consumer
still gets RGBA. Verified occlusion-proof live: a Notepad window covered by
Terminal captured its own clean pixels (PW_RENDERFULLCONTENT renders the
WinUI content, not the black rectangle a plain PrintWindow gives a modern
app). Two traps found and fixed on the way: writing the FileStream directly
from Emit raced the reader thread and silently killed the observer (window
events stopped while replies kept coming); and a helper restarted without
restarting the shell desyncs the one-client virtio port, so the shell reads
an empty window list until it reconnects — restart the shell after the
helper. Check: "agents: a guest app is launched, owned, typed into, and
captured" also asserts capture succeeds while the human holds the lease.

## Phase 3 — semantics through the helper

- Helper: `semantic_tree {hwnd}` walks UIA with a `CacheRequest` (Name,
  ControlType, IsEnabled, the patterns available, BoundingRectangle),
  depth-limited, and returns nodes with stable ids for the tree's lifetime;
  `perform_action {hwnd, node, action}` maps `invoke`/`set_value`/`toggle`/
  `select`/`expand`/`collapse`/`scroll_into_view` onto the patterns.
  Chromium (Edge, WebView2) exposes UIA natively; the first query is slow,
  so the tree op has its own timeout.
- Broker: the proxy chooses the bridge when the window is a guest's; the
  payload is the one it already sends.

**BUILT 2026-09-04 (Phase 3), verified live.** Helper `semantic_tree {hwnd}`
walks UIA (`System.Windows.Automation`, resolved by the up-script from the
GAC/WPF folder — a tenth of the code of raw UIAutomationCore COM) and returns
a FLAT node list in the shell's own semantics shape — `{node, label, role,
rect, actions, value?}` — so an agent reads a Windows app's controls exactly
as it reads a Starling app's. Notepad came back as 39 nodes in ~600 ms (a
warm re-walk 180 ms): the menu bar (File/Edit/View, each invoke/expand/
collapse), the formatting toolbar (Bold/Italic as toggles), the tab strip
(TabItem with select), the editor (Document with set_value), the title-bar
buttons (Minimize/Maximize/Close as invoke). `perform_action {hwnd, node,
action, value?}` maps invoke/set_value/toggle/select/expand/collapse/
scroll_into_view onto the patterns; verified live, set_value on the editor
node marked the buffer modified. Only elements with a label or an action are
emitted, so a window is a page of controls, not thousands of structural
panes; node ids are valid until the next walk. The broker chooses the bridge
when the window is a guest's, gives the tree op a 20 s timeout (a first UIA
query is slow) and perform_action 10 s, and marks the window for the next
settle exactly as inject does. `agent-client.py`'s `tree`/`act` need no
change — the reply is the shape they already read. Check: "agents: a guest
app answers its accessibility tree, and an action drives it" (pre-cleans to a
single empty Notepad, because a restored multi-tab session opens windows
whose editor is not the one `launch` returns).

## Phase 4 — settled, for a guest

- v1: `await_settled` as it is (scanout frame-quiet). Note it in the reply
  (`"scope": "scanout"`) so a caller knows the quiet is the whole guest's.
- v2, when it bites: helper `settled {hwnd}` — `WaitForInputIdle` and a UIA
  structure-changed quiescence window.

## Phase 5 — the nearly empty session

- Helper: `furniture {hide: true|false}` — the taskbar (`Shell_TrayWnd`,
  `Shell_SecondaryTrayWnd`) and the desktop listview under `Progman`.
  Hidden on seamless attach, shown again on the switch to the console and
  when the helper exits.
- The work area follows: a hidden taskbar returns its strip, so a
  maximised guest window fills the output.

## Phase 6 — tests and docs

- `test/functional.py`: "agents: a guest app is launched, owned, captured,
  typed into and read" — launch Notepad through the broker as an agent,
  assert ownership (`list_windows` shows it, the human's `list_apps` does
  not count it), capture it and assert the pixels are the window's own
  (paint a known string, find it), `text` into it, read it back through
  `semantic_tree`; assert the lease refuses `click` while a guest window is
  human-focused. Skips without a domain, as the M2 check does.
- The conformance loop (`computer-use.md` Phase 4) run against a guest
  window, once its credentials exist on the box.
- `docs/WINDOWS-VM.md` "Apps as windows" gains the agent story and the
  lease notice.

## Traps

- **One input queue, one foreground window.** `SendInput`-class delivery
  lands wherever the guest's foreground is. Every foreground-needing op
  activates first (`activate` exists) and the lease keeps the human out of
  the way; a race between the two is a mis-aimed keystroke, not a crash.
- **UIPI.** An unelevated helper cannot see, capture or drive an elevated
  window. It is not in `list_windows`; the agent never learns of it.
- **PrintWindow is black for our own window** and returns nothing for a
  minimised one. Neither is an agent target.
- **A packaged app's `launch` pid is a broker's pid.** Pairing is by
  identity and time, never by pid.
- **Cloaked-when-minimised.** A Store app the agent minimises leaves the
  list (M2 leftover); the agent's next op fails "no such owned window". The
  filter fix is the real helper's; until then, document.
- **The channel is serial.** A 5 MB screenshot is fine; ten a second is
  not. The shim asks for one per action.
- **The fixture and the real helper must not diverge** on the filter, the
  identity rule or the ops' shapes; the C# is the reference, as in M2.

## Decisions to settle at approval

**Taken as recommended, 2026-09-04.** The reply to this draft was "Continue"
with no choice on the three; each came with a recommendation, and that is
what Phase 1 was built on: capture through the helper, the lease per
domain, furniture hidden. Any of them can still be reversed before the
phase that depends on it is built (Phases 2, 1 and 5 respectively).

- **Capture: PrintWindow via the helper (recommended) or crop-of-scanout.**
  The crop is a dozen lines in the broker and shows whatever overlaps the
  window in the guest; the helper's capture is occlusion-proof and costs a
  round trip. Recommended: the helper, because "a covered window captures
  the same as a bare one" is the property the broker promises.
- **Lease granularity: per domain (recommended) or per window.** Per window
  matches the Linux model on paper and lies in practice.
- **The empty session: hide furniture (recommended) or wait for
  `WinShellBar --session`.** Hiding is reversible, needs no toolchain, and
  is what seamless mode actually needs; the shell replacement brings the
  guest's tray and notifications to the Linux side, which is a feature, not
  a prerequisite.
