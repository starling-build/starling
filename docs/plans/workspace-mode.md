# Workspace mode — a driver app, and whatever it opens

Goal: a mode built around **one app you are working in** — Claude Code in a
terminal, or VS Code — with **whatever opens while you are there appearing
beside it as tabs**. Nothing about AI.

This replaces the AI Space (codename Murmuration), which is very nearly this
layout already, carrying far more machinery than the idea needs.

## The shape

Three columns, full height, below the status bar, on a dedicated space.

```
┌──────────────┬──────────────────────┬───────────────────────────┐
│ WORKSPACES   │  driver app          │ [Chrome][Files][Terminal] │ tabs
│              │                      ├───────────────────────────┤
│ ▸ starling   │  (Claude Code,       │                           │
│   sdk-win    │   VS Code, …)        │    the selected window    │
│   scratch    │                      │                           │
│   + New      │                      │                           │
└──────────────┴──────────────────────┴───────────────────────────┘
      280px          resizable ↔                    rest
```

**Left — the workspace list.** One row per workspace, plus `+ New`. Selecting a
row switches the other two columns to that workspace.

**Middle — the driver.** One app. When empty it shows a `+` button; clicking it
opens the launcher, and the app chosen becomes the driver.

**Right — what the driver opened.** Empty by default. A tab strip over captured
windows, one visible at a time.

**When the driver quits, the right-hand apps stay** and the middle returns to
its empty `+` state. The workspace outlives its driver; you can pick another and
carry on with the same set of open windows beside it.

## Where we are

`Shell/AgentSpace.swift` is 781 lines building almost exactly this: a 280px
sessions rail with a `+ New` button and 58px rows, a ~688px column (clamped
420–1100) rendering the agent's terminal, a stage with a tab strip over the
agent's other windows, and a draggable 8px divider between the last two.

The space is a first-class virtual desktop: `SpaceKind.agent`
(`WindowManager.swift:145`), created lazily by `ensureAgentSpace()`, pinned last
in the strip, and excluded from Ctrl+←/→, Ctrl+Tab, Mission Control and
`removeSpace`. Entered with **Ctrl+Down** or the desktop context menu. A 1s
timer forces rebuilds while it shows, because texture updates do not dirty
widgets.

Ownership is one field, `WindowInfo.ownerAgentId`, stamped at launch and never
inferred. Owned windows get `spaceId = kNoSpaceId` and are filtered out of every
desktop query — dock dots, tiling, Mission Control, focus — so they have no
desktop presence. **This is already per-agent, so it becomes per-workspace with
a rename**: one workspace's tabs are invisible to another's, for free.

## The decision that shrinks this: capture on open

**While a workspace is active, any newly-opened window becomes one of its
tabs.** No pids, no `/proc`, no environment tags, no launch-chain arming.

Genuinely attributing "opened by the driver" was investigated and rejected. It
is both harder and worse:

- It fails on exactly the cases that motivate the feature. Claude Code running
  `xdg-open https://…` reaches the shim in `build/appbin/xdg-open`, which execs
  `app-run chrome <url>`; if Chrome is **already running** the URL folds into
  the existing process and no new window or process appears at all. VS Code
  opening a file makes a tab inside itself, not a toplevel.
- The mechanisms that would work are partial. `xdg_activation` is a stub that
  hands out dummy tokens. Process ancestry breaks on double-forks and D-Bus
  activation. An inherited `STARLING_WORKSPACE=` env tag stamped by `app-run`
  and read back from `/proc/<pid>/environ` is the most robust of them — the
  shell and its clients run as the same uid, so that read works, verified — but
  it still cannot see through a singleton handoff.

Capture-on-open needs none of it, and gives a rule you can hold in your head:
*things you open while you are in a workspace land in that workspace.*

### The carve-out that makes it work

The `+` button launches into the **middle**, not the right. So the capture rule
needs one exception: a launch started by `+` fills the driver slot; everything
else captured while the workspace is active goes right.

The shell already has this exact pattern and its scar tissue. `_launchAgentChrome`
arms `_pendingAgentWayland` immediately before spawning, and the first toplevel
from a new `wl_client` consumes it (`DesktopShell.swift:1055-1062`). The
documented hazard is that a claim left armed is *still armed later*, so "the
human opens a browser and their window becomes the agent's" — which is why a
timeout disarms it. Reuse the pattern **and** the timeout.

## The part that will bite: the AI apparatus is load-bearing for the tests

The instinct is to delete `AgentBroker.swift` and `AgentSemanticsEndpoint.swift`
along with the AI framing. **That would blind a third of the functional tier.**

`test/functional.py` drives the desktop through the broker's *agent-scoped* ops
with a real identity — `hello`, `launch`, `list_windows`, `semantic_tree`,
`perform_action`. The Settings, control-centre and datetime checks all work by
launching a pane into an owned window and asserting on its **semantic tree**,
which is how this suite avoids asserting on pixels. `semantic_tree` and
`perform_action` are proxied to the child's `agentEndpointPath`, served by
`sdk/.../AgentSemanticsEndpoint.swift`, which only starts when
`$STARLING_AGENT_ENDPOINT` is set — and the only thing that sets it is
`AgentSpace.swift:650`.

So the rename carries a hard requirement: **the workspace launch path must keep
setting that endpoint variable**, or those checks stop working. The "agent"
concept survives as *a broker client with an identity* — a headless automation
session, not an AI.

Two other consumers, both narrower than they look: `build/shell-drive.py` uses
only `screen` and `dock_rects`; `apps/AppStoreApp/.../ShellLink.swift` uses only
`subscribe_apps`. Both unscoped, both unaffected.

## Reuse

| What | Where | Note |
| --- | --- | --- |
| The rail | `AgentSpace.swift:65-129` | Becomes the workspace list; `+ New` is already there. Rows lose the working/idle dot |
| `_agentPane()` | `:419-481` | The pane renderer: texture, Y-flip, scaled pointer/scroll forwarding in content-local coords, focus-on-click |
| Tab strip | `:188-232` | Already right, including duplicate-title suffixes and stale-selection cleanup |
| Divider | `:275-297` | Reconfigures clients on pointer-up, not per frame |
| `_applyAgentWindowGeometry()` | `:328-350` | "Window rect is authoritative, client follows via `onContentResize`" is exactly this model |
| `_updateAgentFrameThrottles()` | `:377-398` | Off-tab windows at 5fps — a real win once tabs exist |
| Space mechanism | `WindowManager.swift:145-260` | Layout-agnostic; only the `SpaceKind` case is renamed |
| Ownership + desktop filtering | `ownerAgentId` and its ~8 filter sites | → `ownerWorkspaceId`; semantics unchanged |
| Pending-claim arming | `DesktopShell.swift:1055-1062` | Becomes the `+`-launch → driver-slot carve-out |

**Do not adopt the SDK's `FluentUI/Controls/Navigation/TabView`.** It is a
complete, unused, ported control and it looks like the obvious answer. The shell
is deliberately Fluent-free (CLAUDE.md, "macOS style by default") and does not
link FluentUI at all today. The hand-rolled strip stays.

## What goes

Roughly half of `AgentSpace.swift`, all of it AI-specific:

- `_linkAgentSkill()` (51 lines) — symlinks a Claude Code skill into
  `~/.claude/skills`
- `_runAgentDemo()` (61) + the "Run Files task" button and demo status line
- `_newAgent()` — hardcodes a fleet of TerminalApp + FileExplorerApp; `+ New`
  now makes an empty workspace instead
- `_launchAgentChrome()`'s CDP profile plumbing, and the `cdp_endpoint` op
- `_agentIsWorking` / `_agentWindowActive` — working/idle dots from broker op
  recency
- The middle column's "the terminal IS the chat" special-casing
  (`terminalWindowId`, `isTerminal:` threading, native-scale rendering) — the
  driver is any app now
- `_humanControlledWindows` and the Esc take-over — that exists only because an
  agent is otherwise driving the window
- Broker ops `inject`, `capture`, `await_settled` (no test uses them;
  `agent-client.py` does, and goes with the AI mode)

## Built so far

The layout and the driver slot, as a **new space alongside the AI Space** —
nothing in `AgentSpace.swift` or the broker was touched, so the functional tier
is unaffected.

- `SpaceKind.workspace` + `WorkspaceInfo`, `ensureWorkspaceSpace()`, and
  `isSpecial` so both special spaces are pinned past the user spaces and
  excluded from Ctrl+←/→, Ctrl+Tab, Mission Control and `removeSpace`
- `WorkspaceSpace.swift` — rail, driver column with its `+` empty state,
  divider, tab column (empty for now), pane renderer, geometry
- Entered with **Ctrl+Shift+Down** or the desktop context menu → "Workspace".
  Ctrl+Up was already Mission Control and Ctrl+Down the AI Space, so Down with
  Shift is the only arrow left
- `+` opens the launcher into the driver slot; the app lands in the middle
- The driver quitting empties the middle and leaves the workspace intact

Two things this shook out, both found by driving it rather than reading it:

- **The launcher had two launch paths.** The click list called `onLaunch`; Enter
  called `_launchOrFocusApp` directly. Wiring only the first meant clicking an
  app worked and typing its name put it on the desktop instead. Both now go
  through `_launchFromLauncher`.
- **Keystrokes are routed by `processTextureIds[win.appId]`,** so a window whose
  app id is not in that map is mouse-only — it looks alive and ignores the
  keyboard. Workspace children use a `"<workspaceId>:<appId>"` composite key,
  like the AI Space does, which also keeps them from lighting the dock.

The right panel receives windows two ways, both working:

- **Wayland clients spawned by the driver.** Typing `weston-flower &` into the
  Terminal driver puts the flower in the right panel as a live tab. This is the
  case the whole idea is about.
- **The launcher**, via a `+` at the end of the tab strip — needed because the
  dock is faded out in this mode, so otherwise there is no way to open a second
  app from inside a workspace.

Tabs switch by clicking; the newest opens selected.

A third trap, found the same way as the other two: **`addWindow` hops the active
space to a user space**, so asking "is a workspace on screen?" *after* creating
the window always answers no, and the window lands on the desktop the user
cannot see. It has to be sampled before. The agent path already compensated for
that hop, which is why its own capture worked.

Not built: only first-party apps can drive the middle column — VS Code and
Chrome arrive as Wayland clients and need the launch-chain claim.

## Staging

1. **Rename in place, no behaviour change.** `SpaceKind.agent` → `.workspace`,
   `ownerAgentId` → `ownerWorkspaceId`, `AgentInfo` → `WorkspaceInfo`,
   `ensureAgentSpace` → `ensureWorkspace`. Keep the broker's op names on the
   wire so `functional.py` passes untouched — the wire protocol is a
   compatibility surface, not an internal name. Green tier after this step.
2. **Empty state + `+` in the middle**, with the launcher wired to fill the
   driver slot, and the pending-claim carve-out (with its timeout).
3. **Capture on open** into the active workspace's tabs. This is the feature.
4. **Driver-quit behaviour**: middle returns to empty, tabs survive.
5. **Rail becomes workspaces**: create, select, rename, remove.
6. **Delete the AI-specific code** above, keeping the endpoint variable wired.

## Decisions still open

- **Escape hatch.** A captured window needs a way out — "Move to Desktop" on the
  tab's context menu is the obvious one. Without it, anything opened in a
  workspace is trapped there.
- **Removing a workspace** that still has tabs: close those windows, or move
  them to the desktop? Moving is the safer default; destroying user windows on a
  rail click is the kind of thing that gets discovered the hard way.
- **Portal dialogs.** `PortalFileChooser` calls `addWindow` too. A file picker
  the driver opened probably wants to be modal over the middle pane rather than
  a tab; capture-on-open would make it a tab.
- **Pre-existing windows.** Entering a workspace does not pull in what is
  already open on the desktop. Least surprising, but "put this window in my
  workspace" will want an affordance eventually.
- **Persistence.** Do workspaces and their driver choice survive a logout? The
  windows cannot, but the list and the remembered driver could.
