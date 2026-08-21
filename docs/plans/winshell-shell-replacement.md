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

### Phase 4 — the surfaces explorer's family draws

- **Toast banners.** The centre reads the store; without explorer nothing
  pops. A listener plus a transient banner window (popup surfaces again).
- **Run dialog** on Win+R — a small launcher mode, not a new app.
- **Alt-Tab**: Windows' fallback switcher survives shell replacement;
  ours-with-previews (the dock's DWM thumbnail machinery) is a follow-up,
  not a blocker.
- **Volume/brightness OSD**: verify in the VM whether the system's own
  survives shell-less; build only if it does not.

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
