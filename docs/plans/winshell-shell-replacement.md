# winshell — replacing explorer.exe

The plan for the last phase of the Windows port: Starling as the SHELL, not
a shell drawn over explorer's. Written 2026-08-21, when the file explorer
reached feature parity and the chrome (dock, Start, Quick Settings,
notification centre) was already ours.

## What "the shell" is, and what we already hold

explorer.exe is four things at once (flwin32_explorer.c says this first):
the taskbar, Start, the notification tray, and the desktop — wallpaper,
icons, drag-and-drop, and the shell dialog plumbing. "Replace the shell"
means the registry's `Winlogon\Shell` value, which replaces all four in one
stroke and leaves the user with no desktop at all if we crash. That is why
it is the LAST phase, and why every step before it must keep its own
reversal path (the `--restore-taskbar` discipline).

Already replaced, with explorer still running underneath:

- Taskbar → the dock (appbar reservation, native taskbar hidden with state
  saved and three ways back).
- Start → the launcher (Win+key).
- Quick Settings → Win+A; notification centre → Win+N, reading the real
  toast store.
- File windows → Starling Files, registered as the file-manager role.
- Tray DISPLAY → the dock shows the icons by reading explorer's tray; the
  probe work in flwin32_tray.c already decoded the 32-bit NOTIFYICONDATA
  wire format and proved we can take and hand back the Shell_TrayWnd class.

Still explorer's: the desktop surface, tray OWNERSHIP, toast banners, the
startup-apps run, a handful of hotkey roles (Win+E, Win+D, Win+R), and the
session slot itself.

## The dependency spine

Ordered so each phase pays on its own even if the next never lands, and so
nothing risky runs on a real machine before the VM has survived it.

### Phase 0 — two prerequisites that pay four times each

**Shell-namespace enumeration.** Starling Files lists with FileManager;
IShellFolder appears only in fileops for verb binding. A namespace listing
mode (enumerate PIDLs, display names, icons, and attributes through
IShellFolder/IShellItem) unlocks: the Recycle Bin view, Network and Quick
Access, ZIP-as-folder — and later the desktop icon grid, which is nothing
but a folder view of Desktop + Public Desktop. This is the single largest
enabler in the plan.

**Popup-window surfaces.** The parked context-menu-as-its-own-window spike
(task list, deferred section). The desktop's right-click menu, tray icon
flyouts, and toast banners all need a surface that can overhang and stand
alone; the feasibility notes (FlutterDesktopEngineCreateViewController
exported, secondaryPipelines view-generic, per-view pointer routing) carry
over unchanged.

### Phase 1 — finish Explorer-the-app

With namespace enumeration in hand: Recycle Bin and Network in the sidebar
(they were withheld as "a row that navigates nowhere is worse than
absence" — now they navigate), Quick Access pinning, ZIP browsing. Plus
the non-namespace gaps: per-file thumbnails in the listing
(IShellItemImageFactory — the mica tint already exercises it), typed path
entry in the breadcrumb (click flips to an edit field), Ctrl+Z bound to
the IFileOperation undo stack that already exists, and subtree search
(honest version: a cancellable walk, not an index). Win+E opens Starling
Files.

### Phase 2 — the desktop surface

A per-monitor bottom-of-z-order window: wallpaper (IDesktopWallpaper /
the registry value we already read), the icon grid as a namespace folder
view, OLE drop target and drag source (the machinery from the Files
window), right-click menu on the popup surfaces, and icon-position
persistence in our own store. Win+D parks/restores.

Decision made here rather than discovered later: the desktop surface
ACTIVATES ONLY IN NO-EXPLORER MODE. While explorer runs, Progman owns the
bottom of the z-order and fighting it for wallpaper clicks is a losing
game; the surface exists for the endgame, tested in the VM's trial mode.

### Phase 3 — tray ownership

Flip flwin32_tray.c from reading explorer's tray to BEING Shell_TrayWnd
full-time: answer NIM_ADD/MODIFY/DELETE off the decoded wire format,
service the appbar protocol that arrives on the same window (SHAppBarMessage
resolves the same class — other appbars' reservations become ours to
grant), broadcast TaskbarCreated so every running app re-adds its icons,
and hand the class back on any exit path. With explorer present this runs
in forward-what-isn't-ours mode (already prototyped); with explorer absent
we ARE the answer.

**DONE 2026-08-21 (track 3).** The appbar service is live in flwin32_tray.c:
registry, QUERYPOS/SETPOS clipping with same-edge stacking, GETTASKBARPOS
answered with the dock's own bar (found by pid, no dock touchpoint),
GET/SETSTATE, GET/SETAUTOHIDEBAR per edge, ABN_POSCHANGED to other bars,
and SPI_SETWORKAREA recomputed on every grant (saved and restored on stop).
Serving activates when explorer's tray is absent, or under STARLING_TRAY_OWN=1
for tests. Verified in the VM with explorer killed: work area 712, GETTASKBARPOS
(0,712,1024,768) edge 3 from an out-of-process probe, icons and dock intact,
explorer restored cleanly after. Three wire facts worth keeping: the envelope
is packed-32-bit APPBARDATA(40) + u64 dwMessage + u64 hSharedMemory + u64 pid;
hSharedMemory is an SHAllocShared block (a raw POINTER for same-process
callers), so results are written back through SHLockShared/SHUnlockShared —
MapViewOfFile fails ERROR_INVALID_HANDLE; and the pid field names the process
the handle is valid in (the tray's own, pre-duplicated by the sender's
shell32). One ordering rule bought with a failed test: the dock takes the
tray class BEFORE its panel registers the appbar (main.swift), because
SHAppBarMessage resolves Shell_TrayWnd at call time.

### Phase 4 — the surfaces explorer's family draws

- **Toast banners.** The centre reads the store; without explorer nothing
  pops. A listener plus a transient banner window (popup surfaces again).
- **Run dialog** on Win+R — a small launcher mode, not a new app.
- **Alt-Tab**: Windows' fallback switcher survives shell replacement;
  ours-with-previews (the dock's DWM thumbnail machinery) is a follow-up,
  not a blocker.
- **Volume/brightness OSD**: verify in the VM whether the system's own
  survives shell-less; build only if it does not.

**Banners + Run DONE 2026-08-21, VM-verified.** Both ride the parked-overlay
machinery rather than the popup-surface spike — each is its own process
(`--banners`, `--run`) with a named toggle channel, which the overlay work
had already made cheap. What each took:

- *Banners* (Banner.swift): a controller OUTSIDE the widget tree (a parked
  overlay's tree does not mount until first shown, and deciding when to show
  is the whole job) polls the store every 2s off the UI thread, seeds
  silently on first read (the login backlog is the centre's business), and
  pops only what the native shell cannot: explorer absent, or
  STARLING_BANNERS=1 for tests, never while the centre is on screen. The
  overlay grew a **passive** mode for it — show without activation and
  without the global Escape hotkey — because a surface that appears while
  the user is typing must steal nothing. Verified in the VM with explorer
  killed: banner pops on a fresh toast, keystrokes keep landing in notepad
  WHILE it is up, it auto-dismisses at 6s, body-click opens the centre,
  X-click just dismisses, and with explorer alive or the centre open it
  stays suppressed. Restoring explorer had ShellExperienceHost pop the
  backlog toast natively — the muteness really is explorer-keyed.
- *Run* (RunDialog.swift): overlay pinned to the work area's bottom-LEFT
  (a `leftMargin` anchor, mirroring the centre's right pin), Win+R joins
  the dock's chord capture. Executes via ShellExecute with %VAR% expansion
  first; failure is the native dialog's wording drawn inline, not a modal.
  Verified: chord opens ours (explorer's RunFileDlg never appears), the
  last command comes back selected on reopen with any stale error cleared,
  `%windir%\notepad.exe` expands and launches, Esc and the Cancel button
  both dismiss.
- The chase for "who draws banners without explorer" was settled in the VM
  first: ShellExperienceHost survives explorer's death but goes MUTE —
  Show() succeeds, the store fills, nothing pops.
- A pre-existing dock bug surfaced by the Run overlay's show/hide churn:
  `_rebuild`'s `claimed` set never included the two fixed tiles' keys, so
  `retain(only:)` freed the Files folder texture on every window event and
  the tile flashed the fallback glyph until re-rasterize. Fixed by claiming
  kLauncherKey/kFilesKey.
- Still open in this phase: Alt-Tab-with-previews (follow-up, not a
  blocker) and the OSD survival check — both as bulleted above. Toast
  arrival is polled; wiring UserNotificationListener's NotificationChanged
  through the raw ABI would make it instant. The banner's app logo draws
  Settings' plated icon as a dot at 16pt where native shows the bare gear —
  cosmetic, needs the unplated asset.

### Phase 5 — the session slot

- **Startup runner**: HKLM/HKCU Run, RunOnce (delete-before-run
  semantics), and the Startup folders, in explorer's order.
- **Registration**: per-user `HKCU ...\Winlogon\Shell` first (one account
  opts in; every other account still gets explorer), machine-wide never
  during development.
- **The supervisor**: a tiny watchdog whose only jobs are restart-on-crash
  and restore-explorer-on-repeated-crash. A shell that dies twice in a
  minute writes `Shell=explorer.exe` back and lets the machine live.
  Ctrl+Alt+Del → Task Manager → Run is the documented last resort; it
  survives any shell.
- **The long tail, audited not assumed**: ShellExecute paths that bounce
  through DDE, autoplay and device-arrival UI, safely-remove. Each gets a
  VM check; most are expected to work or degrade harmlessly.
- **Signing**: flwin32_explorer.c already records that a Shell= binary
  needs EV signing to live with SmartScreen. That is a release concern,
  not a development one — the VM does not care.

## Parallelization — four tracks, owned files, two test targets

The dependency graph allows more parallelism than the files do. Phases 0a
(namespace), 0b (popup surfaces), 3 (tray), and 5's early parts have no
code dependencies on each other; what collides is ownership of the hot
files and the two machines that can run the result. The 2026-08-21
action-center merge landed clean because the parallel sessions pushed
early and mostly alternated deploys — this section makes that luck into
policy.

Wave 1, four tracks, each owning its files exclusively:

| track | work | owns | test target |
|---|---|---|---|
| 1 | namespace enumeration (0a), then the Phase-1 file-manager items SERIALLY | Win32Files.swift, FilesBloc.swift, Files.swift, new flwin32_namespace.c | dev box |
| 2 | popup surfaces (0b) | Adapter.swift (secondary views), flwin32_host.c, new popup host files | dev box — coordinate deploy windows with track 1 |
| 3 | tray ownership (Phase 3) | flwin32_tray.c, one dock touchpoint | the VM — taking Shell_TrayWnd full-time is exactly what must not be first tried on the machine being worked on |
| 4 | session plumbing (Phase 5 early): startup runner, supervisor, oracles, VM survival scripts | all new files, docs/windows-vm/ | the VM |

A fifth track fits with zero collisions if there is appetite: the engine
repo's frame-dispatch scheduler work (its smoothness gate is now built —
STARLING_PRESENT_LOG's gap histogram), which touches no desktop-repo file.

Rules that make it work:

- **Files.swift/FilesBloc.swift belong to track 1, full stop.** Thumbnails,
  typed paths, Ctrl+Z, search and the namespace rows all land there; they
  are one serial queue inside track 1, never a second session's edit.
- **main.swift flag additions will conflict trivially** (every track adds a
  --print-* oracle); accept and resolve, they are one-line.
- **Push early and often.** The clean merge this plan was written under
  happened because both sessions kept origin/winshell current.
- **Before wave 1 starts: a per-track dist.** The deploy loop is
  `Stop-Process -Name WinShellBar` plus overwriting one dist folder, so
  two dev-box sessions kill each other's running tests. A `--dist <dir>`
  (or a second dist folder for track 2) is a ten-minute change that buys
  the whole scheme.

Wave 2, as wave 1 merges: the desktop surface (needs 0a AND 0b), toast
banners (needs 0b), Win+E/Win+R riding whichever track is open. Phase-1
items continue inside track 1 throughout. The waves converge to two
tracks, then to one for the Shell= switch and the VM soak — that last
step is deliberately not parallel with anything.

## Trial mode and verification

Everything from Phase 2 on is proven in the libvirt Windows guest FIRST
(docs/windows-vm: winrun.py drives PowerShell through the guest agent,
wshot.py/wclick.py screenshot and click from the host, autounattend.xml
rebuilds the guest from nothing). The gate before the dev box ever runs
`Shell=starling`: the VM survives login → startup apps ran → tray fills
with a real app's icon → a toast banners and lands in the centre → the
shell is killed and the supervisor recovers it → the shell is killed twice
and explorer comes back on its own.

Per-phase oracles in the established `--print-*` style: `--print-tray`
(who owns Shell_TrayWnd, what icons are registered), `--print-desktop`
(icon count and positions), `--print-startup` (what would run). The only
honest check of a shell's claim is asking the system from outside the
process that makes it.

## Explicitly not ours

winlogon, the lock screen, UAC/consent, credential UI, DWM and
composition, in-app file dialogs (comdlg runs in the calling process),
and UWP app hosting. The plan replaces explorer.exe, not Windows.

## Sizing

Namespace enumeration and the popup-surface spike are a session each;
Phase 1's remainder one more; the desktop surface one to two; tray
ownership one (the research is done); banners-and-hotkeys one; the
session slot plus the VM soak one to two. Roughly seven to nine sessions
end to end, each leaving the tree shippable and explorer-compatible —
the switch at the end is one registry value, with its hand on the way
back.
