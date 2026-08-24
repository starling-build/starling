# Installing the Starling desktop on Windows

One file, one account, no administrator. `StarlingSetup-<version>.exe` puts
the desktop under `%LOCALAPPDATA%\Programs\Starling` and registers it as the
shell **for the account that ran it** — every other account on the machine
still signs in to Explorer.

**One binary is the whole desktop.** `WinShellBar.exe` is the dock, the
desktop plane, the Start launcher, the notification centre, the banners, the
Run dialog **and the file explorer**. The file explorer is an engine *view*
inside the shell's process rather than a program of its own, which is why
there is no second exe in the package and why Win+E opens a window without
starting a process. That is also where its speed comes from
(`docs/perf/winshell-launch-2026-08-23/`).

## What you need

- Windows 11 x64. Measured and soaked on **build 26200**; the shell-
  replacement path is per-user Winlogon, which has been stable for a decade.
- ~140 MB on disk, ~48 MB downloaded.
- **No administrator, no Program Files, no service, no HKLM.** The only thing
  written outside the install directory is one registry value:
  `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`.
- The build is **unsigned**, so Windows will object once — see
  [If Windows blocks it](#if-windows-blocks-it).

## Install

### The setup exe

Double-click `StarlingSetup-<version>.exe`, confirm the prompt, done. It
installs and registers; **you are still in Explorer until you sign out and
back in**, which is the reversible way to try a shell.

Unattended (deployment, or a machine you are driving over SSH):

```powershell
StarlingSetup-0.1.0.exe /Q:A
```

### The zip

Same payload without the wrapper — this is the one to use if you want the
options.

```powershell
Expand-Archive Starling-0.1.0-win-x64.zip -DestinationPath $env:TEMP\starling
powershell -ExecutionPolicy Bypass -File $env:TEMP\starling\Install.ps1
```

| flag | what it does |
|---|---|
| *(none)* | install + register; takes effect at the next sign-in |
| `-Now` | also switch **this** session over: stops Explorer, starts Starling |
| `-NoRegister` | install the files only, change no registry value |
| `-Destination <path>` | somewhere other than `%LOCALAPPDATA%\Programs\Starling` |

### From source

`build/win/package-shell.ps1` is the **single definition of what an install
contains** — `build/package-desktop.sh`'s counterpart. It builds, assembles,
zips, and wraps the zip in the setup exe:

```powershell
.\build\win\package-shell.ps1                 # build + package
.\build\win\package-shell.ps1 -SkipBuild      # repackage what is already built
```

It takes `-Version`, `-OutDir`, `-EngineOut` and `-SwiftRuntime`; the
defaults match a box set up per `docs/BUILDING.md`. Add `-Sign` with either
`-SigningMetadata` (Azure Artifact Signing) or `-CertThumbprint` (a
certificate on a token) to sign the payload and the setup exe — see
[`docs/WINDOWS-SIGNING.md`](WINDOWS-SIGNING.md), which is also where the
Smart App Control argument for bothering lives. `Install.ps1` and
`Uninstall.ps1` are copied into the package **verbatim** — edit them in
`build/win/`, never re-inline them in the packager, or a built package ships
a stale installer.

## First sign-in

Sign out and back in. Winlogon starts `WinShellBar.exe --session`, the
supervisor: it spawns the shell, replays the startup sources a real session
replays (HKLM RunOnce, HKLM Run in both views, HKCU Run, both Startup
folders, HKCU RunOnce — `--print-startup` lists them without running any),
and watches its children. Explorer never starts.

The dock is at the bottom, icons centred; right-click it for **Icons to the
start** if you would rather have them at the left, Windows-10 style.

The Windows key opens Start, and the four chords are ours too: **Win+E** the
file explorer, **Win+R** the Run dialog, **Win+A** Quick Settings, **Win+N**
the notification centre. Every other `Win+<key>` Windows defines still works
— the shell masks the bare tap rather than eating the keydown, so it never
had to re-implement the shortcut table.

## Uninstall

```powershell
powershell -File "$env:LOCALAPPDATA\Programs\Starling\Uninstall.ps1"
```

It un-registers *first* (while the binary that owns the value is still
there), restores Explorer's taskbar — our dock hides it rather than closing
it — starts Explorer, and then deletes the directory. `-KeepFiles` stops
being the shell without removing anything.

## If it fails to start

**It recovers itself.** The supervisor counts child exits: two within a
minute and it deletes its own `Winlogon\Shell` value, starts Explorer in the
session you are sitting in, and exits. The next sign-in is a stock Windows
one. No recovery console, no safe mode.

To do it by hand from a session with no shell — Ctrl+Shift+Esc opens Task
Manager even with nothing else running, then *Run new task*:

```
explorer.exe
```

and to make it permanent:

```
reg delete "HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" /v Shell /f
```

The session log is `%LOCALAPPDATA%\Starling\session.log` — every spawn,
every exit, the startup replay, and the bail if there was one.

## If Windows blocks it

The package is not code-signed, and Windows has two separate defences that
say so in different words:

- **SmartScreen** — "Windows protected your PC" on a downloaded file. *More
  info* → *Run anyway*. Once.
- **Smart App Control** — refuses unsigned binaries outright, with no
  override. It can only be turned **off**, and turning it off is
  **irreversible without a clean install of Windows**. That is a decision
  about the machine, not a step in an install; on a machine that keeps it on,
  *this* package cannot run at all.

  **Unsigned is the operative word, and it is fixable.** SAC blocks
  "malware, PUA, and unknown, unsigned code" — where its intelligence
  service has no opinion about a file, it still allows one *signed by a CA
  in the Microsoft Trusted Root Program*
  ([overview](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview)).
  So a publicly-trusted signature is what moves this package from "cannot
  run" to "runs", and it is the reason to sign that outweighs the
  SmartScreen dialog — which a signature does **not** remove, because
  reputation builds per file hash and per publisher over weeks of downloads
  ([SmartScreen reputation](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)).

  Two mitigations that need no certificate: SAC can only switch on at a
  **clean install** of Windows, and Microsoft turns it off automatically on
  machines whose usage looks like development. Anyone replacing their shell
  is likely to be on such a machine already.

## Running it beside Explorer

`--session` refuses to start while Explorer is running — two shells fighting
over startup, the tray and the appbar is not a state anyone asked for. For a
smoke test on a machine you do not want to convert:

```powershell
$env:STARLING_SESSION_TRIAL = "1"
& "$env:LOCALAPPDATA\Programs\Starling\WinShellBar.exe" --session
```

The desktop plane's own gate honours the same variable, inherited by the
children. This is a *test* mode: Explorer's taskbar and ours both exist, and
startup is not replayed (Explorer already ran it this logon).

## What is in the package

47 files, 136.5 MB staged:

| | |
|---|---|
| `WinShellBar.exe` | the desktop — every surface listed at the top |
| `flutter_engine.dll`, `flutter_windows.dll` | the engine, release build |
| `data\icudtl.dat`, `data\flutter_assets` | ICU, and the asset bundle |
| `FlutterSwift_CupertinoIcons.resources` | the icon font |
| `*.dll` (Swift runtime) | most of the size, and all of the portability |
| `BUILD-STAMP.txt` | version, commit, build time, engine directory |
| `Install.ps1`, `Uninstall.ps1` | shipped inside, run from inside |

The Swift runtime is bundled because a machine that never installed the
toolchain has none of it. To check the closure is complete rather than
assuming it — a build box has the toolchain on `PATH`, which hides a missing
DLL — run the exe with a system-only `PATH`:

```powershell
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
& .\WinShellBar.exe --print-startup
```

Every static import resolves before `main`, so if that prints, the package is
self-contained. (`dumpbin /dependents` will list `api-ms-win-*` entries as
"missing" — those are API-set contracts resolved by the OS schema, not files.)

## Traps

- **A quiet iexpress install runs `UserQuietInstCmd`, not `AppLaunched`.**
  Leave it empty and `/Q:A` extracts the payload perfectly, runs nothing, and
  exits `0x80070002` — "file not found", for the empty command. It reads like
  a corrupt package. `/C /T:<dir>` extracts without running and settles which
  half is broken in one command.
- **Un-register before deleting.** A `Winlogon\Shell` pointing at a path that
  no longer exists signs you in to a black screen with no shell to fix it
  from. `Uninstall.ps1` orders it that way for this reason.
- **Restore the taskbar before stopping the dock.** Our dock *hides*
  Explorer's taskbar rather than closing it, so stopping first leaves a
  desktop with neither bar. `WinShellBar.exe --restore-taskbar` is the
  standalone recovery for a shell that was killed rather than closed — it
  also re-announces the tray, which does not repopulate on its own.
- **Killing Explorer does not leave you shell-less.** `AutoRestartShell` is
  `1` on a stock Windows, so Explorer comes back on its own within seconds —
  and `--session` then refuses to start beside it, which looks like "the
  shell would not start" when it is really "Explorer won the race". Switch a
  live session over with `Install.ps1 -Now`, which stops Explorer and starts
  the shell as one step, or just sign out and back in.
- **`Install.ps1` stops a running `WinShellBar` before copying.** A running
  copy holds its own exe open; without the stop the copy fails halfway and
  leaves a tree that is half of each build.
