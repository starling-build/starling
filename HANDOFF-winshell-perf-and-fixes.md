# Checkpoint — Windows shell fixes + perf, 2026-08-26

Continues `HANDOFF-winshell-minimize-and-packaged-apps.md` (which is current
through the "borrow died, explorer service returns" work). This one covers what
landed AFTER that: the console-window fix, the UI-thread perf fix, the
Start-menu head-to-head against native Windows, and the file-manager benchmark
that was interrupted when the box went offline.

Box: the physical machine (`starling@192.168.68.60`). **As of this checkpoint
the box is DOWN** — see "Box state" at the bottom; that is the first thing to
deal with.

## Headline

Two shell fixes landed and verified this session; the Start-menu latency now
beats native Windows ~2–4×; the file-manager comparison is the one unfinished
piece. Mainline is pushed through `8f79405`.

## What landed this session (all pushed to main)

| | commit | what | verified |
|---|---|---|---|
| Explorer service default-on again | `b12ed96` | borrow-per-launch was condemned (flapping frames, blacked desktop); one hidden explorer stays alive for CoreWindow app launch | 12/12 packaged-app launches framed on a cold boot |
| ImmersiveShell activation decode + survey | `9a69c4a` (+ survey) | decoded the undocumented COM surface CoreWindow apps need (2 interfaces, 1 method each); surveyed how other shells handle it (nobody reimplements it — Cairo/Microsoft's CustomShellHost both keep/consume explorer) | `docs/plans/immersive-shell-activation-decode.md` |
| No console window | `6ed3326` | shell was a console-subsystem exe, so Winlogon gave it a Windows-Terminal console window in the corner; now linked `/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup` so no console is ever created | gate **10/10** on a cold boot; corner clean |
| Window-list hooks off the UI thread | `8f79405` | the dock's machine-wide WinEvent hooks (+ their per-event DWM queries) ran on the UI thread; explorer's window-event flood cost the Start-menu render a frame. Moved to a dedicated hook thread; only filtered events cross to the UI thread via a message-only window | Start menu 83→50 ms (High Perf); see below |

`6ed3326` also required a gate fix: PowerShell's `&` does not wait for or
capture a GUI-subsystem process, so the gate's `--launch-app` check must use
`Start-Process -Wait -PassThru` (done in `test/win/gate.ps1`). Any script
driving `WinShellBar.exe --launch-app` must do the same.

## Start-menu latency: the numbers

Measured on the box, warm, `ddagrab`, 8+ reps, `test/bench/win-latency/`.

**Head-to-head, both on High Performance** (the answer to "ours vs native"):

| | first pixels | fully drawn |
|---|---|---|
| Starling (with `8f79405`) | ~50–67 ms | **same** — appears complete, no fade |
| Windows 11 native | 133 ms | **267 ms** — fades in over ~4 frames |

Ours ≈2× faster to first pixels, ≈4× faster to a usable menu.

**Why it had regressed (from the historical tight 67 ms), fully isolated:**
1. **Power plan.** The box was on **Balanced**, which idle-downclocks the CPU
   (3046 of 3801 MHz at idle). The menu opens from idle on a cold core →
   worst-case 133 ms (4-frame) spikes. High Performance removes those.
2. **The dock's UI-thread WinEvent hooks** (fixed in `8f79405`) — the ~1-frame
   median cost. After the fix, Balanced is back to 67 ms median (one 133 spike
   left, which is the power plan, not our code); High Perf is 50 ms.

## The file-manager benchmark — UNFINISHED, how to run it

The one piece left of "do the head-to-head for the file manager too."

Rig: `test/bench/win-latency/capture-launch-winE.ps1` (Win+E trigger, full-screen
`ddagrab`), analysed by `analyze-launch.py` at **grid 64** (16 flatters explorer
by 400 ms). extract crops used for the Start menu do NOT apply — this is
full-screen; use marker-crop `60:60:80:80` and a region starting at x≥400.

Procedure (both shells on High Performance, same box):
1. Ours: box registered as our shell → `capture-launch-winE.ps1 -Label ours`.
2. Switch to native: `WinShellBar.exe --unregister-shell` + **reboot** →
   explorer is the shell. Verify `DefaultPassword` length is 13 (autologon)
   BEFORE rebooting or the box parks at LogonUI.
3. Native: `capture-launch-winE.ps1 -Label native`.
4. Switch back: `WinShellBar.exe --register-shell` + reboot.

Historical numbers to beat (pre-fix, Balanced): ours 500 ms usable vs explorer
1149 ms. Re-baseline on High Performance with the fix in place.

**Why it stopped:** the box went completely offline mid-capture (see below).

## Box state — DEAL WITH THIS FIRST

**The box is unreachable** as of this checkpoint — 3+ hours of 100% packet loss
and ARP `FAILED` (not even MAC-resolvable), while the gateway responds fine. A
Windows update would have returned by now, so it is **hung or powered off** and
needs a **physical power-cycle**. There is no out-of-band access.

**Suspected cause:** I had switched the box to **High Performance** (CPU pinned
at 3801 MHz) for the benchmark, and this is a mobile APU (Ryzen 7 8845HS). A
sustained full-speed load during the repeated Win+E launches may have overheated
or wedged it. Treat High Performance on this box as suspect for sustained
benchmarks.

**When it comes back (a recovery watch is running to auto-detect it):**
1. **FIRST restore Balanced:** `powercfg /setactive
   381b4222-f694-41f0-9685-ff5bb260df2e`. High Perf persists across reboot and
   is the suspected culprit.
2. Verify shipped state: our shell (5 `WinShellBar` procs), explorer service
   (1), Balanced, and the fix binary — `WinShellBar.exe` SHA256 begins
   `909D5911D1B86228`.
3. Then, if desired, resume the file-manager benchmark above.

## Traps re-learned this session (all cost real time)

- **The capture rig leaves a stray `ffmpeg` holding Desktop Duplication.** The
  next `ddagrab` then silently records nothing AND locks the old mkv (delete
  fails). Kill ffmpeg and verify the new mkv/stamps are FRESH — qpc resets at
  boot, so a stale stamps file has a much larger qpc than the new uptime.
- **The first interactive scheduled task after a reboot often no-ops.** Re-run
  once the session settles.
- **Native Win11 Start now has a "View: Category" grid** (Developer Tools /
  Productivity / …) identical to ours on build 26100 — our launcher mimics it.
  Identify which shell is running by the PROCESS (`WinShellBar` count) and the
  taskbar, never by the menu's appearance. Nearly discarded a valid native
  capture over this.
- **278 leftover `Star*` test scheduled tasks** had piled up (a real benchmark
  hazard — a stray one can fire mid-measurement). Cleaned up; Windows' own
  `Start*` system tasks were kept (they reference neither `C:\st` nor
  `C:\dist`). ~11 `Star*` remain.
- **`$null` → `""` for a PowerShell P/Invoke string** bit again in a probe
  (reported "Progman owner Idle"); use `[NullString]::Value`.

## Memory updated this session

`winshell-borrow-died-service-returns`, `immersive-shell-activation-decode`,
`windows-shell-gate` (console fix → 10/10), `winshell-start-latency-measurement`
(perf investigation + the UI-thread fix + the native head-to-head).

---

# Addendum — 2026-08-26 evening: box recovered, and the STOCK-CPU head-to-head

**The box is up and healthy again** (11/11 gate, our shell registered, Balanced).
It was power-cycled by the user. Everything below supersedes the "Box state"
section above, which is now history.

## High Performance is confirmed dangerous on this box — do not use it

The hang above was not a one-off. High Performance was enabled again this
evening (not knowing about the morning's hang — the warning was in this file
and went unread) and **the box died the same way within ~35 minutes**, under
the same benchmark. Two hard hangs, same day, same trigger.

Forensics from the boot afterwards: `Kernel-Power` **id 41, BugcheckCode 0**,
and nothing else — **no WHEA hardware errors, no bugcheck, no crash dump, no
thermal events**. A silent freeze, not a driver fault and not an error the CPU
reported. Machine is a **GMKtec NucBox K8 Plus** (Ryzen 7 8845HS, 35–54 W
envelope), BIOS AMI 1.01 (2025-02-18), never updated — a BIOS update is the
first thing to try if this is ever chased. Ethernet MAC `C8-FF-BF-0D-D2-AD`
with Wake-on-LAN **enabled**, so a future hang may be recoverable remotely
rather than needing hands on the power button.

The processor settings this box ships with — **min 80% / max 50% / boost mode
0 on AC**, i.e. pinned at ~3.0 GHz with turbo off — should be read as a
**deliberate stability cap and left alone**. Undoing them makes it 1.65x faster
and then hangs it.

## Start menu, both shells, on the STOCK CPU settings

The comparison above was taken on High Performance. This is the same
measurement on the settings the machine actually runs at day to day — which is
the number that describes what a user experiences. Same rig, same crops, same
`ddagrab` instrument, **20 reps each**, ours as the registered shell and
Windows' own shell for the native side.

| | first pixels | fully drawn |
|---|---|---|
| **Starling** | **100 ms** (IQR 67–100, range 67–133) | **100 ms** — same frame, no fade |
| **Windows 11** | 167 ms (IQR 150–167, range 133–200) | 300 ms (IQR 283–300, range 267–333) |

**1.7x faster to first pixels, 3.0x faster to a usable menu.** Both ranges are
fully disjoint, so this clears the "two frames or it is unmeasured" bar in
`test/bench/win-latency/README.md` on both columns.

For reference, ours on High Performance measured **67 ms** median in the same
session (20 reps) — so the CPU cap costs us about one frame, and reintroduces
the 133 ms worst case. Windows' own menu was not re-measured on High
Performance this evening; the 133/267 figures above are from the morning run.

## Addendum 2 — the third hang, and what actually triggers it

**"Boost on demand" (min 5 / max 100 / boost 2 / EPP 0) also hung the box**, ~40
minutes after being applied. So "pinning the floor removes idle states" — the
theory in Addendum 1 — is **wrong**. Three hard hangs on 2026-08-26.

**What every run of the day says, together:**

| CPU config | workload | outcome |
|---|---|---|
| High Perf | repeated Win+E capture (heavy) | **HUNG** |
| High Perf | gate, Start-menu recording (light) | ok |
| High Perf | ffmpeg extract **on the box** (heavy all-core) | **HUNG** (2nd run) |
| **as-shipped cap** | **recording + ffmpeg extract on the box** | **ok — the control** |
| boost on demand | short load tests, recording, gate | ok |
| boost on demand | ffmpeg extract **on the box** | **HUNG** |

**The trigger is sustained all-core load while the chip may draw full power.**
Light work is fine on any setting. The as-shipped cap survived the exact
workload that killed the other two.

**And the cap is not slower under load** — capped all-core is 3.0 GHz; boost on
demand settled at **2.5 GHz** all-core, because with boost on and EPP 0 the chip
requests its top voltage/current point and then throttles frequency to fit,
i.e. it sits *on* the VRM limit continuously. Capped, it sits at a defined
low-voltage P-state well inside the envelope. On a 35–54 W mini-PC that is the
difference. **Leave the cap alone.**

**Process fix, and it is the avoidable part:** `extract.sh` is meant to run on
the **Linux** side (this repo's README says so). Running the ffmpeg extraction
*on the box* to save an 80 MB transfer is implicated in two of the three hangs.
Copy the `.mkv` back and extract locally. The capture always survives — the
video is on disk before the heavy step begins.

## Start menu, both shells, on BOTH CPU configurations (20 reps each)

| CPU config | | first pixels | fully drawn |
|---|---|---|---|
| **as shipped** (3.0 GHz capped) | Starling | **100 ms** (IQR 67–100) | **100 ms** |
| | Windows 11 | 167 ms (IQR 150–167) | 300 ms (IQR 283–300) |
| | | *1.7x* | *3.0x* |
| **boost on demand** | Starling | **67 ms** (IQR 67–83) | **67 ms** |
| | Windows 11 | 133 ms (IQR 133–167) | 267 ms (IQR 267–300) |
| | | *2.0x* | *4.0x* |

Ours is finished in the frame it first appears on every configuration; Windows
fades in over ~4 more frames, which is why its second column is always the
worse one. The interquartile ranges are disjoint in every comparison.

**Use the as-shipped row as the headline** — it is what the machine safely runs.

## Addendum 3 — the other two benchmarks, finished (2026-08-27)

Both on the box's **as-shipped CPU settings** (the safe ones), ours as the
registered shell vs Windows' own shell, `ddagrab`, extraction done **on Linux**.

### File manager launch (Win+E) — the one left unfinished

| | first pixels | window finished | n |
|---|---|---|---|
| **Starling** | **83 ms** (IQR 67–100) | **83 ms** — done in the frame it appears | 20 |
| Windows Explorer | 367 ms (IQR 333–367) | 1116 ms (IQR 1100–1133) | 20 |
| | **4.4x** | **13.4x** | |

Ranges are disjoint: ours 33–133 ms, Explorer 333–433 ms.

The historical pre-fix pair was ours 500 ms vs Explorer 1149 ms. Explorer has
not moved (1149 → 1116); **ours went 500 → 97 ms**, which is the Files-hosted-
in-the-shell work — Win+E opens a view in a process that is already running, so
there is no process to create.

**A rig bug found while chasing "only 14 of 20 reps captured", now fixed.**
`CloseFileManager` broke out of its retry loop only when `FindWindowW` returned
null. Our file manager is a surface view that is **hidden, not destroyed** — the
very fact `FileManagerUp` three lines below is built around — so the handle kept
answering and the loop ran all 14 retries at 350 ms **on every rep**. That added
~4.9 s per rep, stretching ours to ~13.6 s against Explorer's ~8.9, so six reps
fell off the end of a fixed-length recording. It presented as a capture problem
and was a harness one.

Fixed by breaking on `IsWindowVisible` rather than on a null handle, and the
per-rep budget went 9 → 10 s for margin. Our reps now pace at 8.93 s, matching
Explorer's, and 20 of 20 land. The first-pixel median moved 97 → 83 ms with the
extra reps (the 14-rep figure was not wrong, just short).

### Context menu (right-click a folder row)

| | first pixels | fully drawn | n |
|---|---|---|---|
| **Starling** | **67 ms** (IQR 67–100) | **67 ms** | 20 |
| Windows Explorer | 233 ms (IQR 233–233) | 267 ms (IQR 267–267) | 20 |
| | **3.5x** | **4.0x** | |

Reproduces the 2026-08-23 measurement (66.6/66.6 vs 233.2/299.8) almost exactly
on a different day, a different CPU configuration and a rebuilt shell.

First-pixel ranges are **fully disjoint** in both tables.

### A trap in the analysis, worth writing down

`analyze-menu.py` reported **"0 reps detected"** over 20 clean marker edges for
both context-menu captures. That phrasing means the REGION never changed — the
crops carried over from the Start-menu arm do not apply here, because
`capture-ctxmenu.ps1` computes its own crop from wherever the row turned out to
be, and prints it. Do not reuse crops between arms. The reliable method is to
diff a before/after frame and take the bounding box — and **blank the sync
marker's own square first**, or the marker's black→white flip lands in the
bounding box and the "region" starts at the marker instead of the menu.
